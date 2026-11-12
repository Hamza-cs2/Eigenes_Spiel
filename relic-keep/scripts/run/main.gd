extends Node
## Main scene: switches between main menu, a run, and the game-over screen.

const MAIN_MENU := preload("res://scenes/ui/main_menu.tscn")
const RUN := preload("res://scenes/run/run.tscn")
const GAME_OVER := preload("res://scenes/ui/game_over.tscn")

var current: Node


func _ready() -> void:
	show_menu()


func show_menu() -> void:
	var menu := MAIN_MENU.instantiate()
	menu.start_pressed.connect(start_run)
	_swap(menu)


func start_run() -> void:
	GameState.start_new_run()
	var run := RUN.instantiate()
	run.run_finished.connect(show_game_over)
	_swap(run)


func show_game_over() -> void:
	var screen := GAME_OVER.instantiate()
	screen.new_run_pressed.connect(start_run)
	screen.menu_pressed.connect(show_menu)
	_swap(screen)


func _swap(node: Node) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if current:
		current.queue_free()
	current = node
	add_child(node)
