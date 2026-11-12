extends Node
## Autoload "GameState": everything about the current run.
## Permadeath: when the run ends, all of this is thrown away. Only best_depth / runs_played are saved.

signal hp_changed(hp: int, max_hp: int)
signal items_changed
signal item_picked_up(item: ItemData)

const SAVE_PATH := "user://save.cfg"
const DAMAGE_NUMBER := preload("res://scenes/ui/damage_number.tscn")

const BASE_STATS := {
	"max_hp": 100.0,
	"damage": 10.0,
	"attack_speed": 1.0,
	"move_speed": 1.0,
	"dash_cooldown": 1.0, # multiplier, lower = faster
	"extra_jumps": 0.0,
	"lifesteal": 0.0, # fraction of damage dealt that heals you
	"crit_chance": 0.05,
	"armor": 0.0, # fraction of damage blocked (max 0.6)
}

const ITEM_POOL: Array[ItemData] = [
	preload("res://resources/items/iron_ring.tres"),
	preload("res://resources/items/swift_boots.tres"),
	preload("res://resources/items/heart_charm.tres"),
	preload("res://resources/items/whetstone.tres"),
	preload("res://resources/items/light_gloves.tres"),
	preload("res://resources/items/leather_vest.tres"),
	preload("res://resources/items/feather_cape.tres"),
	preload("res://resources/items/vampire_fang.tres"),
	preload("res://resources/items/storm_sigil.tres"),
	preload("res://resources/items/berserker_brand.tres"),
	preload("res://resources/items/keepers_crown.tres"),
	preload("res://resources/items/blade_of_ages.tres"),
	preload("res://resources/items/hourglass_heart.tres"),
	preload("res://resources/items/wings_of_dawn.tres"),
	preload("res://resources/items/bloodstone.tres"),
]

var run_active := false
## Current level (region) number, starts at 1.
var depth := 0
var levels_since_defense := 0
var kills := 0
var defenses_won := 0
var defenses_lost := 0
var hp := 100
var items: Array[ItemData] = []
var rng := RandomNumberGenerator.new()
var last_run := {}

var best_depth := 0
var runs_played := 0

## Node that floating effects (damage numbers, drops) get added to. Set by the Run to the current room.
var effects_root: Node = null

var _lifesteal_acc := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # so F11 also works in the pause menu
	_load_save()


## F11 switches between fullscreen and a big window.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------- run lifecycle

func start_new_run() -> void:
	run_active = true
	depth = 0
	levels_since_defense = 0
	kills = 0
	defenses_won = 0
	defenses_lost = 0
	items.clear()
	_lifesteal_acc = 0.0
	rng.randomize()
	hp = get_max_hp()
	items_changed.emit()
	hp_changed.emit(hp, get_max_hp())


func end_run() -> void:
	if not run_active:
		return
	run_active = false
	runs_played += 1
	var new_best := depth > best_depth
	best_depth = maxi(best_depth, depth)
	last_run = {
		"depth": depth,
		"kills": kills,
		"defenses_won": defenses_won,
		"defenses_lost": defenses_lost,
		"items": items.size(),
		"new_best": new_best,
	}
	_save()


# ---------------------------------------------------------------- stats & items

func get_stat(stat: String) -> float:
	var value: float = BASE_STATS.get(stat, 0.0)
	for item in items:
		value += float(item.stats.get(stat, 0.0))
	match stat:
		"max_hp":
			value = maxf(value, 30.0)
		"attack_speed":
			value = maxf(value, 0.5)
		"move_speed":
			value = clampf(value, 0.5, 2.0)
		"dash_cooldown":
			value = maxf(value, 0.3)
		"armor":
			value = clampf(value, 0.0, 0.6)
		"crit_chance":
			value = clampf(value, 0.0, 1.0)
	return value


func get_max_hp() -> int:
	return roundi(get_stat("max_hp"))


func add_item(item: ItemData) -> void:
	items.append(item)
	var hp_bonus := int(item.stats.get("max_hp", 0))
	if hp_bonus > 0:
		hp += hp_bonus
	hp = clampi(hp + item.heal, 1, get_max_hp())
	items_changed.emit()
	item_picked_up.emit(item)
	hp_changed.emit(hp, get_max_hp())


func roll_item(rarity: ItemData.Rarity) -> ItemData:
	var options := ITEM_POOL.filter(func(i: ItemData) -> bool: return i.rarity == rarity)
	return options[rng.randi_range(0, options.size() - 1)]


## Normal room reward: mostly common, rare gets more likely on later levels.
func roll_room_reward() -> ItemData:
	var rare_chance := minf(0.2 + 0.08 * depth, 0.6)
	return roll_item(ItemData.Rarity.RARE if rng.randf() < rare_chance else ItemData.Rarity.COMMON)


## Relic rooms are rare: not on level 1, about every 2-3 levels.
func should_spawn_defense() -> bool:
	if depth < 2:
		return false
	return levels_since_defense >= 2 or rng.randf() < 0.4


# ---------------------------------------------------------------- health

func damage_player(amount: int) -> void:
	hp = maxi(hp - amount, 0)
	hp_changed.emit(hp, get_max_hp())


func heal_player(amount: int) -> void:
	if amount <= 0:
		return
	hp = mini(hp + amount, get_max_hp())
	hp_changed.emit(hp, get_max_hp())


func on_player_dealt_damage(amount: int) -> void:
	var ls := get_stat("lifesteal")
	if ls <= 0.0:
		return
	_lifesteal_acc += amount * ls
	if _lifesteal_acc >= 1.0:
		var heal := floori(_lifesteal_acc)
		_lifesteal_acc -= heal
		heal_player(heal)


# ---------------------------------------------------------------- difficulty

func enemy_hp_mult() -> float:
	return 1.0 + maxi(depth - 1, 0) * 0.3


func enemy_damage_mult() -> float:
	return 1.0 + maxi(depth - 1, 0) * 0.2


# ---------------------------------------------------------------- effects

func spawn_damage_number(pos: Vector2, amount: int, color := Color.WHITE) -> void:
	if not is_instance_valid(effects_root):
		return
	var dn := DAMAGE_NUMBER.instantiate()
	effects_root.add_child(dn)
	dn.setup(pos, str(amount), color)


## Tiny freeze-frame that makes hits feel heavy.
func hitstop(duration := 0.04) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- save

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best_depth", best_depth)
	cfg.set_value("progress", "runs_played", runs_played)
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_depth = cfg.get_value("progress", "best_depth", 0)
		runs_played = cfg.get_value("progress", "runs_played", 0)
