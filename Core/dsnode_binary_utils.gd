## A collection of scripts for storing/restoring DS nodes to/from
## a serialised binary file
class_name DSNodeBin
extends Object

const ID_NODE := 1
const ID_CHOICE := 2
const ID_EVENT := 3


#region Writers

## Encodes a [DialogueChoice] object into a binary format
static func write_choice(writer: FileAccess, choice: DialogueChoice) -> void:
	# Head #
	writer.store_8(ID_CHOICE)
	writer.store_pascal_string(choice.m_display_text)
	writer.store_pascal_string(choice.m_target_id)

	# Required flags #
	writer.store_8(choice.p_required_flags.size())

	for flag: StringName in choice.p_required_flags:
		writer.store_pascal_string(flag)


## Encodes a [DialogueEvent] object into a binary format
static func write_event(writer: FileAccess, event: DialogueEvent) -> void:
	# Head #
	writer.store_8(ID_EVENT)
	writer.store_pascal_string(event.m_command_id)

	# Parameters
	writer.store_8(event.p_parameters.size())

	for parameter: String in event.p_parameters:
		writer.store_pascal_string(parameter)


## Encodes a [DialogueNode] into a binary format
static func write_node(writer: FileAccess,
					   dialogue: DialogueNode,
					   char_map: Dictionary[StringName, int]) -> void:

	# Head #
	writer.store_8(ID_NODE)
	writer.store_pascal_string(dialogue.m_id)
	writer.store_8(char_map[dialogue.m_character_id])
	writer.store_pascal_string(dialogue.m_text)

	# Sub Data: Events #
	writer.store_8(dialogue.p_events.size())

	for event: DialogueEvent in dialogue.p_events:
		write_event(writer, event)

	# Sub Data: Choices #
	writer.store_8(dialogue.p_choices.size())

	for choice: DialogueChoice in dialogue.p_choices:
		write_choice(writer, choice)


## Encodes an entire [DialogueGraph] into a binary format
static func write_graph(writer: FileAccess, graph: DialogueGraph) -> void:
	# Character Map #
	var char_map: Dictionary[StringName, int]
	var counter := 0

	for node: DialogueNode in graph.p_nodes:
		if char_map.has(node.m_character_id):
			continue

		char_map[node.m_character_id] = counter
		counter += 1

	writer.store_8(char_map.size())

	for char_id: StringName in char_map:
		writer.store_pascal_string(char_id)
		writer.store_8(char_map[char_id])

	# Nodes #
	writer.store_16(graph.p_nodes.size())

	for node: DialogueNode in graph.p_nodes:
		write_node(writer, node, char_map)

#endregion

#region Readers

## Reads the next [DialogueChoice] object in the current reader
static func read_choice(reader: FileAccess) -> DialogueChoice:
	# Head #
	if !__is_stored_type(reader, ID_CHOICE):
		return null

	var choice := DialogueChoice.new()

	choice.m_display_text = reader.get_pascal_string()
	choice.m_target_id = reader.get_pascal_string()

	# Required Flags #
	var size := reader.get_8()

	if size > 0:
		choice.p_required_flags.resize(size)

		for i: int in range(size):
			choice.p_required_flags[i] = reader.get_pascal_string()

	return choice


## Reads the next [DialogueEvent] object in the current reader
static func read_event(reader: FileAccess) -> DialogueEvent:
	# Head #
	if !__is_stored_type(reader, ID_EVENT):
		return null

	var event := DialogueEvent.new()
	event.m_command_id = reader.get_pascal_string()

	# Parameters #
	var size := reader.get_8()

	if size > 0:
		event.p_parameters.resize(size)

		for i: int in range(size):
			event.p_parameters[i] = reader.get_pascal_string()

	return event


## Reads the next [DialogueNode] object in the current reader
static func read_node(reader: FileAccess,
					  char_map: Dictionary[int, StringName]) -> DialogueNode:

	# Head #
	if !__is_stored_type(reader, ID_NODE):
		return null

	var node := DialogueNode.new()

	node.m_id = reader.get_pascal_string()
	node.m_character_id = char_map[reader.get_8()]
	node.m_text = reader.get_pascal_string()

	# Sub Data: Events #

	var events_size := reader.get_8()

	if events_size > 0:
		node.p_events.resize(events_size)

		for i: int in range(events_size):
			node.p_events[i] = read_event(reader)

	# Sub Data: Choices #

	var choices_size := reader.get_8()

	if choices_size > 0:
		node.p_choices.resize(choices_size)

		for i: int in range(choices_size):
			node.p_choices[i] = read_choice(reader)

	return node


## Reads an entire [DialogueGraph] file from the current reader
static func read_graph(reader: FileAccess) -> DialogueGraph:
	# Character Map #
	var char_map: Dictionary[int, StringName]

	for _i: int in range(reader.get_8()):
		var char_name: StringName = reader.get_pascal_string()
		var char_id: int = reader.get_8()

		char_map[char_id] = char_name

	# Nodes #
	var graph := DialogueGraph.new()
	var size := reader.get_16()

	graph.p_nodes.resize(size)

	for i: int in range(size):
		graph.p_nodes[i] = read_node(reader, char_map)

	return graph

#endregion

#region Utils

static func __is_stored_type(reader: FileAccess, type: int) -> bool:
	return reader.get_8() == type


#endregion
