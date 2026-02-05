extends Control
class_name StatsSwitcher

@export var player_path: NodePath
@export var stats_folder: String = "res://resources/character_stats/"
@export var explicit_stats: Array[CharacterStats] = []
@export var keep_ratios_on_swap: bool = true

@onready var dropdown: OptionButton = $StatsDropdown

var _player: Node = null
var _loaded_stats: Array[CharacterStats] = []

func _ready() -> void:
	_player = _resolve_player()
	if _player == null:
		push_error("StatsSwitcher: Player not found. Set player_path or add Player to a group.")
		return

	_loaded_stats = _gather_stats()
	_populate_dropdown(_loaded_stats)

	dropdown.item_selected.connect(_on_item_selected)

func _resolve_player() -> Node:
	if player_path != NodePath():
		return get_node_or_null(player_path)

	# Fallback: find by group if you add Player to group "player"
	var p := get_tree().get_first_node_in_group("player")
	if p:
		return p

	# Last resort: try common path (adjust if needed)
	return get_node_or_null("/root/TestEnvironment/Player")

func _gather_stats() -> Array[CharacterStats]:
	var out: Array[CharacterStats] = []

	# 1) Explicit list wins if provided
	for s in explicit_stats:
		if s != null:
			out.append(s)

	if out.size() > 0:
		return out

	# 2) Otherwise, scan folder for *.tres
	var dir := DirAccess.open(stats_folder)
	if dir == null:
		push_error("StatsSwitcher: Could not open folder: %s" % stats_folder)
		return out

	dir.list_dir_begin()
	while true:
		var file := dir.get_next()
		if file == "":
			break
		if dir.current_is_dir():
			continue
		if not file.ends_with(".tres"):
			continue

		var res_path := stats_folder.path_join(file)
		var res := load(res_path)
		if res is CharacterStats:
			out.append(res)

	dir.list_dir_end()
	return out

func _populate_dropdown(list: Array[CharacterStats]) -> void:
	dropdown.clear()

	for i in list.size():
		var s := list[i]
		var name := s.character_name if s.character_name != "" else ("Stats %d" % i)
		dropdown.add_item(name, i)

	# If player already has stats, select matching entry
	if _player.has_method("get") and _player.get("stats") != null:
		var current: CharacterStats = _player.get("stats")
		for i in list.size():
			if list[i] == current:
				dropdown.select(i)
				return

func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _loaded_stats.size():
		return

	var new_stats := _loaded_stats[index]
	if _player.has_method("set_character_stats"):
		_player.call("set_character_stats", new_stats, keep_ratios_on_swap)
	else:
		# Fallback: assign directly (less ideal, but functional)
		_player.set("stats", new_stats)
