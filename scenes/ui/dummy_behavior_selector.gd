extends Control
class_name DummyBehaviorSelector

@export var dummy_path: NodePath

@onready var dropdown: OptionButton = $BehaviorDropdown

var _dummy: Node = null

const MODE_LABELS := [
	"Light Combo",
	"Light > Heavy Mix-up",
	"Heavy Only",
	"Block",
	"Dash Evade",
]

func _ready() -> void:
	_dummy = _resolve_dummy()
	if _dummy == null:
		push_error("DummyBehaviorSelector: Dummy not found. Set dummy_path or add to group 'training_dummy'.")
		return

	_populate_dropdown()
	dropdown.item_selected.connect(_on_item_selected)
	dropdown.focus_mode = Control.FOCUS_NONE

func _resolve_dummy() -> Node:
	if dummy_path != NodePath():
		return get_node_or_null(dummy_path)

	var d := get_tree().get_first_node_in_group("training_dummy")
	if d:
		return d

	return get_node_or_null("/root/TestEnvironment/TrainingDummy")

func _populate_dropdown() -> void:
	dropdown.clear()
	for i in MODE_LABELS.size():
		dropdown.add_item(MODE_LABELS[i], i)

func _on_item_selected(index: int) -> void:
	if _dummy and _dummy.has_method("set_behavior_mode"):
		_dummy.set_behavior_mode(index)
