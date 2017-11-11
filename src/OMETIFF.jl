module OMETIFF

__precompile__()

using Unitful
using AxisArrays
using FixedPointNumbers
using Colors
using EzXML
using FileIO
using DataStructures
using JSON
using ImageMetadata
using Images

include("utils.jl")
include("files.jl")
include("parsing.jl")
include("loader.jl")

end # module
