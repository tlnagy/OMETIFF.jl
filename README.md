# OMETIFF.jl


| PackageEvaluator  | Master Status  | Code coverage  |
|:--|:--|:--|
|  [![OMETIFF](http://pkg.julialang.org/badges/OMETIFF_0.6.svg)](http://pkg.julialang.org/detail/OMETIFF) | [![Build Status](https://travis-ci.org/tlnagy/OMETIFF.jl.svg?branch=master)](https://travis-ci.org/tlnagy/OMETIFF.jl)  | [![codecov.io](http://codecov.io/github/tlnagy/OMETIFF.jl/coverage.svg?branch=master)](http://codecov.io/github/tlnagy/OMETIFF.jl?branch=master)  |

Adds support for reading OME-TIFF files to the [Images.jl](https://github.com/JuliaImages/Images.jl)
platform. Allows fast and easy interfacing with high-dimensional data with nice
labeled axes provided by [AxisArrays.jl](https://github.com/JuliaImages/AxisArrays.jl).

![](screenshot.png)

## Installation

`OMETIFF.jl` will be automatically installed when you use [FileIO](https://github.com/JuliaIO/FileIO.jl) to open an OME-TIFF file. You can also install it by running the following in the Julia REPL:

```julia
Pkg.add("OMETIFF")
```

## Usage

```julia
Pkg.checkout("FileIO") # we need the bleeding edge version of FileIO.jl for now
using FileIO
img = load("path/to/ome.tif") # FileIO will install OME-TIFF upon running this command
println(axisnames(img))
println(axisvalues(img))
```

```
(:y, :x, :channel, :time)
(1:1024, 1:1024, Symbol[:_561_CF, :Conf_DIA], 0.0 ms:10000.0 ms:290000.0 ms)
```
