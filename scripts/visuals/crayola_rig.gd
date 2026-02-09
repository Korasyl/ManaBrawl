extends Node2D
class_name CrayolaRig

@export var rig_scale: float = 2.0
@export var arm_lerp_speed: float = 18.0

const CHEST_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Chest.png")
const STOMACH_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Stomach.png")
const NECK_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Neck.png")
const HEAD_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Head.png")
const FRONT_ARM_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Front_Arm.png")
const FRONT_HAND_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Front_Hand.png")
const BACK_ARM_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Back_Arm.png")
const BACK_HAND_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Back_Hand.png")
const FRONT_LEG_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Front_Leg.png")
const FRONT_FOOT_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Front_Foot.png")
const BACK_LEG_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Back_Leg.png")
const BACK_FOOT_TEX := preload("res://sprites/crayola/bodyparts/Crayola_Back_Foot.png")

const TORSO_POSES := {
	"idle": Vector2(0.0, 0.0),
	"walk": Vector2(0.05, 0.0),
	"walk_back": Vector2(-0.05, 0.0),
	"sprint": Vector2(0.12, 0.0),
	"sprint_back": Vector2(-0.12, 0.0),
	"crouch": Vector2(0.0, 10.0),
	"crouchwalk": Vector2(0.06, 10.0),
	"crouchwalk_back": Vector2(-0.06, 10.0),
	"jump": Vector2(-0.05, -4.0),
	"fall": Vector2(0.05, -1.0),
	"hit": Vector2(-0.1, 0.0),
	"block": Vector2(-0.08, 0.0),
	"dash": Vector2(0.18, 0.0),
	"wall_cling": Vector2(-0.08, 0.0),
	"wall_slide": Vector2(-0.05, 0.0),
	"coalesce_ground": Vector2(-0.08, 0.0),
	"coalesce_air": Vector2(-0.06, -2.0),
	"coalesce_wall": Vector2(-0.06, 0.0),
	"ledge_grab": Vector2(-0.12, -1.0),
	"ledge_clamber": Vector2(-0.06, -1.0),
}

const ARM_POSES := {
	"idle": Vector2(0.08, -0.08),
	"walk": Vector2(0.25, -0.2),
	"walk_back": Vector2(-0.2, 0.25),
	"sprint": Vector2(0.4, -0.35),
	"sprint_back": Vector2(-0.35, 0.4),
	"crouch": Vector2(0.15, -0.1),
	"crouchwalk": Vector2(0.25, -0.15),
	"crouchwalk_back": Vector2(-0.15, 0.25),
	"jump": Vector2(-0.35, 0.3),
	"fall": Vector2(0.45, -0.25),
	"hit": Vector2(0.3, 0.2),
	"block": Vector2(-0.9, -0.7),
	"dash": Vector2(0.6, 0.5),
	"wall_cling": Vector2(-0.4, 0.15),
	"wall_slide": Vector2(-0.25, 0.1),
	"coalesce_ground": Vector2(-0.6, 0.6),
	"coalesce_air": Vector2(-0.55, 0.55),
	"coalesce_wall": Vector2(-0.5, 0.35),
	"ledge_grab": Vector2(-1.2, -1.0),
	"ledge_clamber": Vector2(-0.8, -0.6),
}

var _current_anim: String = "idle"
var _facing_right: bool = true
var _front_arm_angle: float = 0.0
var _back_arm_angle: float = 0.0
var _stomach_base_position: Vector2 = Vector2.ZERO

@onready var stomach_pivot: Node2D = $StomachPivot
@onready var back_arm_pivot: Node2D = $StomachPivot/ChestPivot/BackArmPivot
@onready var back_forearm: Node2D = $StomachPivot/ChestPivot/BackArmPivot/BackForearmPivot
@onready var front_arm_pivot: Node2D = $StomachPivot/ChestPivot/FrontArmPivot
@onready var front_forearm: Node2D = $StomachPivot/ChestPivot/FrontArmPivot/FrontForearmPivot

func _ready() -> void:
	_stomach_base_position = stomach_pivot.position
	scale = Vector2.ONE * rig_scale
	_apply_sprite_textures()
	_apply_pixel_settings(self)

func set_body_animation(anim: String) -> void:
	_current_anim = anim
	var torso_pose: Vector2 = TORSO_POSES.get(anim, Vector2.ZERO)
	stomach_pivot.rotation = torso_pose.x
	stomach_pivot.position = _stomach_base_position + Vector2(0.0, torso_pose.y)

func set_facing_right(value: bool) -> void:
	_facing_right = value
	scale.x = abs(rig_scale) if _facing_right else -abs(rig_scale)

func update_arm_pose(aim_override: bool, aim_world_pos: Vector2) -> void:
	if aim_override:
		var front_target := _compute_aim_angle(front_arm_pivot.global_position, aim_world_pos)
		var back_target := _compute_aim_angle(back_arm_pivot.global_position, aim_world_pos)
		_front_arm_angle = lerp_angle(_front_arm_angle, front_target, 0.15 * arm_lerp_speed / 18.0)
		_back_arm_angle = lerp_angle(_back_arm_angle, back_target, 0.15 * arm_lerp_speed / 18.0)
	else:
		var sign := 1.0 if _facing_right else -1.0
		var pose: Vector2 = ARM_POSES.get(_current_anim, Vector2(0.08, -0.08))
		_front_arm_angle = pose.x * sign
		_back_arm_angle = pose.y * sign

	front_arm_pivot.rotation = _front_arm_angle
	back_arm_pivot.rotation = _back_arm_angle
	front_forearm.rotation = _front_arm_angle * 0.25
	back_forearm.rotation = _back_arm_angle * 0.25

func _compute_aim_angle(shoulder_pos: Vector2, aim_world_pos: Vector2) -> float:
	var aim_angle := (aim_world_pos - shoulder_pos).angle() - PI / 2.0
	if _facing_right:
		return clamp(aim_angle, -1.45, 1.2)
	return clamp(aim_angle, -1.2, 1.45)

func _apply_sprite_textures() -> void:
	$StomachPivot/ChestPivot/Chest.texture = CHEST_TEX
	$StomachPivot/Stomach.texture = STOMACH_TEX
	$StomachPivot/ChestPivot/NeckPivot/Neck.texture = NECK_TEX
	$StomachPivot/ChestPivot/NeckPivot/HeadPivot/Head.texture = HEAD_TEX
	$StomachPivot/BackLegPivot/BackLeg.texture = BACK_LEG_TEX
	$StomachPivot/BackLegPivot/BackFootPivot/BackFoot.texture = BACK_FOOT_TEX
	$StomachPivot/FrontLegPivot/FrontLeg.texture = FRONT_LEG_TEX
	$StomachPivot/FrontLegPivot/FrontFootPivot/FrontFoot.texture = FRONT_FOOT_TEX
	$StomachPivot/ChestPivot/BackArmPivot/BackUpperArm.texture = BACK_ARM_TEX
	$StomachPivot/ChestPivot/BackArmPivot/BackForearmPivot/BackHand.texture = BACK_HAND_TEX
	$StomachPivot/ChestPivot/FrontArmPivot/FrontUpperArm.texture = FRONT_ARM_TEX
	$StomachPivot/ChestPivot/FrontArmPivot/FrontForearmPivot/FrontHand.texture = FRONT_HAND_TEX

func _apply_pixel_settings(root: Node) -> void:
	for child in root.get_children():
		if child is Sprite2D:
			child.centered = false
			child.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_apply_pixel_settings(child)
