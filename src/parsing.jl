function read_tiffdatas(orig_file::TiffFile, images::Vector{EzXML.Node})
    # tiffdatas = DefaultDict{String, Vector{TiffData}}(Vector{TiffData}())

    # for (img_idx, image) in enumerate(images)
    #     tiffdataxml = findall(".//ns:TiffData", image, ["ns"=>namespace(image)])

    #     for item in tiffdataxml
    #         filepath, tiffdata = read_tiffdata(orig_file, item, img_idx)
    #         push!(tiffdatas[filepath], tiffdata)
    #     end
    # end
    # tiffdatas
end


"""
    read_tiffdata(orig_file, tiffdata)

Reads the XML corresponding to a TiffData entry and generates an `TiffData` object from it.
"""
function read_tiffdata!(ifds::OrderedDict{NTuple{4, Int}, IFD},
                        tiffdata::EzXML.Node,
                        files::Dict{String, TiffFile},
                        orig_file::TiffFile)


    uuid_node = findfirst("./ns:UUID", tiffdata, ["ns"=>namespace(tiffdata)])
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
end

function getattribute(tiffdata::EzXML.Node, attr::String)
    try
        parse(Int, tiffdata[attr])+1
    catch e
        (!isa(e, KeyError)) && rethrow(e)
        -1
    end
end

"""
    ifdindex!(ifds, image, dims, imageidx)

Update the master ifd index list, `ifds`, using the TiffData's in `image`.
`dims` is a NamedTuple of the size of each dimension of `image` in the order
specified by the `DimensionOrder` parameter. `imageidx` is positive integer
corresponding to the index of the current image in the OME-TIFF file.

When we read the `TiffFile` we'll know what indices in the 6D matrix each IFD
belongs to.
"""
function ifdindex!(ifd_index::Array{Union{NTuple{4, Int}, Nothing}},
                   ifd_files::Array{Union{Tuple{String, String}, Nothing}},
                   obs_filepaths::Set{String},
                   image::EzXML.Node,
                   dims::NamedTuple,
                   filepath::String,
                   imageidx::Int)

    tiffdatas = findall(".//ns:TiffData", image, ["ns"=>namespace(image)])

    ifd = 1
    pos = 1
    for tiffdata in tiffdatas
        try # if this tiffdata specifies the corresponding IFD
            ifd = parse(Int, tiffdata["IFD"]) + 1
        catch
            ifd = 1
        end

        uuid_node = findfirst("./ns:UUID", tiffdata, ["ns"=>namespace(tiffdata)])
        if uuid_node != nothing
            uuid = nodecontent(uuid_node)
            filepath = joinpath(dirname(filepath), uuid_node["FileName"])
            if !in(filepath, obs_filepaths)
                ifd = pos
                pos += 1
                push!(obs_filepaths, filepath)
            end
            ifd_files[ifd] = (uuid, filepath)
        end

        # get Z, C, T indices (in order specified by `dims`)
        indices = Tuple(getattribute(tiffdata, "First$x") for x in keys(dims)[3:5])
        # how many ifds does this tiffdata correspond to
        p = getattribute(tiffdata, "PlaneCount") - 1

        # if none of the Z, C, T indices are specified then we'll assume the
        # indices starting with the inner dimension, etc
        if all(indices .< 0)
            # index in the master ifd list
            idx = ifd
            # reverse iterate since we cycle the inner dimension the most
            for k=1:dims[5], j=1:dims[4], i=1:dims[3]
                ifd_index[idx] = (i, j, k, imageidx)
                ifd_files[idx] = nothing
                # if this tiffdata applies to multiple ifds then check that we
                # don't exceed the specified number of ifds
                (p > 1 && idx >= p+ifd-1) && break
                idx += 1
            end
        # if any of the indices are specified in the tiffdata then use these
        else
            indices = (indices..., imageidx) # add the position index
            # all the indices that are not specified, we assume the first index
            ifd_index[ifd] = Tuple(pos > 0 ? pos : 1 for pos in indices)

        end
    end
end


const axis_name_mapping = (X = :x, Y = :y, Z=:z, T=:time, C=:channel, P=:position)
"""
    build_axes(omexml::EzXML.Node)

Returns an array of ints with dimension sizes and an array of `AxisArrays.Axis`
objects both in XYZCT order given the Pixels node of the OME-XML document
"""
function build_axes(image::EzXML.Node)
    order = "YX"*join(replace(split(image["DimensionOrder"], ""), "X"=>"", "Y"=>""))
    order = Tuple(Symbol(dim) for dim in order)
    dims = NamedTuple{order, NTuple{5, Int}}(Tuple(parse(Int, image["Size$(x)"]) for x in order))
    dims = merge(dims, [:P=>1])

    # extract channel names
    channel_names = nodecontent.(findall("ns:Channel/@Name", image, ["ns"=>namespace(image)]))
    if isempty(channel_names)
        channel_names = ["C$x" for x in 1:dims[:C]]
    end

    time_axis = 1:dims[:T]
    try # attempt to build a more specific time axis
        # grab increment
        increment = parse(Float64, image["TimeIncrement"])
        # attempt to map the time units
        unittype = getfield(Unitful, Symbol(image["TimeIncrementUnit"]))

        time_axis = Unitful.upreferred.((0:increment:increment*(dims[5]-1))*unittype)
    catch
    end

    vals =  (X=1:dims[:X], Y=1:dims[:Y], Z=1:dims[:Z], C=to_symbol.(channel_names), T=time_axis, P=1)

    axes = [Axis{axis_name_mapping[key]}(vals[key]) for key in keys(dims)]

    dims, axes
end
