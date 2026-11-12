class_name ArcherEnemy
extends Enemy
## Keeps its distance and shoots arrows at the target.

@export var projectile_scene: PackedScene
@export var preferred_distance := 120.0
@export var shot_windup := 0.6
@export var projectile_speed := 220.0

var shooting := false
var _shot_id := 0

@onready var muzzle: Marker2D = $Muzzle


func _ai(delta: float) -> void:
	if shooting:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		return
	var to := target.global_position - global_position
	facing = 1 if to.x > 0.0 else -1
	var dist := absf(to.x)
	if dist < preferred_distance * 0.6 and not is_on_wall() and _floor_behind():
		velocity.x = -facing * move_speed # back off
	elif dist > preferred_distance * 1.3 and has_floor_ahead():
		velocity.x = facing * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if attack_timer <= 0.0:
		_shoot()


func _floor_behind() -> bool:
	facing *= -1
	var ok := has_floor_ahead()
	facing *= -1
	return ok


func _shoot() -> void:
	shooting = true
	attack_timer = attack_cooldown
	_shot_id += 1
	var my_id := _shot_id
	var tw := create_tween()
	tw.tween_property(sprite, "self_modulate", Color(2.0, 1.6, 0.6), shot_windup)
	await get_tree().create_timer(shot_windup, false).timeout
	sprite.self_modulate = Color.WHITE
	shooting = false
	if dead or my_id != _shot_id or target == null or not is_instance_valid(target):
		return
	muzzle.position.x = absf(muzzle.position.x) * facing
	var arrow: Projectile = projectile_scene.instantiate()
	arrow.global_position = muzzle.global_position
	var dir: Vector2 = (target_center() - muzzle.global_position).normalized()
	arrow.launch(dir, projectile_speed, attack_damage, self)
	get_parent().add_child(arrow)


func _interrupt() -> void:
	_shot_id += 1
	shooting = false
	sprite.self_modulate = Color.WHITE
