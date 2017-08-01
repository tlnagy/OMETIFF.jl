"""
Cleans up `input` string and converts it into a symbol
"""
function to_symbol(input::String)
    fixed = replace(input, r"[^\w\ \-\_]", "")
    fixed = replace(fixed, r"[\ \-\_]+", "_")
    Symbol(replace(fixed, r"^[\d]", s"_\g<0>"))
end
