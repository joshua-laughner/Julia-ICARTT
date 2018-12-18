module ReadICARTT

import DataStructures: OrderedDict;
using Dates;
using Unitful;

using ..ICARTTUnits;
using ..ICARTTExceptions: ICARTTParsingException, ICARTTNotImplementedException;

export read_icartt_file;

##############
# Exceptions #
##############

_no_default(name) = error("$name is a required argument");

"""
    _HeaderField(fields, readfxn)

A struct used internally to decribed how to read a field in the ICARTT header,
before the "bulk" part. `fields` must be a tuple of strings that are the key(s)
in the metadata dict to store the value(s). `readfxn` must be a function that,
given the line read in from the ICARTT file, parses it and returns the value(s)
to store. The number of values stored must equal the number of fields, i.e. in:

```
julia> _HeaderField(("Acquisition_date", "Processing_date"), _icartt_read_data_dates)
```

`_icartt_read_data_dates` must return two values; the first is stored in the metadata
dict under "Acquisition_date" and the second under "Processing_date". This is
how you handle when multiple pieces of information are defined on one line.
"""
struct _HeaderField
    fields::Tuple
    readfxn::Function
end

"""
    MergeDataField{T <: Unitful.Quantity}(name, unit, fill, scale, values)

This struct is used to represent the data in the ICARTT file. It has fields "name",
"unit", "fill", "scale", and "values".

    * "name" is the name of the variable, as a String
    * "unit" is the units of the variable, as a Unitful.Units instance
    * "fill" is the fill value of the variable, as a Float
    * "scale" is the scale factor of the variable, as a Float
    * "values" is a 1D array with elements of type T. It is required that T be
      a child of Unitful.Quantity; this enforces keeping the units of the measurements
      with them.

This struct has both positional and named constructors for clarity., e.g. the two
methods will create the same struct:
```
julia> MergeDataField("Altitude", u"m", -999999.0, 1.0, Array{1.0u"m", 1}(...))
julia> MergeDataField(name="Altitude", unit=u"m", fill=-999999.0, scale=1.0, values=Array{1.0u"m", 1}(...))
```
Note however that the two cannot be mixed and matched.
"""
struct MergeDataField{T <: Unitful.Quantity}
    name::String;
    unit::Unitful.Units;
    fill::Float64;
    scale::Float64;
    values::Array{T, 1};  # in theory, I think the type could be inferred from "unit"
    MergeDataField(name, unit, fill, scale, values::Array{T,1}) where T <: Unitful.Quantity = new{T}(name, unit, fill, scale, values);
    MergeDataField(;name=_no_default("name"), unit=_no_default("unit"), fill=_no_default("fill"),
                    scale=_no_default("scale"), values::Array{T,1}=_no_default("values")) where T <: Unitful.Quantity = new{T}(name, unit, fill, scale, values);
end

"""
    AirMerge(data, metadata)

A struct that represents a whole ICARTT file. `data` is the ordered dict of data
fields returned by `_read_icartt_data` and `metadata` the ordered dict of metadata
returned by `_read_icartt_metadata`.
"""
struct AirMerge
    data::OrderedDict{String, MergeDataField};
    metadata::OrderedDict{String, Any};
end

"""
    _icartt_read_simple(line)

Function to read in header line that needs no conversion except to be returned
in a tuple so that indexing the returned result gives the whole line.
"""
function _icartt_read_simple(line)
    return (line,)
end

"""
    _icartt_read_data_dates(line)

Specialized function to read the two data dates from the ICARTT header. Since both
the acquisition and processing dates are given on the same line, this separates them
and returns two separate `Date` structs.
"""
function _icartt_read_data_dates(line)
    acq_yr, acq_mn, acq_day, proc_yr, proc_mn, proc_dy = _split_icartt_line(line)
    acq_date = Date("$acq_yr-$acq_mn-$acq_day", "y-m-d")
    proc_date = Date("$proc_yr-$proc_mn-$proc_dy", "y-m-d")
    return acq_date, proc_date
end

#############
# Constants #
#############

# Define the line numbers on which each of these pieces of information should
# be. This is only for the one-line pieces of information; multiline pieces are
# handled by their own custom functions.
const _ICARTT_HDR_PI = 2
const _ICARTT_HDR_PI_AFFIL = _ICARTT_HDR_PI + 1
const _ICARTT_HDR_DESCRIPTION = _ICARTT_HDR_PI_AFFIL + 1
const _ICARTT_HDR_MISSION = _ICARTT_HDR_DESCRIPTION + 1
const _ICARTT_HDR_FILE_VOL_NUM = _ICARTT_HDR_MISSION + 1
const _ICARTT_HDR_DATA_UTC_DATES = _ICARTT_HDR_FILE_VOL_NUM + 1
const _ICARTT_HDR_DATA_INTERVAL_SEC = _ICARTT_HDR_DATA_UTC_DATES + 1
const _ICARTT_HDR_INDEPENDENT_VAR = _ICARTT_HDR_DATA_INTERVAL_SEC + 1
const _ICARTT_HDR_N_VAR = _ICARTT_HDR_INDEPENDENT_VAR + 1
const _ICARTT_HDR_SCALE_FACTORS = _ICARTT_HDR_N_VAR + 1
const _ICARTT_HDR_FILL_VALS = _ICARTT_HDR_SCALE_FACTORS + 1
const _ICARTT_HDR_START_HEADER_BULK = _ICARTT_HDR_FILL_VALS + 1

# This dictionary maps the line number to the piece of information it contains.
# See the HeaderField struct docstring for more info.
_ICARTT_HDR_SPECIALS = Dict(
    _ICARTT_HDR_PI => _HeaderField(("PI",), _icartt_read_simple),
    _ICARTT_HDR_PI_AFFIL => _HeaderField(("PI_affiliation",), _icartt_read_simple),
    _ICARTT_HDR_DESCRIPTION => _HeaderField(("Data_description",), _icartt_read_simple),
    _ICARTT_HDR_MISSION => _HeaderField(("Mission",), _icartt_read_simple),
    _ICARTT_HDR_DATA_UTC_DATES => _HeaderField(("Acquisition_date", "Processing_date"), _icartt_read_data_dates),
    _ICARTT_HDR_DATA_INTERVAL_SEC => _HeaderField(("Data_interval",), _icartt_read_simple),
    _ICARTT_HDR_INDEPENDENT_VAR => _HeaderField(("Independent_variable",), _icartt_read_simple),
)

# This tuple lists the categories of information expected in the normal comments
# section. These will be used in a regular expression, so regex wildcards can be
# used.
_ICARTT_NORMAL_COMMENTS = ("PI_CONTACT_INFO", "PLATFORM", "LOCATION", "ASSOCIATED_DATA",
                           "INSTRUMENT_INFO", "DATA_INFO", "UNCERTAINTY",
                           "ULOD_FLAG", "ULOD_VALUE", "LLOD_FLAG", "LLOD_VALUE",
                           "DM_CONTACT_INFO", "PROJECT_INFO", "STIPULATIONS_ON_USE",
                           "OTHER_COMMENTS", "REVISION", "R\\d+");


"""
    read_icartt_file(filename::String; extra_aliases=nothing, extra_alias_files=nothing, alias_dict_overwrite=false, no_default_aliases=false, verbose=0)

Reads data files formatted to the ICARTT standard defined at
https://www-air.larc.nasa.gov/missions/etc/IcarttDataFormat.htm
and
https://cdn.earthdata.nasa.gov/conduit/upload/6158/ESDS-RFC-029v2.pdf
Returns an `AirMerge` structure containing the ICARTT metadata and data.

`verbose` controls the level of printing to the console, for debugging purposes.
Set to higher numbers to give more information.

The data from the ICARTT file is stored as arrays of Unitful `Quantity`s that
combine the value and unit from the file. The helps ensure that calculations
don't miss conversion factors, but requires that the units defined in the ICARTT
header are written in a way that Unitful can understand. To aid that, the units
are reformatted by `ICARTTUnits.sanitize_raw_unit_strings()`. One of the steps
it takes is to replace undefined units with their Unitful equivalent. What units
it replaces are defined by the alias dictionary, which can be modified by the
following keyword arguments.

`no_default_aliases` will eliminate the default aliases defined in `ICARTTUnits`.

`extra_aliases`, `extra_alias_files`, and `alias_dict_overwrite` allow you to
specify additional unit aliases.

An example is when time is given in units of "hours"; Unitful can't understand
"hours" so we need to replace it with the abbreviation that it does understand,
"hr". This function has three ways to specify what unit strings should be
replaced:

1. ICARTT.ICARTTUnits has some built-in aliases. These are stored in the
   dictionary `ICARTT.ICARTTUnits.unit_aliases`, or can be printed by
   `ICARTT.ICARTTUnits.list_default_unit_aliases()`. You can modify this
   dictionary to add new units globally, though this is not the recommended
   method. The format of the dictionary is the same
2. Pass as `extra_aliases` a dictionary that defines the desired units as the keys
   as the strings that should be replaced in arrays as the values. That is the
   following dict would define replacing "hour" with "hr" and any of "deg", "degs",
   or "Degs" with "°":

```
   extra_aliases = Dict("hr" => ["hour"], "°" => ["deg", "degs", "Degs"]);
```

   Note that the behavior when one of the units defined in the `extra_aliases` is
   already defined depends on the value of `alias_dict_overwrite`. If it is `false`
   (default), the definitions in `extra_aliases` are added to any existing definitions.
   If `true`, then existing definitions are replaced. For example, the default
   aliases include one to replace "nanometers" with "nm". If

```
   extra_aliases = Dict("nm" => "nanometres")
```

   i.e. it uses the British spelling, then with `alias_dict_overwrite = false`,
   both "nanometers" and "nanometres" will be replaced by "nm". If `alias_dict_overwrite = true`,
   then *only* "nanometres" will be replaced.

3. Pass names of one or more text files that describe the same mapping as the
   dictionary as `extra_alias_files`. May pass a single file as a string, or more
   than one as an array of strings. The format of these files is:

```
   replace with: to replace[, to replace[, to replace]][: {replace,append}]
```

   Each line is the same as a key-value pair in the `extra_aliases` dictionary.
   The standard aliases are defined in such a file, the first few lines are:


   °: degs, deg, Degs
   hr: hour
   percent: %
   std_m: std m
   nm: nanometers
   : #


   This says to replace "degs", "deg", or "Degs" with "°", "hour" with "hr", and so
   on. Note that "std m" (including the space) gets replaced with "std_m", and "#"
   with nothing. For both the strings to replace and to replace them with, spaces
   inside of letters matter, so e.g. in "std m" even though the full string between
   the colon and comma is " std m", the leading (and if applicable, trailing) spaces
   are stripped.

   For your text files, the final "append" or "replace" after an optional second
   colon controls what happens if your file declares aliases for a unit that already
   had aliases. If your file had a line:

```
   °: degree, degrees
```

   then any of "degs", "deg", "Degs", "degree", or "degrees" would be replaced
   with "°" (the first three from the defaults, the last two from your file). If
   instead the line was:

```
   °: degree, degrees : replace
```

   then *only* "degree" and "degrees" would be replaced with "°". This allows you
   to override defaults selectively. Note that the order you pass the files in
   matters. If you had two files:

```
   # File A.txt:
   °: degree, degrees : replace

   # File B.txt:
   °: Deg
```

   then passing `extra_alias_files=["File A.txt", "File B.txt"]` would mean that
   "degree", "degrees", and "Deg" would all be replaced by "°", while
   `extra_alias_files=["File B.txt", "File A.txt"]` means *only* "degree" and
   "degrees" get replaced by "°" - the replace line in File A wipes out the
   corresponding line in File B as well as the defaults.
"""
function read_icartt_file(filename::String; extra_aliases=nothing, extra_alias_files=nothing,
        alias_dict_overwrite=false, no_default_aliases=false, verbose=0)
    metadata, data = open(filename, "r") do io
        metadata, variable_info = _read_icartt_metadata(io; extra_aliases=extra_aliases,
            extra_alias_files=extra_alias_files, alias_dict_overwrite=alias_dict_overwrite,
            no_default_aliases=no_default_aliases, verbose=verbose);
        data = _read_icartt_data(io, variable_info; verbose=verbose);
        return metadata, data
    end
    return AirMerge(data, metadata);
end

"""
    _read_icartt_metadata(io::IO; extra_aliases=nothing, extra_alias_files=nothing, alias_dict_overwrite=false, no_default_aliases=false, verbose=0)

Given a handle to an open ICARTT file (`io`), reads in the metadata in the header
of the file and returns it as a dictionary. Note that this assumes that the file
pointed to by `io` has been opened, but nothing read from it (or that the position
of the IO cursor has been returned to the start of the file).

`verbose` controls the level of printing to the console, for debugging purposes.
Set to higher numbers to give more information.

See `read_icartt_file` for a description of `extra_aliases`, `extra_alias_files`,
and `alias_dict_overwrite`.
"""
function _read_icartt_metadata(io::IO; extra_aliases=nothing, extra_alias_files=nothing, alias_dict_overwrite=false, no_default_aliases=false, verbose=0)
    if verbose > 0
        println("Reading metadata")
    end

    metadict = OrderedDict{String, Any}();
    aliases_dict = _setup_unit_aliases(extra_aliases, extra_alias_files; dict_overwrite=alias_dict_overwrite, no_default_aliases=no_default_aliases, verbose=verbose);

    # read the first line to get the number of lines in the header and the file format index
    n_header_lines, ffi = _split_icartt_line(readline(io));
    n_header_lines = parse(Int64, n_header_lines);
    metadict["file_format_index"] = ffi;

    # now read in the rest of the header lines
    n_line = 2;
    bulk_mode = "variable_names";
    # init variables to be set in the if statement due to scoping rules
    n_var = nothing;
    scale_factors = nothing;
    fill_values = nothing;
    variables = nothing;
    table_header = nothing;

    while n_line <= n_header_lines
        if n_line < _ICARTT_HDR_START_HEADER_BULK
            # While we're in the initial part of the header, where there is one
            # piece of information per line, we read in each line first, then
            # decide what to do with it.
            line = readline(io);
            if verbose > 1
                println("Read line: $line")
            end

            # since ICARTT isn't a fully self-describing format, we have to hard-code
            # some of the meanings of the header elements.
            if n_line in keys(_ICARTT_HDR_SPECIALS)
                # Deal with the one-line header information fields that we save into
                # the metadata.
                fields = _ICARTT_HDR_SPECIALS[n_line].fields;
                readfxn = _ICARTT_HDR_SPECIALS[n_line].readfxn;
                values = readfxn(line);
                for i_val = 1:length(fields)
                    metadict[fields[i_val]] = values[i_val];
                end
            elseif n_line == _ICARTT_HDR_N_VAR
                n_var = parse(Int64, line);
            elseif n_line == _ICARTT_HDR_SCALE_FACTORS
                scale_factors = _split_icartt_array(Int64, line);
            elseif n_line == _ICARTT_HDR_FILL_VALS
                fill_values = _split_icartt_array(Float64, line);
            else
                if verbose > 0
                    println("ICARTT parsing: ignoring line $n_line ($line)");
                end
            end

            n_line += 1;
        else
            # Once we get into what I call the "bulk" part of the header, where
            # information for one particular category is spread across multiple
            # lines, it makes more sense to let the subfunctions handle reading
            # the lines, since it's cleaner to let them determine how many
            # lines to read.
            if bulk_mode == "variable_names";
                if verbose > 0
                    println("Reading variables");
                end
                variables, n_line = _parse_variable_names(io, n_var, n_line; aliases_dict=aliases_dict, verbose=verbose);
                bulk_mode = "special_comments";

            elseif bulk_mode == "special_comments"
                if verbose > 0
                    println("Reading special comments");
                end
                metadict["Special_comments"], n_line = _parse_special_comments(io, n_line);
                bulk_mode = "normal_comments";

            elseif bulk_mode == "normal_comments"
                if verbose > 0
                    println("Reading normal comments");
                end
                comments, table_header, n_line = _parse_normal_comments(io, n_line);
                metadict = merge(metadict, comments);
                bulk_mode == "complete";

            elseif bulk_mode == "complete"
                throw(ICARTTParsingException("Still trying to parse the header,
                but have already finished parsing the last section (normal comments)"));

            else
                throw(ICARTTNotImplementedException("No behavior defined for
                bulk_mode = '$bulk_mode'"));
            end
        end
    end

    # Almost done. The last three things we want to do are 1) merge the lists of
    # scale factors and fill values into the array of descriptive tuples,
    # 2) insert the primary variable into the front of the list of variables and
    # their units, then 3) check that the list of variables matches the table header.
    variables = _merge_variable_info(variables, fill_values, scale_factors)

    temp_tup = _parse_variable(metadict["Independent_variable"]);
    primary_unit_tup = (field=temp_tup.field, unit=temp_tup.unit, fill=NaN, scale=1.0)
    splice!(variables, 1:0, [primary_unit_tup]);

    _check_variables_vs_header(variables, table_header);

    return metadict, variables
end

"""
    _read_icartt_data(io::IO, variable_info; verbose=0)

Reads the data table section of an ICARTT file, given a handle to an open ICARTT
file (`io`) and an array of named tuples (`variable_info`) describing the
name ("field", String), unit ("unit", Unitful.Units), fill value ("fill", Float),
and scale factor ("scale", Float) of each variable, in order.

`verbose` controls the level of printing to the console, for debugging purposes.
Set to higher numbers to give more information.

Returns a dictionary with String keys (variable names) and MergeDataField values.
"""
function _read_icartt_data(io::IO, variable_info; verbose=0)
    # go ahead and read in the rest of the data. we can use this to figure
    # out the array length to preallocate
    if verbose > 0
        println("Reading data.")
    end

    table_lines = [_split_icartt_array(Float64, l) for l in readlines(io)];
    n_meas = length(table_lines);
    # setup a dict of the final structs to receive the data
    data = OrderedDict{String, MergeDataField}();

    for (i, info) in enumerate(variable_info)
        data_array = Array{typeof(Unitful.Quantity(1.0,info.unit)), 1}(undef, n_meas);
        if verbose > 1
            println("Reading variable #$i: $(info.field) $(info.unit)")
        end
        for j = 1:n_meas
            data_array[j] = Unitful.Quantity(table_lines[j][i], info.unit);
        end

        data[info.field] = MergeDataField(name=info.field,
                                          unit=info.unit,
                                          fill=info.fill,
                                          scale=info.scale,
                                          values=data_array);
    end

    return data;
end

#####################
# Utility functions #
#####################

"""
    _split_icartt_line(line)

Split a line in an ICARTT file into an array of strings. Assumes that separate
values are separated by commas, and automatically strips whitespace from each
component.
"""
function _split_icartt_line(line)
    return [strip(s) for s in split(line, ",")];
end

"""
    _split_icartt_array(T, line)

Takes a line of an ICARTT file (`line`) and converts it to an array of type `T`
using _split_icartt_line to separate distinct values.
"""
function _split_icartt_array(T, line)
    return [parse(T, s) for s in _split_icartt_line(line)];
end

"""
    _setup_unit_aliases(extra_aliases::Nothing, extra_alias_files; dict_overwrite=false, no_default_aliases=false, verbose=0)
    _setup_unit_aliases(extra_aliases::AbstractDict, extra_alias_files::Nothing; dict_overwrite=false, no_default_aliases=false, verbose=0)
    _setup_unit_aliases(extra_aliases::AbstractDict, extra_alias_files::AbstractString; dict_overwrite=false, no_default_aliases=false, verbose=0)
    _setup_unit_aliases(extra_aliases::AbstractDict, extra_alias_files::AbstractArray; dict_overwrite=false, no_default_aliases=false, verbose=0)

Combine the standard unit aliases dictionary with additional configuration files
and/or an additional dictionary. The different methods handle different cases;
if no extra dictionary is desired, pass `nothing` for `extra_aliases`. If no
additional alias files desired, pass `nothing` for `extra_alias_files` as well.
Otherwise, `extra_alias_files` can be a string or array of strings.

`dict_overwrite` will cause entries in the `extra_aliases` to override those
defined in the defaults or the extra files. `no_default_aliases` will omit the
predefined aliases from the mapping.
"""
function _setup_unit_aliases(extra_aliases::Nothing, extra_alias_files; dict_overwrite=false, no_default_aliases=false, verbose=0)
    return _setup_unit_aliases(Dict{String, Array{AbstractString,1}}(), extra_alias_files; dict_overwrite=dict_overwrite, verbose=verbose);
end

# A note on types for future: there is a distinction between specifying a type
# as in extra_alias_files::AbstractString and the "internal" types of a dict or
# array. In the former, it seems that Julia's dispatch will match if extra_alias_files
# is any subtype of AbstractString and there is not a more specific method
# available. However, in the latter, for e.g. extra_aliases::AbstractDict, that will
# also match for any subtype of AbstractDict, but if we want to specify the internal
# types of the dict, then e.g. AbstractDict{AbstractString, AbstractString} will *not*
# match any subtype of AbstractDict with any subtype of AbstractString for the keys
# and values; in this case, we must *explicitly* indicate that subtypes are acceptable
# with the AbstractDict{<:AbstractString,<:AbstractString} notation.
#
# This particular case is even messier b/c we want a dict with any type of array
# containing any type of strings as the values. Consider the following:
#
# julia> isa(Dict{String,Array{String,1}}(), Dict{String,<:AbstractArray{String,1}})
# true
#
# julia> isa(Dict{String,Array{String,1}}(), Dict{String,<:AbstractArray{AbstractString,1}})
# false
#
# In the first, the concrete dict has arrays as values, and since arrays are subtypes of
# AbstractArray *and* have the *exact same type* for their values, the concrete dict
# is a subtype of the given datatype. In the second though, since the expected type
# expects some type of array with AbstractStrings, it doesn't match. We must do:
#
# julia> isa(Dict{String,Array{String,1}}(), Dict{String,<:AbstractArray{<:AbstractString,1}})
# true

function _setup_unit_aliases(extra_aliases::AbstractDict{<:AbstractString, <:AbstractArray{<:AbstractString,1}}, extra_alias_files::Nothing;
        dict_overwrite=false, no_default_aliases=false, verbose=0)
    return _setup_unit_aliases(extra_aliases, Array{String,1}(); verbose=verbose);
end

function _setup_unit_aliases(extra_aliases::AbstractDict{<:AbstractString, <:AbstractArray{<:AbstractString,1}}, extra_alias_files::AbstractString;
        dict_overwrite=false, no_default_aliases=false, verbose=0)
    return _setup_unit_aliases(extra_aliases, [extra_alias_files]; verbose=verbose);
end

function _setup_unit_aliases(extra_aliases::AbstractDict{<:AbstractString, <:AbstractArray{<:AbstractString,1}},
                             extra_alias_files::AbstractArray{<:AbstractString,1};
                             dict_overwrite=false, no_default_aliases=false, verbose=0)
    if no_default_aliases
        aliases = Dict{String, Array{AbstractString,1}}();
    else
        aliases = copy(ICARTTUnits.unit_aliases);
    end
    for f in extra_alias_files
        if verbose > 1
            println("Reading alias file $f...")
        end
        ICARTTUnits._read_alias_config!(aliases, f; verbose=verbose);
    end

    if dict_overwrite
        merge!(aliases, extra_aliases);
    else
        for (key, val) in extra_aliases
            if key in keys(aliases)
                append!(aliases[key], val);
            else
                aliases[key] = val;
            end
        end
    end
    return aliases;
end

"""
    _parse_variable_names(io, n_vars, n_lines; aliases_dict=nothing, verbose=0)

Parse the list of variables in the ICARTT header file pointed to by `io`. Assumes
that the next call to `readline(io)` will return the first line defining a variable.
`n_vars` must be an integer specifying how many variables there are to read.
`n_line` is the current line number of the ICARTT file; it will be advanced properly
and returned with the variables.

`aliases_dict` is the dictionary that defines what parts of the unit string to
replace so that Unitful understands the definition.

`verbose` controls the level of printing to the console, for debugging purposes.
Set to higher numbers to give more information.

Returns:
    1) an array of named tuples with fields "field" and "unit" describing the
name and unit of the variable. "unit" will be a Unitful.Units instance.
    2) the line number at the end of the variables section of the header.
"""
function _parse_variable_names(io::IO, n_vars, n_line; aliases_dict=nothing, verbose=0)
    # must retain order to be able to match them up with their fill values
    varnames = Array{NamedTuple{(:field, :unit), Tuple{String,Unitful.Units}}, 1}(undef, n_vars)
    for i = 1:n_vars
        n_line += 1
        # assuming the variable name lines are of the form "name, unit"
        line = readline(io);
        if verbose > 1
            println("$i: $line");
        end
        varnames[i] = _parse_variable(line, n_line; aliases_dict=aliases_dict);
    end
    return varnames, n_line;
end

"""
    _parse_variable(line, n_line=-1; aliases_dict=nothing)

Given a line read in from an ICARTT file containing a variable name and unit
separated by a comma, creates a named tuple containing the variable name as a
string and the unit as a Unitful.Units instance. The fields are named "field" and
"unit", respectively.

`n_line` is optional, if given, it should specify the line number of the ICARTT
file that the variable is being read from; it will be included in an error message
if there is a problem interpreting the variable.

`aliases_dict` is the dictionary that defines what parts of the unit string to
replace so that Unitful understands the definition.
"""
function _parse_variable(line, n_line=-1; aliases_dict=nothing)
    name, unit = _split_icartt_line(line);
    punit = nothing;
    try
        punit = ICARTTUnits.parse_unit_string(unit; aliases_dict=aliases_dict)
    catch err
        # Unitful doesn't use a specific error type for unit conversion
        # errors so the best course of action is to print a message explaining
        # what unit failed and rethrow the error
        printstyled("Problem while converting unit \"$unit\" on line $n_line:\n"; color=:red)
        rethrow(err)
    end
    return (field=name, unit=punit);
end

"""
    _parse_special_comments(io, n_line)

Parse the special comments section of the ICARTT file pointed to by IO handle
`io`. `n_line` is the current line number, it will be advanced as the special
comments are read in.

Returns the special comments as a single string and the line number at the end
of the special comments section.
"""
function _parse_special_comments(io, n_line)
    # The number of special comment lines is the next line to read.
    n_cmt_lines = parse(Int64, readline(io));
    n_line += 1;
    special_comments = "";
    for i = 1:n_cmt_lines
        n_line += 1;
        line = readline(io, keep=true);
        special_comments *= line;
    end
    return special_comments, n_line;
end

"""
    _parse_normal_comments(io, n_line)

Parse the normal comments section of the ICARTT file pointed to by IO handle
`io`. `n_line` is the current line number, it will be advanced as the normal
comments are read in.

Returns the comments as an OrderedDict containing the standard comment categories
as keys and their values as the string values, also returns the line number at
the end of the normal comments section.
"""
function _parse_normal_comments(io, n_line)
    n_cmt_lines = parse(Int64, readline(io));
    n_line += 1;
    comments = OrderedDict{String, Any}();

    # Unlike the special comments section, which is intended to be pretty open
    # for whatever comments are needed, the normal comments section has specific
    # piece of information that are expected to be included. This should always
    # start their line and be followed immedately by a colon. After the line
    # that indicates the number of normal comments to read, we start searching
    # for this pattern.
    #
    # Note that section 2.3.2.17 of https://cdn.earthdata.nasa.gov/conduit/upload/6158/ESDS-RFC-029v2.pdf
    # indicates that the normal comments section may include a free form text
    # section that is not currently implemented by this reader. This section may
    # include both unformatted text and custom keyword-value pairs.
    current_cmt = nothing;
    categories = join(_ICARTT_NORMAL_COMMENTS, "|");
    re = Regex("^($categories)(?=:)");
    for i = 1:(n_cmt_lines - 1)
        line = readline(io);
        n_line += 1;

        # See if this line starts a new category:
        m = match(re, line);
        if m != nothing
            # This line starts a new category. Set that as the category we'll
            # store the value in and initialize that value in the dictionary with
            # the rest of this line.
            current_cmt = m.match;
            comments[current_cmt] = strip(split(line, ":")[2]);
        else
            # This line does not start a new category.
            if current_cmt == nothing
                # If we don't have a current category, then there's something wrong
                # either with the format of the file or our parsing of it.
                throw(ICARTTParsingException("Trying to read a normal comment, but have not found a comment keyword yet!"))
            else
                # This must be a multiline comment, so append it to the current
                # value.
                comments[current_cmt] *= " " * line;
            end
        end
    end

    # The last line will be the table header
    line = readline(io);
    n_line += 1;
    header = _split_icartt_line(line);
    return comments, header, n_line
end

"""
    _merge_variable_info(variables, fill_vals, scale_factors)

Combine the fill values, scale factors, and units for each variable into a
single named tuple with fields "field", "unit", "fill", and "scale". Returns an
array of these tuples, one per variable.

`variable` must be the array of tuples containing the variable name and units.
`fill_vals` must be an array of the same length containing the fill values for
each unit. `scale_factors` is likewise the array of scale factors. Order matters,
the order must be the same for all three inputs.
"""
function _merge_variable_info(variables, fill_vals, scale_factors)
    new_vars = Array{NamedTuple{(:field, :unit, :fill, :scale), Tuple{String, Unitful.Units, Float64, Float64}}, 1}(undef, length(variables));
    for i in 1:length(new_vars)
        new_tup = (field=variables[i].field, unit=variables[i].unit, fill=fill_vals[i], scale=scale_factors[i]);
        new_vars[i] = new_tup;
    end
    return new_vars;
end

"""
    _check_variables_vs_header(vars, header)

Check the array of variable information against the table header. `vars` is the
array of named tuples created by `_merge_variable_info`, with the primary unit
added. `header` is the array of variable names resulting from reading the table
header which is the last line of the file header.

Throws an ICARTTParsingException if the two do not match (either are different
lengths or have a variable name that is different).
"""
function _check_variables_vs_header(vars, header)
    if length(vars) != length(header)
        throw(ICARTTParsingException("The number of variables defined ($(length(vars)))  different from the number in the table header ($(length(header)))"));
    end

    for i=1:length(vars)
        if vars[i].field != header[i]
            throw(ICARTTParsingException("Variable number $i has a different name ($(vars[i].field)) than in the table header ($(header[i]))"));
        end
    end
end

end
