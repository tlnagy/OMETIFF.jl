const Streamable = Union{Base.ReshapedArray{T, N, <: ReadonlyTiffDiskArray}, ReadonlyTiffDiskArray} where {T, N}

"""
    StreamingTiffDiskArray

A wrapper around the normal out-of-memory labeled axes object that allows the
dynamic swapping of the underlying array so that on-disk changes are reflected
faithfully. This is needed since AxisArrays are immutable and do not allow the
parent data or axes to be updated, instead the whole AxisArray + parent data are
swapped out whenever an on-disk change is detected. See the [`update`](@ref)
function to see how this is done.
"""
mutable struct StreamingTiffDiskArray{T, N, S, Ax} <: AbstractArray{T, N}
    data::AxisArray{T, N, S, Ax}

    function StreamingTiffDiskArray{T, N, Ax}(arr::AxisArray{T, N, <: Streamable, Ax}) where {T, N, Ax}
        new{T, N, typeof(parent(arr)), Ax}(arr)
    end
end

function StreamingTiffDiskArray(arr::AxisArray)
    S = typeof(parent(arr))
    @assert S <: Streamable "The underlying array type must be streamable."

    axtype = typeof(AxisArrays.axes(arr))
    StreamingTiffDiskArray{eltype(arr), ndims(arr), axtype}(arr)
end

"""
    update(arr)
"""
function update(arr::StreamingTiffDiskArray)

end

Base.size(arr::StreamingTiffDiskArray) = size(arr.data)
Base.getindex(arr::StreamingTiffDiskArray, i...) = getindex(arr.data, i)
Base.setindex!(arr::StreamingTiffDiskArray, val, i...) = setindex!(arr.data, val, i...)
Base.setindex!(arr::StreamingTiffDiskArray, val, ax::Axis, i...) = setindex!(arr.data, val, i...)

function Base.summary(io::IO, arr::StreamingTiffDiskArray)
    println(io, nameof(typeof(arr)), ", containing: ")
    summary(io, arr.data)
end