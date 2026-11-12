class_name ExitDoor
extends Area2D
## Door to the next room. Locked until the room is cleared.

signal entered

var locked := true
var _player_inside := false

@onready var sprite: Sprite2D = $Sprite
@onready var prompt: Label = $Prompt


func _ready() -> void:
	body_entered.connect(func(b: Node2D) -> void: if b is Player: _set_inside(true))
	body_exited.connect(func(b: Node2D) -> void: if b is Player: _set_inside(false))
	set_locked(locked)
	prompt.visible = false


func set_locked(value: bool) -> void:
	locked = value
	if not is_node_ready():
		return
	sprite.modulate = Color(0.75, 0.2, 0.25) if locked else Color(0.3, 0.9, 0.5)
	prompt.text = "Locked - defeat all enemies" if locked else "[E] Next room"


func _set_inside(value: bool) -> void:
	_player_inside = value
	prompt.visible = value


func _process(_delta: float) -> void:
	if _player_inside and not locked and Input.is_action_just_pressed("interact"):
		_player_inside = false
		entered.emit()
