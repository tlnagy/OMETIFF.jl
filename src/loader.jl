function load(f::File{format"OMETIFF"})
    open(f) do s
        ret = load(s)
    end
end

function load(io::Stream{format"OMETIFF"})
    if io.filename != nothing && !occursin(".ome.tif", io.filename)
        throw(FileIO.LoaderError("OMETIFF", "Not an OME TIFF file!"))
    end

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
    n_ifds = 0

    for (idx, container) in enumerate(containers)
        dims, axes_info = build_axes(container)
        push!(dimlist, dims)
        push!(axeslist, axes_info)
        n_ifds += dims[:Z]*dims[:C]*dims[:T]
        rawtype, mappedtype = type_mapping[container["Type"]]

        if master_rawtype == nothing
            master_rawtype = rawtype
        elseif master_rawtype != rawtype
            throw(FileIO.LoaderError("OMETIFF", "Multiple different storage types are not yet support in a multi position image"))
        end
    end

    ifd_index = Array{Union{NTuple{4, Int}, Nothing}}(nothing, n_ifds)
    ifd_files = Array{Union{Tuple{String, String}, Nothing}}(nothing, n_ifds)
    obs_filepaths = Set{String}()
    for (idx, container) in enumerate(containers)
        OMETIFF.ifdindex!(ifd_index, ifd_files, obs_filepaths, container, dimlist[idx], "", idx)
    end
    @assert length(ifd_index) == length(ifd_files)

    files, ifds = get_ifds(orig_file, ifd_files)

    if length(unique(dimlist)) == 1
        master_dims = merge(unique(dimlist)[1], [:P=>length(containers)])
        dimlist = [master_dims]
        masteraxis = copy(axeslist[1])
        masteraxis[6] = Axis{:position}(to_symbol.(pos_names))
        axeslist = [masteraxis]
    end

    inmemoryarray(ifd_index, ifds, master_dims, masteraxis, master_rawtype, mappedtype)
end

"""
Builds an in-memory high-dimensional image from the list of IFDs, `ifds`, and
the corresponding indices, `ifd_index`, in the high-dimensional array.
"""
function inmemoryarray(ifd_index::Array{Union{NTuple{4, Int}, Nothing}},
                       ifds::Array{Union{IFD, Nothing}},
                       master_dims::NamedTuple,
                       masteraxis::Array{Axis},
                       master_rawtype::Type,
                       mappedtype::Type)

    data = Array{master_rawtype, length(master_dims)}(undef, master_dims...)

    # iterate over each IFD
    for idx in 1:length(ifd_index)
        indices = ifd_index[idx]
        ifd = ifds[idx]
        (ifd == nothing) && continue

        width, height = master_dims[:X], master_dims[:Y]

        n_strips = length(ifd.strip_offsets)
        strip_len = floor(Int, (width * height) / n_strips)
        read_dims = n_strips > 1 ? (strip_len) : (height, width)

        # TODO: This shouldn't be allocated for each ifd
        tmp = Array{master_rawtype}(undef, read_dims...)
        for j in 1:n_strips
            seek(ifd.file.io, ifd.strip_offsets[j])
            read!(ifd.file.io, tmp)
            do_bswap(ifd.file, tmp)
            if n_strips > 1
                data[j, :, indices...] = tmp
            else
                data[:, :, indices...] = tmp'
            end
        end
    end

    data = reinterpret(Gray{mappedtype}, data)
    unused_dims = Tuple(idx for (idx, key) in enumerate(keys(master_dims)) if master_dims[idx] == 1)
    squeezed_data = dropdims(data; dims=unused_dims)
    used_axes = [masteraxis[i] for i in 1:length(masteraxis) if !(i in unused_dims)]
    ImageMeta(AxisArray(squeezed_data, used_axes...), Summary=summary)
end

"""Corresponding Julian types for OME-XML types"""
type_mapping = Dict(
    "uint8" => (UInt8, N0f8),
    "uint16" => (UInt16, N0f16),
    "uint32" => (UInt32, N0f32),
    "float" => (Float32, Float32),
    "double" => (Float64, Float64),
    "int8" => (Int8, N0f8)
)
