extends Node2D
## One run. Holds the player, HUD and the current Level.
## Inside a level everything is seamless (no loading, no teleports). Only the level exit doors
## load the next region (each door leads to a different one): the one place with a fade + teleport.

signal run_finished

const LEVEL_SCRIPT := preload("res://scripts/level/level.gd")

@onready var level_holder: Node2D = $LevelHolder
@onready var player: Player = $Player
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var map_screen: CanvasLayer = $MapScreen

var level: Level
var next_region := 0
var _transitioning := false
var _over := false


func _ready() -> void:
	player.died.connect(_on_player_died)
	pause_menu.abandon_requested.connect(_end_run)
	_build_next_level()


func _build_next_level() -> void:
	if level:
		level_holder.remove_child(level)
		level.queue_free()
	GameState.depth += 1
	var with_defense := GameState.should_spawn_defense()
	level = LEVEL_SCRIPT.new()
	level.name = "Level"
	level_holder.add_child(level)
	GameState.effects_root = level
	level.message.connect(hud.show_toast)
	level.level_exit_entered.connect(_go_to_next_level)
	map_screen.level = level
	level.defense_started.connect(hud.show_defense)
	level.wave_changed.connect(hud.set_wave)
	level.defense_finished.connect(func(_ok: bool) -> void: hud.hide_defense(3.0))
	hud.hide_defense()
	level.build(GameState.rng, GameState.depth, next_region, with_defense)
	if level.has_defense:
		GameState.levels_since_defense = 0
	else:
		GameState.levels_since_defense += 1
	player.teleport(level.player_spawn, level.bounds)
	hud.set_level(GameState.depth, level.region.name)
	hud.show_toast("Level %d - %s" % [GameState.depth, level.region.name], 2.0)


func _go_to_next_level(region_index := -1) -> void:
	if _transitioning or _over:
		return
	_transitioning = true
	next_region = region_index if region_index >= 0 else (level.region_index + 1) % Level.REGIONS.size()
	player.input_locked = true
	await hud.fade_to(1.0, 0.35)
	_build_next_level()
	await hud.fade_to(0.0, 0.35)
	player.input_locked = false
	_transitioning = false


func _on_player_died() -> void:
	hud.show_toast("You died. Permadeath - this run is over.", 3.0)
	await get_tree().create_timer(1.8).timeout
	_end_run()


func _end_run() -> void:
	if _over:
		return
	_over = true
	GameState.end_run()
	run_finished.emit()
