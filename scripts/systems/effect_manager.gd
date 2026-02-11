extends Node

## EffectManager — Autoload singleton for spawning VFX, playing SFX, and
## triggering screen feedback (shake, flash) in response to game events.
##
## SETUP:
## 1. Add this script as an Autoload in Project > Project Settings > Autoload
##    Name: "Effects"  Path: res://scripts/systems/effect_manager.gd
## 2. Create EffectProfile resources for different hit types, spells, etc.
## 3. Call Effects.play_hit(...) from take_damage, or Effects.play_profile(...)
##    from animation events.
##
## USAGE FROM PLAYER CODE:
##   Effects.play_hit(global_position, "melee", "heavy")
##   Effects.play_sfx(preload("res://audio/sfx/slash.wav"), global_position)
##   Effects.spawn_vfx(preload("res://scenes/vfx/spark.tscn"), global_position)
##   Effects.screen_shake(8.0, 0.15)
##
## USAGE FROM RIG ANIM EVENTS:
##   # In player's _on_rig_anim_event:
##   "impact":
##       var ws := crayola_rig.get_weapon_sprite()
##       var pos := ws.get_impact_position() if ws else global_position
##       Effects.play_profile(stats.light_attack_data.effect_profile, pos)

# ---- Screen Shake State (applied to active camera) ----

var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _shake_original_offset: Vector2 = Vector2.ZERO

# ---- Hitstop State ----

var _hitstop_timer: float = 0.0
var _hitstop_active: bool = false

# ---- Object Pool ----

## Pool of inactive AudioStreamPlayer nodes for SFX reuse
var _sfx_pool: Array[AudioStreamPlayer2D] = []
const SFX_POOL_SIZE: int = 16

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep running during hitstop
	_init_sfx_pool()

func _process(delta: float) -> void:
	_process_screen_shake(delta)
	_process_hitstop(delta)

# ========================================================================
# PUBLIC API
# ========================================================================

## Play a complete hit feedback package at a position.
## hit_type: "melee", "ranged", "spell", "block", "clash"
## strength: "light", "heavy", "critical"
func play_hit(position: Vector2, hit_type: String = "melee", strength: String = "light") -> void:
	# Hitstop
	match strength:
		"light":
			hitstop(0.04)
			screen_shake(3.0, 0.1)
		"heavy":
			hitstop(0.08)
			screen_shake(7.0, 0.2)
		"critical":
			hitstop(0.12)
			screen_shake(12.0, 0.25)

	# VFX (spawn default hit particles if no profile)
	# Override by using play_profile() with an EffectProfile resource instead

## Play an EffectProfile at a position (data-driven VFX+SFX combo).
func play_profile(profile: EffectProfile, position: Vector2) -> void:
	if profile == null:
		return

	# VFX
	if profile.vfx_scene:
		spawn_vfx(profile.vfx_scene, position, profile.vfx_scale, profile.vfx_rotation)

	# SFX
	if profile.sfx_stream:
		play_sfx(profile.sfx_stream, position, profile.sfx_volume_db, profile.sfx_pitch_variance)

	# Screen shake
	if profile.shake_intensity > 0:
		screen_shake(profile.shake_intensity, profile.shake_duration)

	# Hitstop
	if profile.hitstop_duration > 0:
		hitstop(profile.hitstop_duration)

## Spawn a VFX scene at a world position. Auto-frees after lifetime.
func spawn_vfx(scene: PackedScene, position: Vector2, vfx_scale: Vector2 = Vector2.ONE, rotation_deg: float = 0.0) -> Node:
	if scene == null:
		return null

	var instance := scene.instantiate()
	get_tree().current_scene.add_child(instance)
	instance.global_position = position
	instance.scale = vfx_scale
	instance.rotation_degrees = rotation_deg

	# Auto-free: if it's a GPUParticles2D, free after emission.
	# Otherwise free after 2 seconds as a safety net.
	if instance is GPUParticles2D:
		instance.emitting = true
		instance.finished.connect(instance.queue_free)
	elif instance is CPUParticles2D:
		instance.emitting = true
		instance.finished.connect(instance.queue_free)
	else:
		# Generic node — free after a delay
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(instance):
				instance.queue_free()
		)

	return instance

## Play a sound effect at a world position using the SFX pool.
func play_sfx(stream: AudioStream, position: Vector2 = Vector2.ZERO, volume_db: float = 0.0, pitch_variance: float = 0.0) -> void:
	if stream == null:
		return

	var player := _get_pooled_sfx()
	if player == null:
		return

	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	if pitch_variance > 0:
		player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	else:
		player.pitch_scale = 1.0
	player.play()

## Trigger screen shake on the active camera.
func screen_shake(intensity: float, duration: float) -> void:
	# Stack shakes by taking the stronger of current vs new
	if intensity > _shake_intensity:
		_shake_intensity = intensity
	_shake_duration = max(_shake_duration, duration)
	_shake_timer = _shake_duration

## Trigger hitstop (brief game freeze for impact feel).
## Does NOT affect this manager (process_mode = ALWAYS).
func hitstop(duration: float) -> void:
	if duration <= 0:
		return
	# Extend if already active
	_hitstop_timer = max(_hitstop_timer, duration)
	if not _hitstop_active:
		_hitstop_active = true
		get_tree().paused = true

## Flash a node white briefly (hit flash on sprites/rigs).
## Works on any CanvasItem. Restores original modulate after duration.
func hit_flash(target: CanvasItem, flash_color: Color = Color.WHITE, duration: float = 0.08) -> void:
	if target == null or not is_instance_valid(target):
		return

	var original_modulate := target.modulate
	target.modulate = flash_color

	# Use a timer that runs even during hitstop
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func():
		if is_instance_valid(target):
			target.modulate = original_modulate
	)

## Convenience: flash + shake + hitstop combo for a standard hit.
func hit_feedback(target: CanvasItem, position: Vector2, strength: String = "light") -> void:
	play_hit(position, "melee", strength)
	hit_flash(target, Color.WHITE, 0.08 if strength == "light" else 0.12)

# ========================================================================
# INTERNAL
# ========================================================================

func _process_screen_shake(delta: float) -> void:
	if _shake_timer <= 0:
		return

	_shake_timer -= delta

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		_shake_timer = 0
		return

	if _shake_timer > 0:
		var decay := _shake_timer / _shake_duration
		var offset := Vector2(
			randf_range(-_shake_intensity, _shake_intensity) * decay,
			randf_range(-_shake_intensity, _shake_intensity) * decay
		)
		camera.offset = offset
	else:
		camera.offset = Vector2.ZERO
		_shake_intensity = 0
		_shake_duration = 0

func _process_hitstop(delta: float) -> void:
	if not _hitstop_active:
		return

	_hitstop_timer -= delta
	if _hitstop_timer <= 0:
		_hitstop_active = false
		_hitstop_timer = 0
		get_tree().paused = false

func _init_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		player.bus = "SFX"  # Route to SFX audio bus (create in Audio tab)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_sfx_pool.append(player)

func _get_pooled_sfx() -> AudioStreamPlayer2D:
	for player in _sfx_pool:
		if not player.playing:
			return player

	# All busy — steal the oldest (first in pool)
	var stolen := _sfx_pool[0]
	stolen.stop()
	return stolen
