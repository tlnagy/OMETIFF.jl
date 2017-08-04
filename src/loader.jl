function load(f::File{format"OMETIFF"})
    open(f) do s
        ret = load(s)
    end
end

function load(io::Stream{format"OMETIFF"})
    if !contains(get(io.filename), ".ome.tif") && !contains(get(io.filename), ".ome.tiff")
        throw(FileIO.LoaderError("Not an OME TIFF file!"))
    end

    need_bswap = check_bswap(io)

    first_ifd = read(io, UInt32)
    first_ifd = need_bswap ? Int(bswap(first_ifd)) : Int(first_ifd)

    data_offsets = Array{Int}[]
    next_ifd, strip_offset, omexml = read_ifd(io, first_ifd, need_bswap)
    push!(data_offsets, strip_offset)

    while next_ifd > 0
        next_ifd, strip_offset, _ = read_ifd(io, next_ifd, need_bswap)
        push!(data_offsets, strip_offset)
    end

    metadata = parse_metadata(omexml)

    present_dims = find(metadata.dims .> 1)
    order_dims = present_dims[3:end]
    height, width = metadata.dims[1:2]
    data = Array{metadata.rawtype, length(present_dims)}(height, width, metadata.dims[order_dims]...)
    for i in 1:size(metadata.order, 2)
        strip_offsets = data_offsets[i]

        n_strips = length(strip_offsets)
        strip_len = floor(Int, (width * height) / n_strips)
        dims = n_strips > 1 ? (strip_len) : (height, width)
        tmp = Array{metadata.rawtype}(dims...)
        for j in 1:n_strips
            seek(io, strip_offsets[j])
            read!(io, tmp)
            tmp = need_bswap ? bswap.(tmp) : tmp
            if n_strips > 1
                data[j, :, metadata.order[order_dims-2, i]...] = tmp
            else
                data[:, :, metadata.order[order_dims-2, i]...] = tmp
            end
        end
    end

    AxisArray(Gray.(reinterpret(metadata.mappedtype, data)), metadata.axes[[present_dims...]]...)
end


"""
    check_bswap(io::Stream)

Check endianness of TIFF file to see if we need to swap bytes
"""
function check_bswap(io::Stream)
    seekstart(io)
    endianness = read(io, UInt16)
    # check if we need to swap byte order
    need_bswap = endianness != myendian()

    tiff_version = read(io, UInt8, 2)
    (tiff_version != [0x2a, 0x00] && tiff_version != [0x00, 0x2a]) && error("Big-TIFF files aren't supported yet")

    return need_bswap
end


function read_ifd(io::Stream, offset::Integer, need_bswap::Bool)
    seek(io, offset)

    number_of_entries = read(io, UInt16)
    number_of_entries = need_bswap ? Int(bswap(number_of_entries)) : Int(number_of_entries)

    strip_offset_list = []
    strip_offset = 0
    strip_count = 0
    width = 0
    height = 0
    rawxml = ""

    for i in 1:number_of_entries
        tag_bytes = Unsigned[]
        append!(tag_bytes, read(io, UInt16, 2))
        append!(tag_bytes, read(io, UInt32, 2))
        tag_bytes = need_bswap ? bswap.(tag_bytes) : tag_bytes
        tag_id, tag_type, data_count, data_offset = Int.(tag_bytes)

        curr_pos = position(io)
        if tag_id == 256
            width = data_offset
        elseif tag_id == 257 # height of image
            height = data_offset
        elseif tag_id == 273 # offset in stream to first strip
            strip_offset = data_offset
            strip_count = data_count
        # number of rows per strip should be equal to the height of image for now
        elseif tag_id == 278
            rows_per_strip = data_offset
            strip_num = floor(Int, (height + rows_per_strip - 1) / rows_per_strip)

            # if the data is spread across multiple strips
            if strip_num > 1
                seek(io, strip_offset)
                strip_offsets = read(io, UInt32, strip_num)
                strip_offsets = need_bswap ? bswap.(strip_offsets) : strip_offsets
                append!(strip_offset_list, Int.(strip_offsets))
            else
                push!(strip_offset_list, strip_offset)
            end
        elseif tag_id == 279 # Strip byte counts
            # println("-- $data_offset")
        elseif tag_id == 270 # Image Description tag
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

    next_ifd = read(io, UInt32)
    next_ifd = need_bswap ? bswap(next_ifd) : next_ifd
    Int(next_ifd), strip_offset_list, rawxml
end
