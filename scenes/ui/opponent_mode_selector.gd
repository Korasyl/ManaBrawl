extends Control
class_name OpponentModeSelector

signal opponent_mode_changed(mode: int, node: Node)

enum OpponentMode {
	NONE,
	TRAINING_DUMMY,
	AI_OPPONENT,
}

@export var world_root_path: NodePath
@export var spawn_position: Vector2 = Vector2(-313, 452)
@export var dummy_scene: PackedScene = preload("res://characters/training_dummy.tscn")
@export var ai_opponent_scene: PackedScene = preload("res://characters/ai_opponent.tscn")
@export var dummy_selector_path: NodePath
@export var ai_selector_path: NodePath

@onready var dropdown: OptionButton = $ModeDropdown

func _ready() -> void:
	dropdown.clear()
	dropdown.add_item("No Opponent", OpponentMode.NONE)
	dropdown.add_item("Training Dummy", OpponentMode.TRAINING_DUMMY)
	dropdown.add_item("AI Opponent", OpponentMode.AI_OPPONENT)
	dropdown.item_selected.connect(_on_mode_selected)
	dropdown.focus_mode = Control.FOCUS_NONE

	_sync_mode_from_scene()
	_refresh_selector_visibility()

func _sync_mode_from_scene() -> void:
	var mode := OpponentMode.NONE
	if get_tree().get_first_node_in_group("ai_opponent"):
		mode = OpponentMode.AI_OPPONENT
	elif get_tree().get_first_node_in_group("training_dummy"):
		mode = OpponentMode.TRAINING_DUMMY
	dropdown.select(mode)

func _on_mode_selected(index: int) -> void:
	_set_mode(index)

func _set_mode(mode: int) -> void:
	_clear_existing_opponents()
	var spawned: Node = null
	match mode:
		OpponentMode.TRAINING_DUMMY:
			spawned = _spawn_scene(dummy_scene, "TrainingDummy")
		OpponentMode.AI_OPPONENT:
			spawned = _spawn_scene(ai_opponent_scene, "AIOpponent")

	emit_signal("opponent_mode_changed", mode, spawned)
	_refresh_selector_visibility()
	# Deferred refresh_binding so the spawned node is fully in the tree.
	call_deferred("_refresh_selector_bindings")


func _set_selector_visible(path: NodePath, visible: bool) -> void:
	var selector := get_node_or_null(path)
	if selector and selector is CanvasItem:
		selector.visible = visible

func _spawn_scene(scene: PackedScene, fallback_name: String) -> Node:
	if scene == null:
		return null
	var root := _resolve_world_root()
	if root == null:
		return null
	var inst := scene.instantiate()
	root.add_child(inst)
	inst.global_position = spawn_position
	if inst.name == "":
		inst.name = fallback_name
	return inst

func _clear_existing_opponents() -> void:
	for n in get_tree().get_nodes_in_group("training_dummy"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("ai_opponent"):
		n.queue_free()

func _resolve_world_root() -> Node:
	if world_root_path != NodePath():
		var explicit := get_node_or_null(world_root_path)
		if explicit:
			return explicit
	return get_tree().current_scene

func _refresh_selector_visibility() -> void:
	# Use the dropdown selection as the source of truth — not tree scanning.
	# Tree scanning is unreliable because queue_free() is deferred.
	var mode := dropdown.selected as int
	_set_selector_visible(dummy_selector_path, mode == OpponentMode.TRAINING_DUMMY)
	_set_selector_visible(ai_selector_path, mode == OpponentMode.AI_OPPONENT)

func _refresh_selector_bindings() -> void:
	var mode := dropdown.selected as int
	match mode:
		OpponentMode.TRAINING_DUMMY:
			var sel := get_node_or_null(dummy_selector_path)
			if sel and sel.has_method("refresh_binding"):
				sel.call("refresh_binding")
		OpponentMode.AI_OPPONENT:
			var sel := get_node_or_null(ai_selector_path)
			if sel and sel.has_method("refresh_binding"):
				sel.call("refresh_binding")
