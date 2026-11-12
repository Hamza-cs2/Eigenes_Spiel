@tool
class_name EnemySpawn
extends Marker2D
## Possible enemy spawn point. Put it inside the room's "EnemySpawns" node.
## GROUND: place it on the floor (the marker = the enemy's feet). AIR: anywhere in the air (flyers).
## Not every spawn point is used: the game picks a random number based on the level.

enum Kind { GROUND, AIR }

@export var kind: Kind = Kind.GROUND:
	set(value):
		kind = value
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col := Color(1, 0.3, 0.3) if kind == Kind.GROUND else Color(0.4, 0.8, 1)
	if kind == Kind.GROUND:
		draw_rect(Rect2(-6, -18, 12, 18), Color(col, 0.35))
		draw_rect(Rect2(-6, -18, 12, 18), col, false, 1.0)
	else:
		draw_circle(Vector2.ZERO, 7, Color(col, 0.35))
		draw_arc(Vector2.ZERO, 7, 0, TAU, 16, col, 1.0)
