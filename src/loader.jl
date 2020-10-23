function load(f::File{format"OMETIFF"}; dropunused=true, inmemory=true)
    open(f) do s
        ret = load(s; dropunused=dropunused, inmemory=inmemory)
    end
end

"""
    load(io; dropunused, inmemory, stream) -> ImageMetadata.ImageMeta

Load an OMETIFF file using the stream `io`.

**Arguments**
- `dropunused::Bool`: controls whether dimensions of length 1 are dropped
  automatically (default) or not.
- `inmemory::Bool`: controls whether arrays are fully loaded into memory
  (default) or left on disk and specific parts only loaded when accessed.
- `stream::Bool`: whether to watch the file and load any changes (default
  false), can only be used with out-of-memory files

!!! tip
    The `inmemory=false` flag currently returns a read-only view of the data on
    the disk for data integrity reasons. In order to modify the contents, you
    must copy the data into an in-memory container--at least until
    [#52](https://github.com/tlnagy/OMETIFF.jl/issues/52) is fixed--like so:

    ```
    copy(arr)
    ```
"""
function load(io::Stream{format"OMETIFF"}; dropunused=true, inmemory=true, stream=false)
    if io.filename != nothing && !occursin(".ome.tif", io.filename)
        throw(FileIO.LoaderError("OMETIFF", "Not an OME TIFF file!"))
    end

    (inmemory && stream) && error("Cannot stream an in-memory file.")

    orig_file = TiffFile(io)
    summary = load_comments(orig_file)

    # load master OME-XML that contains all information about this dataset
    omexml = load_master_xml(orig_file)

    # find all images in this dataset, can either have the Image or Pixel tag
    containers = findall("//*[@DimensionOrder]", omexml)

    pos_names = nodecontent.(findall("/ns:OME/ns:Image/ns:StageLabel[@Name]/@Name", omexml, ["ns"=>namespace(omexml)]))
    # if all position names aren't unique then substitute names
    if length(pos_names) == 0 || !allunique(pos_names)
        pos_names = ["Pos$i" for i in 1:length(containers)]
    end

    master_rawtype = nothing
    mappedtype = Int64
    dimlist = []
    axeslist = []

    for (idx, container) in enumerate(containers)
        dims, axes_info = build_axes(container)
        push!(dimlist, dims)
        push!(axeslist, axes_info)
        rawtype, mappedtype = type_mapping[container["Type"]]

        if master_rawtype === nothing
            master_rawtype = rawtype
        elseif master_rawtype != rawtype
            throw(FileIO.LoaderError("OMETIFF", "Multiple different storage types are not yet support in a multi position image"))
        end
    end

    ifd_indices = OrderedDict{Int, NTuple{4, Int}}()
    ifd_files = OrderedDict{Int, Tuple{String, String}}()
    obs_filepaths = Dict{String, Int}()
    for (idx, container) in enumerate(containers)
        OMETIFF.ifdindex!(ifd_indices, ifd_files, obs_filepaths, container, dimlist[idx], orig_file, idx)
    end

    files, ifds = get_ifds(orig_file, ifd_indices, ifd_files)

    # determine size of all the dims from the ifds in the tiff file instead
    # of the sizes embedded in the Pixel node
    true_dims = [Set{Int}() for i in 1:4]
    for ifd_index in keys(ifds), dim in 1:4
        push!(true_dims[dim], ifd_index[dim])
    end

    # generate new master dim list with the true dims from above
    master_dims = dimlist[1]
    dimnames = keys(master_dims)[3:6]
    new_data = [dimnames[i]=>length(true_dims[i]) for i in 1:4]
    master_dims = merge(master_dims, new_data)

    masteraxis = copy(axeslist[1])
    masteraxis[6] = Axis{:position}(OMETIFF.to_symbol.(pos_names))

    # check if the axes computed earlier are the correct length, if not,
    # we're not sure about the information through the whole movie so lets
    # strip the units
    err_axes = findall(length.(masteraxis) .!== values(master_dims))
    for ax in err_axes
        masteraxis[ax] = masteraxis[ax](1:master_dims[ax])
    end

    elapsed_times = get_elapsed_times(containers, master_dims, masteraxis)

    if inmemory
        img = inmemoryarray(ifds, master_dims, master_rawtype, mappedtype)
    else
        img = ReadonlyTiffDiskArray(Gray{mappedtype}, master_rawtype, ifds, values(master_dims));
    end

    # find dimensions of length 1 and remove them
    if dropunused
        unused_dims = findall(values(master_dims) .== 1)
        img = dropdims(img; dims=tuple(unused_dims...))
        deleteat!(masteraxis, unused_dims)
    end

    ImageMeta(AxisArray(img, masteraxis...),
              Description=summary,
              Elapsed_Times=elapsed_times)
end


"""
    inmemoryarray(ifds, dims, rawtype, mappedtype) -> Array

Builds an in-memory high-dimensional image using the mapping provided by `ifds`
from indices to [`OMETIFF.IFD`](@ref) objects. The IFD objects store handles to
the file objects and the offsets for the data. `dims` stores the size of each
named dimension. The `rawtype` parameter describes the storage layout of each
element on disk and `mappedtype` is the corresponding fixed or floating point
type.
"""
function inmemoryarray(ifds::OrderedDict{NTuple{4, Int}, IFD},
                       dims::NamedTuple,
                       rawtype::Type,
                       mappedtype::Type)

    data = Array{rawtype, length(dims)}(undef, dims...)

    width, height = dims[1], dims[2]
    # assume no strips
    tmp = Array{rawtype}(undef, height, width)

    # iterate over each IFD
    for (indices, ifd) in ifds
        n_strips = length(ifd.strip_offsets)
        strip_len = floor(Int, (width * height) / n_strips)

        # if the data is stripped and we haven't fix tmp's layout then lets make
        # tmp equal to one strip. This'll be fixed in Julia 1.4
        if n_strips > 1 && size(tmp) != (strip_len, )
            tmp = Array{rawtype}(undef, strip_len)
        end

        target = view(data, :, :, indices...)
        _read_ifd_data!(ifd, target, tmp)

        # transposition must happen here since the on-disk variant does this on access
        if ndims(tmp) == 2
            target .= tmp'
        end
    end

    reinterpret(Gray{mappedtype}, data)
end
