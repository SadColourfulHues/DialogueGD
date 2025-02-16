## An object representing an event that triggers at the start of a dialogue
class_name DialogueEvent
extends RefCounted

var m_command_id: StringName
var p_parameters: Array[String]


#region Utils

## Takes a string and converts it to the appropriate type
## -> decimals will be converted to float
## -> integers to int
## -> yes/no true/false to bool
## -> unresolvable -> string
static func resolve_param(parameter: String):
    if parameter.is_valid_float():
        return float(parameter)
    elif parameter.is_valid_int():
        return int(parameter)

    match parameter.to_lower():
        &"yes", &"true":
            return true

        &"no", &"false":
            return false

        _:
            return parameter

#endregion
