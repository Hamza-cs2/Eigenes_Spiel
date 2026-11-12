extends Control

signal start_pressed

@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton
@onready var best_label: Label = %BestLabel


func _ready() -> void:
	start_button.pressed.connect(start_pressed.emit)
	quit_button.pressed.connect(get_tree().quit)
	best_label.text = "Best level: %d    Runs: %d" % [GameState.best_depth, GameState.runs_played]
	start_button.grab_focus()
