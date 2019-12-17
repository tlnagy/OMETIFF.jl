"""
    ReadonlyTiffDiskArray(mappedtype, rawtype, ifds, dims) -> ReadonlyTiffDiskArray

A lazy representation of a OMETIFF file. This custom type is needed since TIFF
files are laid out noncontiguously and nonregularly. It uses an internal index
to determine the mapping from indices to the locations of data slices on disk.
These slices are generally XY slices and are usually loaded in all at once so it
is quickly loaded into an internal cache to speed up the process. Externally,
this type should behave very similarly to an in-memory array, albeit with a
higher cost of accessing an element.

$(FIELDS)
"""
mutable struct ReadonlyTiffDiskArray{T <: Gray, R, N1, N2} <: AbstractArray{T, N2}
    """
    A map of dimensions (sans XY) to the corresponding [`IFD`](@ref)
    """
    ifds::OrderedDict{NTuple{N1, Int}, IFD}

    """
    The full set of dimensions of the TIFF file, including XY
    """
    dims::NTuple{N2, Int}

    """
    An internal cache to fill when reading from disk
    """
    cache::Array{R, 2}

    """
    The dimension indices corresponding to the slice currently in the cache
    """
    cache_index::NTuple{N1, Int}

    function ReadonlyTiffDiskArray(::Type{T}, ::Type{R}, ifds::OrderedDict{NTuple{N1, Int}, IFD}, dims::NTuple{N2, Int}) where {T, R, N1, N2}
        if N2 - 2 != N1
            error("$N2 dimensions given, but the IFDs are indexed on $N1 dimensions instead of "*
                  "expected $(N2-2).")
        end
        new{T, R, N1, N2}(ifds, dims, Array{R}(undef, dims[1], dims[2]), (-1, -1, -1, -1))
    end
end

Base.size(A::ReadonlyTiffDiskArray) = A.dims

function Base.getindex(A::ReadonlyTiffDiskArray{Gray{T}, R, N1, N2}, i1::Int, i2::Int, i::Vararg{Int, N1}) where {T, R, N1, N2}
    # check the loaded cache is already the correct slice
    if A.cache_index == i
        return Gray(reinterpret(T, A.cache[i2, i1]))
    end

    ifd = A.ifds[i]

    # if the file isn't open, lets open a handle and update it
    if !isopen(ifd.file.io)
        path = ifd.file.filepath
        ifd.file.io = Stream(format"OMETIFF", open(path), path)
    end

    n_strips = length(ifd.strip_offsets)
    strip_len = floor(Int, (size(A.cache, 1) * size(A.cache, 2)) / n_strips)

    # if the data is striped then we need to change the buffer shape so that we
    # can read into it. This should be replaced with a view of cache in Julia
    # >1.4, see https://github.com/JuliaLang/julia/pull/33046
    if n_strips > 1 && size(tmp) != (strip_len, )
        tmp = Array{R}(undef, strip_len)
    else
        tmp = A.cache
    end

    _read_ifd_data!(ifd, A.cache, tmp)

    A.cache_index = i

    return Gray(reinterpret(T, A.cache[i2, i1]))
end

function Base.setindex!(A::ReadonlyTiffDiskArray{Gray{T}, R, N1, N2}, X, I...) where {T, R, N1, N2}
   @error("This array is on disk and is read only. Convert to a mutable in-memory version by running "*
        "`copy(arr)`. \n\n𝗡𝗼𝘁𝗲: For large files this can be quite expensive. A future PR will add "*
        "support for reading and writing to/from disk.")
end