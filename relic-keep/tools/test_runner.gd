extends Node
## Automated smoke test. Run with:
##   godot --headless --path . --fixed-fps 60 res://tools/test_runner.tscn
## Checks every scene loads, generates lots of levels, then plays a run.

var fails := 0


func _ready() -> void:
	await _check_all_resources()
	_check_templates()
	await _check_level_generation()
	await _play_test()
	print("=== TEST DONE, failures: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _check_all_resources() -> void:
	print("--- loading all resources")
	var bad := 0
	for path in _walk("res://"):
		if not (path.ends_with(".gd") or path.ends_with(".tscn") or path.ends_with(".tres")):
			continue
		if path.begins_with("res://tools/"):
			continue
		var res = load(path)
		if res == null:
			bad += 1
			print("  FAIL load ", path)
		elif res is PackedScene:
			var inst: Node = res.instantiate()
			if inst == null:
				bad += 1
				print("  FAIL instantiate ", path)
			else:
				inst.free()
	check(bad == 0, "all scripts/scenes/resources load")
	fails += 0


func _walk(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_walk(dir.path_join(d)))
	return out


func _check_templates() -> void:
	print("--- room templates")
	var t := RoomLibrary.get_templates()
	var by_type := {}
	for m in t:
		by_type[m.type] = by_type.get(m.type, 0) + 1
	check(t.size() >= 15, "%d valid templates found (base template ignored)" % t.size())
	for type in RoomTemplate.RoomType.values():
		check(by_type.get(type, 0) > 0, "has %s rooms: %d" % [RoomTemplate.RoomType.keys()[type], by_type.get(type, 0)])


func _check_level_generation() -> void:
	print("--- level generation (40 levels)")
	var rng := RandomNumberGenerator.new()
	var overlaps := 0
	var bad_exits := 0
	var missing := 0
	var blocked_passages := 0
	var close_enemies := 0
	var room_counts := []
	var vertical := 0
	var total_loops := 0
	var two_exits := 0
	var max_w := 0
	var max_h := 0
	var long_stacks := 0
	for i in 40:
		rng.seed = i * 7919
		GameState.depth = 1 + i % 6
		var lvl := Level.new()
		add_child(lvl)
		lvl.build(rng, GameState.depth, i % 6, i % 2 == 0)
		room_counts.append(lvl.rooms.size())
		total_loops += lvl.loops
		if lvl.exit_markers.size() >= 2:
			two_exits += 1
		max_w = maxi(max_w, int(lvl.bounds.size.x / 16))
		max_h = maxi(max_h, int(lvl.bounds.size.y / 16))
		long_stacks += _count_long_stacks(lvl)
		var types := lvl.rooms.map(func(r: RoomTemplate) -> int: return r.room_type)
		if not (RoomTemplate.RoomType.START in types and RoomTemplate.RoomType.END in types):
			missing += 1
		if i % 2 == 0 and not RoomTemplate.RoomType.DEFENSE in types:
			missing += 1
		for a in lvl.rooms.size():
			var ra := lvl.rooms[a]
			for b in range(a + 1, lvl.rooms.size()):
				if Rect2i(ra.origin_tiles, ra.size_tiles).intersects(Rect2i(lvl.rooms[b].origin_tiles, lvl.rooms[b].size_tiles)):
					overlaps += 1
			for ex in ra.get_exits():
				if ex.dir >= RoomExit.Dir.UP and ex.connected:
					vertical += 1
				var cells := ex.opening_cells(ra.size_tiles)
				var tiles := ra.get_tiles()
				for cell in cells:
					var atlas := tiles.get_cell_atlas_coords(cell)
					if ex.connected and atlas == Vector2i(0, 0):
						blocked_passages += 1
					if not ex.connected and atlas != Vector2i(0, 0):
						bad_exits += 1
			var enemies := ra.enemies_root.get_children()
			for x in enemies.size():
				for y in range(x + 1, enemies.size()):
					if enemies[x].position.distance_to(enemies[y].position) < RoomTemplate.MIN_ENEMY_SPACING - 1:
						close_enemies += 1
		lvl.free()
		await get_tree().process_frame
	check(missing == 0, "every level has START + END (+ DEFENSE when asked)")
	check(overlaps == 0, "no rooms overlap")
	check(bad_exits == 0, "all unused exits are walled up")
	check(blocked_passages == 0, "all connected exits are open")
	check(close_enemies == 0, "no enemies spawn inside each other")
	check(vertical > 10, "levels go up and down (%d vertical connections)" % vertical)
	check(total_loops >= 40, "levels have loops (%d loops in 40 levels)" % total_loops)
	check(two_exits >= 30, "most levels have 2 exits to different regions (%d/40)" % two_exits)
	check(long_stacks == 0, "no room stacks taller than %d rooms straight down" % Level.MAX_VERTICAL_GROUP)
	check(room_counts.min() >= 16, "levels are big (%d-%d rooms, up to %dx%d tiles)" % [room_counts.min(), room_counts.max(), max_w, max_h])


## Follows connected DOWN exits room by room and returns how many chains are longer than allowed.
func _count_long_stacks(lvl: Level) -> int:
	var below := {}
	for r in lvl.rooms:
		for ex in r.get_exits():
			if ex.connected and ex.dir == RoomExit.Dir.DOWN:
				var target := r.origin_tiles + ex.tile_pos() + Vector2i(0, 1)
				for r2 in lvl.rooms:
					if Rect2i(r2.origin_tiles, r2.size_tiles).has_point(target):
						below[r] = r2
	var bad := 0
	for r in below:
		var n := 1
		var cur = r
		while below.has(cur) and n < 10:
			cur = below[cur]
			n += 1
		if n > Level.MAX_VERTICAL_GROUP:
			bad += 1
	return bad


func _find_ledge(lvl: Level) -> Dictionary:
	for room in lvl.rooms:
		var tiles := room.get_tiles()
		for cell in tiles.get_used_cells():
			if tiles.get_cell_atlas_coords(cell) == Vector2i(3, 0):
				return {"room": room, "cell": cell}
	return {}


func _find_platform_spot(lvl: Level) -> Dictionary:
	# A platform cell with open air above and solid ground somewhere below it.
	for room in lvl.rooms:
		var tiles := room.get_tiles()
		for cell in tiles.get_used_cells():
			if tiles.get_cell_atlas_coords(cell) != Vector2i(2, 0) or cell.y < 4:
				continue
			if tiles.get_cell_source_id(cell + Vector2i(0, -1)) != -1 or tiles.get_cell_source_id(cell + Vector2i(0, -2)) != -1:
				continue
			for dy in range(1, 12):
				var below := cell + Vector2i(0, dy)
				var src := tiles.get_cell_source_id(below)
				if src != -1:
					if tiles.get_cell_atlas_coords(below) != Vector2i(2, 0) and dy >= 3:
						return {"room": room, "cell": cell, "ground": below}
					break
	return {}


func _play_test() -> void:
	print("--- play test")
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await wait(0.2)
	main.start_run()
	await wait(0.6)
	var run: Node = main.current
	var player: Player = run.player
	var lvl: Level = run.level
	check(GameState.depth == 1, "run starts on level 1 (%s)" % lvl.region.name)
	check(player.is_on_floor(), "player stands on the floor in the start room")
	check(player.camera.limit_right == int(lvl.bounds.end.x), "camera limited to the whole level")

	# Movement
	var x0 := player.global_position.x
	var right := 1 if lvl.rooms[0].get_exits()[0].dir == RoomExit.Dir.RIGHT else -1
	Input.action_press("move_right" if right == 1 else "move_left")
	await wait(0.5)
	Input.action_release("move_right" if right == 1 else "move_left")
	check(absf(player.global_position.x - x0) > 30, "player moves")

	# Enemies patrol while the player is far away
	var all_enemies: Array = get_tree().get_nodes_in_group("enemies")
	var far := all_enemies.filter(func(e: Enemy) -> bool:
		return e.uses_gravity and e.global_position.distance_to(player.global_position) > 400)
	var start_pos := far.map(func(e: Enemy) -> Vector2: return e.global_position)
	await wait(4.0)
	var moved := 0
	for i in far.size():
		if is_instance_valid(far[i]) and far[i].global_position.distance_to(start_pos[i]) > 8:
			moved += 1
	check(far.size() > 0 and moved >= far.size() / 2, "idle enemies patrol (%d/%d moved)" % [moved, far.size()])
	check(far.all(func(e: Enemy) -> bool: return not is_instance_valid(e) or not e.aggroed), "far enemies are not aggroed")

	# Aggro needs closeness: put a walker next to the player
	var w: Enemy = lvl.rooms[0].spawn_enemy("walker", lvl.rooms[0].to_local(player.global_position) + Vector2(60, 0))
	await wait(0.5)
	check(w.aggroed, "enemy close to the player notices him")
	w._die()
	GameState.heal_player(999)

	# Slam: tap down in the air, falls THROUGH a platform onto solid ground
	print("--- slam + platforms")
	var spot := _find_platform_spot(lvl)
	check(not spot.is_empty(), "found a platform to test on")
	if not spot.is_empty():
		var room: RoomTemplate = spot.room
		var visited_before := room.visited
		var plat_world: Vector2 = room.to_global(Vector2(spot.cell * 16) + Vector2(8, 0))
		var ground_y: float = room.to_global(Vector2(spot.ground * 16)).y
		player.global_position = plat_world + Vector2(0, -1)
		player.velocity = Vector2.ZERO
		await wait(0.3)
		check(player.is_on_floor() and absf(player.global_position.y - plat_world.y) < 2, "player can stand on a platform")
		var slams := [0]
		player.slam_landed.connect(func() -> void: slams[0] += 1)
		Input.action_press("jump")
		await wait(0.15)
		Input.action_release("jump")
		await wait(0.05)
		Input.action_press("move_down")
		await wait(0.04)
		Input.action_release("move_down")
		await wait(0.8)
		check(slams[0] == 1, "single tap down in the air slams")
		check(absf(player.global_position.y - ground_y) < 2, "slam went through the platform to the ground (y %.0f, ground %.0f)" % [player.global_position.y, ground_y])
		check(player.get_collision_mask_value(7), "platform collision restored after slam")
		# Tap down on the ground does nothing
		Input.action_press("move_down")
		await wait(0.04)
		Input.action_release("move_down")
		await wait(0.3)
		check(slams[0] == 1, "tap down on the ground does not slam")
		# Drop through: stand on platform, down + jump
		player.global_position = plat_world + Vector2(0, -1)
		await wait(0.3)
		Input.action_press("move_down")
		Input.action_press("jump")
		await wait(0.05)
		Input.action_release("jump")
		await wait(0.05)
		Input.action_release("move_down")
		await wait(0.8)
		check(player.global_position.y > plat_world.y + 8 and slams[0] == 1, "down + jump drops through the platform (no slam)")

	# Slam lands on ledges between stacked rooms (no falling through the whole level)
	var ledge := _find_ledge(lvl)
	check(not ledge.is_empty(), "level has ledges between stacked rooms")
	if not ledge.is_empty():
		var lroom: RoomTemplate = ledge.room
		var ledge_world: Vector2 = lroom.to_global(Vector2(ledge.cell * 16) + Vector2(8, 0))
		player.global_position = ledge_world + Vector2(0, -40)
		player.velocity = Vector2.ZERO
		await wait(0.05)
		Input.action_press("move_down")
		await wait(0.04)
		Input.action_release("move_down")
		await wait(0.6)
		check(absf(player.global_position.y - ledge_world.y) < 2, "slam stops on the ledge (y %.0f, ledge %.0f)" % [player.global_position.y, ledge_world.y])
		Input.action_press("move_down")
		Input.action_press("jump")
		await wait(0.05)
		Input.action_release("jump")
		await wait(0.05)
		Input.action_release("move_down")
		await wait(0.4)
		check(player.global_position.y > ledge_world.y + 16, "down + jump drops through the ledge")
		await wait(1.0)

	# Map screen
	var map: CanvasLayer = run.map_screen
	var visited := lvl.rooms.filter(func(r: RoomTemplate) -> bool: return r.visited).size()
	check(visited >= 2, "rooms get marked as explored (%d)" % visited)
	var ev := InputEventAction.new()
	ev.action = "map"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	check(map.visible and get_tree().paused, "M opens the map and pauses")
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not map.visible and not get_tree().paused, "M closes the map")

	# Combo direction
	player.facing = 1
	Input.action_press("attack")
	await wait(0.03)
	Input.action_release("attack")
	await wait(0.05)
	Input.action_press("move_left")
	Input.action_press("attack")
	await wait(0.03)
	Input.action_release("attack")
	await wait(0.35)
	Input.action_release("move_left")
	check(player.attack_pivot.scale.x == -1, "combo follows the direction keys")
	await wait(0.6)

	# Level exit -> next region (the only teleport)
	print("--- next level")
	run._go_to_next_level()
	await wait(1.2)
	check(GameState.depth == 2 and run.level != lvl, "level exit loads level 2 (%s)" % run.level.region.name)
	check(player.is_on_floor(), "player placed in the new start room")

	# Defense room
	print("--- defense room")
	GameState.levels_since_defense = 5
	run._go_to_next_level()
	await wait(1.2)
	lvl = run.level
	var droom: DefenseRoom = null
	for r in lvl.rooms:
		if r is DefenseRoom:
			droom = r
	check(droom != null, "level 3 has a relic room (forced)")
	if droom:
		var relic := droom.relic
		check(relic.item.rarity == ItemData.Rarity.LEGENDARY, "relic holds legendary: %s" % relic.item.item_name)
		# Stand on the platform above the relic, out of the enemies' way.
		player.global_position = droom.to_global(droom.get_node("RelicSpawn").position + Vector2(0, -97))
		relic._started = true
		relic.hurtbox.invincible = false
		relic.activated.emit()
		await wait(0.2)
		var sealed := droom.get_exits().filter(func(e: RoomExit) -> bool: return e.connected).all(func(e: RoomExit) -> bool:
			return droom.get_tiles().get_cell_atlas_coords(e.opening_cells(droom.size_tiles)[0]) == Vector2i(0, 0))
		check(sealed, "doors seal during the defense")
		await wait(9.0)
		check(droom.wave >= 1 and relic.durability < relic.max_durability, "waves attack the relic (%d/%d)" % [relic.durability, relic.max_durability])
		var guard := 0
		while not droom.finished and guard < 60:
			guard += 1
			for e in droom.enemies_root.get_children():
				if e is Enemy and not e.dead:
					e._die()
			await wait(1.0)
		check(droom.finished, "all %d waves done" % droom.total_waves)
		var reopened := droom.get_exits().filter(func(e: RoomExit) -> bool: return e.connected).all(func(e: RoomExit) -> bool:
			return droom.get_tiles().get_cell_atlas_coords(e.opening_cells(droom.size_tiles)[0]) != Vector2i(0, 0))
		check(reopened, "doors open again after the defense")
		check(GameState.defenses_won + GameState.defenses_lost == 1, "defense result tracked")

	# Permadeath
	print("--- death")
	var depth := GameState.depth
	var hb := Hitbox.new()
	hb.damage = 9999
	player.invincible_timer.stop()
	player.is_dashing = false
	player.is_slamming = false
	player._on_hurt(hb)
	hb.free()
	check(player.dead, "player died")
	await wait(2.5)
	check(main.current.name == "GameOver", "game over screen shown")
	check(not GameState.run_active and GameState.last_run.get("depth") == depth, "run ended at level %d" % depth)
	main.start_run()
	await wait(0.5)
	check(GameState.depth == 1 and GameState.items.is_empty() and GameState.hp == GameState.get_max_hp(), "new run starts fresh (permadeath)")
