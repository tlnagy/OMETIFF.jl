module OMETIFF

using Unitful
using AxisArrays
using FixedPointNumbers
using Colors
using EzXML

export loadtiff

include("types.jl")
include("utils.jl")
include("parsing.jl")
include("loader.jl")

end # module
