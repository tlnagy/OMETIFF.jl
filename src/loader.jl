function TiffImages.load(f::File{format"OMETIFF"}; dropunused=true, inmemory=true)
    open(f) do s
        ret = load(s; dropunused=dropunused, inmemory=inmemory)
    end
end

"""
    load(io; dropunused, verbose, inmemory) -> ImageMetadata.ImageMeta

Load an OMETIFF file using the stream `io`.

**Arguments**
- `dropunused::Bool`: controls whether dimensions of length 1 are dropped
  automatically (default) or not.
- `verbose::Bool`: if true then prints a progress bar during loading
- `inmemory::Bool`: controls whether arrays are fully loaded into memory
  (default) or left on disk and specific parts only loaded when accessed.

!!! tip
    The `inmemory=false` flag currently returns a read-only view of the data on
    the disk for data integrity reasons. In order to modify the contents, you
    must copy the data into an in-memory container--at least until
    [#52](https://github.com/tlnagy/OMETIFF.jl/issues/52) is fixed--like so:

    ```
    copy(arr)
    ```
"""
function TiffImages.load(io::Stream{format"OMETIFF"}; dropunused=true, verbose = true, inmemory=true)
    if io.filename !== nothing && !occursin(".ome.tif", io.filename)
        throw(FileIO.LoaderError("OMETIFF", "Not an OME TIFF file!", ErrorException("")))
    end

    orig_file = read(io, TiffFile)
    summary = load_comments(orig_file)

    # load master OME-XML that contains all information about this dataset
    omexml = load_master_xml(orig_file)

    # find all images in this dataset, can either have the Image or Pixel tag
    containers = findall("//*[@DimensionOrder]", omexml, ["ns" => namespace(omexml)])

    pos_names = nodecontent.(findall("/ns:OME/ns:Image/ns:StageLabel[@Name]/@Name", omexml, ["ns"=>namespace(omexml)]))
    # if all position names aren't unique then substitute names
    if length(pos_names) == 0 || !allunique(pos_names)
        pos_names = ["Pos$i" for i in 1:length(containers)]
    end

    dimlist = []
    axeslist = []

    for (idx, container) in enumerate(containers)
        dims, axes_info = build_axes(container)
        push!(dimlist, dims)
        push!(axeslist, axes_info)
    end

    ifd_indices = OrderedDict{Int, NTuple{4, Int}}()
    ifd_files = OrderedDict{Int, Tuple{UUID, String}}()
    obs_filepaths = Dict{String, Int}()
    for (idx, container) in enumerate(containers)
        ifdindex!(ifd_indices, ifd_files, obs_filepaths, container, dimlist[idx], orig_file, idx)
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
    masteraxis[6] = Axis{:position}(to_symbol.(pos_names))

    # check if the axes computed earlier are the correct length, if not,
    # we're not sure about the information through the whole movie so lets
    # strip the units
    err_axes = findall(length.(masteraxis) .!== values(master_dims))
    for ax in err_axes
        masteraxis[ax] = masteraxis[ax](1:master_dims[ax])
    end

    elapsed_times = get_elapsed_times(containers, master_dims, masteraxis)

    if inmemory
        loaded = inmemoryarray(ifds, master_dims; verbose = verbose)
    else
        loaded = DiskOMETaggedImage(ifds, values(master_dims));
    end

    data = fixcolors(loaded, first(values(ifds))[2])

    # find dimensions of length 1 and remove them
    if dropunused
        unused_dims = findall(values(master_dims) .== 1)
        data = dropdims(data; dims=tuple(unused_dims...))
        deleteat!(masteraxis, unused_dims)
    end

    ImageMeta(AxisArray(data, masteraxis...),
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
function inmemoryarray(ifds, dims::NamedTuple; verbose = true)

    ifd = first(values(ifds))[2]
    cache = getcache(ifd)

    data = similar(cache, dims...)

    freq = verbose ? 1 : Inf

    # iterate over each IFD
    @showprogress for (indices, (file, ifd)) in ifds
        read!(cache, file, ifd)
        data[:, :, indices...] .= cache'
    end

    return data
end
