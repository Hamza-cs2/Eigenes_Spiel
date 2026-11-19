extends CanvasLayer
## Pause menu that opens when you pick up a Scroll of Power: choose 1 of 3 upgrades.
## Lives in run.tscn (group "upgrade_choice"). process_mode = Always so it works while paused.

signal chosen(upgrade: Dictionary)

const OPTIONS := 3

@onready var options_box: HBoxContainer = %Options


func _ready() -> void:
	add_to_group("upgrade_choice")
	visible = false


## Shows OPTIONS different random upgrades and pauses the game.
func open() -> void:
	for c in options_box.get_children():
		c.queue_free()
	var pool: Array = GameState.UPGRADE_TYPES.duplicate()
	pool.shuffle()
	var first: Button = null
	for i in mini(OPTIONS, pool.size()):
		var up: Dictionary = pool[i]
		var b := Button.new()
		b.text = up.text
		b.custom_minimum_size = Vector2(150, 70)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_pick.bind(up))
		options_box.add_child(b)
		if first == null:
			first = b
	visible = true
	get_tree().paused = true
	first.grab_focus()


func _pick(up: Dictionary) -> void:
	GameState.add_upgrade(up)
	visible = false
	get_tree().paused = false
	chosen.emit(up)
