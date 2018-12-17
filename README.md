# Julia-ICARTT

A Julia package for reading ICARTT files.

## Fair use policy

By using this code in your research you agree to the following terms in addition to the terms of reuse given in the license:

  1. Only the master branch is considered stable. All other branches are under development, subject to change,
     and are not recommended for scientific use.
  1. We do our best to ensure that the master branch is bug-free and scientifically sound. However, we cannot test all
     possible use cases. The user is ultimately responsible for ensuring that any results obtained using this code are
     scientifically accurate.
  1. If you wish to make a modified version of this code publicly available, you may do so, provided that clear attribution
     to this repository is provided. The preferred method is to create a fork on GitHub and make that fork publicly available.
     If that is not possible, the statement "This code is adapted from Julia-JLLUtils, available at 
     https://github.com/joshua-laughner/Julia-ICARTT" must be included in a README file in the modified copy.

## First steps

The main purpose of this package is to read data from ICARTT files. ICARTT is a standardized format for storing atmospheric
data taken during aircraft campaigns, starting with the International Consortium for Atmospheric Research on Transport and Transformation
campaign in 2004. For more information, see https://earthdata.nasa.gov/user-resources/standards-and-references/icartt-file-format.

To read an ICARTT file named "example.ict" in the current directory:

```
using ICARTT.ReadICARTT; # will bring read_icartt_file() into this namespace
ict = read_icartt_file("example.ict");
```

`ict` will be a `ICARTT.ReadICARTT.AirMerge` structure with fields `metadata` and `data`. `data` contains individual variables
from the ICARTT file in an ordered dictionary. Each value in the `data` dictionary will be a `ICARTT.ReadICARTT.MergeDataField`
struct. Data points are stored as an array of Float64 [Unitful](http://ajkeller34.github.io/Unitful.jl/stable/). Quantity values
in the `values` field.

The `values` field will still have fill values, ULOD flags, and LLOD flags in it. To remove this, we provide a utility function
`get_merge_data`:

```
using ICARTT.ICARTTUtils;
wnd = get_merge_data(ict, "WND");
```

Assuming your ICARTT file has a variable named "WND" this will return the array of values for that variable with fills and LOD 
flags replaced with NaNs (`missing` values are currently incompatible with Unitful).

## Limitations

* The ICARTT format does not specify a standard set of units to use, therefore it is likely that you will have some units that
  this package does not automatically recognize in your ICARTT file. We hope to have a mechanism to allow easy aliasing of units
  in the ICARTT file to units understood by Unitful.
* We expect that ICARTT files from campaigns that we do not use in our research may contain subtle differences that this package
  does not expect. If you encounter such a problem, please open an issue on the [GitHub page](https://github.com/joshua-laughner/Julia-ICARTT)
  and attach or link to the offending ICARTT file.
