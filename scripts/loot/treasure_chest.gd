extends StaticBody3D

## Treasure chest interactable in dungeons.
## Player clicks it, walks over, and it opens to drop loot + gold.

var display_name: String = "Treasure Chest"
var interact_hint: String = "Click to open"

var _opened := false
var _lid_node: Node3D
var _floor_level: int = 1


func setup(floor_lvl: int) -> void:
	_floor_level = floor_lvl


func interact(player: Node) -> void:
	if _opened:
		return
	if not player or not is_instance_valid(player):
		return
	_opened = true
	display_name = "Empty Chest"
	interact_hint = ""
	_animate_open()


func server_interact(player: Node) -> void:
	## Called by the server to drop loot. Client calls interact() for animation only.
	_drop_contents(player)


func _animate_open() -> void:
	if _lid_node:
		var tween := create_tween()
		tween.tween_property(_lid_node, "rotation:x", -PI * 0.65, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _drop_contents(player: Node) -> void:
	# Gold
	var gold_amount := randi_range(10, 30) * _floor_level
	var gold_scene := preload("res://scenes/loot/gold_drop.tscn")
	var gold := gold_scene.instantiate()
	gold.name = "ChestGold_%d" % randi()
	get_parent().add_child(gold)
	gold.global_position = global_position + Vector3(0, 0.5, 0)
	gold.setup(gold_amount)

	# 1-3 item drops
	var drop_count := randi_range(1, 3)
	var drops := ItemDatabase.generate_enemy_drops(_floor_level)
	# Always guarantee at least one equipment drop from a chest
	if drops.is_empty():
		if randf() < 0.5:
			drops.append(ItemDatabase.get_random_weapon(_floor_level))
		else:
			drops.append(ItemDatabase.get_random_armor(_floor_level))
	for i in drops.size():
		var offset := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
		var loot_scene := preload("res://scenes/loot/loot_drop.tscn")
		var loot := loot_scene.instantiate()
		loot.name = "ChestLoot_%d" % randi()
		get_parent().add_child(loot)
		loot.global_position = global_position + offset + Vector3(0, 0.5, 0)
		loot.setup(drops[i])


func set_lid(node: Node3D) -> void:
	_lid_node = node
