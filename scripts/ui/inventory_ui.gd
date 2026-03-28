extends Control

## Inventory panel UI — shows items in a grid, equipment slots, and item tooltip.

signal closed

@onready var grid: GridContainer = $Panel/MarginContainer/VBoxContainer/ItemGrid
@onready var equip_panel: VBoxContainer = $Panel/MarginContainer/VBoxContainer/EquipPanel
@onready var tooltip: Panel = $Tooltip
@onready var tooltip_label: RichTextLabel = $Tooltip/RichTextLabel
@onready var gold_label: Label = $Panel/MarginContainer/VBoxContainer/GoldLabel

var inventory: Inventory
var player_ref: Node

const SLOT_SIZE := Vector2(48, 48)


func setup(inv: Inventory, player: Node) -> void:
	inventory = inv
	player_ref = player
	inventory.inventory_changed.connect(_refresh)
	inventory.gold_changed.connect(_on_gold_changed)
	_refresh()
	_update_gold()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		visible = !visible
		if visible:
			_refresh()


func _refresh() -> void:
	if not inventory:
		return

	# Clear grid
	for child in grid.get_children():
		child.queue_free()

	# Populate inventory slots
	for i in inventory.items.size():
		var btn := _create_slot_button(inventory.items[i], i)
		grid.add_child(btn)

	# Fill remaining slots
	for i in range(inventory.items.size(), Inventory.MAX_SLOTS):
		var empty := _create_empty_slot()
		grid.add_child(empty)

	# Update equipment display
	_refresh_equipment()


func _refresh_equipment() -> void:
	for child in equip_panel.get_children():
		child.queue_free()

	for slot_name in inventory.equipment:
		var hbox := HBoxContainer.new()
		var label := Label.new()
		label.text = slot_name.capitalize() + ": "
		label.custom_minimum_size = Vector2(70, 0)
		hbox.add_child(label)

		var item: ItemData = inventory.equipment[slot_name]
		if item:
			var btn := Button.new()
			btn.text = item.display_name
			btn.add_theme_color_override("font_color", ItemData.get_rarity_color(item.rarity))
			btn.custom_minimum_size = SLOT_SIZE
			var s: String = slot_name  # Capture for lambda
			btn.pressed.connect(func(): inventory.unequip_item(s, player_ref))
			btn.mouse_entered.connect(func(): _show_tooltip(item, btn))
			btn.mouse_exited.connect(_hide_tooltip)
			hbox.add_child(btn)
		else:
			var empty_label := Label.new()
			empty_label.text = "(empty)"
			empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			hbox.add_child(empty_label)

		equip_panel.add_child(hbox)


func _create_slot_button(item: ItemData, index: int) -> Button:
	var btn := Button.new()
	btn.text = item.display_name.left(6)
	btn.custom_minimum_size = SLOT_SIZE
	btn.add_theme_color_override("font_color", ItemData.get_rarity_color(item.rarity))
	btn.tooltip_text = item.display_name

	var idx := index  # Capture for lambda
	btn.pressed.connect(func(): inventory.use_item(idx, player_ref); _refresh())
	btn.mouse_entered.connect(func(): _show_tooltip(item, btn))
	btn.mouse_exited.connect(_hide_tooltip)
	return btn


func _create_empty_slot() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	return panel


func _show_tooltip(item: ItemData, anchor: Control) -> void:
	tooltip.visible = true
	var text := "[b]%s[/b]\n" % item.display_name
	text += "[color=#%s]%s[/color]\n" % [
		ItemData.get_rarity_color(item.rarity).to_html(false),
		ItemData.Rarity.keys()[item.rarity]
	]
	if item.bonus_damage > 0:
		text += "+%.0f Damage\n" % item.bonus_damage
	if item.bonus_defense > 0:
		text += "+%.0f Defense\n" % item.bonus_defense
	if item.bonus_health > 0:
		text += "+%.0f Health\n" % item.bonus_health
	if item.bonus_mana > 0:
		text += "+%.0f Mana\n" % item.bonus_mana
	if item.heal_amount > 0:
		text += "Heals %.0f HP\n" % item.heal_amount
	if item.mana_restore > 0:
		text += "Restores %.0f Mana\n" % item.mana_restore
	tooltip_label.text = text
	tooltip.global_position = anchor.global_position + Vector2(SLOT_SIZE.x + 8, 0)


func _hide_tooltip() -> void:
	tooltip.visible = false


func _on_gold_changed(_amount: int) -> void:
	_update_gold()


func _update_gold() -> void:
	if gold_label and inventory:
		gold_label.text = "Gold: %d" % inventory.gold
		gold_label.add_theme_color_override("font_color", Color.GOLD)
