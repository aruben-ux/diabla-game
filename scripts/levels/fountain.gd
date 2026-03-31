extends StaticBody3D

## Interactable fountain that restores health and mana on click.

var display_name: String = tr("Fountain")
var interact_hint: String = tr("Click to restore Health & Mana")


func interact(player: Node) -> void:
	if not player or not is_instance_valid(player):
		return
	var s = player.stats
	if s:
		s.health = s.max_health
		s.mana = s.max_mana
