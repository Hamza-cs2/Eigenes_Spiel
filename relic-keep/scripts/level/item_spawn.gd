@tool
class_name ItemSpawn
extends Marker2D
## Possible item drop. Put it inside the room's "ItemSpawns" node, on the floor.
## Chance comes from the room's item_chance (BRANCH rooms always spawn their items).


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var pts := PackedVector2Array([Vector2(0, -16), Vector2(7, -8), Vector2(0, 0), Vector2(-7, -8)])
	draw_colored_polygon(pts, Color(1, 0.85, 0.2, 0.4))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 0.85, 0.2), 1.0)
