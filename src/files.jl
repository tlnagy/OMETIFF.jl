"""
    TiffFile(io) -> TiffFile

Wrap `io` with helper parameters to keep track of file attributes.

$(FIELDS)
"""
mutable struct TiffFile
    """A unique ID describing this file that is embedded in the XML"""
    uuid::String

    """The relative path to this file"""
    filepath::String

    """The file stream"""
    io::Stream

    """Location of the first IFD in the file stream"""
    first_offset::Int

    """Whether this file has a different endianness than the host computer"""
    need_bswap::Bool

    function TiffFile(io::Stream)
        file = new()
        file.io = io
        seekstart(io)
        # TODO: Parsing the filename from the IO name is likely to be fragile
        file.filepath = extract_filename(io)
        file.need_bswap = check_bswap(io)
        file.first_offset = Int(do_bswap(file, read(file.io, UInt32)))
        file
    end
end

function TiffFile(uuid::String, filepath::String)
    try
        file = TiffFile(open(filepath))
        file.uuid = uuid
        file.filepath = filepath
        return file
    catch e # the file probably got renamed
        (!isa(e, SystemError)) && rethrow(e)
        throw(FileIO.LoaderError("OMETIFF", "It looks like this file was renamed, "*
        "but has internal links with the original name. Please rename to $filepath "*
        "to load. See https://github.com/tlnagy/OMETIFF.jl/issues/14 for details."))
    end
end

TiffFile(io::IOStream) = TiffFile(getstream(io))

"""
    usingUUID(tf) -> Bool

Whether there was a UUID embedded in this file. According to the
[schema](https://www.openmicroscopy.org/Schemas/Documentation/Generated/OME-2016-06/ome.html)
UUIDs have the following pattern:
`(urn:uuid:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})`
"""
usingUUID(tf::TiffFile) = isdefined(tf, :uuid) && startswith(tf.uuid, "urn:uuid:")

"""
    IFD(file, strip_offsets) -> IFD

Build an Image File Directory (IFD), i.e. a TIFF slice. This structure retains a
pointer to its parent file and a list of the offsets within the file
corresponding to the data strips.

$(FIELDS)
"""
struct IFD
    """Pointer to the file containing this IFD"""
    file::TiffFile

    """Location(s) in `file` of the data corresponding to this IFD"""
    strip_offsets::Vector{Int}
end

"""
    get_ifds(orig_file, ifd_index, ifd_files) -> Dict, Dict

Run through all the IFDs extracted from the OMEXML and open all the referenced
files to construct a mapping of ZCTP (not guaranteed order) index to IFD object.
This is necessary because there can be multiple files referenced in a single
OMEXML and we need to iterate over the files to identify the actual offsets for
the data since this information isn't found in the OMEXML.

**Output**
- `Dict{Tuple{String, String}, TiffFile}`: a mapping of filepath, UUID to the
   actual TiffFile object
- `OrderedDict{NTuple{4, Int}, IFD}`: a mapping of ZCTP (or other order) index
   to the IFD objects in order that the IFDs are referenced in the OMEXML
"""
function get_ifds(orig_file::TiffFile,
                  ifd_index::OrderedDict{Int, NTuple{4, Int}},
                  ifd_files::OrderedDict{Int, Tuple{String, String}})

    # open all files referenced by the tiffdatas
    files = Dict{Tuple{String, String}, TiffFile}()
    for item in unique(values(ifd_files))
        uuid, filepath = item

        target_uuid = isdefined(orig_file, :uuid) ? orig_file.uuid : nothing

        # if this file is the same as the base file, then don't open it again
        if uuid != nothing && uuid == target_uuid
            files[item] = orig_file
        # if the UUID is missing or different, attempt to match on filepath
        elseif filepath == orig_file.filepath
            files[item] = orig_file
        # else open a new pointer to this file
        else
            files[item] = TiffFile(uuid, filepath)
        end
    end

    ifds = OrderedDict{NTuple{4, Int}, IFD}()

    for (fileid, file) in files
        # iterate over the file and find all stored offsets for IFDs
        ifd_offsets = collect(file)

        ifd_idx_in_file = 0
        for ifd in sort(collect(keys(ifd_index)))
            ifd_file = ifd_files[ifd]

            if ifd_file == fileid
                ifds[ifd_index[ifd]] = IFD(file, ifd_offsets[ifd_idx_in_file+=1])
            end
        end
    end
    files, ifds
end

"""
    load_master_xml(file::TiffFile) -> EzXML.doc

Loads the master OME-XML file from `file` or from a linked file.
"""
function load_master_xml(file::TiffFile)
    omexml = loadxml(file)
    # update the UUID of the file with the value from the OMEXML
    uuid_node = findfirst("/ns:OME/@UUID", omexml, ["ns"=>namespace(omexml)])
    if uuid_node != nothing
        file.uuid = nodecontent(uuid_node)
    else # if there isn't a UUID, there might still be an internal filename
        internal_filename = findfirst("(//ns:Image | //ns:Pixels)[@Name]/@Name", omexml, ["ns"=>namespace(omexml)])
        if internal_filename != nothing
            file.uuid = nodecontent(internal_filename)
        end
    end
    try
        # Check if the full OME-XML metadata is stored in another file
        metadata_file = findfirst("/ns:OME/ns:BinaryOnly", omexml, ["ns"=>namespace(omexml)])
        (metadata_file == nothing) && return omexml
        uuid, filepath = metadata_file["UUID"], joinpath(dirname(file.filepath), metadata_file["MetadataFile"])

        # we have a companion metadata file
        if endswith(filepath, ".companion.ome")
            xdoc = readxml(filepath)
            omexml = root(xdoc)
        else
            metadata_file = TiffFile(uuid, filepath)
            omexml = loadxml(metadata_file)
            close(metadata_file.io) # clean up
            return omexml
        end
    catch err
        isa(err, BoundsError) && return omexml
        rethrow(err)
    end
end

"""
    dump_omexml(filepath) -> String

Returns the OME-XML embedded inside the OME-TIFF as a prettified string.
"""
function dump_omexml(filepath::String)
    if !endswith(filepath, ".ome.tif")
        error("Passed file is not an OME-TIFF")
    end
    io = IOBuffer()
    open(filepath) do f
        s = getstream(f)
        orig_file = OMETIFF.TiffFile(s)
        omexml = OMETIFF.load_master_xml(orig_file)
        prettyprint(io, omexml)
    end
    String(take!(io))
end

Base.eltype(::Type{TiffFile}) = Vector{Int}
Base.IteratorSize(::Type{TiffFile}) = Base.SizeUnknown()

"""
    iterate(file) -> Vector

Initializes the iterator over all IFDs in a TIFF file. This is necessary to find
the offsets for all data strips in the file, which is not stored in the OME-XML and
can only be determined by visiting each IFD.

**Output**
- `Vector{Int}`: Offsets within file for all strips corresponding to the current
   IFD
"""
Base.iterate(file::TiffFile) = iterate(file, (read_ifd(file, file.first_offset)))

"""
    iterate(file, state) -> Vector, Int

Advances the iterator to the next IFD.

**Output**
- `Vector{Int}`: Offsets within file for all strips corresponding to the current
   IFD
- `Int`: Offset of the next IFD
"""
function Base.iterate(file::TiffFile, state::Tuple{Union{Vector{Int}, Nothing}, Int})
    strip_locs, ifd = state
    # if current element doesn't exist, exit
    (strip_locs == nothing) && return nothing
    (ifd <= 0) && return (strip_locs, (nothing, 0))

    next_strip_locs, next_ifd = read_ifd(file, ifd)

    return (strip_locs, (next_strip_locs, next_ifd))
end

loadxml(file::TiffFile) = read_ifd(file, file.first_offset; getxml=true)

"""
    read_ifd(file, offset; getxml)

Read the tags of the IFD located at `offset` in TiffFile `file`.
"""
function read_ifd(file::TiffFile, offset::Int; getxml=false)
    seek(file.io, offset)

    number_of_entries = do_bswap(file, read(file.io, UInt16))

    strip_offset_list = Int[]
    strip_offset = 0
    strip_count = 0
    width = 0
    height = 0

    tag_info = Array{UInt16}(undef, 2)
    data_info = Array{UInt32}(undef, 2)

    for i in 1:number_of_entries
        read!(file.io, tag_info)
        read!(file.io, data_info)
        tag_id, tag_type = do_bswap(file, tag_info)
        data_count, data_offset = do_bswap(file, data_info)

        curr_pos = position(file.io)
        if tag_id == 256
            width = data_offset
        elseif tag_id == 257 # height of image
            height = data_offset
        elseif tag_id == 273 # offset in stream to first strip
            strip_offset = data_offset
            strip_count = data_count
        # number of rows per strip should be equal to the height of image for now
        elseif tag_id == 278
            rows_per_strip = data_offset
            strip_num = floor(Int, (height + rows_per_strip - 1) / rows_per_strip)

            # if the data is spread across multiple strips
            if strip_num > 1
                seek(file.io, strip_offset)
                strip_info = Vector{UInt32}(undef, strip_num)
                read!(file.io, strip_info)
                strip_offsets = do_bswap(file, strip_info)
                strip_offset_list = Int.(strip_offsets)
            else
                strip_offset_list = [Int(strip_offset)]
            end
        elseif getxml && tag_id == 270 # Image Description tag
            seek(file.io, data_offset)
            # strip null values from string
            _data = Array{UInt8}(undef, data_count)
            read!(file.io, _data)
            raw_str = replace(String(_data), "\0"=>"")
            # check if is xml since ImageJ display settings are also stored in
            # ImageDescription tags
            # TODO: This should be replaced with some proper validation
            if raw_str[1:5] == "<?xml"
                xdoc = parsexml(raw_str)
                return root(xdoc)
            end
        end
        seek(file.io, curr_pos)
    end

    next_ifd = Int(do_bswap(file, read(file.io, UInt32)))
    strip_offset_list, next_ifd
end

"""
    load_comments(file) -> String

Extracts the MicroManager embedded description, if present. Else returns an
empty string.
"""
function load_comments(file)
    seek(file.io, 24)
    comment_header = Int(do_bswap(file, read(file.io, UInt32)))
    if comment_header != 99384722
        return ""
    end
    comment_offset = Int(do_bswap(file, read(file.io, UInt32)))
    seek(file.io, comment_offset)
    comment_header = read(file.io, UInt32)
    comment_length = Int(do_bswap(file, read(file.io, UInt32)))
    metadata_bytes = Array{UInt8}(undef, comment_length)
    read!(file.io, metadata_bytes)
    metadata = JSON.parse(String(metadata_bytes))
    if !haskey(metadata, "Summary")
        return ""
    end
    metadata["Summary"]
end

"""
    _read_ifd_data!(target, ifd, buffer)

Reads the IFD `ifd` into `target` using a temporary buffer `buffer`. If the IFD
is stripped, `buffer` must be 1-dimensional array, otherwise, it should be the
same size as a `target`.
"""
function _read_ifd_data!(ifd::IFD, target::AbstractArray{T, 2}, buffer::AbstractArray{T, 1}) where {T}
    n_strips = length(ifd.strip_offsets)

    for j in 1:n_strips
        seek(ifd.file.io, ifd.strip_offsets[j])
        read!(ifd.file.io, buffer)
        do_bswap(ifd.file, buffer)
        view(target, j, :) .= buffer
    end
end

function _read_ifd_data!(ifd::IFD, target::AbstractArray{T, 2}, buffer::AbstractArray{T, 2}) where {T}
    seek(ifd.file.io, first(ifd.strip_offsets))
    read!(ifd.file.io, buffer)
    do_bswap(ifd.file, buffer)
end

"""
    do_bswap(file, values) -> Array

If the endianness of file is different than that of the current machine, swap
the byte order.
"""
function do_bswap(file::TiffFile, values::AbstractArray)
    if file.need_bswap
        values .= bswap.(values)
    end
    values
end

do_bswap(file::TiffFile, value) = file.need_bswap ? bswap(value) : value