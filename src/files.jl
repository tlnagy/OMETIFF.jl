function TiffFile(uuid::UUID, filepath::String)
    try
        io = open(filepath)
        file = read(io, TiffFile)
        file.uuid = uuid
        file.filepath = filepath
        return file
    catch e # the file probably got renamed
        # if isa(e, SystemError)
        #     dir = dirname(filepath)
        #     filter(x->occursin(".ome.tif", x), readdir(dir))
        # end
        throw(FileIO.LoaderError("OMETIFF", "It looks like this file was renamed, "*
        "but has internal links with the original name. Please rename to $filepath "*
        "to load. See https://github.com/tlnagy/OMETIFF.jl/issues/14 for details.", e))
    end
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
function get_ifds(orig_file::TiffFile{O},
                  ifd_index::OrderedDict{Int, NTuple{4, Int}},
                  ifd_files::OrderedDict{Int, Tuple{UUID, String}}) where {O <: Unsigned}

    # open all files referenced by the tiffdatas
    files = OrderedDict{Tuple{UUID, String}, TiffFile{O}}()
    for item in unique(values(ifd_files))
        uuid, filepath = item

        target_uuid = orig_file.uuid

        # if this file is the same as the base file, then don't open it again
        if uuid !== nothing && uuid == target_uuid
            files[item] = orig_file
        # if the UUID is missing or different, attempt to match on filepath
        elseif filepath == orig_file.filepath
            files[item] = orig_file
        # else open a new pointer to this file
        else
            files[item] = TiffFile(uuid, filepath)
        end
    end

    ifds = OrderedDict{NTuple{4, Int}, Tuple{TiffFile{O}, IFD{O}}}()

    for (fileid, file) in files
        # load all IFDs in this file
        rawifds = collect(file)
        foreach(ifd -> load!(file, ifd), rawifds)

        # there is a global IFD index across all files and also a per-file
        # index, e.g. if each IFD is in a separate file than an IFD can have an
        # index of 5 globally yet have an index of 1 in the 5th file.
        ifd_idx_in_file = 0
        for ifd in sort(collect(keys(ifd_index)))
            ifd_file = ifd_files[ifd]

            if ifd_file == fileid
                ifds[ifd_index[ifd]] = (file, rawifds[ifd_idx_in_file+=1])
            end
        end
    end
    files, ifds
end

function loadxml(file::TiffFile)
    ifd = first(file)
    load!(file, ifd)

    xml = nothing
    # grab all IMAGEDESCRIPTION tags in the first ifd, there can be multiple so
    # we need to check all of them
    for descriptions in ifd[Iterable(IMAGEDESCRIPTION)]
        try 
            newxml = parsexml(descriptions.data)
            if xml === nothing
                xml = newxml
            else
                throw(ErrorException("Multiple XML entries detected, aborting"))
            end
        catch
        end
    end
    if xml === nothing # if the xml failed to parse or is missing throw an error
        throw(ErrorException("XML missing or corrupted, aborting"))
    end
    root(xml)
end

make_uuid(uuid::String) = UUID(startswith(uuid, "urn:uuid:") ? uuid[10:end] : uuid)


"""
    load_master_xml(file::TiffFile) -> EzXML.doc

Loads the master OME-XML file from `file` or from a linked file.
"""
function load_master_xml(file::TiffFile)
    omexml = loadxml(file)
    # update the UUID of the file with the value from the OMEXML
    uuid_node = findfirst("/ns:OME/@UUID", omexml, ["ns"=>namespace(omexml)])
    if uuid_node !== nothing
        file.uuid = make_uuid(nodecontent(uuid_node))
    # if the file doesn't have a UUID attempt to match based on name attribute
    # of the Image element. This is often, though not guaranteed, where the
    # file's internal filename is stored. We need this to handle cases where the
    # file was renamed.
    else
        main_filename = nodecontent(findfirst("/ns:OME/ns:Image/@Name", omexml, ["ns"=>namespace(omexml)]))
        main_filename = basename(split(main_filename, ".ome.")[1])

        uuids = findall("/ns:OME//ns:TiffData/ns:UUID", omexml, ["ns"=>namespace(omexml)])
        
        plane_uuids = unique(nodecontent.(uuids))
        # if there's only one UUID mentioned in the XML then we'll assume it's
        # referring to the current file
        if length(plane_uuids) == 1
            uuid_node = first(uuids)
            if haskey(uuid_node, "FileName") 
                plane_filename = basename(split(uuid_node["FileName"], ".ome.")[1])
                if main_filename != plane_filename
                    @warn "TIFF planes refer to a nonexistent file. Proceeding "*
                    "with assumption that they refer to the current file."
                end
            end

            file.uuid = make_uuid(nodecontent(uuid_node))
        end
    end
    try
        # Check if the full OME-XML metadata is stored in another file
        metadata_file = findfirst("/ns:OME/ns:BinaryOnly", omexml, ["ns"=>namespace(omexml)])
        (metadata_file === nothing) && return omexml
        fileuuid, filepath = metadata_file["UUID"], joinpath(dirname(file.filepath), metadata_file["MetadataFile"])

        # we have a companion metadata file
        if endswith(filepath, ".companion.ome")
            xdoc = readxml(filepath)
            omexml = root(xdoc)
        else
            io = open(filepath)
            metadata_file = read(io, TiffFile)
            metadata_file.uuid = make_uuid(fileuuid)
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
        orig_file = read(f, TiffFile)
        omexml = load_master_xml(orig_file)
        prettyprint(io, omexml)
    end
    String(take!(io))
end

"""
    load_comments(file) -> String

Extracts the MicroManager embedded description, if present. Else returns an
empty string.
"""
function load_comments(file)
    seek(file, 24)
    comment_header = Int(read(file, UInt32))
    if comment_header != 99384722
        return ""
    end
    comment_offset = Int(read(file, UInt32))
    seek(file, comment_offset)
    comment_header = read(file, UInt32)
    comment_length = Int(read(file, UInt32))
    metadata_bytes = Array{UInt8}(undef, comment_length)
    read!(file, metadata_bytes)
    metadata = JSON.parse(String(metadata_bytes))
    if !haskey(metadata, "Summary")
        return ""
    end
    metadata["Summary"]
end