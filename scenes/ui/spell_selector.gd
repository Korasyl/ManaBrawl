extends Control
class_name SpellSelector

@export var player_path: NodePath
@export var spells_folder: String = "res://resources/spells/"
@export var allow_empty: bool = true

# Dropdown references (set up in _ready via the scene tree)
var _dropdowns: Array[OptionButton] = []

# Tooltip panel nodes
var _tooltip_panel: Panel = null
var _tooltip_label: RichTextLabel = null

var _player: Node = null
var _spells: Array[SpellData] = []

const SLOT_COUNT := 4

func _ready() -> void:
	_player = _resolve_player()
	if _player == null:
		push_error("SpellSelector: Player not found. Set player_path or add Player to group 'player'.")
		return

	_spells = _load_spells(spells_folder)
	_build_ui()
	_sync_from_player()

# ---------------------------------------------------------------------------
# Player resolution (same pattern as AttunementSelector)
# ---------------------------------------------------------------------------

func _resolve_player() -> Node:
	if player_path != NodePath():
		return get_node_or_null(player_path)
	var p := get_tree().get_first_node_in_group("player")
	if p:
		return p
	return null

# ---------------------------------------------------------------------------
# Spell loading
# ---------------------------------------------------------------------------

func _load_spells(folder: String) -> Array[SpellData]:
	var out: Array[SpellData] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		push_error("SpellSelector: Could not open folder: %s" % folder)
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
		if res is SpellData:
			out.append(res)

	dir.list_dir_end()
	out.sort_custom(func(a, b): return a.spell_name < b.spell_name)
	return out

# ---------------------------------------------------------------------------
# Dynamic UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# --- Background panel ---
	var bg := Panel.new()
	bg.name = "BackgroundPanel"
	bg.position = Vector2(-6, 0)
	bg.size = Vector2(200, 28 + SLOT_COUNT * 28)
	add_child(bg)

	# --- VBoxContainer for slot rows ---
	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.position = Vector2(0, 0)
	vbox.size = Vector2(188, 0)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Spells"
	vbox.add_child(title)

	# Slot rows
	for i in range(SLOT_COUNT):
		var row := HBoxContainer.new()
		row.name = "Slot%dRow" % (i + 1)
		vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = "Slot %d" % (i + 1)
		lbl.custom_minimum_size.x = 44
		row.add_child(lbl)

		var dd := OptionButton.new()
		dd.name = "Slot%dDropdown" % (i + 1)
		dd.focus_mode = Control.FOCUS_NONE
		dd.custom_minimum_size.x = 140
		row.add_child(dd)

		_dropdowns.append(dd)

		# Connect selection signal (capture slot index via lambda)
		var slot_idx := i
		dd.item_selected.connect(func(item_idx): _apply_selection(slot_idx, item_idx))

		# Connect hover signals for tooltip
		dd.mouse_entered.connect(func(): _show_tooltip_for_dropdown(dd, slot_idx))
		dd.mouse_exited.connect(func(): _hide_tooltip())

	# --- Tooltip popup (starts hidden) ---
	_tooltip_panel = Panel.new()
	_tooltip_panel.name = "TooltipPanel"
	_tooltip_panel.visible = false
	_tooltip_panel.z_index = 100
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip_panel)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.name = "TooltipLabel"
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.position = Vector2(6, 4)
	_tooltip_label.size = Vector2(238, 200)
	_tooltip_panel.add_child(_tooltip_label)

	# Populate all dropdowns
	_refresh_all_dropdowns()

# ---------------------------------------------------------------------------
# Dropdown population with duplicate-prevention
# ---------------------------------------------------------------------------

func _refresh_all_dropdowns() -> void:
	# Gather which spells are currently selected in each slot
	var selected_spells: Array[SpellData] = []
	for i in range(SLOT_COUNT):
		selected_spells.append(_get_current_spell_for_slot(i))

	for i in range(SLOT_COUNT):
		_populate_dropdown(i, selected_spells)

func _populate_dropdown(slot_index: int, selected_spells: Array[SpellData]) -> void:
	var dd := _dropdowns[slot_index]
	var current_spell := selected_spells[slot_index]

	# Remember scroll position-ish: just track what we want selected
	dd.clear()

	if allow_empty:
		dd.add_item("— Empty —", -1)

	var select_idx := 0  # default to empty

	for i in range(_spells.size()):
		var spell := _spells[i]

		# Check if this spell is already used in another slot (duplicate prevention)
		var used_in_other_slot := false
		for s in range(SLOT_COUNT):
			if s == slot_index:
				continue
			if selected_spells[s] == spell:
				used_in_other_slot = true
				break

		if used_in_other_slot:
			continue  # Don't add spells that are already slotted elsewhere

		var label := spell.spell_name if spell.spell_name != "" else "Unnamed"
		dd.add_item(label, i)

		# Check if this is the currently selected spell for this slot
		if current_spell == spell:
			select_idx = dd.item_count - 1

	dd.select(select_idx)

func _get_current_spell_for_slot(slot_index: int) -> SpellData:
	if _player and _player.has_method("get_spell_slot"):
		return _player.call("get_spell_slot", slot_index)
	return null

# ---------------------------------------------------------------------------
# Selection handling
# ---------------------------------------------------------------------------

func _apply_selection(slot_index: int, item_index: int) -> void:
	var chosen: SpellData = null

	if allow_empty and item_index == 0:
		chosen = null
	else:
		# The item metadata id maps back to the _spells array index
		var dd := _dropdowns[slot_index]
		var spell_list_index: int = dd.get_item_id(item_index)
		if spell_list_index >= 0 and spell_list_index < _spells.size():
			chosen = _spells[spell_list_index]

	if _player and _player.has_method("set_spell_slot"):
		_player.call("set_spell_slot", slot_index, chosen)
	else:
		push_error("SpellSelector: Player missing method set_spell_slot(index, spell).")

	# Drop focus so Space/gameplay keys never interact with dropdown
	_dropdowns[slot_index].release_focus()

	# Refresh all dropdowns to update available options (duplicate prevention)
	_refresh_all_dropdowns()

	# Update tooltip if still hovering
	_show_tooltip_for_dropdown(_dropdowns[slot_index], slot_index)

# ---------------------------------------------------------------------------
# Sync dropdowns from player's current spell_slots on startup
# ---------------------------------------------------------------------------

func _sync_from_player() -> void:
	if not _player or not _player.has_method("get_spell_slot"):
		return

	# The dropdowns were already populated — just re-run refresh which handles selection
	_refresh_all_dropdowns()

# ---------------------------------------------------------------------------
# Tooltip display
# ---------------------------------------------------------------------------

func _show_tooltip_for_dropdown(dd: OptionButton, slot_index: int) -> void:
	var spell := _get_current_spell_for_slot(slot_index)
	if spell == null:
		_hide_tooltip()
		return

	var text := _build_tooltip_text(spell)
	_tooltip_label.text = text

	# Wait a frame so RichTextLabel computes content height
	await get_tree().process_frame
	if not is_instance_valid(_tooltip_panel):
		return

	var content_h := _tooltip_label.get_content_height() + 8
	var panel_w := 250.0
	_tooltip_panel.size = Vector2(panel_w, content_h)
	_tooltip_label.size = Vector2(panel_w - 12, content_h)

	# Position tooltip to the right of the dropdown
	var dd_rect := dd.get_global_rect()
	var tip_pos := Vector2(dd_rect.end.x + 8, dd_rect.position.y)

	# Convert from global to local for this Control
	_tooltip_panel.global_position = tip_pos
	_tooltip_panel.visible = true

func _hide_tooltip() -> void:
	if _tooltip_panel:
		_tooltip_panel.visible = false

func _build_tooltip_text(spell: SpellData) -> String:
	var lines: Array[String] = []
	lines.append("[b][color=white]%s[/color][/b]" % spell.spell_name)

	if spell.description != "":
		lines.append("[color=silver]%s[/color]" % spell.description)

	lines.append("")

	# Cast type tag
	var type_color := "cyan"
	match spell.cast_type:
		"free_aim": type_color = "cyan"
		"targeted": type_color = "orange"
		"toggled": type_color = "lime"
		"placement": type_color = "yellow"
	lines.append("[color=%s]%s[/color]" % [type_color, spell.cast_type.capitalize()])

	# Core stats
	lines.append("[color=dodgerblue]Mana:[/color] %.0f" % spell.mana_cost)
	lines.append("[color=goldenrod]Cooldown:[/color] %.1fs" % spell.cooldown)

	if spell.damage > 0:
		lines.append("[color=red]Damage:[/color] %.0f" % spell.damage)

	if spell.interrupt_type != "none" and spell.interrupt_type != "":
		lines.append("[color=coral]Interrupt:[/color] %s" % spell.interrupt_type.capitalize())

	# Channeled info
	if spell.is_channeled:
		lines.append("")
		lines.append("[color=violet]Channeled[/color]")
		lines.append("  Drain: %.0f mana/s" % spell.channel_mana_drain_per_second)
		lines.append("  Fire rate: %.2fs" % spell.channel_fire_interval)

	# Toggle info
	if spell.cast_type == "toggled":
		lines.append("[color=lime]Drain:[/color] %.0f mana/s" % spell.toggle_mana_drain)

	# Projectile speed (if relevant)
	if spell.projectile_speed > 0:
		lines.append("[color=silver]Speed:[/color] %.0f" % spell.projectile_speed)

	# Homing (if targeted with projectile delivery)
	if spell.cast_type == "targeted" and spell.targeted_delivery == "projectile":
		lines.append("[color=silver]Homing:[/color] %.0f deg/s" % rad_to_deg(spell.targeted_homing_turn_speed))

	# Movement modifiers
	if spell.prevent_move:
		lines.append("[color=red]Prevents movement[/color]")
	elif spell.slow_move != 1.0 and spell.cast_type != "toggled":
		lines.append("[color=yellow]Move speed: %.0f%%[/color]" % (spell.slow_move * 100))

	return "\n".join(lines)
