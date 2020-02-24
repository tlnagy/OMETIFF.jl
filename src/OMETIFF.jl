module OMETIFF

using Unitful
using AxisArrays
using EzXML
using FileIO
using JSON
using ImageCore
using ImageMetadata
using ImageShow
using DataStructures
using DocStringExtensions

include("utils.jl")
include("files.jl")
include("parsing.jl")
include("mmap.jl")
include("stream.jl")
include("loader.jl")

end # module
