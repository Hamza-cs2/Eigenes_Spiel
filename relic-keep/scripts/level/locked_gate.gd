class_name LockedGate
extends StaticBody2D
## Bars in front of a locked treasure room. Press E to open with a KEY or by paying COINS.
## StaticBody2D on layer 1 (World), so it blocks the player, enemies and line of sight.
## The level generator places it in the doorway of locked side rooms; you can also put it in a
## room template yourself (set lock_type, cost and gate_size in the Inspector).

signal opened

enum LockType { KEY, COINS }

@export var lock_type: LockType = LockType.KEY
@export var cost := 100
## Size of the bars in pixels (a 4-tile doorway through a 2-tile wall = 32x64 or 64x32).
@export var gate_size := Vector2(32, 64)

var _player_inside := false
var _flash := 0.0

@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var interact_shape: CollisionShape2D = $InteractArea/CollisionShape2D
@onready var interact_area: Area2D = $InteractArea
@onready var prompt: Label = $Prompt


func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = gate_size
	shape.shape = rect
	var area_rect := RectangleShape2D.new()
	area_rect.size = gate_size + Vector2(56, 56)
	interact_shape.shape = area_rect
	interact_area.body_entered.connect(func(b: Node2D) -> void: if b is Player: _set_inside(true))
	interact_area.body_exited.connect(func(b: Node2D) -> void: if b is Player: _set_inside(false))
	prompt.position = Vector2(-80, -gate_size.y / 2.0 - 30)
	prompt.visible = false
	_update_prompt()
	queue_redraw()


func _set_inside(value: bool) -> void:
	_player_inside = value
	prompt.visible = value
	_update_prompt()


func _update_prompt() -> void:
	if lock_type == LockType.KEY:
		prompt.text = "[E] Unlock (1 key)  -  you have %d" % GameState.keys
	else:
		prompt.text = "[E] Unlock for %d coins  -  you have %d" % [cost, GameState.coins]


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_update_prompt()
	if _player_inside and Input.is_action_just_pressed("interact"):
		try_open()


func try_open() -> bool:
	var ok := GameState.use_key() if lock_type == LockType.KEY else GameState.spend_coins(cost)
	if not ok:
		prompt.text = "You need a key!" if lock_type == LockType.KEY else "Not enough coins!"
		_flash = 1.2
		return false
	shape.set_deferred("disabled", true)
	set_process(false)
	prompt.visible = false
	opened.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
	return true


func _draw() -> void:
	var r := Rect2(-gate_size / 2.0, gate_size)
	var col := Color(0.75, 0.78, 0.85) if lock_type == LockType.KEY else Color(1.0, 0.8, 0.3)
	draw_rect(r, Color(0.05, 0.05, 0.08, 0.55))
	var vertical := gate_size.y >= gate_size.x
	var step := 6.0
	if vertical:
		var x := r.position.x + 3.0
		while x < r.end.x:
			draw_rect(Rect2(x, r.position.y, 2, r.size.y), col)
			x += step
		for y in [r.position.y + 6, r.end.y - 8]:
			draw_rect(Rect2(r.position.x, y, r.size.x, 2), col.darkened(0.2))
	else:
		var y := r.position.y + 3.0
		while y < r.end.y:
			draw_rect(Rect2(r.position.x, y, r.size.x, 2), col)
			y += step
		for x in [r.position.x + 6, r.end.x - 8]:
			draw_rect(Rect2(x, r.position.y, 2, r.size.y), col.darkened(0.2))
	# Lock in the middle
	draw_rect(Rect2(-5, -4, 10, 9), col.darkened(0.4))
	draw_rect(Rect2(-1, -1, 2, 4), Color(0.05, 0.05, 0.08))
