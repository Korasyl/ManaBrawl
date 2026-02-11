extends Control
class_name AIStrategySelector

@export var opponent_path: NodePath
@export var strategies_folder: String = "res://resources/ai_strategies/"

@onready var dropdown: OptionButton = $StrategyDropdown

var _opponent: Node = null
var _loaded_strategies: Array[AIStrategy] = []

func _ready() -> void:
	_loaded_strategies = _gather_strategies()
	dropdown.item_selected.connect(_on_item_selected)
	dropdown.focus_mode = Control.FOCUS_NONE
	refresh_binding()

func refresh_binding() -> void:
	_opponent = _resolve_opponent()
	visible = _opponent != null
	_populate_dropdown()

func _resolve_opponent() -> Node:
	if opponent_path != NodePath():
		return get_node_or_null(opponent_path)
	var ai := get_tree().get_first_node_in_group("ai_opponent")
	if ai:
		return ai
	return get_node_or_null("/root/TestEnvironment/AIOpponent")

func _gather_strategies() -> Array[AIStrategy]:
	var out: Array[AIStrategy] = []
	var dir := DirAccess.open(strategies_folder)
	if dir == null:
		push_error("AIStrategySelector: Could not open folder: %s" % strategies_folder)
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
		var res := load(strategies_folder.path_join(file))
		if res is AIStrategy:
			out.append(res)
	dir.list_dir_end()
	return out

func _populate_dropdown() -> void:
	dropdown.clear()
	for i in _loaded_strategies.size():
		var s := _loaded_strategies[i]
		dropdown.add_item(s.strategy_name, i)

	# Select matching current strategy
	if _opponent and "strategy" in _opponent and _opponent.strategy != null:
		for i in _loaded_strategies.size():
			if _loaded_strategies[i] == _opponent.strategy:
				dropdown.select(i)
				return

func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _loaded_strategies.size():
		return
	if _opponent == null:
		refresh_binding()
	if _opponent and _opponent.has_method("set_strategy"):
		_opponent.set_strategy(_loaded_strategies[index])
