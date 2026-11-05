class_name Player
extends CharacterBody2D

# --- Movement ---
@export_group("Movement")
@export var max_speed: float = 180.0
@export var acceleration: float = 1400.0
@export var friction: float = 1800.0
@export var air_acceleration: float = 1000.0
@export var air_friction: float = 600.0

# --- Jumping ---
@export_group("Jumping")
@export var jump_velocity: float = -380.0
@export var jump_cut_multiplier: float = 0.4  # releasing jump early cuts upward speed
@export var gravity_scale: float = 1.0
@export var fall_gravity_multiplier: float = 1.5
@export var max_fall_speed: float = 600.0

# --- Dash ---
@export_group("Dash")
@export var dash_speed: float = 420.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_buffer_timer: Timer = $JumpBufferTimer
@onready var dash_timer: Timer = $DashTimer
@onready var dash_cooldown_timer: Timer = $DashCooldownTimer

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var facing: int = 1
var is_dashing: bool = false
var was_on_floor: bool = false


func _physics_process(delta: float) -> void:
	if is_dashing:
		_process_dash()
	else:
		_apply_gravity(delta)
		_handle_jump()
		_handle_horizontal(delta)
		_handle_dash_input()

	move_and_slide()
	_update_coyote()
	_update_animation()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity * gravity_scale
	if velocity.y > 0.0:
		g *= fall_gravity_multiplier
	velocity.y = minf(velocity.y + g * delta, max_fall_speed)


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer.start()

	var can_jump := is_on_floor() or not coyote_timer.is_stopped()
	if not jump_buffer_timer.is_stopped() and can_jump:
		velocity.y = jump_velocity
		jump_buffer_timer.stop()
		coyote_timer.stop()

	# Variable jump height: releasing early shortens the jump
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier


func _handle_horizontal(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	var accel := acceleration if is_on_floor() else air_acceleration
	var fric := friction if is_on_floor() else air_friction

	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * max_speed, accel * delta)
		facing = int(signf(direction))
	else:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)


func _handle_dash_input() -> void:
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer.is_stopped():
		is_dashing = true
		dash_timer.start()
		dash_cooldown_timer.start()


func _process_dash() -> void:
	velocity.x = facing * dash_speed
	velocity.y = 0.0  # no gravity during the dash
	if dash_timer.is_stopped():
		is_dashing = false


func _update_coyote() -> void:
	# Start coyote time the moment we walk off a ledge (not when jumping)
	if was_on_floor and not is_on_floor() and velocity.y >= 0.0:
		coyote_timer.start()
	was_on_floor = is_on_floor()


func _update_animation() -> void:
	sprite.flip_h = facing < 0

	var anim := "idle"
	if is_dashing:
		anim = "dash"
	elif not is_on_floor():
		anim = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 10.0:
		anim = "run"

	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)
