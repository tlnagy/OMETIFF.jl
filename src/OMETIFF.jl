module OMETIFF

using AxisArrays
using DataStructures
using DocStringExtensions
using EzXML
using FileIO
using ImageMetadata
using JSON
using ProgressMeter
using TiffImages: AbstractDenseTIFF, TiffFile, Iterable, IFD, 
                  IMAGEDESCRIPTION, load!, getcache, getstream, fixcolors
using Unitful
using UUIDs

include("utils.jl")
include("files.jl")
include("parsing.jl")
include("mmap.jl")
include("loader.jl")
include("omexml.jl")

end # module
