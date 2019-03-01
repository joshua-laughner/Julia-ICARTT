module ICARTTUtils

using Unitful;

using ..ReadICARTT: AirMerge;
using ..ICARTTExceptions: ICARTTNotImplementedException;


_strip_units(v) = v.val;

export get_merge_data;

"""
    get_merge_data(air_merge::AirMerge, field::String; replace_fills=true, tol=1e-10, reltol=1e-4)

Get the data from an AirMerge data field, replacing fill values with NaNs. `air_merge`
is a struct returned by ICARTT.ReadICARTT.read_icartt_file (or in general a
`ICARTT.ReadICARTT.AirMerge` struct). `field` is the name of the key in air_merge.data
to read.

Keyword arguments are:

* `replace_fills` allows you to disable the automatic replacement of fill value
with NaNs.
* `lod_mode` allows you to specify how to treat values flagged as above (below)
the upper (lower) limit of detection. Default is `"default"`, which means they
will be replaced by the ULOD_VALUE and LLOD_VALUE given in the metadata. If
those values are "N/A", then they will be replaced with `NaN`. The
other choice is `"leave"`, which leaves them alone.
* `tol` sets the absolute tolerance used when finding fill values.
* `reltol` sets the relative tolerance used when finding fill values.

A value is consider a fill if for value ``v`` and fill ``f``, either ``|v - f| < tol``
or ``|(v - f)/v| < reltol`` is true. This helps account for floating point error, which
could cause `v == f` to return `false` improperly.

`NaN`s had to be used instead of `missing` because `missing` is currently incompatible
with `Unitful.Quantity`s.
"""
function get_merge_data(air_merge::AirMerge, field::String; replace_fills=true, no_units=false, lod_mode="default",  tol=1e-10, reltol=1e-4)
    replace_fills::Bool;
    tol::Float64;
    reltol::Float64;

    values = copy(air_merge.data[field].values);
    fill = air_merge.data[field].fill;
    llod_flag = parse(Float64, air_merge.metadata["LLOD_FLAG"]);
    ulod_flag = parse(Float64, air_merge.metadata["ULOD_FLAG"]);
    raw_values = _strip_units.(values);
    is_fill = _is_within_tol(raw_values, fill, tol, reltol);
    is_llod = _is_within_tol(raw_values, llod_flag, tol, reltol);
    is_ulod = _is_within_tol(raw_values, ulod_flag, tol, reltol);

    # Assumes that all values in the array have the same units. They should,
    # and if not, since the array is typed by unit, this should error if we
    # try to insert a dimensionally incompatible unit.
    values[is_fill] .= Unitful.Quantity(NaN, Unitful.unit(values[1]));

    if lowercase(lod_mode) == "default"
        llod_val, ulod_val = _get_lod_values(air_merge);
    elseif lowercase(lod_mode) != "leave"
        throw(ICARTTNotImplementedException("lod_mode == '$lod_mode' is not recognized"));
    end

    if lowercase(lod_mode) != "leave"
        values[is_llod] .= Unitful.Quantity(llod_val, Unitful.unit(values[1]));
        values[is_ulod] .= Unitful.Quantity(ulod_val, Unitful.unit(values[1]));
    end

    if no_units
        return _strip_units.(values)
    else
        return values
    end
end

function _is_within_tol(raw_values, target_val, tol, reltol)
    abscheck = (abs.(raw_values .- target_val)) .< tol;
    relcheck = abs.(raw_values .- target_val ./ raw_values) .< reltol;
    return abscheck .| relcheck;
end

function _get_lod_values(air_merge::AirMerge)
    ulod_val = air_merge.metadata["ULOD_VALUE"];
    llod_val = air_merge.metadata["LLOD_VALUE"];
    not_avail = "N/A";
    ulod_val = ulod_val == not_avail ? NaN : parse(Float64, ulod_val);
    llod_val = llod_val == not_avail ? NaN : parse(Float64, llod_val);
    return llod_val, ulod_val;
end


function search_icartt_variables(air_merge::AirMerge, pattern::Union{AbstractString, Regex, AbstractChar})
    matches = Array{AbstractString,1}();
    for k in keys(air_merge.data)
        if occursin(pattern, k)
            push!(matches, k)
        end
    end

    return matches;
end

end
