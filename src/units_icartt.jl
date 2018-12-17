module ICARTTUnits

using Unitful;

# Custom Exceptions #

struct ICARTTUnitsException <: Exception
    msg;
end

# The unit aliases dictionary defines aliases for existing Unitful units that
# might be written differently in ICARTT files. The key should be the Unitful
# abbreviation string, and the value must be a tuple of alternate aliases that
# that unit may go by in the ICARTT files. It must be a tuple, even if there is
# only one alias. Note that the aliases will be matched in order of decreasing
# length, no matter what order they are listed in.
unit_aliases = Dict{String, Tuple}("°"  => ("degs", "deg", "Degs"),
                                   "hr"       => ("hour",),
                                   "percent"  => ("%",),
                                   "std_m" => ("std m",),  # temporary until I decide how to treat STP volumes
                                   "nm" => ("nanometers",),  # also a kludge for KORUS
                                   "" => ("#",))

# Treat "unitless" and "none" slightly differently: "unitless" implies that it
# is a physical quantity that has no dimensionality; while "none" implies that
# it is not a physical quantity, e.g. an index of some sort.
@unit(unitless, "unitless", unitless, Quantity(1, Unitful.NoUnits), false);
@unit(none, "no_units", none, Quantity(1, Unitful.NoUnits), false);
# mach numbers are technically unitless b/c the represent the speed of the craft
# relative to the speed of sound _in that medium_ so they do not map to an
# absolute speed
@unit(mach, "mach", MachNumber, Quantity(1, Unitful.NoUnits), false);

# units relating to amount of matter
@unit(molec, "molec.", molec, Quantity(1/Unitful.Na.val, Unitful.mol), false); # can't use // because Na is a float
@unit(DU, "DU", DobsonUnit, Quantity(0.4462, Unitful.mmol), false);

# the UnitfulMoles package was not working on 5 Dec 2018, so I'm defining
# mixing ratios here
@unit(ppm, "ppm", parts_per_million, Quantity(1, Unitful.μmol / Unitful.mol), false);
@unit(ppmv, "ppmv", parts_per_million_volume, Quantity(1, Unitful.μL / Unitful.L), false);
@unit(ppb, "ppb", parts_per_billion, Quantity(1, Unitful.nmol / Unitful.mol), false);
@unit(ppbv, "ppb", parts_per_billion_volume, Quantity(1, Unitful.nL / Unitful.L), false);
@unit(ppt, "ppt", parts_per_trillion, Quantity(1, Unitful.pmol / Unitful.mol), false);
@unit(pptv, "pptv", parts_per_trillion_volume, Quantity(1, Unitful.pL / Unitful.L), false);

# time units
@unit(days, "days", days, Quantity(24, Unitful.hr), false);

# volume units
@unit(std_m, "std m", m_at_stp, Quantity(1, Unitful.m), false);

# Recommended by http://ajkeller34.github.io/Unitful.jl/stable/extending/
# if a package gets precompiled

const localunits = Unitful.basefactors
function __init__()
    merge!(Unitful.basefactors, localunits)
    Unitful.register(ICARTTUnits)
end

"""
    parse_unit_string(ustr)

Given a string describing a unit or combination of units, convert it into a
Unitful.Units instance. This uses `sanitize_raw_unit_strings` to preformat the
string into a format that Unitful is more likely to understand.
"""
function parse_unit_string(ustr)
    # Since I could not find a version of the Unitful @u_str macro that was a
    # function, I'm replicating the internals of @u_str here
    ustr = sanitize_raw_unit_strings(ustr);
    # The way the @u_str macro works in Unitful is that, given an expression or
    # symbol, tries to replace each symbol (whether standalone or in the expression)
    # with a Units instance. Then the final expression is automatically evaluated
    # by the macro before returning, so e.g. "m * s^-1" becomes:
    #   FreeUnit(m) / FreeUnit(s)
    # which gets evaluated to
    #   FreeUnit(m / s)
    # When reading from a file, I don't think there's any way to replicate that
    # without doing a run-time eval. This should be safe, as Unitful.replace_value
    # will error if a symbol is not recognized, and replaces all symbols with the
    # apporpriate Unitful.FreeUnit instances.
    try
        expr = Unitful.replace_value(Meta.parse(ustr));
        return eval(expr); # do not need the `esc` call since not returning from macro
    catch err
        # Since ICARTT files are ASCII encoded, the "micro" prefix will be represent
        # most often by a "u", but we can't just replace "u" with "μ" in all cases,
        # that would break e.g. "unitless". The only way I can figure out that doesn't
        # involve manually entering _every_ unit with the prefix "μ" that we want
        # to handle is to try the parsing and, if it fails because a symbol starting
        # with "u" isn't recognized, replace that with "μ" and try again.
        if ~(:msg in fieldnames(typeof(err)))
            # if no message, then not the right error
            rethrow(err);
        end
        m = match(r"(?<=Symbol )u[a-zA-Z]+", err.msg);
        if m === nothing
            rethrow(err);
        else
            orig_str = ustr
            new_str = replace(ustr, Regex("$(m.match)") => SubstitutionString("μ" * m.match[2:end]), count=1);
            try
                return parse_unit_string(new_str);
            catch err2
                msg = "Tried replacing 'u' prefix with 'μ' ($orig_str -> $new_str) but this failed: $(err2)";
                throw(ICARTTUnitsException(msg));
            end
        end
    end
end

"""
    sanitize_raw_unit_strings(ustr)

Preprocesses a unit string (`ustr`) read in from ICARTT files into a form that
can be understood by Unitful. Does several things:

    1. Replaces any substrings defined by `unit_aliases` with their key value.
       This helps standardize the units used.
    2. Replaces blank space between an alphanumeric character and a letter with
       a "*" e.g. "m s-1" becomes "m * s-1"
    3. Inserts a "^" between units and their exponents; specifically, if a letter
       is followed immediately by a number, +, or -, a "^" is inserted.

"""
function sanitize_raw_unit_strings(ustr)
    #print("Sanitizing '$ustr', ")
    # The first one is the most complicated because we need to look for any of
    # the aliases defined in the unit_aliases dictionary, but they need to match
    # a whole word, or be prefixed. That makes this a bit of a mess. We require
    # either:
    #   A) the string to substitute (S) is preceeded by a start of the string, or
    #   B) S is preceeded by a whitspace character, or
    #   C) S is preceeded by one of the defined metric prefixes, which is itself
    #       preceeded by a start-of-string or whitespace
    # and
    #   D) S is followed by a non-letter character, or an end-of-string

    # This is the first step, we need to construct a look-ahead pattern that matches
    # on start-of-string (\A), whitespace (\s), or one of the prefixes preceeded
    # by a start-of-string or whitespace.
    #
    # The joins will correctly put the | and either \A or \s in front of each
    # prefix except the first one, so the first "\\A" adds it for the first prefix
    # and the "|\\s" adds it for the first prefix of the second group. We shouldn't
    # need to explicitly include \A and \s without a prefix because the prefixdict
    # includes an empty string for no prefix.
    #
    # This part relies heavily on ICARTT files being ASCII encoded; it's not compatible
    # with Unicode encodings. This has to happen first in case we want to treat
    # a string with spaces, e.g. "std m" specially.
    prefixes = "\\A" * join(values(Unitful.prefixdict), "|\\A") * "|\\s" * join(values(Unitful.prefixdict), "|\\s")
    for (key, val) in pairs(unit_aliases)
        # Force the aliases to be searched in order of decreasing length (longest
        # first); this ensures that if a shorter alias is a subset of a longer one
        # that the entirety of the longer one gets matched. E.g. if searching
        # for "deg" or "degrees" and "deg" came up first, it would replace only
        # the first three letters of "degrees" with the proper ° symbol, i.e. we'd
        # get "°rees", which wouldn't match any known unit.\
        # Also there's no `sort` method for tuples, so we have to convert to a
        # temporary array
        sorted_aliases = sort([val...], by=length, rev=true)
        aliases = join(val, "|");
        sub = SubstitutionString(key)
        # Look for any of the aliases preceeded by any of the metric prefixes and
        # either the start-of-string or whitespace, and succeeded by any non-letter
        # character or an end-of-string
        re = Regex("(?<=$(prefixes))($(aliases))(?=[^a-zA-Z]|\\Z)");
        #println("sub = $sub, re = $re")
        ustr = replace(ustr, re => sub)
    end

    # Replace any spaces between a letter/number and letter with *, so e.g.
    # m s-1 -> m * s-1 and m2 s-1 -> m2 * s-1. User groups to keep the last
    # character of the preceeding unit and first letter of the succeeding unit
    # in the result
    ustr = replace(ustr, r"([a-zA-Z0-9])\s+([a-zA-Z])" => s"\1 * \2")

    # Insert a caret between units and their exponents. Assumes units will never
    # contain digits. Gets the last non-digit character of the unit as group 1
    # and the exponent which is the numbers and optionally a leading + or - as
    # group 2, and insert the ^ between them. Right now, there cannot be spaces
    # between the unit and exponent.
    ustr = replace(ustr, r"([a-zA-Z])([+\-]?\d+)" => s"\1^\2")

    #println(" result: '$ustr'")
    return ustr
end

end
