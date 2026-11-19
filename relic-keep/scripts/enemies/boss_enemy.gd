class_name BossEnemy
extends Enemy
## Mini bosses and bosses. Waits until the arena calls activate(), then cycles through its attacks.
## Pick the attacks per boss in the Inspector (`attacks`):
##   "slash"  - telegraphed melee swing with a lunge
##   "charge" - glows, then rushes across the arena (contact damage), stunned briefly after
##   "slam"   - jumps at you and sends shockwaves along the ground both ways on landing
##   "volley" - fires a fan of arrows at you
##   "summon" - (phase 2 only) calls in helpers (summon_kinds)
## Below phase2_ratio HP it gets faster (phase 2).
##
## Node tree (see warden.tscn / keeper.tscn):
## Boss (CharacterBody2D, Layer 3, Mask 1+7+8) -> Sprite, CollisionShape2D, Hurtbox (Mask 4),
##   AttackPivot/Hitbox (Layer 5) + AttackPivot/Slash, BodyHitbox (hitbox.tscn, Layer 5), Muzzle (Marker2D)

signal summon_requested(kind: String, global_pos: Vector2)

@export_group("Boss")
@export var boss_title := "Boss"
@export var attacks: PackedStringArray = ["slash", "charge"]
@export_range(0.0, 1.0) var phase2_ratio := 0.5
## Pause between attacks (phase 2: 60% of this).
@export var attack_pause := 1.0
@export var slash_range := 44.0
@export var charge_speed_mult := 3.4
@export var shockwave_scene: PackedScene
@export var projectile_scene: PackedScene
@export var summon_kinds: PackedStringArray = []
@export var max_summons := 3

var active := false
var phase := 1
var busy := false
var _pause := 1.2
var _atk_id := 0

@onready var attack_pivot: Node2D = $AttackPivot
@onready var melee_hitbox: Hitbox = $AttackPivot/Hitbox
@onready var slash: Sprite2D = $AttackPivot/Slash
@onready var body_hitbox: Hitbox = $BodyHitbox
@onready var muzzle: Marker2D = $Muzzle


func _ready() -> void:
	super()
	melee_hitbox.source = self
	body_hitbox.source = self
	slash.visible = false


## Called by the arena when the fight starts.
func activate() -> void:
	active = true
	aggroed = true
	_pause = 1.0


func _pick_target() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	target = player if active and player and not player.dead else null


func _patrol(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)


func _ai(delta: float) -> void:
	if phase == 1 and hp <= max_hp * phase2_ratio:
		_enter_phase2()
	if busy:
		return
	var to := target.global_position - global_position
	facing = 1 if to.x > 0.0 else -1
	attack_pivot.scale.x = facing
	var dist := absf(to.x)
	_pause -= delta
	if _pause > 0.0:
		if dist > slash_range * 0.8:
			velocity.x = facing * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		return
	var options: Array[String] = []
	if "slash" in attacks and dist < slash_range * 1.5:
		options.append_array(["slash", "slash"])
	if "charge" in attacks and dist > 56.0:
		options.append("charge")
	if "slam" in attacks:
		options.append("slam")
	if "volley" in attacks and dist > 72.0 and projectile_scene:
		options.append("volley")
	if phase == 2 and "summon" in attacks and not summon_kinds.is_empty() and _summons_alive() < max_summons:
		options.append("summon")
	if options.is_empty():
		velocity.x = facing * move_speed
		return
	var choice: String = options[randi() % options.size()]
	call("_attack_" + choice)


func _enter_phase2() -> void:
	phase = 2
	move_speed *= 1.25
	sprite.self_modulate = Color(1.4, 0.8, 0.8)


func _next_pause() -> float:
	return attack_pause * (0.6 if phase == 2 else 1.0)


func _windup(time: float, color: Color) -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", color, time)
	await get_tree().create_timer(time, false).timeout
	sprite.modulate = Color.WHITE


func _speed() -> float:
	return 0.7 if phase == 2 else 1.0


# ---------------------------------------------------------------- attacks

func _attack_slash() -> void:
	busy = true
	_atk_id += 1
	var id := _atk_id
	velocity.x = 0.0
	await _windup(0.5 * _speed(), Color(2.0, 0.7, 0.7))
	if dead or id != _atk_id:
		return
	velocity.x = facing * 150.0
	melee_hitbox.damage = attack_damage
	melee_hitbox.knockback = 180.0
	melee_hitbox.set_active(true)
	slash.visible = true
	await get_tree().create_timer(0.18, false).timeout
	melee_hitbox.set_active(false)
	slash.visible = false
	await get_tree().create_timer(0.35 * _speed(), false).timeout
	_finish_attack(id)


func _attack_charge() -> void:
	busy = true
	_atk_id += 1
	var id := _atk_id
	velocity.x = 0.0
	await _windup(0.6 * _speed(), Color(2.2, 1.2, 0.5))
	if dead or id != _atk_id:
		return
	body_hitbox.damage = attack_damage
	body_hitbox.knockback = 220.0
	body_hitbox.set_active(true)
	var t := 0.0
	while t < 1.0 and not dead:
		velocity.x = facing * move_speed * charge_speed_mult
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > 0.1 and is_on_wall():
			break
	body_hitbox.set_active(false)
	velocity.x = 0.0
	# Stunned for a moment: your chance to punish.
	sprite.modulate = Color(0.6, 0.6, 0.8)
	await get_tree().create_timer(0.7 * _speed(), false).timeout
	sprite.modulate = Color.WHITE
	_finish_attack(id)


func _attack_slam() -> void:
	busy = true
	_atk_id += 1
	var id := _atk_id
	velocity.x = 0.0
	await _windup(0.35 * _speed(), Color(1.6, 1.6, 2.2))
	if dead or id != _atk_id or target == null:
		return
	velocity.y = -400.0
	velocity.x = clampf((target.global_position.x - global_position.x) * 1.3, -220.0, 220.0)
	await get_tree().create_timer(0.15, false).timeout
	var t := 0.0
	while not is_on_floor() and t < 2.0 and not dead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if dead or id != _atk_id:
		return
	velocity.x = 0.0
	body_hitbox.damage = attack_damage
	body_hitbox.knockback = 200.0
	body_hitbox.set_active(true)
	if shockwave_scene:
		for dir in [-1, 1]:
			var wave: Projectile = shockwave_scene.instantiate()
			wave.global_position = global_position + Vector2(dir * 12, -6)
			wave.launch(Vector2(dir, 0), 190.0, roundi(attack_damage * 0.7), self)
			wave.rotation = 0.0
			wave.scale.x = dir
			get_parent().add_child(wave)
	var player := target as Player
	if player:
		player.shake(5.0)
	await get_tree().create_timer(0.15, false).timeout
	body_hitbox.set_active(false)
	await get_tree().create_timer(0.5 * _speed(), false).timeout
	_finish_attack(id)


func _attack_volley() -> void:
	busy = true
	_atk_id += 1
	var id := _atk_id
	velocity.x = 0.0
	await _windup(0.5 * _speed(), Color(2.0, 1.8, 0.6))
	if dead or id != _atk_id or target == null:
		return
	muzzle.position.x = absf(muzzle.position.x) * facing
	var base_dir := (target_center() - muzzle.global_position).normalized()
	var count := 5 if phase == 2 else 3
	for i in count:
		var angle := (i - (count - 1) / 2.0) * 0.22
		var arrow: Projectile = projectile_scene.instantiate()
		arrow.global_position = muzzle.global_position
		arrow.launch(base_dir.rotated(angle), 230.0, roundi(attack_damage * 0.6), self)
		get_parent().add_child(arrow)
	await get_tree().create_timer(0.45 * _speed(), false).timeout
	_finish_attack(id)


func _attack_summon() -> void:
	busy = true
	_atk_id += 1
	var id := _atk_id
	velocity.x = 0.0
	await _windup(0.5, Color(1.6, 0.6, 2.0))
	if dead or id != _atk_id:
		return
	for i in 2:
		var kind: String = summon_kinds[randi() % summon_kinds.size()]
		var offset := Vector2((i * 2 - 1) * 60, -60 if kind == "flyer" else 0)
		summon_requested.emit(kind, global_position + offset)
	await get_tree().create_timer(0.4, false).timeout
	_finish_attack(id)


func _finish_attack(id: int) -> void:
	if id != _atk_id:
		return
	busy = false
	_pause = _next_pause()


func _summons_alive() -> int:
	var n := 0
	for e in get_parent().get_children():
		if e is Enemy and e != self and not e.dead:
			n += 1
	return n


func _die() -> void:
	_atk_id += 1
	busy = false
	melee_hitbox.set_active(false)
	body_hitbox.set_active(false)
	slash.visible = false
	super()
