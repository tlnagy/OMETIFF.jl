module OMETIFF

__precompile__()

using Unitful
using AxisArrays
using FixedPointNumbers
using Colors
using EzXML
using FileIO

include("types.jl")
include("utils.jl")
include("parsing.jl")
include("loader.jl")

end # module
