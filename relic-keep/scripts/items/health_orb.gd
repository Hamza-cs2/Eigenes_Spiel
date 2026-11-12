extends Area2D
## Dropped by enemies. Touch it to heal.

@export var heal_amount := 15

var _time := 0.0
var _base_y := 0.0


func _ready() -> void:
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 4.0) * 2.0


func _on_body_entered(body: Node2D) -> void:
	if body is Player and GameState.hp < GameState.get_max_hp():
		GameState.heal_player(heal_amount)
		GameState.spawn_damage_number(global_position, heal_amount, Color(0.4, 1, 0.4))
		queue_free()
