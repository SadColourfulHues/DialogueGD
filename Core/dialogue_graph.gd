## An object representing a usable version of a dialogue script
class_name DialogueGraph
extends RefCounted

var p_nodes: Array[DialogueNode]


#region Utils

## Returns a DialogueNode with the specified bookmark ID from this graph
## (Returns null if noything was found)
func find_node(id: StringName) -> DialogueNode:
    for node: DialogueNode in p_nodes:
        if node.m_id != id:
            continue

        return node
    return null

#endregion
