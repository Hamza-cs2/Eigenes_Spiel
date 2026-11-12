extends CanvasLayer
## Full-screen map (M / Tab), Dead-Cells style: shows the rooms you've explored,
## where you are, the relic room and the level exits with the region they lead to.

const MAP_AREA := Rect2(16, 40, 608, 290)
const MAX_SCALE := 3.0

var level: Level
var _textures := {}
var _time := 0.0

@onready var view: Control = $View
@onready var title: Label = $Title


func _ready() -> void:
	visible = false
	view.draw.connect(_draw_map)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		_toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if not visible and get_tree().paused:
		return # pause menu is open
	visible = not visible
	get_tree().paused = visible
	if visible and level:
		title.text = "%s  -  Level %d" % [level.region.name, level.level_index]
		view.queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_time += delta
		view.queue_redraw()


func _draw_map() -> void:
	if level == null or not is_instance_valid(level):
		return
	var b := level.bounds
	var tiles_size := b.size / Level.TILE
	var scale := minf(minf(MAP_AREA.size.x / tiles_size.x, MAP_AREA.size.y / tiles_size.y), MAX_SCALE)
	var offset := MAP_AREA.position + (MAP_AREA.size - tiles_size * scale) / 2.0
	var to_map := func(world: Vector2) -> Vector2:
		return offset + (world - b.position) / Level.TILE * scale

	for room in level.rooms:
		if not room.visited:
			continue
		if not _textures.has(room):
			_textures[room] = ImageTexture.create_from_image(room.get_map_image())
		var rect := Rect2(to_map.call(room.position), Vector2(room.size_tiles) * scale)
		var tint := Color(1.4, 0.6, 1.2) if room is DefenseRoom else Color.WHITE
		view.draw_texture_rect(_textures[room], rect, false, tint)

	var font := ThemeDB.fallback_font
	for ex in level.exit_markers:
		var room := _room_at(ex.position)
		if room == null or not room.visited:
			continue
		var p: Vector2 = to_map.call(ex.position)
		view.draw_rect(Rect2(p - Vector2(3, 6), Vector2(6, 6)), Color(1, 0.85, 0.2))
		view.draw_string(font, p + Vector2(-40, -9), ex.region, HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color(1, 0.9, 0.5))

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and fmod(_time, 0.6) < 0.4:
		var pp: Vector2 = to_map.call(player.global_position)
		view.draw_circle(pp + Vector2(0, -2), 2.5, Color(1, 0.3, 0.3))


func _room_at(pos: Vector2) -> RoomTemplate:
	for room in level.rooms:
		if room.get_rect_px().has_point(pos):
			return room
	return null
