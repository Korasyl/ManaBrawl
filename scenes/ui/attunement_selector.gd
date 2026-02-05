extends Control
class_name AttunementSelector

@export var player_path: NodePath
@export var attunements_folder: String = "res://resources/attunements/"
@export var allow_empty: bool = true

@onready var dd1: OptionButton = $VBoxContainer/Slot1Row/Slot1Dropdown
@onready var dd2: OptionButton = $VBoxContainer/Slot2Row/Slot2Dropdown
@onready var dd3: OptionButton = $VBoxContainer/Slot3Row/Slot3Dropdown
@onready var summary_label: Label = $SummaryBackgroundPanel/SummaryLabel

var _player: Node = null
var _attunements: Array[Attunement] = []

func _ready() -> void:
	_player = _resolve_player()
	if _player == null:
		push_error("AttunementSelector: Player not found. Set player_path or add Player to group 'player'.")
		return

	# Avoid keyboard focus stealing gameplay inputs
	for dd in [dd1, dd2, dd3]:
		dd.focus_mode = Control.FOCUS_NONE

	_attunements = _load_attunements(attunements_folder)

	_populate_dropdown(dd1)
	_populate_dropdown(dd2)
	_populate_dropdown(dd3)

	dd1.item_selected.connect(func(i): _apply_selection(0, i))
	dd2.item_selected.connect(func(i): _apply_selection(1, i))
	dd3.item_selected.connect(func(i): _apply_selection(2, i))

	_sync_from_player()

	# --- Quick retry hookup (wait a frame for Player to finish creating attunements) ---
	_try_hook_attunement_signals()
	await get_tree().process_frame
	_try_hook_attunement_signals()

	_update_summary()

func _resolve_player() -> Node:
	if player_path != NodePath():
		return get_node_or_null(player_path)

	var p := get_tree().get_first_node_in_group("player")
	if p:
		return p

	return null

func _load_attunements(folder: String) -> Array[Attunement]:
	var out: Array[Attunement] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		push_error("AttunementSelector: Could not open folder: %s" % folder)
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

		var res := load(folder.path_join(file))
		if res is Attunement:
			out.append(res)

	dir.list_dir_end()

	out.sort_custom(func(a, b): return a.attunement_name < b.attunement_name)
	return out

func _populate_dropdown(dd: OptionButton) -> void:
	dd.clear()
	if allow_empty:
		dd.add_item("— Empty —", -1)

	for i in range(_attunements.size()):
		var a := _attunements[i]
		var label := a.attunement_name if a.attunement_name != "" else "Unnamed"
		dd.add_item(label, i)

	if allow_empty:
		dd.select(0)

func _apply_selection(slot_index: int, item_index: int) -> void:
	var chosen: Attunement = null

	if allow_empty and item_index == 0:
		chosen = null
	else:
		var list_index := item_index - (1 if allow_empty else 0)
		if list_index >= 0 and list_index < _attunements.size():
			chosen = _attunements[list_index]

	if _player.has_method("set_attunement_slot"):
		_player.call("set_attunement_slot", slot_index, chosen)
		_update_summary()
	else:
		push_error("Player missing method set_attunement_slot(slot_index, attunement).")

	# Drop focus so Space never opens dropdown
	match slot_index:
		0: dd1.release_focus()
		1: dd2.release_focus()
		2: dd3.release_focus()

func _sync_from_player() -> void:
	# Optional: pre-select dropdowns to match current player slots
	if not _player.has_method("get_attunement_slot"):
		return

	var slots := [
		_player.call("get_attunement_slot", 0),
		_player.call("get_attunement_slot", 1),
		_player.call("get_attunement_slot", 2),
	]

	var dds := [dd1, dd2, dd3]

	for s in range(3):
		var a: Attunement = slots[s]
		if a == null:
			if allow_empty:
				dds[s].select(0)
			continue

		var found := -1
		for i in range(_attunements.size()):
			if _attunements[i] == a:
				found = i
				break

		if found != -1:
			dds[s].select(found + (1 if allow_empty else 0))

func _update_summary() -> void:
	if summary_label == null or _player == null:
		return

	var mgr = _player.get("attunements")
	var stats = _player.get("stats")

	if mgr == null or not mgr.has_method("get_debug_summary_text"):
		summary_label.text = "No attunement summary available."
		return

	summary_label.text = mgr.call("get_debug_summary_text", stats)

func _try_hook_attunement_signals() -> void:
	if _player == null:
		return

	var mgr = _player.get("attunements")
	if mgr == null:
		return

	if mgr.has_signal("attunements_changed"):
		# Avoid double-connecting
		if not mgr.attunements_changed.is_connected(_on_attunements_changed):
			mgr.attunements_changed.connect(_on_attunements_changed)

func _on_attunements_changed(_slots: Array) -> void:
	_update_summary()
	# Optional: also re-sync dropdown selection if changes could come from elsewhere
	# _sync_from_player()
