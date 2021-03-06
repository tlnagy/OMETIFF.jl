module OMETIFF

using Unitful
using AxisArrays
using EzXML
using FileIO
using JSON
using ImageCore
using ImageMetadata
using DataStructures
using DocStringExtensions

include("utils.jl")
include("files.jl")
include("parsing.jl")
include("mmap.jl")
include("loader.jl")

end # module
