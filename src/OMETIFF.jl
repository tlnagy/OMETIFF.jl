module OMETIFF

__precompile__()

using Unitful
using AxisArrays
using FixedPointNumbers
using Colors
using EzXML
using FileIO
using JSON
using ImageMetadata
using ImageShow

include("utils.jl")
include("files.jl")
include("parsing.jl")
include("loader.jl")

end # module
