extends Node
## Builds the starter room templates from tools/room_layouts.json into scenes/rooms/templates/.
##   godot --headless --path . res://tools/build_room_templates.tscn
## You don't need this for your own rooms - paint those in the editor (see README).
## Layout legend: # ground, = one-way platform, . air, P player spawn, X level exit, R relic,
## E ground enemy spawn, F air enemy spawn, I item spawn. Holes in the 2-tile border become exits.

const TILE := 16
const OUT_DIR := "res://scenes/rooms/templates/"
const TYPES := {"NORMAL": 0, "START": 1, "END": 2, "DEFENSE": 3, "BRANCH": 4}


func _ready() -> void:
	var layouts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/room_layouts.json"))
	var tileset: TileSet = load("res://assets/tiles/tileset.tres")
	for layout in layouts:
		var rows: Array = layout.rows
		var h := rows.size()
		var w: int = rows[0].length()
		var root := Node2D.new()
		root.name = _pascal(layout.name)
		root.set_script(load("res://scripts/%s.gd" % ("rooms/defense_room" if layout.script == "defense_room" else "level/room_template")))
		root.size_tiles = Vector2i(w, h)
		root.room_type = TYPES[layout.type]
		root.weight = layout.weight
		root.min_level = int(layout.min_level)

		var tiles := TileMapLayer.new()
		tiles.name = "Tiles"
		tiles.tile_set = tileset
		_add(root, tiles)
		var exits := _add(root, _node2d("Exits"))
		var enemy_spawns := _add(root, _node2d("EnemySpawns"))
		var item_spawns := _add(root, _node2d("ItemSpawns"))

		for y in h:
			for x in w:
				var c: String = rows[y][x]
				var feet := Vector2(x * TILE + TILE / 2.0, (y + 1) * TILE)
				match c:
					"#":
						var above_open: bool = y > 0 and rows[y - 1][x] != "#"
						tiles.set_cell(Vector2i(x, y), 0, Vector2i(1, 0) if above_open else Vector2i(0, 0))
					"=":
						tiles.set_cell(Vector2i(x, y), 0, Vector2i(2, 0))
					"P", "X", "R":
						var names := {"P": "PlayerSpawn", "X": "LevelExit", "R": "RelicSpawn"}
						var mk := Marker2D.new()
						mk.name = names[c]
						mk.position = feet
						_add(root, mk)
					"E", "F":
						var es := Marker2D.new()
						es.set_script(load("res://scripts/level/enemy_spawn.gd"))
						es.name = "Enemy%d" % enemy_spawns.get_child_count()
						es.kind = 0 if c == "E" else 1
						es.position = feet if c == "E" else Vector2(x * TILE + 8, y * TILE + 8)
						_add(enemy_spawns, es)
					"I":
						var it := Marker2D.new()
						it.set_script(load("res://scripts/level/item_spawn.gd"))
						it.name = "Item%d" % item_spawns.get_child_count()
						it.position = feet
						_add(item_spawns, it)

		# Exits = runs of open cells in the border.
		for side in ["LEFT", "RIGHT", "UP", "DOWN"]:
			var run_start := -1
			var length := h if side in ["LEFT", "RIGHT"] else w
			for i in length + 1:
				var open := false
				if i >= 2 and i < length - 2:
					match side:
						"LEFT": open = rows[i][0] != "#"
						"RIGHT": open = rows[i][w - 1] != "#"
						"UP": open = rows[0][i] != "#"
						"DOWN": open = rows[h - 1][i] != "#"
				if open and run_start == -1:
					run_start = i
				elif not open and run_start != -1:
					var ex := Marker2D.new()
					ex.set_script(load("res://scripts/level/room_exit.gd"))
					ex.name = "Exit" + side.capitalize()
					ex.dir = ["LEFT", "RIGHT", "UP", "DOWN"].find(side)
					ex.width_tiles = i - run_start
					var mid: int = (run_start + ex.width_tiles / 2) * TILE
					match side:
						"LEFT": ex.position = Vector2(0, mid)
						"RIGHT": ex.position = Vector2(w * TILE, mid)
						"UP": ex.position = Vector2(mid, 0)
						"DOWN": ex.position = Vector2(mid, h * TILE)
					_add(exits, ex)
					run_start = -1

		_set_owner(root, root)
		var packed := PackedScene.new()
		packed.pack(root)
		var path: String = OUT_DIR + layout.name + ".tscn"
		var err := ResourceSaver.save(packed, path)
		print("%s: %s" % [path, error_string(err)])
		root.free()
	get_tree().quit()


func _node2d(n: String) -> Node2D:
	var node := Node2D.new()
	node.name = n
	return node


func _add(parent: Node, child: Node) -> Node:
	parent.add_child(child)
	return child


func _set_owner(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)


func _pascal(s: String) -> String:
	return s.trim_prefix("_").to_pascal_case()
