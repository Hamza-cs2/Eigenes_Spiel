@tool
class_name RoomExit
extends Marker2D
## A doorway in a room template. Put it inside the room's "Exits" node.
## In the editor it snaps itself onto the room border and shows the hole you have to leave in the wall.
##
## RULES (so rooms fit together):
##  - The hole in the wall must be exactly width_tiles wide (default 4) and go through the whole
##    border (2 tiles thick). Green box in the editor = where the hole must be.
##  - LEFT/RIGHT exits: the floor under the hole should be at the bottom of the hole.
##  - UP exits: the player must be able to reach row 5 under the hole (e.g. a platform there).
##    The game adds a one-way platform in row 2 under the hole automatically.
##  - DOWN exits: the game adds a one-way LEDGE at the bottom of the hole automatically
##    (the slam can't break through ledges, so you can't fall through the whole level).
## Unused exits are filled with wall tiles automatically.

enum Dir { LEFT, RIGHT, UP, DOWN }

const TILE := 16
const BORDER := 2

@export var dir: Dir = Dir.RIGHT:
	set(value):
		dir = value
		queue_redraw()
@export var width_tiles := 4:
	set(value):
		width_tiles = value
		queue_redraw()

var connected := false
var _backup := {}


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_snap_to_border()
	else:
		set_process(false)


func opposite() -> Dir:
	return [Dir.RIGHT, Dir.LEFT, Dir.DOWN, Dir.UP][dir]


func tile_pos() -> Vector2i:
	return Vector2i(roundi(position.x / TILE), roundi(position.y / TILE))


## Cells of the hole in the room's tile coordinates.
func opening_cells(room_size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var p := tile_pos()
	var start := (p.y if dir <= Dir.RIGHT else p.x) - width_tiles / 2
	for i in width_tiles:
		for d in BORDER:
			match dir:
				Dir.LEFT:
					cells.append(Vector2i(d, start + i))
				Dir.RIGHT:
					cells.append(Vector2i(room_size.x - 1 - d, start + i))
				Dir.UP:
					cells.append(Vector2i(start + i, d))
				Dir.DOWN:
					cells.append(Vector2i(start + i, room_size.y - 1 - d))
	return cells


## Fill the hole with wall tiles (unused exit, or locked during a relic defense).
func seal(tiles: TileMapLayer, room_size: Vector2i) -> void:
	for cell in opening_cells(room_size):
		if not _backup.has(cell):
			_backup[cell] = [tiles.get_cell_source_id(cell), tiles.get_cell_atlas_coords(cell)]
		tiles.set_cell(cell, 0, Vector2i(0, 0))


## Undo seal().
func unseal(tiles: TileMapLayer) -> void:
	for cell in _backup:
		var data: Array = _backup[cell]
		if data[0] == -1:
			tiles.erase_cell(cell)
		else:
			tiles.set_cell(cell, data[0], data[1])
	_backup.clear()


## Called when this exit is connected to another room: adds the climbing platforms for vertical exits.
func open_passage(tiles: TileMapLayer, room_size: Vector2i) -> void:
	var p := tile_pos()
	var start := p.x - width_tiles / 2
	for i in width_tiles:
		match dir:
			Dir.DOWN:
				tiles.set_cell(Vector2i(start + i, room_size.y - 1), 0, Vector2i(3, 0))
			Dir.UP:
				var cell := Vector2i(start + i, BORDER)
				if tiles.get_cell_source_id(cell) == -1:
					tiles.set_cell(cell, 0, Vector2i(2, 0))


# ---------------------------------------------------------------- editor helpers

func _room() -> Node:
	var p := get_parent()
	return p.get_parent() if p else null


func _snap_to_border() -> void:
	var room := _room()
	if room == null or not "size_tiles" in room:
		return
	var size: Vector2i = room.size_tiles
	var snapped := position.snapped(Vector2(TILE, TILE))
	match dir:
		Dir.LEFT:
			snapped.x = 0
		Dir.RIGHT:
			snapped.x = size.x * TILE
		Dir.UP:
			snapped.y = 0
		Dir.DOWN:
			snapped.y = size.y * TILE
	if snapped != position:
		position = snapped


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var w := width_tiles * TILE
	var b := BORDER * TILE
	var rect: Rect2
	var arrow: Vector2
	match dir:
		Dir.LEFT:
			rect = Rect2(0, -w / 2.0, b, w)
			arrow = Vector2.LEFT
		Dir.RIGHT:
			rect = Rect2(-b, -w / 2.0, b, w)
			arrow = Vector2.RIGHT
		Dir.UP:
			rect = Rect2(-w / 2.0, 0, w, b)
			arrow = Vector2.UP
		Dir.DOWN:
			rect = Rect2(-w / 2.0, -b, w, b)
			arrow = Vector2.DOWN
	draw_rect(rect, Color(0.2, 1, 0.4, 0.35))
	draw_rect(rect, Color(0.2, 1, 0.4), false, 1.0)
	draw_line(Vector2.ZERO, arrow * 24, Color(0.2, 1, 0.4), 2.0)
	draw_line(arrow * 24, arrow * 16 + arrow.orthogonal() * 6, Color(0.2, 1, 0.4), 2.0)
	draw_line(arrow * 24, arrow * 16 - arrow.orthogonal() * 6, Color(0.2, 1, 0.4), 2.0)
