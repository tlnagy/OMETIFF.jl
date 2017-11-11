"""
    to_symbol(input::String)

Cleans up `input` string and converts it into a symbol
"""
function to_symbol(input::String)
    fixed = replace(input, r"[^\w\ \-\_]", "")
    fixed = replace(fixed, r"[\ \-\_]+", "_")
    Symbol(replace(fixed, r"^[\d]", s"_\g<0>"))
end


"""
    myendian()

Returns the TIFF endian byte order expected if its endianness matches the host's
"""
function myendian()
    if ENDIAN_BOM == 0x04030201
        return 0x4949
    elseif ENDIAN_BOM == 0x01020304
        return 0x4d4d
    end
end


do_bswap(file, value) = file.need_bswap ? bswap.(value) : value

"""
    check_bswap(io::Union{Stream, IOStream})

Check endianness of TIFF file to see if we need to swap bytes
"""
function check_bswap(io::Union{Stream, IOStream})
    seekstart(io)
    endianness = read(io, UInt16)
    # check if we need to swap byte order
    need_bswap = endianness != myendian()

    tiff_version = read(io, UInt8, 2)
    (tiff_version != [0x2a, 0x00] && tiff_version != [0x00, 0x2a]) && error("Big-TIFF files aren't supported yet")

    return need_bswap
end

"""
Extract the name of the file backing a stream
"""
extract_filename(io::IOStream) = split(io.name, " ")[2][1:end-1]
extract_filename(io::Stream) = get(io.filename)
