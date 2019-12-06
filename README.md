# OMETIFF.jl

| **Documentation**                 | **Build Status**                                              |
|:----------------------------------|:--------------------------------------------------------------|
| [![][docs-dev-img]][docs-dev-url] | [![][status-img]][status-url] [![][travis-img]][travis-url] [![][codecov-img]][codecov-url] |

Adds support for reading OME-TIFF files to the [Images.jl](https://github.com/JuliaImages/Images.jl)
platform. Allows fast and easy interfacing with high-dimensional data with nice
labeled axes provided by [AxisArrays.jl](https://github.com/JuliaImages/AxisArrays.jl).

## Features

- Can open a wide-range of OMETIFF files with a special focus on [correctness](https://github.com/tlnagy/OMETIFF.jl/blob/master/test/runtests.jl)
- Spatial and temporal axes are annotated with units if available (like μm, s, etc)
- Channel and position axes use their original names
- Elapsed times are extracted and returned using the same labeled axes
- Important metadata is extracted and included in an easy to access format

## Installation

`OMETIFF.jl` will be automatically installed when you use [FileIO](https://github.com/JuliaIO/FileIO.jl) to open an OME-TIFF file. You can also install it by running the following in the Julia REPL:

```julia
] add OMETIFF
```

## Usage

```julia
julia> using FileIO, Images

julia> img = load("/Users/tamasnagy/Downloads/66perc-h2o-vs-iso_1_MMStack.ome.tif")
Gray ImageMeta with:
  data: 4-dimensional AxisArray{Gray{N0f16},4,...} with axes:
    :y, 0.0 μm:0.6518 μm:666.7914000000001 μm
    :x, 0.0 μm:0.6518 μm:666.7914000000001 μm
    :time, 0.0 ms:15000.0 ms:405000.0 ms
    :position, Symbol[:A5_Site_0, :A5_Site_1, :B5_Site_0, :B5_Site_1]
And data, a 1024×1024×28×4 reshape(reinterpret(Gray{N0f16}, ::Array{UInt16,6}), 1024, 1024, 28, 4) with eltype Gray{Normed{UInt16,16}}
  properties:
    Elapsed_Times: Unitful.Quantity{Float64,𝐓,Unitful.FreeUnits{(s,),𝐓,nothing}}[2.525 s 3.35 s 5.638 s 6.534 s; 15.398 s 16.195 s 18.743 s 19.506 s; … ; 390.389 s 391.154 s 393.282 s 393.984 s; 405.391 s 406.13 s 408.316 s 409.101 s]
    Description: nd4 + nd8 in

julia> size(img) # lets get the dimensions
(1024, 1024, 28, 4)

julia> axisnames(img) # wait, but what do they correspond to?
(:y, :x, :time, :position)

julia> img[Axis{:position}(:A5_Site_1), Axis{:time}(2)]; # get the 2nd time point in position A5

julia> img["Elapsed_Times"][Axis{:position}(:A5_Site_1), Axis{:time}(2)] # get exact time when that slice was taken
16.195 s

julia> img["Description"] # get any notes embedded in the image
"nd4 + nd8 in"
```

### More advanced usage

The image updates all the axes as we subset it. Observe that since we're grabbing 5x5x1x1 subset of
the image, all the axes update to reflect this slice.

```julia
julia> using Unitful

julia> img[Axis{:y}(1:5), Axis{:x}(1:5), Axis{:time}(15000u"ms"), Axis{:position}(1)]
Gray ImageMeta with:
  data: 2-dimensional AxisArray{Gray{N0f16},2,...} with axes:
    :y, 0.0 μm:0.6518 μm:2.6072 μm
    :x, 0.0 μm:0.6518 μm:2.6072 μm
And data, a 5×5 Array{Gray{N0f16},2} with eltype Gray{Normed{UInt16,16}}
  properties:
    Elapsed_Times: Quantity{Float64,𝐓,Unitful.FreeUnits{(s,),𝐓,nothing}}[2.525 s 3.35 s 5.638 s 6.534 s; 15.398 s 16.195 s 18.743 s 19.506 s; … ; 390.389 s 391.154 s 393.282 s 393.984 s; 405.391 s 406.13 s 408.316 s 409.101 s]
    Description: nd4 + nd8 in
```

### Dumping embedded OME-XML

To quickly access the OME-XML stored inside a TIFF file, use the
`OMETIFF.dump_omexml` function:

```julia
julia> using OMETIFF

julia> println(OMETIFF.dump_omexml("test/testdata/singles/single-channel.ome.tif"))
<OME xmlns="http://www.openmicroscopy.org/Schemas/OME/2016-06" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" Creator="OME Bio-Formats 5.2.2" UUID="urn:uuid:2bc2aa39-30d2-44ee-8399-c513492dd5de" xsi:schemaLocation="http://www.openmicroscopy.org/Schemas/OME/2016-06 http://www.openmicroscopy.org/Schemas/OME/2016-06/ome.xsd">
  <Image ID="Image:0" Name="single-channel.ome.tif">
    <Pixels BigEndian="true" DimensionOrder="XYZCT" ID="Pixels:0" SizeC="1" SizeT="1" SizeX="439" SizeY="167" SizeZ="1" Type="int8">
      <Channel ID="Channel:0:0" SamplesPerPixel="1">
        <LightPath/>
      </Channel>
      <TiffData FirstC="0" FirstT="0" FirstZ="0" IFD="0" PlaneCount="1">
        <UUID FileName="single-channel.ome.tif">urn:uuid:2bc2aa39-30d2-44ee-8399-c513492dd5de</UUID>
      </TiffData>
    </Pixels>
  </Image>
</OME>
```


[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://tamasnagy.com/OMETIFF.jl/dev

[travis-img]: https://travis-ci.org/tlnagy/OMETIFF.jl.svg?branch=master
[travis-url]: https://travis-ci.org/tlnagy/OMETIFF.jl

[codecov-img]: https://codecov.io/gh/tlnagy/OMETIFF.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/tlnagy/OMETIFF.jl

[status-img]: https://www.repostatus.org/badges/latest/active.svg
[status-url]: https://www.repostatus.org/#active
