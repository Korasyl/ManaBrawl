extends Control

## Node references
@onready var mana_label = $ManaLabel
@onready var mana_bar = $ManaBar
@onready var health_label = $HealthLabel
@onready var health_bar = $HealthBar
@onready var state_label = $StateLabel
@onready var action_log = $ActionLog
@onready var animation_label = $AnimationLabel
@onready var combo_label = $ComboLabel
@onready var spell_label = $SpellLabel

## Action log history
var log_lines: Array[String] = []
const MAX_LOG_LINES = 3

## Smooth bar interpolation
var display_mana: float = -1.0  # -1 = uninitialised, snap on first update
var target_mana: float = 0.0
var display_health: float = -1.0
var target_health: float = 0.0
const BAR_LERP_SPEED: float = 10.0  # Exponential lerp rate

func _ready():
	print("=== DEBUG HUD READY ===")
	print("Mana Label: ", mana_label)
	print("Action Log: ", action_log)
	if action_log:
		print("Action Log class: ", action_log.get_class())
		action_log.text = "[color=yellow]Log initialized[/color]"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_hud"):
		visible = not visible
		get_viewport().set_input_as_handled()

func _process(delta):
	var weight := 1.0 - exp(-BAR_LERP_SPEED * delta)
	if mana_bar and display_mana >= 0 and display_mana != target_mana:
		display_mana = lerp(display_mana, target_mana, weight)
		if absf(display_mana - target_mana) < 0.5:
			display_mana = target_mana
		mana_bar.value = display_mana
	if health_bar and display_health >= 0 and display_health != target_health:
		display_health = lerp(display_health, target_health, weight)
		if absf(display_health - target_health) < 0.5:
			display_health = target_health
		health_bar.value = display_health

func update_mana(current: float, max_value: float):
	mana_label.text = "Mana: %.0f/%.0f" % [current, max_value]
	mana_bar.max_value = max_value
	target_mana = current
	if display_mana < 0:
		# First call — snap immediately so the bar doesn't animate from zero
		display_mana = current
		mana_bar.value = current

func update_health(current: float, max_value: float):
	health_label.text = "Health: %.0f/%.0f" % [current, max_value]
	health_bar.max_value = max_value
	target_health = current
	if display_health < 0:
		display_health = current
		health_bar.value = current

func update_state(state_text: String):
	state_label.text = "State: " + state_text

func log_action(action: String, mana_change: float = 0):
	var color = "white"
	var prefix = ""
	
	if mana_change < 0:
		color = "red"
		prefix = "%.0f mana" % mana_change
	elif mana_change > 0:
		color = "green"
		prefix = "+%.0f mana" % mana_change
	
	var log_text = action
	if prefix != "":
		log_text = "[color=%s]%s[/color] - %s" % [color, prefix, action]
	
	# Add to history
	log_lines.append(log_text)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.pop_front()
	
	# Update display
	action_log.text = "\n".join(log_lines)

func update_animation(anim_name: String):
	animation_label.text = "Animation: " + anim_name

func update_combo(count: int, window_active: bool):
	if combo_label:
		if window_active:
			combo_label.text = "Combo: %d (READY!)" % count
		elif count > 0:
			combo_label.text = "Combo: %d" % count
		else:
			combo_label.text = "Combo: 0"

func update_spells(slots: Array, cooldowns: Array, toggles: Array, queued: int):
	if not spell_label:
		return
	var lines: Array[String] = []
	for i in slots.size():
		if i >= 4:
			break
		var spell = slots[i]
		if spell == null:
			lines.append("[%d] --" % (i + 1))
			continue
		var status := ""
		if queued == i:
			status = "[color=violet]QUEUED[/color]"
		elif i < toggles.size() and toggles[i]:
			status = "[color=lime]ON[/color]"
		elif i < cooldowns.size() and cooldowns[i] > 0:
			status = "[color=red]CD %.1fs[/color]" % cooldowns[i]
		else:
			status = "[color=gray]Ready[/color]"
		lines.append("[%d] %s: %s" % [i + 1, spell.spell_name, status])
	spell_label.text = "\n".join(lines)
