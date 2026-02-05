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

## Action log history
var log_lines: Array[String] = []
const MAX_LOG_LINES = 3

func _ready():
	print("=== DEBUG HUD READY ===")
	print("Mana Label: ", mana_label)
	print("Action Log: ", action_log)
	if action_log:
		print("Action Log class: ", action_log.get_class())
		action_log.text = "[color=yellow]Log initialized[/color]"

func update_mana(current: float, max_value: float):
	mana_label.text = "Mana: %.0f/%.0f" % [current, max_value]
	mana_bar.max_value = max_value
	mana_bar.value = current

func update_health(current: float, max_value: float):
	health_label.text = "Health: %.0f/%.0f" % [current, max_value]
	health_bar.max_value = max_value
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
			combo_label.text = "[color=lime]Combo: %d (READY!)[/color]" % count
		elif count > 0:
			combo_label.text = "Combo: %d" % count
		else:
			combo_label.text = "Combo: 0"
