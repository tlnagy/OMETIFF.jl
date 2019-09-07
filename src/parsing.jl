function getattribute(tiffdata::EzXML.Node, ::Type{Int}, attr::String)
    try
        parse(Int, tiffdata[attr])+1
    catch e
        (!isa(e, KeyError)) && rethrow(e)
        -1
    end
end

function getattribute(tiffdata::EzXML.Node, ::Type{Float64}, attr::String)
    try
        parse(Float64, tiffdata[attr])
    catch e
        (!isa(e, KeyError)) && rethrow(e)
        NaN
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
    # this is an offset value since multiple ifds can share the same index if
    # they are split across files, IFD1 (File1), IFD1 (File2), etc
    file_ifd_offset = 1
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
            # if this file isn't one we've observed before, increment the offset
            if !in(filepath, obs_filepaths)
                ifd = file_ifd_offset
                file_ifd_offset += 1
                push!(obs_filepaths, filepath)
            end
            ifd_files[ifd] = (uuid, filepath)
        end

        # get Z, C, T indices (in order specified by `dims`)
        indices = Tuple(getattribute(tiffdata, Int, "First$x") for x in keys(dims)[3:5])
        # how many ifds does this tiffdata correspond to
        p = getattribute(tiffdata, Int, "PlaneCount") - 1

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

"""
    get_unitful_axis(image, dimsize, stepsize, units)

Attempts to return a unitful axis with a length of `dimsize`. `stepsize` and
`units` should be the XML tags in `image`.
"""
function get_unitful_axis(image::EzXML.Node, dimsize::Int, stepsize::String, units::String)
    try
        # OME-XML stores the step size
        increment = parse(Float64, image[stepsize])

        # This is an ugly hack to convert the unit string into Unitful.Unit till
        # https://github.com/PainterQubits/Unitful.jl/issues/214 gets fixed
        unittype = @eval @u_str $(image[units])

        # Create a unitful range
        return 0*unittype:increment*unittype:increment*(dimsize-1)*unittype
    catch
        # alternatively, just return the bare unitless range
        return 1:dimsize
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

    vals = (
        X=get_unitful_axis(image, dims[:X], "PhysicalSizeX", "PhysicalSizeXUnit"),
        Y=get_unitful_axis(image, dims[:Y], "PhysicalSizeY", "PhysicalSizeYUnit"),
        Z=get_unitful_axis(image, dims[:Z], "PhysicalSizeZ", "PhysicalSizeZUnit"),
        C=to_symbol.(channel_names),
        T=get_unitful_axis(image, dims[:T], "TimeIncrement", "TimeIncrementUnit"),
        P=1
    )

    axes = [Axis{axis_name_mapping[key]}(vals[key]) for key in keys(dims)]

    dims, axes
end


"""
    get_elapsed_times(containers, master_dims, masteraxis; default_unit)

Extracts the actual acquisition times from the OME-XML data. Takes `containers`, a vector of the XML nodes
corresponding to the root of each image.
"""
function get_elapsed_times(containers::Vector{EzXML.Node}, master_dims::NamedTuple, masteraxis::Vector{Axis}; default_unit=Unitful.s)

    # get the used dims that aren't x or y (since each xy plane has one elapsed time)
    nonxydims = NamedTuple{Tuple(k for (k, v) in pairs(master_dims) if k != :X && k != :Y && v > 1)}(master_dims)
    elapsed_times = fill(NaN*default_unit, values(nonxydims))

    # OMETIFF stores the Z, T, C info for each plane in TheZ, TheT, and TheC attributes
    attrnames = ["The$k" for k in keys(nonxydims) if k != :P]
    didx = fill(1, length(nonxydims))

    # we have to track position independently since it isn't stored in the plane tags
    # get which index corresponds to position (usually it's last)
    posdim = findfirst(x->x==:P, keys(nonxydims))
    unitstr = string(default_unit)

    for (pos, container) in enumerate(containers)
        planes = findall("ns:Plane[@DeltaT]", container, ["ns"=>namespace(container)])

        for plane in planes
            for d in 1:length(didx)
                # if this is the position dimension, get it from the current Pixel object since it's
                # not stored in the plane itself
                if d == posdim
                    didx[d] = pos
                else
                    didx[d] = getattribute(plane, Int, attrnames[d])
                end
            end
            try
                unitstr = plane["DeltaTUnit"]
            catch
            end
            unittype = @eval @u_str $unitstr
            elapsed_times[didx...] = getattribute(plane, Float64, "DeltaT")*unittype
        end
    end
    used_axes = (masteraxis[i] for i in findall(x->x in keys(nonxydims), keys(master_dims)))
    AxisArray(elapsed_times, used_axes...)
end