module ICARTTExceptions

using JLLUtils.JLLExceptions; # provides @msgexc

"""
    ICARTTParsingException(msg)

An exception class raised if any issues arise while parsing an ICARTT-formatted
file.
"""
@msgexc ICARTTParsingException

"""
    ICARTTNotImplementedException(msg)

An exception raised if a particular case is recognized, but not implemented, by
the parser.
"""
@msgexc ICARTTNotImplementedException

"""
    ICARTTUnitsException(msg)

An exception raised if there is a problem interpreting a unit in an ICARTT file.
"""
@msgexc ICARTTUnitsException

end
