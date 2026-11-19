class_name UpgradeScroll
extends Area2D
## Scroll of Power: lies somewhere in the level. Touch it -> the game pauses and you choose
## 1 of 3 upgrades (UpgradeChoice menu). Permanent for this run. Layer 6, mask 2.

var upgrade: Dictionary
var _time := 0.0

@onready var icon: Sprite2D = $Icon
@onready var label: Label = $Label


func _ready() -> void:
	label.text = "Scroll of Power"
	body_entered.connect(func(b: Node2D) -> void:
		if b is Player:
			var menu := get_tree().get_first_node_in_group("upgrade_choice")
			if menu:
				menu.call_deferred("open")
			else:
				GameState.add_upgrade(GameState.UPGRADE_TYPES[randi() % GameState.UPGRADE_TYPES.size()])
			queue_free())


func _process(delta: float) -> void:
	_time += delta
	icon.position.y = -12.0 + sin(_time * 3.0) * 2.0
