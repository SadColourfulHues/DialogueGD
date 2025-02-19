## A special utility object that handles the creation of [DialogueGraph]s
## (Typically should only be used by dialogue-authoring tools.)
## (Make sure to call [free] once you're done using it)
class_name DialogueParser
extends Object

## Parser state
enum State
{
	NORMAL,
	CHOICE
}

## DialogueScript Type
enum DSType
{
	LINE,
	CHARACTER,
	COMMENT,
	BOOKMARK,
	EVENT,
	CHOICE,
	CHOICE_REQUIREMENT,
	CHOICE_TARGET,
}

var m_write_started: bool
var m_state := State.NORMAL
var m_tmp_dialogue: String
var m_tmp_character_id: String
var m_tmp_bookmark_id: String

var m_tmp_choice_id: String
var m_tmp_choice_destination: String

var p_tmp_choice_requirements: Array[StringName]

var p_tmp_choices: Array[DialogueChoice]
var p_tmp_events: Array[DialogueEvent]


#region Functions

## Turns a dialogue script string into a reusable graph object
## Use the static [graph_to_file] method on the output to save the graph to disk.
## (Or [script_file_to_graph] to load a script directly from disk.)
func string_to_graph(script: String) -> DialogueGraph:
	m_tmp_bookmark_id = &""
	m_state = State.NORMAL

	__reset_writer()
	__reset_choice_writer()

	var graph := DialogueGraph.new()
	var lines := script.split("\n")

	for line: String in lines:
		# Skip empty lines
		if is_empty_line(line):
			continue

		__process(graph, line)

	# Commit unfinished writes
	__push_node(graph)

	return graph


## Loads a script file from disk and turns it into a [DialogueGraph] object
## (Returns null on empty files or errors.)
func script_file_to_graph(in_path: String) -> DialogueGraph:
	var contents := FileAccess.get_file_as_string(in_path)

	if contents.is_empty():
		return null

	return string_to_graph(contents)


## Reads a stored [DialogueGraph] from disk
## (Returns null if an error occurs during the loading process.)
static func graph_from_file(in_path: String) -> DialogueGraph:
	var file := FileAccess.open(in_path, FileAccess.READ)

	if !file.is_open():
		printerr("DialogueParser: failed to open file at \"%s\"" % in_path)
		return null

	var stored_graph := DSNodeBin.read_graph(file)
	file.close()

	return stored_graph


## Writes a [DialogueGraph] to a reusable file at the specified path
static func graph_to_file(graph: DialogueGraph, out_path: String) -> bool:
	var file := FileAccess.open(out_path, FileAccess.WRITE)

	if !file.is_open():
		printerr("DialogueParser: failed to open file for writing at \"%s\"" % out_path)
		return false

	DSNodeBin.write_graph(file, graph)
	file.close()

	return true


#endregion

#region Utils

## Runs the main parsing process on a given line
func __process(graph: DialogueGraph, line: String) -> void:
	var dstype := identify_line(line)

	# State alterations will cause the parser to
	# re-evaluate the line under the new state
	match m_state:
		State.NORMAL:
			if __process_line(graph, line, dstype):
				return

			__process(graph, line)

		State.CHOICE:
			if __process_choice(line, dstype):
				return

			__process(graph, line)


## Parses the current line in normal mode
## (Should only be called by the parser.)
func __process_line(graph: DialogueGraph,
					line: String,
					dstype: DSType) -> bool:

	if dstype == DSType.COMMENT:
		return true

	## Detect new dialogue blocks
	if (m_write_started && (
		dstype == DSType.BOOKMARK ||
		dstype == DSType.CHARACTER)):

		__push_node(graph)
		return false

	match dstype:
		DSType.BOOKMARK:
			m_tmp_bookmark_id = unwrap_tag(line)

		DSType.CHARACTER:
			m_tmp_character_id = unwrap_tag(line)
			m_write_started = true

		DSType.LINE:
			if m_tmp_dialogue.is_empty():
				m_tmp_dialogue = line
			else:
				m_tmp_dialogue += &" " + line

		DSType.EVENT:
			__push_event(line)

		DSType.CHOICE:
			m_state = State.CHOICE
			return false

	return true


## Parses the current line in choice mode
## (Should only be called by the parser.)
func __process_choice(line: String, dstype: DSType) -> bool:
	if dstype == DSType.COMMENT:
		return true

	var sline := line.strip_edges()

	match dstype:
		DSType.CHOICE:
			# Once the destination property has been set
			# Another choice can be declared, otherwise
			# concatenate!
			if !m_tmp_choice_destination.is_empty():
				__push_choice()
				return false

			if m_tmp_choice_id.is_empty():
				m_tmp_choice_id = sline
			else:
				m_tmp_choice_id += &" " + sline

		DSType.CHOICE_REQUIREMENT:
			p_tmp_choice_requirements.append(unwrap_tag(sline, 2))

		DSType.CHOICE_TARGET:
			m_tmp_choice_destination = unwrap_tag(sline)

		## Non-choice blocks automatically reverts the parser
		## to its normal state
		_:
			__push_choice()
			m_state = State.NORMAL

			return false

	return true


## Returns the DialogueScript type of a given line
static func identify_line(line: String) -> DSType:
	if line.begins_with(&"#"):
		return DSType.COMMENT

	# Choice-specific types #
	if is_indented(line):
		var sline := line.lstrip(" \t")

		if sline.begins_with(&"#"):
			return DSType.COMMENT
		elif sline.begins_with(&"[[") && sline.ends_with(&"]]"):
			return DSType.CHOICE_REQUIREMENT
		elif sline.begins_with(&"[") && sline.ends_with(&"]"):
			return DSType.CHOICE_TARGET

		return DSType.CHOICE

	line = line.strip_edges()

	if line.begins_with(&"[") && line.ends_with(&"]"):
		return DSType.BOOKMARK
	elif line.begins_with(&"<") && line.ends_with(&">"):
		return DSType.CHARACTER
	elif line.begins_with(&"@"):
		return DSType.EVENT

	return DSType.LINE


## Returns the contents of a tag line
static func unwrap_tag(line: String, step: int = 1) -> String:
	return line.substr(step, line.length() - (2 * step))


## Returns true if the given input is empty (spaces and tabs are ignored)
static func is_empty_line(line: String) -> bool:
	return line.lstrip(" \t\n").is_empty()


static func is_indented(line: String) -> bool:
	return line.begins_with(&"\t") || line.begins_with(&"    ")


#endregion

#region Writer

## Resets the writer's current state
func __reset_writer() -> void:
	m_write_started = false

	m_tmp_dialogue = &""
	m_tmp_character_id = &""
	p_tmp_choices.clear()
	p_tmp_events.clear()


## Resets the choice writer's current state
func __reset_choice_writer() -> void:
	m_tmp_choice_id = &""
	m_tmp_choice_destination = &""
	p_tmp_choice_requirements.clear()


## Pushes a new command to the current writer
func __push_event(line: String) -> void:
	var event_params := line.lstrip(&"@").split(" ")
	var event_size := event_params.size()

	# Check for valid command string
	if event_size < 1:
		return

	var event := DialogueEvent.new()
	event.m_command_id = event_params[0]

	if event_size > 1:
		for param: String in event_params.slice(1):
			event.p_parameters.append(param)

	p_tmp_events.append(event)


## Finalises the writer's current operation and resets its state
func __push_node(graph: DialogueGraph) -> void:
	if !m_write_started:
		return

	var node := DialogueNode.new()

	if !m_tmp_bookmark_id.is_empty():
		node.m_id = m_tmp_bookmark_id
		m_tmp_bookmark_id = &""

	node.m_character_id = m_tmp_character_id
	node.m_text = m_tmp_dialogue

	if !p_tmp_choices.is_empty():
		node.p_choices = p_tmp_choices.duplicate()

	if !p_tmp_events.is_empty():
		node.p_events = p_tmp_events.duplicate()

	graph.p_nodes.append(node)
	__reset_writer()


## Finalises the choice writer's current operation and resets its state
func __push_choice() -> void:
	if m_tmp_choice_id.is_empty() || m_tmp_choice_destination.is_empty():
		return

	var choice := DialogueChoice.new()
	choice.m_display_text = m_tmp_choice_id
	choice.m_target_id = m_tmp_choice_destination

	if !p_tmp_choice_requirements.is_empty():
		choice.p_required_flags = p_tmp_choice_requirements.duplicate()

	p_tmp_choices.append(choice)
	__reset_choice_writer()

#endregion
