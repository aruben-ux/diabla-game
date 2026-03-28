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
	## Called by the server to drop loot via player RPCs.
	_drop_contents(player)


func _animate_open() -> void:
	if _lid_node:
		var tween := create_tween()
		tween.tween_property(_lid_node, "rotation:x", -PI * 0.65, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _drop_contents(player: Node) -> void:
	if not player.has_method("rpc_spawn_gold"):
		return
	# Gold
	var gold_amount := randi_range(10, 30) * _floor_level
	player.rpc_spawn_gold(gold_amount, global_position + Vector3(0, 0.5, 0))

	# Item drops
	var drops := ItemDatabase.generate_enemy_drops(_floor_level)
	if drops.is_empty():
		if randf() < 0.5:
			drops.append(ItemDatabase.get_random_weapon(_floor_level))
		else:
			drops.append(ItemDatabase.get_random_armor(_floor_level))
	for i in drops.size():
		var offset := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
		player.rpc_spawn_loot(drops[i].to_dict(), global_position + offset + Vector3(0, 0.5, 0))


func set_lid(node: Node3D) -> void:
	_lid_node = node
