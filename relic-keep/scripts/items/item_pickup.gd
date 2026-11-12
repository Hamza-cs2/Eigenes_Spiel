class_name ItemPickup
extends Area2D
## An item lying in the world. Walk over it and press "interact" to take it.

@export var item: ItemData

var _player_inside := false
var _time := 0.0

@onready var icon: Sprite2D = $Icon
@onready var glow: Sprite2D = $Glow
@onready var prompt: Label = $Prompt


func _ready() -> void:
	body_entered.connect(func(b: Node2D) -> void: if b is Player: _set_inside(true))
	body_exited.connect(func(b: Node2D) -> void: if b is Player: _set_inside(false))
	if item:
		icon.modulate = item.rarity_color()
		glow.modulate = Color(item.rarity_color(), 0.35)
		prompt.text = "[E] %s\n%s" % [item.item_name, item.description]
	prompt.visible = false
	# Pop-in
	scale = Vector2.ZERO
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_inside(value: bool) -> void:
	_player_inside = value
	prompt.visible = value


func _process(delta: float) -> void:
	_time += delta
	icon.position.y = -12.0 + sin(_time * 3.0) * 2.0
	glow.rotation += delta
	if _player_inside and Input.is_action_just_pressed("interact"):
		GameState.add_item(item)
		queue_free()
