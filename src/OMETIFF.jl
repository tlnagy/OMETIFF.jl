module OMETIFF

using Unitful
using Images
using AxisArrays
using EzXML

export loadtiff

include("types.jl")
include("utils.jl")
include("parsing.jl")
include("loader.jl")

end # module
