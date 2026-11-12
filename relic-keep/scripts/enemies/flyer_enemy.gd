class_name FlyerEnemy
extends Enemy
## Flies toward the target, wobbling, then swoops in. Deals contact damage.

@export var swoop_speed_mult := 2.6
@export var swoop_time := 0.45

var _time := 0.0
var _swoop_left := 0.0
var _wander_timer := 0.0
var _wander_point := Vector2.ZERO

@onready var contact_hitbox: Hitbox = $ContactHitbox


func _ready() -> void:
	super()
	contact_hitbox.source = self
	contact_hitbox.damage = attack_damage
	contact_hitbox.hit_landed.connect(_on_contact)
	_time = randf() * TAU


func _ai(delta: float) -> void:
	_time += delta
	var to: Vector2 = target_center() - global_position
	facing = 1 if to.x > 0.0 else -1
	if _swoop_left > 0.0:
		_swoop_left -= delta
		velocity = velocity.move_toward(to.normalized() * move_speed * swoop_speed_mult, 900.0 * delta)
		return
	# Hover slightly above the target and wobble.
	var hover := to + Vector2(0, -30)
	var desired := hover.normalized() * move_speed + Vector2(0, sin(_time * 4.0) * 25.0)
	velocity = velocity.move_toward(desired, 250.0 * delta)
	if attack_timer <= 0.0 and to.length() < 110.0:
		attack_timer = attack_cooldown
		_swoop_left = swoop_time
		sprite.self_modulate = Color(2, 0.7, 0.7)
		create_tween().tween_property(sprite, "self_modulate", Color.WHITE, swoop_time)


## Flyers drift around their spawn point instead of walking.
func _patrol(delta: float) -> void:
	_time += delta
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.5, 3.0)
		_wander_point = home + Vector2(randf_range(-patrol_radius, patrol_radius), randf_range(-30, 30))
	var to := _wander_point - global_position
	if to.x != 0.0:
		facing = 1 if to.x > 0.0 else -1
	var desired := to.limit_length(move_speed * patrol_speed_mult) + Vector2(0, sin(_time * 3.0) * 10.0)
	velocity = velocity.move_toward(desired, 150.0 * delta)


func _on_contact(_hurtbox: Hurtbox) -> void:
	# Bounce away after hitting something.
	_swoop_left = 0.0
	velocity = (global_position - target_center()).normalized() * move_speed * 2.0 if target else Vector2.ZERO


func _interrupt() -> void:
	_swoop_left = 0.0
