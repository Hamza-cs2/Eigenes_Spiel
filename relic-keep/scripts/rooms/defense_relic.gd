class_name DefenseRelic
extends Node2D
## The relic in a defense room. Holds a very good item.
## It has durability (not HP from the player!). Enemies attack it.
## If durability reaches 0 it breaks: waves continue, but you get nothing.

signal durability_changed(current: int, maximum: int)
signal broken_signal
signal activated

@export var max_durability := 150
## Enemies deal less damage to the relic than to you, so you have time to react.
@export var damage_taken_mult := 0.5

var durability := 0
var broken := false
var item: ItemData
var _player_inside := false
var _started := false
var _time := 0.0

@onready var crystal: Sprite2D = $Crystal
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var interact_area: Area2D = $InteractArea
@onready var prompt: Label = $Prompt
@onready var shatter: CPUParticles2D = $Shatter


func _ready() -> void:
	add_to_group("defense_target")
	durability = max_durability
	hurtbox.hurt.connect(_on_hurt)
	hurtbox.invincible = true # can't be hurt before the defense starts
	interact_area.body_entered.connect(func(b: Node2D) -> void: if b is Player: _set_inside(true))
	interact_area.body_exited.connect(func(b: Node2D) -> void: if b is Player: _set_inside(false))
	prompt.visible = false
	if item:
		crystal.modulate = item.rarity_color().lerp(Color(0.6, 1, 1), 0.3)


func _set_inside(value: bool) -> void:
	_player_inside = value
	prompt.visible = value and not _started
	if item:
		prompt.text = "[E] Start the defense\nReward: %s" % item.item_name


func _process(delta: float) -> void:
	_time += delta
	if not broken:
		crystal.position.y = -22.0 + sin(_time * 2.0) * 2.0
	if _player_inside and not _started and Input.is_action_just_pressed("interact"):
		_started = true
		prompt.visible = false
		hurtbox.invincible = false
		activated.emit()


func _on_hurt(hb: Hitbox) -> void:
	if broken:
		return
	var dmg := maxi(1, roundi(hb.damage * damage_taken_mult))
	durability = maxi(durability - dmg, 0)
	GameState.spawn_damage_number(global_position + Vector2(0, -40), dmg, Color(0.5, 0.9, 1))
	crystal.self_modulate = Color(3, 3, 3)
	create_tween().tween_property(crystal, "self_modulate", Color.WHITE, 0.15)
	durability_changed.emit(durability, max_durability)
	queue_redraw()
	if durability <= 0:
		_break()


func _break() -> void:
	broken = true
	hurtbox.invincible = true
	hurtbox.set_deferred("monitoring", false)
	remove_from_group("defense_target")
	crystal.visible = false
	shatter.emitting = true
	broken_signal.emit()
	queue_redraw()


func _draw() -> void:
	if broken or not _started:
		return
	var w := 30.0
	var y := -46.0
	draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 5), Color(0.05, 0.05, 0.1))
	draw_rect(Rect2(-w / 2, y, w * float(durability) / max_durability, 3), Color(0.4, 0.85, 1.0))
