# Internals

Documentation for all non-exported functions can be found below:

## Common

```@docs
OMETIFF.load
OMETIFF.dump_omexml
```

## Types

```@docs
OMETIFF.IFD
OMETIFF.TiffFile
```

## Logic

These are the key logic functions that work through the OME and TIFF data and
determine the mapping between these two. Future changes to the OME specification
should be handle in these functions.

```@docs
OMETIFF.ifdindex!
OMETIFF.get_ifds
OMETIFF.build_axes
```

## Construction

```@docs
OMETIFF.inmemoryarray
```


## Miscellaneous

```@docs
Base.iterate
OMETIFF.get_elapsed_times
OMETIFF.get_unitful_axis
OMETIFF.load_comments
OMETIFF.load_master_xml
OMETIFF.to_symbol
```