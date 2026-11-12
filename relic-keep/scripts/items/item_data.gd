class_name ItemData
extends Resource
## One item. Create new items as .tres files in res://resources/items/
## (right-click folder > New Resource > ItemData) and add them to GameState.ITEM_POOL.

enum Rarity { COMMON, RARE, LEGENDARY }

@export var item_name := "Item"
@export_multiline var description := ""
@export var rarity: Rarity = Rarity.COMMON
## Stat bonuses added to GameState.BASE_STATS. Valid keys:
## max_hp, damage, attack_speed, move_speed, dash_cooldown, extra_jumps, lifesteal, crit_chance, armor
@export var stats: Dictionary = {}
## Instant heal when picked up.
@export var heal := 0


func rarity_color() -> Color:
	match rarity:
		Rarity.RARE:
			return Color(0.4, 0.65, 1.0)
		Rarity.LEGENDARY:
			return Color(1.0, 0.65, 0.2)
	return Color(0.85, 0.85, 0.85)


func rarity_name() -> String:
	return ["Common", "Rare", "Legendary"][rarity]
