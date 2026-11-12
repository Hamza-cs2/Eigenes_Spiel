class_name Player
extends CharacterBody2D
## Player: run, variable jump, coyote time, jump buffer, air jumps (items), dash with i-frames,
## 3-hit combo attack (each swing goes where you're holding), ground slam (tap down in the air,
## falls through platforms but lands on ledges/ground), drop through platforms AND ledges (down + jump),
## knockback + i-frames when hit.

signal died
## Emitted when a ground slam hits the floor (useful for effects / sound).
signal slam_landed

const GRAVITY := 900.0
const MAX_FALL_SPEED := 480.0
const RUN_SPEED := 140.0
const GROUND_ACCEL := 1200.0
const GROUND_FRICTION := 1600.0
const AIR_ACCEL := 900.0
const JUMP_VELOCITY := -330.0
const AIR_JUMP_VELOCITY := -300.0
const JUMP_CUT := 0.45
const DASH_SPEED := 340.0
const DASH_TIME := 0.15
const BASE_DASH_COOLDOWN := 0.6
const HURT_INVINCIBILITY := 0.8
const KNOCKBACK_TIME := 0.18

const COMBO_DAMAGE := [1.0, 1.0, 1.6]
const COMBO_KNOCKBACK := [70.0, 70.0, 180.0]
const SWING_WINDUP := 0.05
const SWING_ACTIVE := 0.1
const SWING_RECOVER := 0.14
## Collision layer 7 "Platforms" (one-way, the slam falls through them) and
## layer 8 "Ledges" (one-way, between stacked rooms: the slam lands on them).
## Works with ANY tileset that puts its tiles on those layers.
const PLATFORM_LAYER_BIT := 64
const LEDGE_LAYER_BIT := 128
const DROP_THROUGH_TIME := 0.25

const SLAM_SPEED := 620.0
const SLAM_DAMAGE_MULT := 2.0
const SLAM_KNOCKBACK := 220.0
const SLAM_ACTIVE_TIME := 0.12

@onready var sprite: Sprite2D = $Sprite
@onready var attack_pivot: Node2D = $AttackPivot
@onready var hitbox: Hitbox = $AttackPivot/Hitbox
@onready var slash: Sprite2D = $AttackPivot/Slash
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var camera: Camera2D = $Camera2D
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_buffer_timer: Timer = $JumpBufferTimer
@onready var dash_timer: Timer = $DashTimer
@onready var dash_cooldown_timer: Timer = $DashCooldownTimer
@onready var invincible_timer: Timer = $InvincibleTimer
@onready var slam_hitbox: Hitbox = $SlamHitbox
@onready var slam_dust: CPUParticles2D = $SlamDust

var facing := 1
var is_dashing := false
var is_slamming := false
var air_jumps_left := 0
var attacking := false
var combo_index := 0
var combo_queued := false
var knockback_time := 0.0
var input_locked := false
var dead := false

var _was_on_floor := true
var _shake := 0.0
var _swing_id := 0
var _time := 0.0
var _drop_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	hitbox.source = self
	hitbox.hit_landed.connect(_on_hit_landed)
	slam_hitbox.source = self
	slam_hitbox.hit_landed.connect(_on_slam_hit_landed)
	hurtbox.hurt.connect(_on_hurt)
	dash_timer.timeout.connect(_end_dash)
	slash.visible = false


func _physics_process(delta: float) -> void:
	if dead:
		return
	_time += delta
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			set_collision_mask_value(8, true)
			if not is_slamming:
				set_collision_mask_value(7, true)
	var on_floor := is_on_floor()
	if on_floor:
		coyote_timer.start()
		air_jumps_left = int(GameState.get_stat("extra_jumps"))

	var dir := 0.0 if input_locked else Input.get_axis("move_left", "move_right")
	if not input_locked and Input.is_action_just_pressed("jump"):
		jump_buffer_timer.start()

	_check_slam_input(on_floor)

	if is_slamming:
		velocity = Vector2(0.0, SLAM_SPEED)
	elif is_dashing:
		velocity = Vector2(facing * DASH_SPEED, 0.0)
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
		if knockback_time > 0.0:
			knockback_time -= delta
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		else:
			var speed := RUN_SPEED * GameState.get_stat("move_speed")
			if attacking and on_floor:
				speed *= 0.3
			var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
			if dir != 0.0:
				velocity.x = move_toward(velocity.x, dir * speed, accel * delta)
				# Turning is always allowed, also mid-combo: the attack follows your direction keys.
				facing = 1 if dir > 0.0 else -1
			else:
				velocity.x = move_toward(velocity.x, 0.0, (GROUND_FRICTION if on_floor else AIR_ACCEL) * delta)
		_handle_jump()
		if Input.is_action_just_released("jump") and velocity.y < 0.0:
			velocity.y *= JUMP_CUT
		if not input_locked and Input.is_action_just_pressed("dash") and dash_cooldown_timer.is_stopped():
			_start_dash(dir)

	if not input_locked and not is_dashing and not is_slamming and Input.is_action_just_pressed("attack"):
		_request_attack()

	move_and_slide()
	if is_slamming and is_on_floor():
		_land_slam()
	_update_visuals(delta)


# ---------------------------------------------------------------- movement

func _handle_jump() -> void:
	if jump_buffer_timer.is_stopped():
		return
	if Input.is_action_pressed("move_down") and is_on_floor() and _standing_on_one_way():
		# Fall through: ignore platforms and ledges for a moment.
		set_collision_mask_value(7, false)
		set_collision_mask_value(8, false)
		_drop_timer = DROP_THROUGH_TIME
		jump_buffer_timer.stop()
		return
	if not coyote_timer.is_stopped():
		velocity.y = JUMP_VELOCITY
		coyote_timer.stop()
		jump_buffer_timer.stop()
		_squash(Vector2(0.75, 1.25))
	elif air_jumps_left > 0 and Input.is_action_just_pressed("jump"):
		air_jumps_left -= 1
		velocity.y = AIR_JUMP_VELOCITY
		jump_buffer_timer.stop()
		_squash(Vector2(0.8, 1.2))


func _standing_on_one_way() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < -0.5:
			var layer := PhysicsServer2D.body_get_collision_layer(col.get_collider_rid())
			if layer & (PLATFORM_LAYER_BIT | LEDGE_LAYER_BIT):
				return true
	return false


func _start_dash(dir: float) -> void:
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
	is_dashing = true
	dash_timer.start(DASH_TIME)
	dash_cooldown_timer.start(BASE_DASH_COOLDOWN * GameState.get_stat("dash_cooldown"))
	sprite.modulate = Color(0.6, 0.9, 1.5)


func _end_dash() -> void:
	is_dashing = false
	velocity.x = facing * RUN_SPEED
	sprite.modulate = Color.WHITE


# ---------------------------------------------------------------- ground slam

## Tap "move_down" while in the air -> slam straight down (through one-way platforms).
func _check_slam_input(on_floor: bool) -> void:
	if input_locked or on_floor or is_dashing or is_slamming:
		return
	if Input.is_action_just_pressed("move_down"):
		_start_slam()


func _start_slam() -> void:
	is_slamming = true
	set_collision_mask_value(7, false) # fall through platforms, land on ledges or solid ground
	# Cancel any running swing.
	_swing_id += 1
	attacking = false
	combo_index = 0
	hitbox.set_active(false)
	slash.visible = false
	sprite.modulate = Color(1.5, 1.2, 0.7)
	_squash(Vector2(0.7, 1.3))


func _land_slam() -> void:
	is_slamming = false
	set_collision_mask_value(7, true)
	sprite.modulate = Color.WHITE
	var dmg := GameState.get_stat("damage") * SLAM_DAMAGE_MULT
	slam_hitbox.is_crit = randf() < GameState.get_stat("crit_chance")
	if slam_hitbox.is_crit:
		dmg *= 2.0
	slam_hitbox.damage = roundi(dmg)
	slam_hitbox.knockback = SLAM_KNOCKBACK
	slam_hitbox.set_active(true)
	slam_dust.restart()
	slam_landed.emit()
	shake(6.0)
	_squash(Vector2(1.5, 0.6))
	await get_tree().create_timer(SLAM_ACTIVE_TIME, false).timeout
	slam_hitbox.set_active(false)


func _on_slam_hit_landed(_hurtbox: Hurtbox) -> void:
	GameState.on_player_dealt_damage(slam_hitbox.damage)
	GameState.hitstop(0.06)


# ---------------------------------------------------------------- attacking

func _request_attack() -> void:
	if attacking:
		combo_queued = true
	else:
		combo_index = 0
		_swing()


func _swing() -> void:
	attacking = true
	combo_queued = false
	_swing_id += 1
	var my_id := _swing_id
	var spd := GameState.get_stat("attack_speed")
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0 and not input_locked:
		facing = 1 if dir > 0.0 else -1
	attack_pivot.scale.x = facing

	await get_tree().create_timer(SWING_WINDUP / spd, false).timeout
	if dead or my_id != _swing_id:
		return
	var dmg: float = GameState.get_stat("damage") * COMBO_DAMAGE[combo_index]
	hitbox.is_crit = randf() < GameState.get_stat("crit_chance")
	if hitbox.is_crit:
		dmg *= 2.0
	hitbox.damage = roundi(dmg)
	hitbox.knockback = COMBO_KNOCKBACK[combo_index]
	hitbox.set_active(true)
	slash.visible = true
	slash.flip_v = combo_index == 1
	slash.scale = Vector2.ONE * (1.3 if combo_index == 2 else 1.0)

	await get_tree().create_timer(SWING_ACTIVE / spd, false).timeout
	hitbox.set_active(false)
	slash.visible = false
	if dead or my_id != _swing_id:
		return

	await get_tree().create_timer(SWING_RECOVER / spd, false).timeout
	if dead or my_id != _swing_id:
		return
	if combo_queued:
		combo_index = (combo_index + 1) % COMBO_DAMAGE.size()
		_swing()
	else:
		combo_index = 0
		attacking = false


func _on_hit_landed(_hurtbox: Hurtbox) -> void:
	GameState.on_player_dealt_damage(hitbox.damage)
	shake(1.5 if not hitbox.is_crit else 3.0)
	GameState.hitstop(0.03 if not hitbox.is_crit else 0.06)


# ---------------------------------------------------------------- getting hurt

func _on_hurt(hb: Hitbox) -> void:
	if dead:
		return
	var armor := GameState.get_stat("armor")
	var dmg := maxi(1, roundi(hb.damage * (1.0 - armor)))
	GameState.damage_player(dmg)
	GameState.spawn_damage_number(global_position + Vector2(0, -24), dmg, Color(1, 0.3, 0.3))
	var dir := signf(global_position.x - hb.origin().x)
	if dir == 0.0:
		dir = 1.0
	velocity = Vector2(dir * maxf(hb.knockback, 120.0), -140.0)
	knockback_time = KNOCKBACK_TIME
	invincible_timer.start(HURT_INVINCIBILITY)
	shake(5.0)
	if GameState.hp <= 0:
		_die()


func _die() -> void:
	dead = true
	hitbox.set_active(false)
	slash.visible = false
	hurtbox.invincible = true
	velocity = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color(1, 0.2, 0.2, 0.0), 0.8)
	died.emit()


# ---------------------------------------------------------------- helpers

## Called by the Run when a new level (region) starts. The only time the player is teleported.
func teleport(pos: Vector2, bounds: Rect2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	is_dashing = false
	is_slamming = false
	_drop_timer = 0.0
	set_collision_mask_value(7, true)
	set_collision_mask_value(8, true)
	sprite.modulate = Color.WHITE
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)
	camera.reset_smoothing()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _squash(s: Vector2) -> void:
	sprite.scale = s
	create_tween().tween_property(sprite, "scale", Vector2.ONE, 0.15)


func _update_visuals(delta: float) -> void:
	sprite.flip_h = facing < 0
	attack_pivot.scale.x = facing
	hurtbox.invincible = is_dashing or is_slamming or not invincible_timer.is_stopped()
	if not invincible_timer.is_stopped():
		sprite.visible = fmod(invincible_timer.time_left, 0.12) > 0.05
	else:
		sprite.visible = true
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_squash(Vector2(1.25, 0.8))
	_was_on_floor = on_floor
	if _shake > 0.0:
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
		_shake = move_toward(_shake, 0.0, 30.0 * delta)
	else:
		camera.offset = Vector2.ZERO
