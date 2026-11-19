extends CanvasLayer
## In-run HUD: HP, level, coins, keys, items, defense info (wave + relic durability),
## boss health bar, toast messages, fade.

@onready var hp_bar: ProgressBar = %HPBar
@onready var hp_label: Label = %HPLabel
@onready var depth_label: Label = %DepthLabel
@onready var items_label: Label = %ItemsLabel
@onready var defense_panel: Control = %DefensePanel
@onready var wave_label: Label = %WaveLabel
@onready var relic_bar: ProgressBar = %RelicBar
@onready var relic_label: Label = %RelicLabel
@onready var toast: Label = %Toast
@onready var fade: ColorRect = %Fade
@onready var coins_label: Label = %CoinsLabel
@onready var keys_label: Label = %KeysLabel
@onready var boss_panel: Control = %BossPanel
@onready var boss_name: Label = %BossName
@onready var boss_bar: ProgressBar = %BossBar

var _boss: Enemy

var _toast_tween: Tween


func _ready() -> void:
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.items_changed.connect(_on_items_changed)
	GameState.item_picked_up.connect(func(item: ItemData) -> void:
		show_toast("%s (%s): %s" % [item.item_name, item.rarity_name(), item.description]))
	GameState.coins_changed.connect(func(c: int) -> void: coins_label.text = "Coins: %d" % c)
	GameState.keys_changed.connect(func(k: int) -> void: keys_label.text = "Keys: %d" % k)
	coins_label.text = "Coins: %d" % GameState.coins
	keys_label.text = "Keys: %d" % GameState.keys
	boss_panel.visible = false
	_on_hp_changed(GameState.hp, GameState.get_max_hp())
	_on_items_changed()
	defense_panel.visible = false
	toast.modulate.a = 0.0
	fade.modulate.a = 0.0


func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [hp, max_hp]


func _on_items_changed() -> void:
	var names: Array[String] = []
	for item in GameState.items:
		names.append(item.item_name)
	items_label.text = "Items: " + (", ".join(names) if names.size() > 0 else "none")


func set_level(level: int, region_name: String) -> void:
	depth_label.text = "Level %d - %s" % [level, region_name]


func show_defense(relic: DefenseRelic) -> void:
	defense_panel.visible = true
	relic_bar.max_value = relic.max_durability
	relic_bar.value = relic.durability
	relic_label.text = "Relic: %s" % relic.item.item_name
	relic.durability_changed.connect(func(cur: int, _max: int) -> void: relic_bar.value = cur)
	relic.broken_signal.connect(func() -> void: relic_label.text = "Relic: BROKEN - no reward")


func set_wave(wave: int, total: int) -> void:
	wave_label.text = "Wave %d / %d" % [wave, total]


func hide_defense(delay := 0.0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	defense_panel.visible = false


func show_boss(boss: Enemy, title: String) -> void:
	_boss = boss
	boss_name.text = title
	boss_bar.max_value = boss.max_hp
	boss_bar.value = boss.hp
	boss_panel.visible = true
	boss.health_changed.connect(func(hp: int, max_hp: int) -> void:
		boss_bar.max_value = max_hp
		boss_bar.value = hp)
	boss.died.connect(func(_e: Enemy) -> void: hide_boss())


func hide_boss() -> void:
	boss_panel.visible = false
	_boss = null


func show_toast(text: String, duration := 2.5) -> void:
	toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.4)


func fade_to(alpha: float, time: float) -> Signal:
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", alpha, time)
	return tw.finished
