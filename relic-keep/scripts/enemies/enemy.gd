class_name Enemy
extends CharacterBody2D
## Base class for every enemy. Dead-Cells-style behaviour:
##  - PATROL: walk back and forth around the spawn point, turn at walls and ledges, pause now and then
##  - AGGRO: only when the player is close, roughly on the same height and in line of sight
##  - lose interest when the player gets far away
## Also handles HP, getting hit, knockback, stun, dying, drops and the health bar.
## Subclasses override _ai(delta) (chasing/attacking) and optionally _patrol(delta) and _interrupt().

signal died(enemy: Enemy)

const GRAVITY := 900.0
const WORLD_MASK := 1 # layer 1: blocks line of sight
const FLOOR_MASK := 1 | 64 | 128 # world + platforms + ledges: something to stand on
const HEALTH_ORB := preload("res://scenes/items/health_orb.tscn")

@export var max_hp := 30
@export var move_speed := 50.0
@export var attack_damage := 10
@export_group("Detection")
## Player must be closer than this to be noticed (and visible).
@export var aggro_range := 130.0
## Max height difference to notice the player.
@export var vertical_aggro := 64.0
## Enemy gives up when the player is further away than this.
@export var lose_aggro_range := 260.0
@export_group("Patrol")
@export var patrol_speed_mult := 0.4
## How far from its spawn point the enemy wanders.
@export var patrol_radius := 90.0
@export_group("Combat")
@export var attack_range := 22.0
@export var attack_cooldown := 1.4
## 0 = full knockback, 1 = immovable.
@export_range(0.0, 1.0) var knockback_resist := 0.0
## If false, getting hit does not cancel this enemy's attack (heavy enemies).
@export var interruptible := true
@export var uses_gravity := true
@export_range(0.0, 1.0) var health_orb_chance := 0.15
@export var health_bar_offset := -26.0

var hp := 0
var target: Node2D = null
## Set by the defense room: the relic this enemy should attack.
var relic: DefenseRelic = null
var aggroed := false
var home := Vector2.ZERO
var stun_time := 0.0
var attack_timer := 0.0
var facing := 1
var dead := false

var _patrol_pause := 0.0
var _patrol_walk := 0.0

@onready var sprite: Sprite2D = $Sprite
@onready var hurtbox: Hurtbox = $Hurtbox


## Call BEFORE add_child to scale the enemy with the level.
func setup(hp_mult: float, damage_mult: float, p_relic: DefenseRelic = null) -> void:
	max_hp = roundi(max_hp * hp_mult)
	attack_damage = roundi(attack_damage * damage_mult)
	relic = p_relic


func _ready() -> void:
	hp = max_hp
	home = global_position
	add_to_group("enemies")
	hurtbox.hurt.connect(_on_hurt)
	attack_timer = randf_range(0.3, attack_cooldown)
	facing = 1 if randf() < 0.5 else -1
	_patrol_walk = randf_range(1.0, 3.0)
	# Spawn fade-in
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_pick_target()
	if uses_gravity:
		velocity.y = minf(velocity.y + GRAVITY * delta, 500.0)
	attack_timer = maxf(attack_timer - delta, 0.0)
	if stun_time > 0.0:
		stun_time -= delta
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		if not uses_gravity:
			velocity.y = move_toward(velocity.y, 0.0, 500.0 * delta)
	elif target == null:
		_patrol(delta)
	else:
		_ai(delta)
	move_and_slide()
	sprite.flip_h = facing < 0


## Override in subclasses: chase / attack the current target.
func _ai(_delta: float) -> void:
	pass


## Override: cancel a running attack.
func _interrupt() -> void:
	pass


# ---------------------------------------------------------------- target & detection

func _pick_target() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var player_ok := player != null and not player.dead
	if is_instance_valid(relic) and not relic.broken:
		# Defense room: go for the relic, but fight back if the player is right next to us.
		if player_ok and global_position.distance_to(player.global_position) < 45.0:
			target = player
		else:
			target = relic
		return
	if not player_ok:
		aggroed = false
		target = null
		return
	var dist := global_position.distance_to(player.global_position)
	if aggroed:
		if dist > lose_aggro_range:
			aggroed = false
			home = global_position # start patrolling where we lost them
	elif dist < aggro_range and absf(player.global_position.y - global_position.y) < vertical_aggro \
			and can_see(player.global_position):
		aggroed = true
	target = player if aggroed else null


func can_see(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(
			global_position + Vector2(0, -10), point + Vector2(0, -10), WORLD_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func target_center() -> Vector2:
	return target.global_position + Vector2(0, -10)


# ---------------------------------------------------------------- patrol

## Default ground patrol: walk, turn at walls / ledges / edge of patrol area, pause sometimes.
func _patrol(delta: float) -> void:
	if _patrol_pause > 0.0:
		_patrol_pause -= delta
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		if _patrol_pause <= 0.0 and randf() < 0.5:
			facing *= -1
		return
	_patrol_walk -= delta
	if _patrol_walk <= 0.0:
		_patrol_pause = randf_range(0.6, 1.8)
		_patrol_walk = randf_range(1.5, 3.5)
		return
	var too_far := (global_position.x - home.x) * facing > patrol_radius
	if is_on_wall() or too_far or (is_on_floor() and not has_floor_ahead()):
		facing *= -1
	velocity.x = facing * move_speed * patrol_speed_mult


## Is there ground in front of our feet? (so we don't walk off ledges while patrolling)
func has_floor_ahead(distance := 10.0) -> bool:
	var from := global_position + Vector2(facing * distance, -4)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 24), FLOOR_MASK)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# ---------------------------------------------------------------- damage

func _on_hurt(hb: Hitbox) -> void:
	if dead:
		return
	aggroed = true
	hp -= hb.damage
	GameState.spawn_damage_number(global_position + Vector2(0, health_bar_offset),
			hb.damage, Color(1, 0.85, 0.2) if hb.is_crit else Color.WHITE)
	sprite.modulate = Color(4, 4, 4)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)
	var dir := signf(global_position.x - hb.origin().x)
	var push := 1.0 - knockback_resist
	velocity.x = dir * hb.knockback * push
	if uses_gravity:
		velocity.y = -60.0 * push
	if interruptible:
		stun_time = 0.25 * push
		_interrupt()
	queue_redraw()
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	GameState.kills += 1
	hurtbox.set_deferred("monitoring", false)
	for child in find_children("*", "Area2D"):
		child.set_deferred("monitorable", false)
	collision_layer = 0
	if randf() < health_orb_chance:
		var orb := HEALTH_ORB.instantiate()
		orb.position = position + Vector2(0, -8)
		get_parent().call_deferred("add_child", orb)
	died.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.25)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if dead or hp >= max_hp:
		return
	var w := 18.0
	var y := health_bar_offset + 4.0
	draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 4), Color(0.1, 0.05, 0.1))
	draw_rect(Rect2(-w / 2, y, w * float(hp) / max_hp, 2), Color(0.9, 0.2, 0.25))
