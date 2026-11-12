class_name Level
extends Node2D
## One level (= region). Builds ONE seamless map out of room templates, Dead-Cells style:
##  1. GROW: start with a START room, then keep attaching NORMAL rooms to random free exits of
##     ANY room already placed -> the map branches out in all directions instead of being a line.
##  2. LOOPS: join dead ends that face each other with generated corridors (and rooms that happen
##     to line up with two exits) -> circular routes like in Dead Cells.
##  3. A relic (DEFENSE) room somewhere in the middle (if wanted).
##  4. 2 EXITS (END rooms) as far from the start as possible, each leading to a different region.
##  5. Treasure side rooms (BRANCH) on leftover free exits.
## Tall vertical stacks are limited (MAX_VERTICAL_GROUP). Unused exits get walled up.

signal message(text: String)
## Emitted when the player uses a level exit. region_index = the region that exit leads to.
signal level_exit_entered(region_index: int)
signal defense_started(relic: DefenseRelic)
signal wave_changed(wave: int, total: int)
signal defense_finished(success: bool)

const TILE := 16
const EXIT_DOOR := preload("res://scenes/rooms/exit_door.tscn")
const TILESET := preload("res://assets/tiles/tileset.tres")
## Corridors that close loops: max length in tiles, max height difference in tiles.
const MAX_CONNECTOR_LENGTH := 70
const MAX_CONNECTOR_RISE := 6
const MAX_ATTEMPTS := 60
## Max rooms connected to each other only by up/down exits (one vertical "column").
const MAX_VERTICAL_GROUP := 3
const OPPOSITE := [RoomExit.Dir.RIGHT, RoomExit.Dir.LEFT, RoomExit.Dir.DOWN, RoomExit.Dir.UP]

const REGIONS := [
	{"name": "Prison Depths", "bg": Color(0.07, 0.06, 0.1), "tint": Color(1, 1, 1)},
	{"name": "Toxic Sewers", "bg": Color(0.04, 0.09, 0.06), "tint": Color(0.75, 1.0, 0.75)},
	{"name": "Ossuary", "bg": Color(0.1, 0.09, 0.07), "tint": Color(1.0, 0.93, 0.8)},
	{"name": "Frozen Ramparts", "bg": Color(0.05, 0.08, 0.13), "tint": Color(0.8, 0.9, 1.15)},
	{"name": "Clock Tower", "bg": Color(0.11, 0.07, 0.05), "tint": Color(1.15, 0.9, 0.7)},
	{"name": "Throne of Ash", "bg": Color(0.12, 0.04, 0.05), "tint": Color(1.2, 0.75, 0.75)},
]

var level_index := 1
var region_index := 0
var region: Dictionary
var rooms: Array[RoomTemplate] = []
var bounds := Rect2()
var player_spawn := Vector2.ZERO
var has_defense := false
## Info for the map: [{position: Vector2, region: String}]
var exit_markers: Array[Dictionary] = []
var loops := 0

var _rng: RandomNumberGenerator
var _current_room: RoomTemplate


## Builds the whole level.
func build(rng: RandomNumberGenerator, p_level: int, p_region: int, with_defense: bool) -> void:
	_rng = rng
	level_index = p_level
	region_index = p_region
	region = REGIONS[region_index]
	var templates := RoomLibrary.get_templates()
	var plan: Array = []
	for attempt in MAX_ATTEMPTS:
		plan = _plan(templates, with_defense and attempt < MAX_ATTEMPTS / 2)
		if not plan.is_empty():
			break
	assert(not plan.is_empty(), "Could not build a level - check the room templates (need START, END and NORMAL rooms with matching exits).")
	_instantiate(plan)


func _physics_process(_delta: float) -> void:
	# Mark rooms as explored for the map.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	if _current_room and _current_room.get_rect_px().has_point(player.global_position):
		return
	for room in rooms:
		if room.get_rect_px().has_point(player.global_position):
			_current_room = room
			room.visited = true
			return


# ---------------------------------------------------------------- planning (data only, no nodes)
# entry = {meta, origin: Vector2i, used: {exit_index: true}, dist: int, vgroup: Array (shared by
#          all rooms joined by up/down exits)}

func _plan(templates: Array[Dictionary], with_defense: bool) -> Array:
	var placed: Array = []
	loops = 0
	var starts := _filter(templates, RoomTemplate.RoomType.START)
	var normals := _filter(templates, RoomTemplate.RoomType.NORMAL)
	if starts.is_empty() or normals.is_empty():
		return []
	_add_entry(placed, _weighted_pick(starts), Vector2i.ZERO, -1, [], {})

	# 1. Grow outwards from random rooms.
	var target := _rng.randi_range(13, 16) + mini(level_index, 4) * 2
	var fails := 0
	while placed.size() < target and fails < 300:
		var hosts := placed.filter(func(e: Dictionary) -> bool: return _free_exits(e).size() > 0)
		if hosts.is_empty():
			break
		var host: Dictionary = hosts[_rng.randi_range(0, hosts.size() - 1)]
		if _attach(placed, host, normals).is_empty():
			fails += 1

	# 2. Loops: rooms that connect two dead ends. Try every room with free exits.
	var want_loops := _rng.randi_range(2, 4)
	for pass_i in 3:
		var hosts := placed.filter(func(e: Dictionary) -> bool: return _free_exits(e).size() > 0)
		_shuffle(hosts)
		for host in hosts:
			if loops >= want_loops:
				break
			_attach(placed, host, normals, true)

	_connect_dead_ends(placed)

	# 3. Relic room somewhere in the middle.
	if with_defense:
		var max_dist := _max_dist(placed)
		var mids := placed.filter(func(e: Dictionary) -> bool:
			return e.dist >= max_dist / 3 and e.dist <= max_dist * 2 / 3 + 1)
		if not _attach_to_any(placed, mids, _filter(templates, RoomTemplate.RoomType.DEFENSE)):
			return []

	# 4. Two exits, as far away from the start as possible (and from each other).
	var ends := _filter(templates, RoomTemplate.RoomType.END)
	var end_count := 0
	for i in 2:
		var by_dist := placed.filter(func(e: Dictionary) -> bool:
			return e.meta.type == RoomTemplate.RoomType.NORMAL and _free_exits(e).size() > 0)
		by_dist.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist > b.dist)
		var far_end := by_dist.slice(0, 6)
		if end_count == 1:
			# Second exit: far from the first one too.
			var first: Dictionary = placed.filter(func(e: Dictionary) -> bool: return e.meta.type == RoomTemplate.RoomType.END)[0]
			far_end.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return Vector2(a.origin).distance_to(first.origin) > Vector2(b.origin).distance_to(first.origin))
		if _attach_to_any(placed, far_end, ends):
			end_count += 1
	if end_count == 0:
		return []

	# 5. Treasure side rooms.
	var branches := _filter(templates, RoomTemplate.RoomType.BRANCH)
	var want_branches := _rng.randi_range(2, 3)
	for i in 30:
		if want_branches <= 0:
			break
		var hosts := placed.filter(func(e: Dictionary) -> bool:
			return e.meta.type == RoomTemplate.RoomType.NORMAL and _free_exits(e).size() > 0)
		if hosts.is_empty():
			break
		if not _attach(placed, hosts[_rng.randi_range(0, hosts.size() - 1)], branches).is_empty():
			want_branches -= 1
	return placed


## Finds RIGHT/LEFT exit pairs that face each other with nothing in between and joins them
## with a generated corridor (steps up/down if needed). Prefers pairs that are far apart in the
## room graph, so the loop is actually a shortcut.
func _connect_dead_ends(placed: Array) -> void:
	var pairs := []
	for a in placed:
		for ai in _free_exits(a):
			var ax: Dictionary = a.meta.exits[ai]
			if ax.dir != RoomExit.Dir.RIGHT:
				continue
			var aw: Vector2i = a.origin + ax.pos
			for b in placed:
				if b == a:
					continue
				for bi in _free_exits(b):
					var bx: Dictionary = b.meta.exits[bi]
					if bx.dir != RoomExit.Dir.LEFT or bx.width != ax.width:
						continue
					var bw: Vector2i = b.origin + bx.pos
					var length := bw.x - aw.x
					var rise := bw.y - aw.y
					if length < 8 + absi(rise) or length > MAX_CONNECTOR_LENGTH or absi(rise) > MAX_CONNECTOR_RISE:
						continue
					pairs.append({"a": a, "ai": ai, "b": b, "bi": bi, "aw": aw, "bw": bw,
							"score": absi(a.dist - b.dist) * 10 - length})
	pairs.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.score > q.score)
	var made := 0
	var want := _rng.randi_range(2, 4)
	for pr in pairs:
		if made >= want:
			break
		if pr.a.used.has(pr.ai) or pr.b.used.has(pr.bi):
			continue
		var top: int = mini(pr.aw.y, pr.bw.y) - 4
		var size := Vector2i(pr.bw.x - pr.aw.x, 8 + absi(pr.bw.y - pr.aw.y))
		var rect := Rect2i(Vector2i(pr.aw.x, top), size)
		if placed.any(func(p: Dictionary) -> bool: return Rect2i(p.origin, p.meta.size).intersects(rect)):
			continue
		var meta := {"connector": true, "type": RoomTemplate.RoomType.NORMAL, "size": size, "exits": [
			{"dir": RoomExit.Dir.LEFT, "width": 4, "pos": Vector2i(0, pr.aw.y - top)},
			{"dir": RoomExit.Dir.RIGHT, "width": 4, "pos": Vector2i(size.x, pr.bw.y - top)},
		]}
		pr.a.used[pr.ai] = true
		pr.b.used[pr.bi] = true
		_add_entry(placed, meta, rect.position, mini(pr.a.dist, pr.b.dist) + 1, [], {0: true, 1: true})
		made += 1
		loops += 1


func _filter(templates: Array[Dictionary], type: RoomTemplate.RoomType) -> Array:
	return templates.filter(func(t: Dictionary) -> bool:
		return t.type == type and t.min_level <= level_index)


func _free_exits(entry: Dictionary) -> Array:
	return range(entry.meta.exits.size()).filter(func(i: int) -> bool: return not entry.used.has(i))


func _max_dist(placed: Array) -> int:
	var m := 0
	for e in placed:
		m = maxi(m, e.dist)
	return m


func _attach_to_any(placed: Array, hosts: Array, candidates: Array) -> bool:
	for host in hosts:
		if not _attach(placed, host, candidates).is_empty():
			return true
	return false


## Try to connect a room from `candidates` to a free exit of `host`. Returns the new entry or {}.
## need_loop: only accept placements that ALSO connect to another room's free exit.
func _attach(placed: Array, host: Dictionary, candidates: Array, need_loop := false) -> Dictionary:
	if candidates.is_empty():
		return {}
	var host_exits := _free_exits(host)
	_shuffle(host_exits)
	for hi in host_exits:
		var hx: Dictionary = host.meta.exits[hi]
		var vertical: bool = hx.dir >= RoomExit.Dir.UP
		if vertical and host.vgroup.size() >= MAX_VERTICAL_GROUP:
			continue
		var order := candidates.duplicate()
		_weighted_shuffle(order)
		for cand in order:
			var cand_exits := range(cand.exits.size())
			_shuffle(cand_exits)
			for ci in cand_exits:
				var cx: Dictionary = cand.exits[ci]
				if cx.dir != OPPOSITE[hx.dir] or cx.width != hx.width:
					continue
				var origin: Vector2i = host.origin + hx.pos - cx.pos
				var rect := Rect2i(origin, cand.size)
				if placed.any(func(p: Dictionary) -> bool: return Rect2i(p.origin, p.meta.size).intersects(rect)):
					continue
				var extra := _find_alignments(placed, cand, origin, ci, host)
				if need_loop and extra.is_empty():
					continue
				var used := {ci: true}
				for link in extra:
					used[link.cand_exit] = true
					link.entry.used[link.exit] = true
				loops += extra.size()
				host.used[hi] = true
				return _add_entry(placed, cand, origin, host.dist + 1, host.vgroup if vertical else [], used)
	return {}


## Exits of a new room that line up exactly with free exits of other placed rooms.
## Only left/right ones, so loops never make vertical stacks taller.
func _find_alignments(placed: Array, cand: Dictionary, origin: Vector2i, skip_exit: int, _host: Dictionary) -> Array:
	var out := []
	for ci in cand.exits.size():
		if ci == skip_exit:
			continue
		var cx: Dictionary = cand.exits[ci]
		if cx.dir >= RoomExit.Dir.UP:
			continue
		var world: Vector2i = origin + cx.pos
		for p in placed:
			for pi in _free_exits(p):
				var px: Dictionary = p.meta.exits[pi]
				if px.dir == OPPOSITE[cx.dir] and px.width == cx.width and p.origin + px.pos == world:
					out.append({"entry": p, "exit": pi, "cand_exit": ci})
	return out


func _add_entry(placed: Array, meta: Dictionary, origin: Vector2i, dist: int, vgroup: Array, used: Dictionary) -> Dictionary:
	var entry := {"meta": meta, "origin": origin, "used": used, "dist": maxi(dist, 0), "vgroup": vgroup}
	vgroup.append(entry)
	placed.append(entry)
	return entry


func _weighted_pick(list: Array) -> Dictionary:
	var total := 0.0
	for t in list:
		total += t.weight
	var r := _rng.randf() * total
	for t in list:
		r -= t.weight
		if r <= 0.0:
			return t
	return list.back()


func _weighted_shuffle(list: Array) -> void:
	var keyed := list.map(func(t: Dictionary) -> Array:
		return [pow(_rng.randf(), 1.0 / maxf(t.weight, 0.01)), t])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in list.size():
		list[i] = keyed[i][1]


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------- building nodes

func _instantiate(plan: Array) -> void:
	RenderingServer.set_default_clear_color(region.bg)
	var exit_regions := _pick_exit_regions(plan.filter(func(e: Dictionary) -> bool:
		return e.meta.type == RoomTemplate.RoomType.END).size())
	for entry in plan:
		var room: RoomTemplate = _build_connector(entry.meta) if entry.meta.has("connector") else entry.meta.scene.instantiate()
		room.origin_tiles = entry.origin
		room.position = Vector2(entry.origin * TILE)
		add_child(room)
		room.get_tiles().modulate = region.tint
		var exits := room.get_exits()
		for i in exits.size():
			if entry.used.has(i):
				exits[i].connected = true
				exits[i].open_passage(room.get_tiles(), room.size_tiles)
			else:
				exits[i].seal(room.get_tiles(), room.size_tiles)
		rooms.append(room)
		bounds = room.get_rect_px() if bounds.size == Vector2.ZERO else bounds.merge(room.get_rect_px())
		room.message.connect(message.emit)
		if room is DefenseRoom:
			has_defense = true
			room.defense_started.connect(defense_started.emit)
			room.wave_changed.connect(wave_changed.emit)
			room.defense_finished.connect(defense_finished.emit)
		match room.room_type:
			RoomTemplate.RoomType.START:
				player_spawn = (room.get_node("PlayerSpawn") as Marker2D).global_position
				room.visited = true
			RoomTemplate.RoomType.END:
				var target_region: int = exit_regions.pop_front()
				var door: ExitDoor = EXIT_DOOR.instantiate()
				door.position = (room.get_node("LevelExit") as Marker2D).position
				room.add_child(door)
				door.set_locked(false)
				door.prompt.text = "[E] Go to: %s" % REGIONS[target_region].name
				door.entered.connect(func() -> void: level_exit_entered.emit(target_region))
				exit_markers.append({"position": door.global_position, "region": REGIONS[target_region].name})
	for room in rooms:
		room.populate(level_index, _rng)


## Builds a corridor room in code: 2-tile border, floor that steps up/down to match both exits.
func _build_connector(meta: Dictionary) -> RoomTemplate:
	var room := RoomTemplate.new()
	room.name = "Connector"
	room.size_tiles = meta.size
	var tiles := TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = TILESET
	room.add_child(tiles)
	var exits := Node2D.new()
	exits.name = "Exits"
	room.add_child(exits)
	var spawns := Node2D.new()
	spawns.name = "EnemySpawns"
	room.add_child(spawns)
	var w: int = meta.size.x
	var h: int = meta.size.y
	var left_y: int = meta.exits[0].pos.y
	var right_y: int = meta.exits[1].pos.y
	for i in 2:
		var ex := RoomExit.new()
		ex.dir = meta.exits[i].dir
		ex.position = Vector2(meta.exits[i].pos * TILE)
		exits.add_child(ex)
	# Floor surface per column: left part at left exit, right part at right exit, steps of max 3.
	var rise := right_y - left_y
	var steps := ceili(absf(rise) / 3.0)
	var floors := PackedInt32Array()
	floors.resize(w)
	for x in w:
		var k := 0
		if steps > 0:
			k = clampi(int(float(x - 2) / float(w - 4) * (steps + 1)), 0, steps)
		floors[x] = left_y + 2 + signi(rise) * mini(absi(rise), 3 * k)
	for x in w:
		for y in h:
			var air := false
			if x < 2:
				air = y >= left_y - 2 and y < left_y + 2
			elif x >= w - 2:
				air = y >= right_y - 2 and y < right_y + 2
			else:
				air = y >= 2 and y < floors[x]
			if not air:
				var grass := x >= 2 and x < w - 2 and y == floors[x]
				tiles.set_cell(Vector2i(x, y), 0, Vector2i(1, 0) if grass else Vector2i(0, 0))
	for x in range(8, w - 6, 12):
		var sp := EnemySpawn.new()
		sp.position = Vector2(x * TILE + 8, floors[x] * TILE)
		spawns.add_child(sp)
	return room


## Different next regions for each exit (never the current one).
func _pick_exit_regions(count: int) -> Array:
	var options := range(REGIONS.size()).filter(func(i: int) -> bool: return i != region_index)
	_shuffle(options)
	return options.slice(0, count)
