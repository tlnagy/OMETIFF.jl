"""
    $SIGNATURES

A lazy representation of a OMETIFF file. This custom type is needed since TIFF
files are laid out noncontiguously and nonregularly. It uses an internal index
to determine the mapping from indices to the locations of data slices on disk.
These slices are generally XY slices and are usually loaded in all at once so it
is quickly loaded into an internal cache to speed up the process. Externally,
this type should behave very similarly to an in-memory array, albeit with a
higher cost of accessing an element.

$(FIELDS)
"""
mutable struct DiskOMETaggedImage{T, N1, N2, O, AA <: AbstractArray} <: AbstractDenseTIFF{T, N2}
    """
    A map of dimensions (sans XY) to the corresponding [`TiffFile`](@ref) and [`IFD`](@ref)
    """
    ifds::OrderedDict{NTuple{N1, Int}, Tuple{TiffFile{O}, IFD{O}}}

    """
    The full set of dimensions of the TIFF file, including XY
    """
    dims::NTuple{N2, Int}

    """
    An internal cache to fill when reading from disk
    """
    cache::AA

    """
    The dimension indices corresponding to the slice currently in the cache
    """
    cache_index::NTuple{N1, Int}

    function DiskOMETaggedImage(ifds::OrderedDict{NTuple{N1, Int}, Tuple{TiffFile{O}, IFD{O}}}, dims::NTuple{N2, Int}) where {N1, O, N2}
        if N2 - 2 != N1
            error("$N2 dimensions given, but the IFDs are indexed on $N1 dimensions instead of "*
                  "expected $(N2-2).")
        end
        ifd = first(values(ifds))[2]
        cache = getcache(ifd)
        new{eltype(cache), N1, N2, O, typeof(cache)}(ifds, dims, cache, (-1, -1, -1, -1))
    end
end

Base.size(A::DiskOMETaggedImage) = A.dims

function Base.getindex(A::DiskOMETaggedImage{T, N1, N2, O, AA}, i1::Int, i2::Int, i::Vararg{Int, N1}) where {T, N1, N2, O, AA}
    # check the loaded cache is already the correct slice
    if A.cache_index == i
        return A.cache[i2, i1]
    end

    file, ifd = A.ifds[i]

    # if the file isn't open, lets open a handle and update it
    if !isopen(file.io)
        path = file.filepath
        file.io = getstream(format"OMETIFF", open(path), path)
    end

    read!(A.cache, file, ifd)

    A.cache_index = i

    return A.cache[i2, i1]
end

function Base.setindex!(A::T, X, I...) where {T <: DiskOMETaggedImage}
    error("This array is on disk and is read only. Convert to a mutable in-memory version by running "*
          "`copy(arr)`. \n\n𝗡𝗼𝘁𝗲: For large files this can be quite expensive. A future PR will add "*
          "support for reading and writing to/from disk.")
end