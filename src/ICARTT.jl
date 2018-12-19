module ICARTT

include("icartt_exceptions.jl")
include("units_icartt.jl")
include("read_icartt.jl")
include("user_utils.jl")

import .ReadICARTT: read_icartt_file;
import .ICARTTUtils: get_merge_data;
export read_icartt_file, get_merge_data;

end # module
