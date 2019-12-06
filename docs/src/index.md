# I/O operations for OME-TIFF files in Julia with a focus on correctness

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
