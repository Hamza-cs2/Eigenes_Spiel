extends Control
## Shown after death. Everything from the run is gone (permadeath).

signal new_run_pressed
signal menu_pressed

@onready var stats_label: Label = %StatsLabel
@onready var new_run_button: Button = %NewRunButton
@onready var menu_button: Button = %MenuButton


func _ready() -> void:
	var r := GameState.last_run
	stats_label.text = "Level reached: %d%s\nEnemies killed: %d\nRelics defended: %d   Relics lost: %d\nItems found: %d" % [
		r.get("depth", 0), "   NEW BEST!" if r.get("new_best", false) else "",
		r.get("kills", 0),
		r.get("defenses_won", 0), r.get("defenses_lost", 0), r.get("items", 0)]
	new_run_button.pressed.connect(new_run_pressed.emit)
	menu_button.pressed.connect(menu_pressed.emit)
	new_run_button.grab_focus()
