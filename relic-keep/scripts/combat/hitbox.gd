class_name Hitbox
extends Area2D
## Deals damage to any Hurtbox that overlaps it while active.
## Put it on layer 4 (PlayerAttack) for the player, layer 5 (EnemyAttack) for enemies. Mask stays empty.

signal hit_landed(hurtbox: Hurtbox)

@export var damage := 10
@export var knockback := 100.0
@export var start_active := false
## true = each Hurtbox is hit only once per set_active(true) (melee swings).
## false = can hit again after the Hurtbox's rehit_delay (contact damage).
@export var once_per_activation := true

var active := false
var is_crit := false
## Who owns this hitbox. Used for knockback direction and so you can't hit yourself.
var source: Node2D = null

var _already_hit := {}


func _ready() -> void:
	monitorable = true
	set_active(start_active)


func set_active(value: bool) -> void:
	active = value
	_already_hit.clear()
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", not value)


func try_hit(hurtbox: Hurtbox) -> bool:
	if not active:
		return false
	var id := hurtbox.get_instance_id()
	if once_per_activation and _already_hit.has(id):
		return false
	_already_hit[id] = true
	return true


## Where the hit "comes from" (for knockback direction).
func origin() -> Vector2:
	return source.global_position if is_instance_valid(source) else global_position


func notify_hit(hurtbox: Hurtbox) -> void:
	hit_landed.emit(hurtbox)
