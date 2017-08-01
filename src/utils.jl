"""
Cleans up `input` string and converts it into a symbol
"""
function to_symbol(input::String)
    fixed = replace(input, r"[^\w\ \-\_]", "")
    fixed = replace(fixed, r"[\ \-\_]+", "_")
    Symbol(replace(fixed, r"^[\d]", s"_\g<0>"))
end

function myendian()
    if ENDIAN_BOM == 0x04030201
        return 0x4949
    elseif ENDIAN_BOM == 0x01020304
        return 0x4d4d
    end
end
