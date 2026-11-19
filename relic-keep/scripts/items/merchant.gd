extends Node2D
## The shopkeeper. Only for looks: greets you when you come close.

const LINES := ["Coins for curiosities!", "Finest relics, barely cursed.", "Look, don't touch. Buy, then touch.", "Back again? Still alive? Good for business."]

@onready var speech: Label = $Speech
@onready var area: Area2D = $Area


func _ready() -> void:
	speech.visible = false
	area.body_entered.connect(func(b: Node2D) -> void:
		if b is Player:
			speech.text = LINES[randi() % LINES.size()]
			speech.visible = true)
	area.body_exited.connect(func(b: Node2D) -> void: if b is Player: speech.visible = false)
