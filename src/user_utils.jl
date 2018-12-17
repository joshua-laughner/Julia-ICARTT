module ICARTTUtils

using Unitful;

using ..ReadICARTT: AirMerge;

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
* `tol` sets the absolute tolerance used when finding fill values.
* `reltol` sets the relative tolerance used when finding fill values.

A value is consider a fill if for value ``v`` and fill ``f``, either ``|v - f| < tol``
or ``|(v - f)/v| < reltol`` is true. This helps account for floating point error, which
could cause `v == f` to return `false` improperly.

`NaN`s had to be used instead of `missing` because `missing` is currently incompatible
with `Unitful.Quantity`s.
"""
function get_merge_data(air_merge::AirMerge, field::String; replace_fills=true, tol=1e-10, reltol=1e-4)
    replace_fills::Bool;
    tol::Float64;
    reltol::Float64;

    values = copy(air_merge.data[field].values);
    fill = air_merge.data[field].fill;
    raw_values = _strip_units.(values);
    abscheck = (abs.(raw_values .- fill)) .< tol;
    relcheck = abs.(raw_values .- fill ./ raw_values) .< reltol;
    is_fill = abscheck .| relcheck;

    #return raw_values, fill, tol, reltol

    # Assumes that all values in the array have the same units. They should,
    # and if not, since the array is typed by unit, this should error if we
    # try to insert a dimensionally incompatible unit.
    values[is_fill] .= Unitful.Quantity(NaN, Unitful.unit(values[1]));
    return values
end

end
