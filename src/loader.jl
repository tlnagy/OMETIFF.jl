function load(f::File{format"OMETIFF"})
    open(f) do s
        ret = load(s)
    end
end

function load(io::Stream{format"OMETIFF"})
    if !contains(get(io.filename), ".ome.tif") && !contains(get(io.filename), ".ome.tiff")
        throw(FileIO.LoaderError("OMETIFF", "Not an OME TIFF file!"))
    end

    orig_file = TiffFile(io)

    # load master OME-XML that contains all information about this dataset
    omexml = load_master_xml(orig_file)

    # find all images in this dataset
    images = find(omexml, "/ns:OME/ns:Image",["ns"=>namespace(omexml)])
    results = Array{AxisArray}(length(images))

    for (idx, image) in enumerate(images)
        files = Dict{String, TiffFile}()

        pixel = findfirst(image, "./ns:Pixels", ["ns"=>namespace(omexml)])
        tiffdatas = find(pixel, "./ns:TiffData", ["ns"=>namespace(omexml)])

        rawtype, mappedtype = type_mapping[pixel["Type"]]

        dims, axes_info = build_axes(pixel)

        # TODO: Only the IFDs with a corresponding slice should be loaded.
        slices = DefaultDict{String, Dict{Int, ImageSlice}}(Dict{Int, ImageSlice}())
        for tiffdata in tiffdatas
            slice = read_tiffdata(tiffdata, files, orig_file)
            slices[slice.file.filepath][slice.ifd_idx] = slice
        end

        data = Array{rawtype, length(dims)}(dims...)
        height, width = dims[1:2]

        for (filepath, ifds) in slices
            file = files[filepath]
            for i in 1:length(ifds)
                ifd = ifds[i]
                strip_offsets = next(file)

                n_strips = length(strip_offsets)
                strip_len = floor(Int, (width * height) / n_strips)
                read_dims = n_strips > 1 ? (strip_len) : (height, width)

                # TODO: This shouldn't be allocated for each ifd
                tmp = Array{rawtype}(read_dims...)
                for j in 1:n_strips
                    seek(file.io, strip_offsets[j])
                    read!(file.io, tmp)
                    tmp = file.need_bswap ? bswap.(tmp) : tmp
                    if n_strips > 1
                        data[j, :, ifd.z_idx, ifd.c_idx, ifd.t_idx]= tmp
                    else
                        data[:, :, ifd.z_idx, ifd.c_idx, ifd.t_idx] = tmp
                    end
                end
            end
        end

        # drop unnecessary axes
        # TODO: Reduce the number of allocations here
        squeezed_data = squeeze(Gray.(reinterpret(mappedtype, data)), (find(dims .== 1)...))
        results[idx] = AxisArray(squeezed_data, axes_info[dims .> 1]...)
    end
    length(results) == 1 ? results[1] : results
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
