@tool
class_name BossArena
extends RoomTemplate
## Room template script for MINIBOSS and BOSS rooms.
## Needs a "BossSpawn" Marker2D (on the floor) and boss_scene set in the Inspector.
## BOSS rooms also need a "LevelExit" Marker2D: the exit door stays sealed until the boss is dead.
## When you walk in, the doors close, the boss wakes up and its health bar appears.

signal boss_started(boss: Enemy, title: String)
signal boss_defeated(boss: Enemy)

@export var boss_scene: PackedScene
## How far inside the room (pixels from the left/right border) you must be before the fight starts.
@export var trigger_margin := 56.0

var boss: BossEnemy
var started := false
var finished := false
## Set by the level for BOSS rooms.
var exit_door: ExitDoor


func _populate_extra() -> void:
	if boss_scene == null:
		push_warning("BossArena '%s' has no boss_scene." % name)
		return
	boss = boss_scene.instantiate()
	var mult := 1.0 if room_type == RoomType.MINIBOSS else 1.0
	boss.setup(GameState.enemy_hp_mult() * mult, GameState.enemy_damage_mult())
	var marker := get_node_or_null("BossSpawn") as Marker2D
	boss.position = (marker.position if marker else Vector2(size_tiles * TILE) / 2.0) + Vector2(0, -1)
	enemies_root.add_child(boss)
	boss.died.connect(_on_boss_died)
	boss.summon_requested.connect(_on_summon)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or started or finished or boss == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var r := get_rect_px()
	var inner := Rect2(r.position.x + trigger_margin, r.position.y, r.size.x - trigger_margin * 2.0, r.size.y)
	if player and inner.has_point(player.global_position):
		start_fight()


func start_fight() -> void:
	if started:
		return
	started = true
	for ex in get_exits():
		if ex.connected:
			ex.seal(get_tiles(), size_tiles)
	boss.activate()
	boss_started.emit(boss, boss.boss_title)
	message.emit("%s awakens!" % boss.boss_title)


func _on_summon(kind: String, global_pos: Vector2) -> void:
	if finished:
		return
	var e := spawn_enemy(kind, to_local(global_pos))
	e.aggroed = true


func _on_boss_died(_e: Enemy) -> void:
	finished = true
	for ex in get_exits():
		if ex.connected:
			ex.unseal(get_tiles())
	# Helpers die with their master.
	for e in enemies_root.get_children():
		if e is Enemy and not e.dead and e != boss:
			e._die()
	var drop_pos := boss.position + Vector2(0, -2)
	if room_type == RoomType.BOSS:
		spawn_item(GameState.roll_item(ItemData.Rarity.LEGENDARY), drop_pos)
		for i in 2:
			var orb: Node2D = Enemy.HEALTH_ORB.instantiate()
			orb.position = drop_pos + Vector2(-30 + 60 * i, -10)
			add_child.call_deferred(orb)
		if exit_door:
			exit_door.set_locked(false)
			exit_door.prompt.text = "[E] Leave: %s" % exit_door.get_meta("region_name", "next region")
		message.emit("%s is defeated! The way onward is open." % boss.boss_title)
	else:
		var rarity := ItemData.Rarity.LEGENDARY if rng.randf() < 0.2 else ItemData.Rarity.RARE
		spawn_item(GameState.roll_item(rarity), drop_pos)
		message.emit("%s is defeated! The doors open." % boss.boss_title)
	boss_defeated.emit(boss)
