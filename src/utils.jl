"""
    to_symbol(input) -> String

Cleans up `input` string and converts it into a symbol, needed so that channel
names work with AxisArrays.
"""
function to_symbol(input::String)
    fixed = replace(input, r"[^\w\ \-\_]"=>"")
    fixed = replace(fixed, r"[\ \-\_]+"=>"_")
    Symbol(replace(fixed, r"^[\d]"=>s"_\g<0>"))
end


"""
    myendian() -> UInt16

Returns the endianness of the host machine
"""
function myendian()
    if ENDIAN_BOM == 0x04030201
        return 0x4949
    elseif ENDIAN_BOM == 0x01020304
        return 0x4d4d
    end
end

"""
    check_bswap(io::Union{Stream, IOStream})

Check endianness of TIFF file to see if we need to swap bytes
"""
function check_bswap(io::Union{Stream, IOStream})
    seekstart(io)
    endianness = read(io, UInt16)
    # check if we need to swap byte order
    need_bswap = endianness != myendian()

    tiff_version = Array{UInt8}(undef, 2)
    read!(io, tiff_version)
    (tiff_version != [0x2a, 0x00] && tiff_version != [0x00, 0x2a]) && error("Big-TIFF files aren't supported yet")

    return need_bswap
end

"""
    extract_filename(io) -> String

Extract the name of the file backing a stream
"""
extract_filename(io::IOStream) = split(io.name, " ")[2][1:end-1]
extract_filename(io::Stream) = io.filename

"""Corresponding Julian types for OME-XML types"""
type_mapping = Dict(
    "uint8" => (UInt8, N0f8),
    "uint16" => (UInt16, N0f16),
    "uint32" => (UInt32, N0f32),
    "float" => (Float32, Float32),
    "double" => (Float64, Float64),
    "int8" => (Int8, N0f8)
)

function getstream(fmt, io, name)
    # adapted from https://github.com/JuliaStats/RDatasets.jl/pull/119/
    if isdefined(FileIO, :action)
        # FileIO >= 1.6
        return Stream{fmt}(io, name)
    else
        # FileIO < 1.6
        return Stream(fmt, io, name)
    end
end

getstream(fmt, io::IOBuffer) = getstream(fmt, io, "")
getstream(fmt, io::IOStream) = getstream(fmt, io, extract_filename(io))
# assume OMETIFF if no format given
getstream(io) = getstream(format"OMETIFF", io)
