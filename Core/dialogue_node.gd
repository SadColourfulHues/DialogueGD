## A node representing a block of dialogue in the dialogue graph
class_name DialogueNode
extends RefCounted

var m_id: StringName
var m_character_id: StringName
var m_text: String

var p_events: Array[DialogueEvent]
var p_choices: Array[DialogueChoice]
