struct Metadata
    """Dimension sizes in XYZCT order"""
    dims::Vector{Int}
    axes::Vector{Axis}
    order::Array{Int, 2}
    """Raw type on disk"""
    rawtype::DataType
    """Mapped type in memory"""
    mappedtype::DataType

    function Metadata(dims::Vector{Int},
                      axes::Vector{Axis},
                      order::Array{Int, 2},
                      datatype::String)
        try
            rawtype, mappedtype = type_mapping[datatype]
            new(dims, axes, order, rawtype, mappedtype)
        catch KeyError
            error("image data is encoded as $datatype, which is not supported")
        end
    end
end

type_mapping = Dict(
    "uint16" => (UInt16, N0f16),
    "uint32" => (UInt32, N0f32),
    "float" => (Float32, Float32),
    "double" => (Float64, Float64),
    "int8" => (Int8, N0f8)
)
