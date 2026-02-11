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

	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)

	_sync_mode_from_scene()
	_refresh_selector_visibility()

func _on_tree_changed(_node: Node) -> void:
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
	# Hide both control panels immediately so "No Opponent" never leaves stale UI visible
	_set_selector_visible(dummy_selector_path, false)
	_set_selector_visible(ai_selector_path, false)

	_clear_existing_opponents()
	var spawned: Node = null
	match mode:
		OpponentMode.TRAINING_DUMMY:
			spawned = _spawn_scene(dummy_scene, "TrainingDummy")
		OpponentMode.AI_OPPONENT:
			spawned = _spawn_scene(ai_opponent_scene, "AIOpponent")
		_:
			pass

	emit_signal("opponent_mode_changed", mode, spawned)
	_refresh_selector_visibility()
	# queue_free() removal resolves at frame end, so re-run once deferred for final truth
	call_deferred("_refresh_selector_visibility")


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
	var dummy_active := get_tree().get_first_node_in_group("training_dummy") != null
	var ai_active := get_tree().get_first_node_in_group("ai_opponent") != null

	var dummy_selector := get_node_or_null(dummy_selector_path)
	if dummy_selector and dummy_selector is CanvasItem:
		dummy_selector.visible = dummy_active
		if dummy_selector.has_method("refresh_binding"):
			dummy_selector.call("refresh_binding")

	var ai_selector := get_node_or_null(ai_selector_path)
	if ai_selector and ai_selector is CanvasItem:
		ai_selector.visible = ai_active
		if ai_selector.has_method("refresh_binding"):
			ai_selector.call("refresh_binding")
