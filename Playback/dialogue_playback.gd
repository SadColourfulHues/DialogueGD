## An object for playing back dialogue graphs
## (Make sure to call [free] once you're done using this.)
class_name DialoguePlayback
extends Object

const NO_CHOICES: Array[DialogueChoice] = []

const EVENT_CONTROL_PASS := 0
const EVENT_CONTROL_HALT := 1

## This signal is triggered when the playback state resets to the
## beginning of a dialogue graph. Or if the graph itself has been changed.
signal resetted()

## This signal can be triggered when the playback reaches the end of a graph
## or if the 'close' or 'exit' event is raised by the script.
signal closed()

## This signal is called when the current dialogue text is changed
signal dialogue_available(text: String)
## This signal is called when the currently-speaking character is changed
signal character_available(text: String)
## This signal is called when the current dialogue block requires the
## player to make a choice.
signal choices_available(choices: Array[DialogueChoice])
## This signal is called when an event is raised by the script
## (Connect to this to implement custom events.)
## (This will get called several times if the block has more than one event in it.)
signal event_available(event_id: StringName, parameters: Array[String])

var m_index: int
var m_last_char_id: StringName
var m_event_control: int

var p_variables: Dictionary[StringName, Variant]
var p_graph: DialogueGraph


func _init(graph: DialogueGraph = null) -> void:
    set_graph(graph)

    m_last_char_id = &""
    m_index = -1


#region Functions

## Sets the playback's current dialogue graph
## (Doing this will also reset its state.)
func set_graph(graph: DialogueGraph) -> void:
    if p_graph == graph:
        return

    p_graph = graph

    # Reject null or empty graphs
    if graph == null || graph.p_nodes.is_empty():
        closed.emit()
        m_index = -1
        return

    m_index = 0
    __present_scene()

    resetted.emit()


## Advances the dialogue
## (Restarts playback if [wrap_at_end] is enabled.)
func advance(wrap_at_end: bool = false, bypass_choices: bool = false) -> bool:
    if p_graph == null:
        printerr("DialoguePlayback: this player does not have a graph assigned to it yet!")
        return false

    var size := p_graph.p_nodes.size()

    # Block advance requests if choices are present
    if !bypass_choices && !p_graph.p_nodes[m_index].p_choices.is_empty():
        return false

    if wrap_at_end:
        m_index = wrapi(m_index + 1, 0, size)
    else:
        m_index += 1

    # Edge check
    if m_index < 0 || m_index >= size:
        closed.emit()
        return false

    __present_scene()
    return true


## Adds the specified flag to the current playback
## (Equivalent to raising the 'flag' event in Dialogue Script.)
func flag(flag_id: StringName) -> void:
    p_variables[flag_id] = true


## Removes the specified flag from the current playback
## (Equivalent to raising the 'unflag' event in Dialogue Script.)
func unflag(flag_id: StringName) -> void:
    p_variables.erase(flag_id)


## (Convenience) Equivalent to calling [seek_to_bookmark] on the
## choice's bookmark target ID
func accept_choice(choice: DialogueChoice) -> void:
    seek_to_bookmark(choice.m_target_id)


## (Advanced) Jumps to the dialogue block at the specified index
func seek_to(index: int) -> void:
    if index < 0 || p_graph == null || index >= p_graph.p_nodes.size():
        printerr("DialoguePlayback: tried to seek to an invalid index.")
        return

    m_index = index
    __present_scene()


## Jumps to the first dialogue block with the specified bookmark ID
## (Does nothing if the bookmark wasn't found.)
func seek_to_bookmark(id: StringName) -> void:
    if p_graph == null:
        return

    for i: int in p_graph.p_nodes.size():
        if p_graph.p_nodes[i].m_id != id:
            continue

        m_index = i
        __present_scene()
        return

    printerr("DialoguePlayback: no scenes were found with the bookmark \"%s\"" % id)


## Jumps to the first dialogue block in the current graph
func seek_to_start() -> void:
    if p_graph == null:
        return

    m_index = 0
    __present_scene()


## (Specific Use-Case) Jumps to the last dialogue block in the current graph
func seek_to_end() -> void:
    if p_graph == null:
        return

    m_index = p_graph.p_nodes.size() - 1
    __present_scene()


## Passes the given control ID to the playback
## (Use on handlers for [event_available] to change processing behaviour.)
func set_event_control(control_id: int) -> void:
    m_event_control = control_id


## Replaces variables in the given [text] with their current variables
func __resolve_vars(text: String) -> String:
    var final_text := text

    # TODO: consider using a different approach for resolution?
    for v_id: StringName in p_variables:
        var v_val: Variant = p_variables[v_id]

        if v_val is not String:
            continue

        final_text = final_text.replace(&"{%s}" % v_id, p_variables[v_id])

    return final_text

#endregion

#region Utils

## (Basic Checking) presents the current dialogue block
## to subscribed views.
func __present_scene() -> void:
    if m_index == -1 || p_graph == null:
        return

    var node := p_graph.p_nodes[m_index]
    var char_id := __resolve_vars(node.m_character_id)

    if m_last_char_id != char_id:
        character_available.emit(char_id)
        m_last_char_id = char_id

    dialogue_available.emit(__resolve_vars(node.m_text))

    if node.p_choices.is_empty():
        choices_available.emit(NO_CHOICES)
    else:
        choices_available.emit(node.p_choices.filter(__filter_choice_flags))

    if __process_inbuilt_events(node.p_events):
        return

    for event: DialogueEvent in node.p_events:
        m_event_control = EVENT_CONTROL_PASS
        event_available.emit(event)

        match m_event_control:
            EVENT_CONTROL_HALT:
                break

            _:
                continue


func __filter_choice_flags(choice: DialogueChoice) -> bool:
    for flag_id: StringName in choice.p_required_flags:
        if !p_variables.has(flag_id):
            return false
    return true


func __process_inbuilt_events(events: Array[DialogueEvent]) -> bool:
    var is_handled := false

    for event: DialogueEvent in events:
        m_event_control = EVENT_CONTROL_PASS

        if __process_inbuilt_event(event):
            is_handled = true

        if m_event_control == EVENT_CONTROL_HALT:
            break

    if is_handled:
        return true

    return false


func __process_inbuilt_event(event: DialogueEvent) -> bool:
    var param_size := event.p_parameters.size()
    var params := event.p_parameters

    match event.m_command_id:
        &"close", &"exit", &"quit":
            closed.emit()
            return true

        &"jump":
            if param_size < 1:
                printerr("DialoguePlayback: event 'jump' requires one parameter to work. Usage: \"jump <target bookmark>\"")
                return false

            seek_to_bookmark(params[0])
            set_event_control(EVENT_CONTROL_HALT)
            return true

        &"jumpif":
            if param_size < 2:
                printerr("DialoguePlayback: event 'jumpif' requires two parameters to work. Usage: \"jumpif <flag_id> <bookmark>\"")
                return false

            if !p_variables.has(params[0]):
                return true

            seek_to_bookmark(params[1])
            set_event_control(EVENT_CONTROL_HALT)
            return true

        &"flag":
            if param_size < 1:
                printerr("DialoguePlayback: event 'flag' requires one parameter to work. Usage: \"flag <flag_id>\"")
                return false

            p_variables[params[0]] = true
            return true

        &"unflag":
            if param_size < 1:
                printerr("DialoguePlayback: event 'unflag' requires one parameter to work. Usage: \"unflag <flag_id>\"")
                return false

            p_variables.erase(params[0])
            return true

        &"set":
            if param_size < 2:
                printerr("DialoguePlayback: event 'set' needs two or more parameters to work. Usage: \"set <variable_id> <value>\"")
                return false

            var var_id: StringName = params[0]

            if params.size() == 2:
                p_variables[var_id] = DialogueEvent.resolve_param(params[1])
                return true

            # set-vars with 3+ params will always be treated as strings
            p_variables[var_id] = &" ".join(params.slice(1))
            return true

    return false

#endregion

#region Variable Persistence

func _on_write(writer: FileAccess) -> void:
    writer.store_16(p_variables.size())

    for var_id: StringName in p_variables:
        writer.store_pascal_string(var_id)
        writer.store_var(p_variables[var_id])


func _on_restore(reader: FileAccess) -> void:
    p_variables.clear()

    for _i: int in range(reader.get_16()):
        var key := reader.get_pascal_string()
        var value: Variant = reader.get_var()

        p_variables[key] = value

#endregion
