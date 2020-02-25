using FileWatching: watch_file

const ReshapedDiskArray = Base.ReshapedArray{T, N, <: ReadonlyTiffDiskArray} where {T, N}
const Streamable = Union{ReshapedDiskArray, ReadonlyTiffDiskArray} where {T, N}

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

    """Which filepaths we're tracking and the async thread for each"""
    tracking::Dict{String, Task}

    function StreamingTiffDiskArray{T, N, Ax}(arr::AxisArray{T, N, <: Streamable, Ax}) where {T, N, Ax}
        streamer = new{T, N, typeof(parent(arr)), Ax}(arr, Dict{String, Task}())
        track(streamer)
        streamer
    end
end

function StreamingTiffDiskArray(arr::AxisArray)
    S = typeof(parent(arr))
    @assert S <: Streamable "The underlying array type must be streamable."

    axtype = typeof(AxisArrays.axes(arr))
    StreamingTiffDiskArray{eltype(arr), ndims(arr), axtype}(arr)
end

function track(arr::StreamingTiffDiskArray)
    files = Set(ifd.file.filepath for ifd in values(ifds(arr)))
    setdiff!(files, arr.tracking)

    for filepath in files
        @info "Tracking $(basename(filepath))"
        arr.tracking[filepath] = @async while true
            event = watch_file(filepath)
            if event.changed
                try
                    update(arr)
                catch
                    @warn "Updating view of on-disk file failed. Changes might not be reflected."
                    sleep(1)
                end
            end
        end
    end
end

"""
    update(arr)
"""
function update(arr::StreamingTiffDiskArray)
    @info "Tracked file updated!"
end

Base.parent(arr::StreamingTiffDiskArray) = arr.data
Base.size(arr::StreamingTiffDiskArray) = size(parent(arr))
Base.getindex(arr::StreamingTiffDiskArray, i...) = getindex(parent(arr), i...)
Base.setindex!(arr::StreamingTiffDiskArray, val, i...) = setindex!(parent(arr), val, i...)
Base.setindex!(arr::StreamingTiffDiskArray, val, ax::Axis, i...) = setindex!(parent(arr), val, ax, i...)

ifds(arr::StreamingTiffDiskArray{T, N, <: ReshapedDiskArray, Ax}) where {T, N, Ax} =
    parent(parent(parent(arr))).ifds

ifds(arr::StreamingTiffDiskArray{T, N, <: ReadonlyTiffDiskArray, Ax}) where {T, N, Ax} =
    parent(parent(arr)).ifds

function Base.summary(io::IO, arr::StreamingTiffDiskArray)
    println(io, nameof(typeof(arr)), ", containing: ")
    summary(io, parent(arr))
end