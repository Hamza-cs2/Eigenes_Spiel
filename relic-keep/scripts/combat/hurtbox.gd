class_name Hurtbox
extends Area2D
## Receives hits. Layer stays empty; Mask = the attack layer that should hurt it
## (Player: 5 EnemyAttack, Enemies: 4 PlayerAttack, Relic: 5 EnemyAttack).

signal hurt(hitbox: Hitbox)

## How long the SAME hitbox has to wait before it can hit this hurtbox again (contact damage).
@export var rehit_delay := 0.5

var invincible := false
var _cooldowns := {}


func _ready() -> void:
	monitoring = true
	monitorable = false


func _physics_process(delta: float) -> void:
	for id in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)
	if invincible or not monitoring:
		return
	for area in get_overlapping_areas():
		var hb := area as Hitbox
		if hb == null or not hb.active or hb.source == owner:
			continue
		var id := hb.get_instance_id()
		if _cooldowns.has(id) or not hb.try_hit(self):
			continue
		_cooldowns[id] = rehit_delay
		hurt.emit(hb)
		hb.notify_hit(self)
		if invincible:
			return
