class_name ShopPedestal
extends Area2D
## One thing for sale in a shop. Walk up and press E to buy.
## Area2D: layer 6 (Pickups), mask 2 (Player).
##
## Right now offers are ItemData (passive items). To sell WEAPONS later: give `offer` your weapon
## resource and add a branch in _give() / _offer_name() / _offer_color() - nothing else changes.

signal bought(offer: Resource)

@export var offer: Resource
@export var price := 100

var sold := false
var _player_inside := false
var _flash := 0.0
var _time := 0.0

@onready var icon: Sprite2D = $Icon
@onready var price_label: Label = $PriceLabel
@onready var prompt: Label = $Prompt


func _ready() -> void:
	body_entered.connect(func(b: Node2D) -> void: if b is Player: _set_inside(true))
	body_exited.connect(func(b: Node2D) -> void: if b is Player: _set_inside(false))
	icon.modulate = _offer_color()
	price_label.text = "%d" % price
	prompt.visible = false
	_update_prompt()


func _set_inside(value: bool) -> void:
	_player_inside = value
	prompt.visible = value and not sold
	_update_prompt()


func _update_prompt() -> void:
	prompt.text = "[E] Buy %s - %d coins\n%s" % [_offer_name(), price, _offer_description()]


func _process(delta: float) -> void:
	_time += delta
	if not sold:
		icon.position.y = -22.0 + sin(_time * 2.5) * 1.5
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_update_prompt()
	if _player_inside and not sold and Input.is_action_just_pressed("interact"):
		buy()


func buy() -> bool:
	if sold:
		return false
	if offer is ItemData and not GameState.can_take_item():
		prompt.text = "Relics + backpack full! Drop one first (Esc)."
		_flash = 1.5
		return false
	if not GameState.spend_coins(price):
		prompt.text = "Not enough coins! (%d / %d)" % [GameState.coins, price]
		_flash = 1.2
		return false
	sold = true
	_give()
	icon.visible = false
	price_label.text = "SOLD"
	prompt.visible = false
	bought.emit(offer)
	return true


func _give() -> void:
	if offer is ItemData:
		GameState.add_item(offer)
	# Later: elif offer is WeaponData: GameState.equip_weapon(offer)


func _offer_name() -> String:
	if offer is ItemData:
		return offer.item_name
	return "???"


func _offer_description() -> String:
	if offer is ItemData:
		return "(%s) %s" % [offer.rarity_name(), offer.description]
	return ""


func _offer_color() -> Color:
	if offer is ItemData:
		return offer.rarity_color()
	return Color.WHITE
