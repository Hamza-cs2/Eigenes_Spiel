@tool
class_name RoomTemplate
extends Node2D
## Root script of every room template (scenes/rooms/templates/*.tscn).
## The level generator stitches these together into one seamless level.
##
## How to make your own room: see README.md ("Making your own rooms").
## Required children:
##   Tiles        (TileMapLayer, tile_set = assets/tiles/tileset.tres) - paint the room here
##   Exits        (Node2D) with RoomExit markers
##   EnemySpawns  (Node2D) with EnemySpawn markers       (optional)
##   ItemSpawns   (Node2D) with ItemSpawn markers        (optional)
##   PlayerSpawn  (Marker2D)  START rooms only
##   LevelExit    (Marker2D)  END rooms only  (door to the next region)
##   RelicSpawn   (Marker2D)  DEFENSE rooms only (use defense_room.gd as script)
##   ShopSlots + Merchant      SHOP rooms only (use shop_room.gd as script)
##   BossSpawn    (Marker2D)  MINIBOSS / BOSS rooms only (use boss_arena.gd as script)

signal message(text: String)

enum RoomType { NORMAL, START, END, DEFENSE, BRANCH, SHOP, MINIBOSS, BOSS }

const TILE := 16
const ENEMY_SCENES := {
	"walker": preload("res://scenes/enemies/walker.tscn"),
	"archer": preload("res://scenes/enemies/archer.tscn"),
	"flyer": preload("res://scenes/enemies/flyer.tscn"),
	"brute": preload("res://scenes/enemies/brute.tscn"),
}
const ITEM_PICKUP := preload("res://scenes/items/item_pickup.tscn")
## Enemies never spawn closer than this to each other.
const MIN_ENEMY_SPACING := 32.0

## Size of the room in tiles (including the 2-tile border). The blue box in the editor.
@export var size_tiles := Vector2i(40, 20):
	set(value):
		size_tiles = value
		queue_redraw()
@export var room_type: RoomType = RoomType.NORMAL
## Higher = picked more often.
@export_range(0.0, 10.0, 0.1) var weight := 1.0
## First level this room can appear in.
@export var min_level := 1
## -1 = automatic (more enemies on later levels). Otherwise the exact max.
@export var max_enemies := -1
## Chance per ItemSpawn marker to drop an item (BRANCH rooms: always).
@export_range(0.0, 1.0) var item_chance := 0.15

var level_index := 1
var rng: RandomNumberGenerator
var origin_tiles := Vector2i.ZERO
var enemies_root: Node2D
## Has the player been in this room? (for the map)
var visited := false
## Set by the level: a key lies in this room, guarded by extra enemies.
var guarded_key := false
## Set by the level: this is a locked treasure room (better loot behind a LockedGate).
var vault := false
var gate: LockedGate

var _used_spawns: Array[Marker2D] = []

var _map_image: Image


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		return
	enemies_root = get_node_or_null("Enemies")
	if enemies_root == null:
		enemies_root = Node2D.new()
		enemies_root.name = "Enemies"
		add_child(enemies_root)


# ---------------------------------------------------------------- accessors

func get_tiles() -> TileMapLayer:
	return get_node("Tiles") as TileMapLayer


func get_exits() -> Array[RoomExit]:
	var out: Array[RoomExit] = []
	var holder := get_node_or_null("Exits")
	if holder:
		for c in holder.get_children():
			if c is RoomExit:
				out.append(c)
	return out


func get_markers(holder_name: String) -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	var holder := get_node_or_null(holder_name)
	if holder:
		for c in holder.get_children():
			if c is Marker2D:
				out.append(c)
	return out


func get_rect_px() -> Rect2:
	return Rect2(position, Vector2(size_tiles * TILE))


# ---------------------------------------------------------------- runtime setup

## Called by the level after all rooms are placed and exits connected/sealed.
func populate(p_level: int, p_rng: RandomNumberGenerator) -> void:
	level_index = p_level
	rng = p_rng
	_spawn_enemies()
	_spawn_items()
	_populate_extra()


## Override in special rooms (defense room).
func _populate_extra() -> void:
	pass


func enemy_count() -> int:
	if max_enemies >= 0:
		return max_enemies
	match room_type:
		RoomType.START, RoomType.DEFENSE, RoomType.SHOP, RoomType.MINIBOSS, RoomType.BOSS:
			return 0
		RoomType.BRANCH:
			return 0 if vault else rng.randi_range(0, 2)
		RoomType.END:
			return rng.randi_range(2, 2 + level_index / 2)
	return rng.randi_range(2 + level_index / 2, 4 + level_index)


func _spawn_enemies() -> void:
	var spawns := get_markers("EnemySpawns")
	_shuffle(spawns)
	var count := mini(enemy_count(), spawns.size())
	var used: Array[Vector2] = []
	for sp in spawns:
		if used.size() >= count:
			break
		if used.any(func(p: Vector2) -> bool: return p.distance_to(sp.position) < MIN_ENEMY_SPACING):
			continue
		var kind := "flyer" if sp is EnemySpawn and sp.kind == EnemySpawn.Kind.AIR else pick_ground_kind()
		spawn_enemy(kind, sp.position)
		used.append(sp.position)
		_used_spawns.append(sp)
	if guarded_key:
		_spawn_guarded_key()


## Puts a key on a free ground spawn point and 2 extra enemies next to it (nearest free spawn points).
func _spawn_guarded_key() -> void:
	var ground := get_markers("EnemySpawns").filter(func(m: Marker2D) -> bool:
		return not (m is EnemySpawn and m.kind == EnemySpawn.Kind.AIR))
	var free := ground.filter(func(m: Marker2D) -> bool: return not m in _used_spawns)
	if free.is_empty():
		free = ground
	if free.is_empty():
		return
	var spot: Marker2D = free[rng.randi_range(0, free.size() - 1)]
	var key := LootPickup.spawn_key(self, spot.position + Vector2(0, -10))
	key.linear_velocity = Vector2.ZERO
	var others := ground.filter(func(m: Marker2D) -> bool: return m != spot and not m in _used_spawns)
	others.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.position.distance_to(spot.position) < b.position.distance_to(spot.position))
	var guards := 0
	for m in others:
		if guards >= 2:
			break
		var e := spawn_enemy(pick_ground_kind(), m.position)
		e.max_hp = roundi(e.max_hp * 1.5)
		e.hp = e.max_hp
		e.modulate = Color(1.3, 1.1, 0.7)
		_used_spawns.append(m)
		guards += 1
	if guards < 2:
		spawn_enemy("flyer", spot.position + Vector2(0, -48))


func pick_ground_kind() -> String:
	var pool := ["walker", "walker", "walker", "archer", "archer"]
	if level_index >= 2:
		pool.append("brute")
	if level_index >= 4:
		pool.append_array(["brute", "archer", "walker"])
	return pool[rng.randi_range(0, pool.size() - 1)]


func spawn_enemy(kind: String, local_pos: Vector2, relic: DefenseRelic = null) -> Enemy:
	var enemy: Enemy = ENEMY_SCENES[kind].instantiate()
	enemy.setup(GameState.enemy_hp_mult(), GameState.enemy_damage_mult(), relic)
	enemy.position = local_pos + Vector2(0, -1)
	enemies_root.add_child(enemy)
	return enemy


func alive_enemies() -> int:
	var n := 0
	for e in enemies_root.get_children():
		if e is Enemy and not e.dead:
			n += 1
	return n


func _spawn_items() -> void:
	var markers := get_markers("ItemSpawns")
	if vault:
		# Locked treasure room: rare or legendary items + a pile of coins.
		for sp in markers:
			var rarity := ItemData.Rarity.LEGENDARY if rng.randf() < 0.25 else ItemData.Rarity.RARE
			spawn_item(GameState.roll_item(rarity), sp.position)
		if not markers.is_empty():
			LootPickup.spawn_coins(self, markers[0].position + Vector2(0, -12), rng.randi_range(30, 60) + 10 * level_index)
		return
	var chance := 1.0 if room_type == RoomType.BRANCH else item_chance
	for sp in markers:
		if rng.randf() < chance:
			spawn_item(GameState.roll_room_reward(), sp.position)


func spawn_item(item: ItemData, local_pos: Vector2) -> void:
	var pickup: ItemPickup = ITEM_PICKUP.instantiate()
	pickup.item = item
	pickup.position = local_pos
	add_child.call_deferred(pickup)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------- map

## 1 pixel per tile picture of the room for the map screen (air = filled, walls = outline).
func get_map_image() -> Image:
	if _map_image:
		return _map_image
	var tiles := get_tiles()
	_map_image = Image.create(size_tiles.x, size_tiles.y, false, Image.FORMAT_RGBA8)
	var air := Color(0.2, 0.25, 0.6)
	var edge := Color(0.95, 0.85, 0.9)
	var plat := Color(0.45, 0.5, 0.85)
	for y in size_tiles.y:
		for x in size_tiles.x:
			var cell := Vector2i(x, y)
			var src := tiles.get_cell_source_id(cell)
			if src == -1:
				_map_image.set_pixel(x, y, air)
			elif tiles.get_cell_atlas_coords(cell).x >= 2:
				_map_image.set_pixel(x, y, plat)
			else:
				# Solid: draw it as outline if it touches air.
				for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nc: Vector2i = cell + n
					if nc.x >= 0 and nc.y >= 0 and nc.x < size_tiles.x and nc.y < size_tiles.y \
							and tiles.get_cell_source_id(nc) == -1:
						_map_image.set_pixel(x, y, edge)
						break
	return _map_image


# ---------------------------------------------------------------- editor preview

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var size := Vector2(size_tiles * TILE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.6, 1.0), false, 2.0)
	var b := 2 * TILE
	draw_rect(Rect2(Vector2(b, b), size - Vector2(b, b) * 2), Color(0.3, 0.6, 1.0, 0.4), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(4, -6),
			"%s  %dx%d tiles" % [RoomType.keys()[room_type], size_tiles.x, size_tiles.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.6, 1.0))
