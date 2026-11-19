@tool
class_name ShopRoom
extends RoomTemplate
## Room template script for merchants (room_type = SHOP).
## Needs: "ShopSlots" (Node2D with Marker2Ds on the floor = one pedestal each) and a "Merchant" Marker2D.
## Slot 1 = common, slot 2 = common/rare, slot 3+ = rare/legendary. No duplicates in one shop.

const PEDESTAL := preload("res://scenes/items/shop_pedestal.tscn")
const MERCHANT := preload("res://scenes/items/merchant.tscn")


func _populate_extra() -> void:
	var merchant_marker := get_node_or_null("Merchant") as Marker2D
	if merchant_marker:
		var m := MERCHANT.instantiate()
		m.position = merchant_marker.position
		add_child(m)
	var used: Array[ItemData] = []
	var slots := get_markers("ShopSlots")
	for i in slots.size():
		var rarity := ItemData.Rarity.COMMON
		if i == 1 and rng.randf() < 0.5:
			rarity = ItemData.Rarity.RARE
		elif i >= 2:
			rarity = ItemData.Rarity.LEGENDARY if rng.randf() < 0.3 else ItemData.Rarity.RARE
		var item := GameState.roll_item(rarity)
		for tries in 10:
			if not item in used:
				break
			item = GameState.roll_item(rarity)
		used.append(item)
		var p: ShopPedestal = PEDESTAL.instantiate()
		p.offer = item
		p.price = GameState.price_for(rarity)
		p.position = slots[i].position
		add_child(p)
