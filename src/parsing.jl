"""
An ImageSlice struct contains all the information from a TiffData element in
the OME-XML.
"""
struct ImageSlice
    """A pointer to the file containing this slice"""
    file::TiffFile

    """The IFD this slice corresponds to in the file"""
    ifd_idx::Int

    """The index of this slice in the Z stack"""
    z_idx::Int

    """The index of this slice in the time dimension"""
    t_idx::Int

    """The index of this slice in the channel dimension"""
    c_idx::Int

    """
    The number of ifds that slice applies to. The information within this object
    will be mapped to IFDs from `ifd_idx` to `ifd_idx`+`num_ifds`-1.
    """
    num_ifds::Int
end



"""
    read_tiffdata(tiffdata::EzXML.Node, files::Dict{String, TiffFile}, orig_file::TiffFile)

Reads a Tiff Data entry and generates an ImageSlice object from it. Keeps track of all relevant
files.
"""
function read_tiffdata(tiffdata::EzXML.Node, files::Dict{String, TiffFile}, orig_file::TiffFile)
    ifd = parse(Int, tiffdata["IFD"])+1
    z = parse(Int, tiffdata["FirstZ"])+1
    t = parse(Int, tiffdata["FirstT"])+1
    c = parse(Int, tiffdata["FirstC"])+1
    p = parse(Int, tiffdata["PlaneCount"])

    uuid_node = findfirst(tiffdata, "./ns:UUID", ["ns"=>namespace(tiffdata)])
    uuid = nodecontent(uuid_node)
    filepath = joinpath(dirname(orig_file.filepath), uuid_node["FileName"])

    # if this file has already been encounter than just find the reference
    if haskey(files, filepath)
        file_ptr = files[filepath]
    elseif filepath == orig_file.filepath
        file_ptr = orig_file
        files[orig_file.filepath] = orig_file
    else
        file_ptr = TiffFile(uuid, filepath)
        files[filepath] = file_ptr
    end

    ImageSlice(file_ptr, ifd, z, t, c, p)
end


"""
    build_axes(omexml::EzXML.Node)

Returns an array of ints with dimension sizes and an array of `AxisArrays.Axis`
objects both in XYZCT order given the Pixels node of the OME-XML document
"""
function build_axes(image::EzXML.Node)
    dim_names = ["SizeY", "SizeX", "SizeZ", "SizeC", "SizeT"]
    dims = map(x->parse(Int, image[x]), dim_names)

    # extract channel names
    channel_names = nodecontent.(find(image, "ns:Channel/@Name", ["ns"=>namespace(image)]))
    if isempty(channel_names)
        channel_names = ["C$x" for x in 1:dims[4]]
    end

    time_axis = Axis{:time}(1:dims[5])
    try # attempt to build a more specific time axis
        # grab increment
        increment = parse(Float64, image["TimeIncrement"])
        # attempt to map the time units
        unittype = getfield(Unitful, Symbol(image["TimeIncrementUnit"]))

        time_axis = Axis{:time}(Unitful.upreferred.((0:increment:increment*(dims[5]-1))*unittype))
    end

    axes = [
        Axis{:y}(1:dims[1]),
        Axis{:x}(1:dims[2]),
        Axis{:z}(1:dims[3]),
        Axis{:channel}(to_symbol.(channel_names)),
        time_axis
    ]

    dims, axes
end
