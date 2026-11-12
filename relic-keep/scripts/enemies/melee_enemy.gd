class_name MeleeEnemy
extends Enemy
## Walks to its target and does a telegraphed melee attack.
## Used by walker.tscn (fast, weak) and brute.tscn (slow, heavy, not interruptible).

@export var windup := 0.45
@export var attack_active_time := 0.15
## Forward burst when the attack comes out.
@export var lunge := 60.0
@export var jump_velocity := -300.0

var attacking := false
var _attack_id := 0
var _jump_cooldown := 0.0

@onready var attack_pivot: Node2D = $AttackPivot
@onready var attack_hitbox: Hitbox = $AttackPivot/Hitbox
@onready var slash: Sprite2D = $AttackPivot/Slash


func _ready() -> void:
	super()
	attack_hitbox.source = self
	slash.visible = false


func _ai(delta: float) -> void:
	_jump_cooldown -= delta
	if attacking:
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
		return
	var to := target.global_position - global_position
	facing = 1 if to.x > 0.0 else -1
	var dist_x := absf(to.x)
	if dist_x <= attack_range and absf(to.y) < 36.0:
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
		if attack_timer <= 0.0:
			_attack()
		return
	# Don't run off a ledge unless the target is below us.
	if is_on_floor() and not has_floor_ahead() and to.y < 16.0:
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
	else:
		velocity.x = facing * move_speed
	if is_on_floor() and _jump_cooldown <= 0.0:
		# Hop up steps, or jump up to a target on a platform above.
		if is_on_wall() or (to.y < -30.0 and dist_x < 70.0):
			velocity.y = jump_velocity
			_jump_cooldown = 0.8


func _attack() -> void:
	attacking = true
	attack_timer = attack_cooldown
	_attack_id += 1
	var my_id := _attack_id
	attack_pivot.scale.x = facing
	# Telegraph: glow red so the player can react.
	var tw := create_tween()
	tw.tween_property(sprite, "self_modulate", Color(2.0, 0.6, 0.6), windup)
	await get_tree().create_timer(windup, false).timeout
	sprite.self_modulate = Color.WHITE
	if dead or my_id != _attack_id:
		return
	velocity.x = facing * lunge
	attack_hitbox.damage = attack_damage
	attack_hitbox.set_active(true)
	slash.visible = true
	await get_tree().create_timer(attack_active_time, false).timeout
	attack_hitbox.set_active(false)
	slash.visible = false
	if dead or my_id != _attack_id:
		return
	await get_tree().create_timer(0.3, false).timeout
	if my_id == _attack_id:
		attacking = false


func _interrupt() -> void:
	_attack_id += 1
	attacking = false
	attack_hitbox.set_active(false)
	slash.visible = false
	sprite.self_modulate = Color.WHITE
