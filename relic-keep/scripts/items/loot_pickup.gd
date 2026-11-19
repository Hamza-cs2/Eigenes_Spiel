class_name LootPickup
extends RigidBody2D
## A coin or a key that bounces out of enemies / chests. Flies to the player when close (magnet).
## Physics: collision_layer 0, mask 1+7+8 (lands on ground, platforms, ledges).
## Child "PickupArea" (Area2D, mask 2) collects it on touch.

enum Kind { COIN, KEY }

## Loaded on first use (not preloaded: these scenes use this script themselves).
const COIN_SCENE_PATH := "res://scenes/items/coin.tscn"
const KEY_SCENE_PATH := "res://scenes/items/key_pickup.tscn"
const PICKUP_DELAY := 0.35

@export var kind: Kind = Kind.COIN
@export var value := 1
@export var magnet_range := 56.0
@export var magnet_speed := 280.0

var _age := 0.0
var _magnet := false
var _collected := false

@onready var area: Area2D = $PickupArea
@onready var sprite: Sprite2D = $Sprite


## Spawns `amount` coins as a few bouncing pieces (big coins are worth 10).
static func spawn_coins(parent: Node, pos: Vector2, amount: int) -> void:
	var pieces: Array[int] = []
	while amount >= 10 and pieces.size() < 10:
		pieces.append(10)
		amount -= 10
	while amount > 0 and pieces.size() < 14:
		pieces.append(1)
		amount -= 1
	if amount > 0:
		pieces[0] += amount
	for v in pieces:
		var c: LootPickup = (load(COIN_SCENE_PATH) as PackedScene).instantiate()
		c.value = v
		c.position = pos
		c.linear_velocity = Vector2(randf_range(-90, 90), randf_range(-220, -120))
		parent.add_child.call_deferred(c)


static func spawn_key(parent: Node, pos: Vector2) -> LootPickup:
	var k: LootPickup = (load(KEY_SCENE_PATH) as PackedScene).instantiate()
	k.position = pos
	k.linear_velocity = Vector2(randf_range(-40, 40), -180)
	parent.add_child.call_deferred(k)
	return k


func _ready() -> void:
	lock_rotation = true
	area.body_entered.connect(_on_body_entered)
	if kind == Kind.COIN and value >= 10:
		sprite.scale = Vector2(1.5, 1.5)
		sprite.modulate = Color(1.2, 0.9, 0.6)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age < PICKUP_DELAY or _collected:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.dead:
		return
	var target := player.global_position + Vector2(0, -10)
	if not _magnet and global_position.distance_to(target) < magnet_range:
		_magnet = true
		set_deferred("freeze", true)
	if _magnet:
		global_position = global_position.move_toward(target, magnet_speed * delta)
		if global_position.distance_to(target) < 8.0:
			_collect()


func _on_body_entered(body: Node2D) -> void:
	if body is Player and _age >= PICKUP_DELAY:
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	if kind == Kind.COIN:
		GameState.add_coins(value)
		GameState.spawn_damage_number(global_position + Vector2(0, -8), value, Color(1, 0.85, 0.3))
	else:
		GameState.add_key()
		GameState.spawn_damage_number(global_position + Vector2(0, -8), 1, Color(0.8, 0.9, 1))
	queue_free()
