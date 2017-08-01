struct Metadata
    """Dimension sizes in XYZCT order"""
    dims::Vector{Int}
    axes::Vector{Axis}
    order::Array{Int, 2}
    datatype::DataType

    function Metadata(dims::Vector{Int},
                      axes::Vector{Axis},
                      order::Array{Int, 2},
                      datatype::String)
        try
            new(dims, axes, order, type_mapping[datatype])
        catch KeyError
            error("image data is encoded as $datatype, which is not supported")
        end
    end
end

type_mapping = Dict(
    "uint16" => UInt16,
    "uint32" => UInt32,
    "float" => Float32,
    "double" => Float64
)
