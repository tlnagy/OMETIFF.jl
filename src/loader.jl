function loadtiff(filename::String)
    open(filename) do io
        check_header(io)

        first_ifd = Int(read(io, UInt32))

        data_offsets = Int[]
        next_ifd, strip_offset, omexml = read_ifd(io, first_ifd)
        push!(data_offsets, strip_offset)

        while next_ifd > 0
            next_ifd, strip_offset, _ = read_ifd(io, next_ifd)
            push!(data_offsets, strip_offset)
        end

        metadata = parse_metadata(omexml)

        present_dims = find(metadata.dims .> 1)
        order_dims = present_dims[3:end]
        data = Array{metadata.datatype, length(present_dims)}(metadata.dims[present_dims]...)
        tmp = Array{metadata.datatype}(metadata.dims[1:2]...)
        for i in 1:size(metadata.order, 2)
            seek(io, data_offsets[i])
            read!(io, tmp)
            data[:, :, metadata.order[order_dims-2, i]...] = tmp
        end

        AxisArray(Gray.(reinterpret(N0f16, data)), metadata.axes[[present_dims...]]...)
    end
end


"""
    check_header(io::IOStream)

Check header of file for the standard TIFF magic bytes, returns true if found
"""
function check_header(io::IOStream)
    seekstart(io)

    endianness = read(io, UInt16)
    # check if a little-endian tiff file
    endianness != 0x4949 && error("Big-endian files aren't supported yet. Please file an issue.")

    tiff_version = read(io, UInt16)
    tiff_version != 0x2a && error("Big-TIFF files aren't supported yet")

    return true
end


function read_ifd(io::IOStream, offset::Integer)
    seek(io, offset)

    number_of_entries = Int(read(io, UInt16))

    strip_offset = 0
    height = 0
    rawxml = ""

    for i in 1:number_of_entries
        tag_id = Int(read(io, UInt16))
        tag_type = Int(read(io, UInt16))
        data_count = Int(read(io, UInt32))
        data_offset = Int(read(io, UInt32))

        curr_pos = position(io)

        if tag_id == 257 # height of image
            height = data_offset
        end
        if tag_id == 273 # offset in stream to first strip
            strip_offset = data_offset
        end
        # number of rows per strip should be equal to the height of image for now
        if tag_id == 278
            (data_offset != height) && error("Multiple strips aren't supported yet. Please file an issue")
        end
        if tag_id == 270 # Image Description tag
            seek(io, data_offset)
            # strip null values from string
            raw_str = replace(String(read(io, UInt8, data_count)), "\0", "")
            # check if is xml since ImageJ display settings are also stored in
            # ImageDescription tags
            if raw_str[1:5] == "<?xml"
                rawxml = raw_str
            end
        end
        seek(io, curr_pos)
    end

    Int(read(io, UInt32)), strip_offset, rawxml
end
