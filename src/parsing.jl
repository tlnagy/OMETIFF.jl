function parse_metadata(rawxml::String)
    xdoc = parsexml(rawxml)
    omexml = root(xdoc)

    image = findfirst(omexml, "/ns:OME//*[@SizeX]",["ns"=>namespace(omexml)])
    dims, axes = build_axes(image)

    order = get_ifd_order(omexml)

    Metadata(dims, axes, order, image["Type"])
end


"""
    get_ifd_order(omexml::EzXML.Node)

Constructs a 3xN array of the Z, C, T indices of each IFD, where N is the
number of IFDs in the TIFF file. Take the root node of the ome-xml file.
"""
function get_ifd_order(omexml::EzXML.Node)
    ifds = find(omexml, "/ns:OME/ns:Image//ns:TiffData", ["ns"=>namespace(omexml)])
    ifd_dims = Array{Int}(3, length(ifds))
    for node in ifds
        idx = parse(Int, node["IFD"])+1
        ifd_dims[1, idx] = parse(Int, node["FirstZ"])+1
        ifd_dims[2, idx] = parse(Int, node["FirstC"])+1
        ifd_dims[3, idx] = parse(Int, node["FirstT"])+1
    end
    ifd_dims
end


"""
    build_axes(omexml::EzXML.Node)

Returns an array of ints with dimension sizes and an array of `AxisArrays.Axis`
objects both in XYZCT order given the Pixels node of the OME-XML document
"""
function build_axes(image::EzXML.Node)
    dim_names = ["SizeX", "SizeY", "SizeZ", "SizeC", "SizeT"]
    dims = map(x->parse(Int, image[x]), dim_names)

    # extract channel names
    channel_names = content.(find(image, "ns:Channel/@Name", ["ns"=>namespace(image)]))

    time_axis = Axis{:time}(1:dims[5])
    try # attempt to build a more specific time axis
        # grab increment
        increment = parse(Float64, image["TimeIncrement"])
        # attempt to map the time units
        unittype = getfield(Unitful, Symbol(image["TimeIncrementUnit"]))

        time_axis = Axis{:time}((0:increment:increment*(dims[5]-1))*unittype)
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
