extends Node

## Global signal bus for decoupled communication between systems.
## Use this for cross-system events that don't belong to a specific node.

# Combat events
signal damage_dealt(attacker_id: int, target_id: int, amount: float)
signal entity_died(entity_id: int)

# Loot events
signal loot_dropped(position: Vector3, item_data: Dictionary)
signal loot_picked_up(player_id: int, item_data: Dictionary)

# UI events
signal show_floating_text(position: Vector3, text: String, color: Color)
signal chat_message_received(sender: String, message: String)

# Game flow events
signal level_load_requested(level_name: String)
signal level_loaded(level_name: String)

# Online / dedicated server events
signal game_token_received(peer_id: int, token: String)

# NPC / dialog events
signal npc_dialog_opened(npc_name: String, lines: Array)
signal npc_dialog_closed()
signal npc_dialog_advance()
