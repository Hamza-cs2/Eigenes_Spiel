@tool
class_name DefenseRoom
extends RoomTemplate
## Room template script for relic rooms (room_type = DEFENSE).
## Needs a "RelicSpawn" Marker2D (on the floor) and EnemySpawns (where the waves come from).
## Press E at the relic: all exits of the room close, waves attack the relic.
## Relic survives -> legendary item. Relic breaks -> beat the remaining waves for nothing.

signal defense_started(relic: DefenseRelic)
signal wave_changed(wave: int, total: int)
signal defense_finished(success: bool)

const RELIC_SCENE := preload("res://scenes/rooms/defense_relic.tscn")
const SPAWN_INTERVAL := 0.5
const WAVE_PAUSE := 2.5

var relic: DefenseRelic
var total_waves := 3
var wave := 0
var finished := false
var _spawning := false
var _between_waves := false


func _populate_extra() -> void:
	total_waves = clampi(2 + level_index / 2, 3, 6)
	relic = RELIC_SCENE.instantiate()
	relic.item = GameState.roll_item(ItemData.Rarity.LEGENDARY)
	relic.max_durability = 120 + level_index * 20
	var marker := get_node_or_null("RelicSpawn") as Marker2D
	relic.position = marker.position if marker else Vector2(size_tiles * TILE) / 2.0
	add_child(relic)
	relic.activated.connect(_start_defense)
	relic.broken_signal.connect(_on_relic_broken)


func _start_defense() -> void:
	# Lock the room.
	for ex in get_exits():
		if ex.connected:
			ex.seal(get_tiles(), size_tiles)
	defense_started.emit(relic)
	message.emit("The doors seal shut. Protect the relic!")
	_next_wave()


func _next_wave() -> void:
	wave += 1
	wave_changed.emit(wave, total_waves)
	_spawning = true
	var count := mini(3 + wave + level_index / 2, 12)
	var ground: Array[Marker2D] = []
	var air: Array[Marker2D] = []
	for sp in get_markers("EnemySpawns"):
		if sp is EnemySpawn and sp.kind == EnemySpawn.Kind.AIR:
			air.append(sp)
		else:
			ground.append(sp)
	for i in count:
		var use_air := not air.is_empty() and (ground.is_empty() or rng.randf() < 0.25)
		var list := air if use_air else ground
		if list.is_empty():
			break
		var sp: Marker2D = list[rng.randi_range(0, list.size() - 1)]
		var e := spawn_enemy("flyer" if use_air else pick_ground_kind(), sp.position, relic)
		e.aggroed = true
		await get_tree().create_timer(SPAWN_INTERVAL, false).timeout
		if not is_inside_tree():
			return
	_spawning = false
	_check_wave_done()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or wave == 0 or finished:
		return
	_check_wave_done()


func _check_wave_done() -> void:
	if _spawning or _between_waves or finished or wave == 0 or alive_enemies() > 0:
		return
	if wave >= total_waves:
		_finish()
		return
	_between_waves = true
	message.emit("Wave %d cleared! Next wave incoming..." % wave)
	await get_tree().create_timer(WAVE_PAUSE, false).timeout
	if not is_inside_tree():
		return
	_between_waves = false
	_next_wave()


func _on_relic_broken() -> void:
	message.emit("The relic shattered! Survive the remaining waves...")


func _finish() -> void:
	finished = true
	for ex in get_exits():
		if ex.connected:
			ex.unseal(get_tiles())
	var success := not relic.broken
	if success:
		GameState.defenses_won += 1
		spawn_item(relic.item, relic.position)
		relic.queue_free()
		message.emit("Relic defended! Claim your reward. The doors open.")
	else:
		GameState.defenses_lost += 1
		message.emit("All waves beaten... but the relic is lost. The doors open.")
	defense_finished.emit(success)
