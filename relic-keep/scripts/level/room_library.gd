class_name RoomLibrary
extends RefCounted
## Finds every room template in TEMPLATE_DIR automatically.
## To add a room: save a new .tscn in that folder. Files starting with "_" are ignored (use that for WIP).
## Problems with a template are printed as warnings in the Output panel when a run starts.

const TEMPLATE_DIR := "res://scenes/rooms/templates/"

static var _cache: Array[Dictionary] = []


## Returns one Dictionary per template:
## { scene, path, type, weight, min_level, size: Vector2i, exits: [{dir, width, pos: Vector2i}] }
static func get_templates() -> Array[Dictionary]:
	if _cache.is_empty():
		_load_all()
	return _cache


static func reload() -> void:
	_cache.clear()
	_load_all()


static func _load_all() -> void:
	for file in ResourceLoader.list_directory(TEMPLATE_DIR):
		if not file.ends_with(".tscn") or file.begins_with("_"):
			continue
		var path := TEMPLATE_DIR + file
		var scene := load(path) as PackedScene
		if scene == null:
			push_warning("Room '%s' could not be loaded." % path)
			continue
		var inst := scene.instantiate()
		if not inst is RoomTemplate:
			push_warning("Room '%s': root node needs the room_template.gd (or defense_room.gd) script." % path)
			inst.free()
			continue
		var room := inst as RoomTemplate
		var meta := {
			"scene": scene, "path": path, "type": room.room_type, "weight": room.weight,
			"min_level": room.min_level, "size": room.size_tiles, "exits": [],
		}
		for ex in room.get_exits():
			meta.exits.append({"dir": ex.dir, "width": ex.width_tiles, "pos": ex.tile_pos()})
		var problems := _validate(room)
		for p in problems:
			push_warning("Room '%s': %s" % [path, p])
		room.free()
		if problems.is_empty():
			_cache.append(meta)


static func _validate(room: RoomTemplate) -> Array[String]:
	var out: Array[String] = []
	if room.get_node_or_null("Tiles") == null:
		out.append("missing a TileMapLayer called 'Tiles'.")
	var exits := room.get_exits()
	if exits.is_empty():
		out.append("has no RoomExit in 'Exits'.")
	for ex in exits:
		var p := ex.tile_pos()
		var on_edge := false
		match ex.dir:
			RoomExit.Dir.LEFT: on_edge = p.x == 0
			RoomExit.Dir.RIGHT: on_edge = p.x == room.size_tiles.x
			RoomExit.Dir.UP: on_edge = p.y == 0
			RoomExit.Dir.DOWN: on_edge = p.y == room.size_tiles.y
		if not on_edge:
			out.append("exit '%s' is not on the %s border (open the room in the editor once so it snaps)." % [ex.name, RoomExit.Dir.keys()[ex.dir]])
	match room.room_type:
		RoomTemplate.RoomType.START:
			if room.get_node_or_null("PlayerSpawn") == null:
				out.append("START room needs a Marker2D called 'PlayerSpawn'.")
		RoomTemplate.RoomType.END:
			if room.get_node_or_null("LevelExit") == null:
				out.append("END room needs a Marker2D called 'LevelExit'.")
		RoomTemplate.RoomType.DEFENSE:
			if not room is DefenseRoom:
				out.append("DEFENSE room needs the defense_room.gd script on the root.")
	return out
