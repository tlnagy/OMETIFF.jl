mutable struct TiffFile
    """A unique ID describing this file that is embedded in the XML"""
    uuid::String

    """The relative path to this file"""
    filepath::String

    io::Union{Stream, IOStream}

    """Location of the first IFD in the file stream"""
    first_offset::Int

    """Whether this file has a different endianness than the host computer"""
    need_bswap::Bool

    function TiffFile(io::Union{Stream, IOStream})
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


"""
    loadxml(file::TiffFile)

Extract the OME-XML embedded in the TiffFile `file`.
"""
function loadxml(file::TiffFile)
    # ome-xml is stored in the first offset
    seek(file.io, file.offsets[1])
    number_of_entries = do_bswap(file, read(file.io, UInt16))
    rawxml = ""

    for i in 1:number_of_entries
        combined = Unsigned[]
        tag_info = Array{UInt16}(undef, 2)
        data_info = Array{UInt32}(undef, 2)
        read!(file.io, tag_info)
        read!(file.io, data_info)
        append!(combined, tag_info)
        append!(combined, data_info)
        tag_id, tag_type, data_count, data_offset = Int.(do_bswap(file, combined))

        if tag_id == 270 # Image Description tag
            seek(file.io, data_offset)
            # strip null values from string
            _data = Array{UInt8}(undef, data_count)
            read!(file.io, _data)
            raw_str = replace(String(_data), "\0"=>"")
            # check if is xml since ImageJ display settings are also stored in
            # ImageDescription tags
            # TODO: This should be replaced with some proper validation
            if raw_str[1:5] == "<?xml"
                rawxml = raw_str
                break
            end
        end
    end
    seek(file.io, file.offsets[end])

    xdoc = parsexml(rawxml)
    omexml = root(xdoc)
end


"""
    load_master_xml(file::TiffFile)

Loads the master OME-XML file from `file` or from a linked file.
"""
function load_master_xml(file::TiffFile)
    omexml = loadxml(file)
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


Base.eltype(::Type{TiffFile}) = Vector{Int}
Base.IteratorSize(::Type{TiffFile}) = Base.SizeUnknown()

Base.iterate(file::TiffFile) = iterate(file, (read_ifd(file, file.first_offset)))

"""
    iterate(file, state)

Given a `state`, returns a tuple with list of locations of the data strips corresponding to
that IFD in `file` and the updated state.
"""
function Base.iterate(file::TiffFile, state::Tuple{Union{Vector{Int}, Nothing}, Int})
    strip_locs, ifd = state
    # if current element doesn't exist, exit
    (strip_locs == nothing) && return nothing
    (ifd <= 0) && return (strip_locs, (nothing, 0))

    next_strip_locs, next_ifd = read_ifd(file, ifd)

    return (strip_locs, (next_strip_locs, next_ifd))
end

function read_ifd(file::TiffFile, offset::Int)
    if offset <= 0
        return nothing, nothing
    end
    seek(file.io, offset)

    number_of_entries = do_bswap(file, read(file.io, UInt16))

    strip_offset_list = Int[]
    strip_offset = 0
    strip_count = 0
    width = 0
    height = 0

    for i in 1:number_of_entries
        combined = Unsigned[]
        tag_info = Array{UInt16}(undef, 2)
        data_info = Array{UInt32}(undef, 2)
        read!(file.io, tag_info)
        read!(file.io, data_info)
        append!(combined, tag_info)
        append!(combined, data_info)
        tag_id, tag_type, data_count, data_offset = Int.(do_bswap(file, combined))
        
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
                strip_info = Array{UInt32}(undef, strip_num)
                read!(file.io, strip_info)
                strip_offsets = do_bswap(file, strip_info)
                strip_offset_list = Int.(strip_offsets)
            else
                strip_offset_list = [strip_offset]
            end
        elseif tag_id == 279 # Strip byte counts
        end
        seek(file.io, curr_pos)
    end

    next_ifd = do_bswap(file, read(file.io, UInt32))
    next_ifd, strip_offset_list
end


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
