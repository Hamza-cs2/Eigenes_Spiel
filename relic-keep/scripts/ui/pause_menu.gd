extends CanvasLayer
## Esc pauses and shows the inventory: weapons (coming later), relics (max 3), backpack (1 spare
## relic) and upgrades. Relics can be dropped or swapped with the backpack here.
## "Abandon Run" ends the run (counts as a death - permadeath).

const ITEM_PICKUP := preload("res://scenes/items/item_pickup.tscn")

signal abandon_requested

@onready var resume_button: Button = %ResumeButton
@onready var abandon_button: Button = %AbandonButton
@onready var inventory: VBoxContainer = %Inventory


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_toggle)
	abandon_button.pressed.connect(func() -> void:
		get_tree().paused = false
		visible = false
		abandon_requested.emit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if get_tree().paused and not visible:
			return # another menu (upgrade choice) has the game paused
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		_build_inventory()
		resume_button.grab_focus()


func _build_inventory() -> void:
	for c in inventory.get_children():
		c.queue_free()
	_header("WEAPONS")
	_text("(coming soon)", Color(0.6, 0.6, 0.6))
	_header("RELICS  %d / %d" % [GameState.items.size(), GameState.MAX_RELICS])
	for i in GameState.MAX_RELICS:
		if i < GameState.items.size():
			var item: ItemData = GameState.items[i]
			_item_row(item, [["Drop", _drop.bind(i)], ["To backpack", _swap.bind(i)]])
		else:
			_text("  - empty -", Color(0.5, 0.5, 0.5))
	_header("BACKPACK")
	if GameState.backpack:
		var actions := [["Drop", _drop.bind(-1)]]
		if GameState.items.size() < GameState.MAX_RELICS:
			actions.append(["Equip", _swap.bind(-1)])
		_item_row(GameState.backpack, actions)
	else:
		_text("  - empty -", Color(0.5, 0.5, 0.5))
	_header("UPGRADES  (%d scrolls)" % GameState.upgrade_count)
	if GameState.upgrades.is_empty():
		_text("  none yet - find scrolls in the levels", Color(0.5, 0.5, 0.5))
	for stat in GameState.upgrades:
		_text("  %s +%s" % [stat.capitalize(), str(snappedf(GameState.upgrades[stat], 0.01))], Color(0.8, 0.65, 1))


func _header(t: String) -> void:
	_text(t, Color(1, 0.85, 0.4), 10)


func _text(t: String, col := Color.WHITE, size := 8) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	inventory.add_child(l)
	return l


func _item_row(item: ItemData, actions: Array) -> void:
	var row := HBoxContainer.new()
	inventory.add_child(row)
	var l := Label.new()
	l.text = "  %s - %s" % [item.item_name, item.description]
	l.add_theme_color_override("font_color", item.rarity_color())
	l.add_theme_font_size_override("font_size", 8)
	l.custom_minimum_size.x = 300
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	for a in actions:
		var b := Button.new()
		b.text = a[0]
		b.add_theme_font_size_override("font_size", 8)
		b.pressed.connect(a[1])
		row.add_child(b)


func _drop(index: int) -> void:
	var item := GameState.remove_item(index)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if item and player and is_instance_valid(GameState.effects_root):
		var p: ItemPickup = ITEM_PICKUP.instantiate()
		p.item = item
		p.position = GameState.effects_root.to_local(player.global_position) + Vector2(-20, 0)
		GameState.effects_root.add_child(p)
	_build_inventory()


func _swap(index: int) -> void:
	if index < 0:
		GameState.swap_backpack(-1)
	elif GameState.backpack:
		GameState.swap_backpack(index)
	else:
		GameState.backpack = GameState.remove_item(index)
		GameState.items_changed.emit()
	_build_inventory()
