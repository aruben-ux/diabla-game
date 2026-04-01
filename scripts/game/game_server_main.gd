extends Node

## Headless dedicated game server entry point.
## Launched by the lobby server's game spawner.
## Parses command-line args, hosts an ENet server, validates player tokens
## with the lobby, and manages authoritative game state.

const SAVE_INTERVAL := 30.0  # Save all player characters every 30s
const IDLE_TIMEOUT := 300.0  # Shut down if empty for 5 minutes
const HEARTBEAT_INTERVAL := 30.0  # Send heartbeat to lobby every 30s

var _lobby_url: String = "http://127.0.0.1:8080"
var _server_secret: String = ""
var _game_id: int = -1
var _port: int = 9000
var _game_seed: int = 0
var _max_players: int = 8
var _difficulty: String = "normal"

var _http: HTTPRequest
var _save_timer: float = 0.0
var _idle_timer: float = 0.0
var _heartbeat_timer: float = 0.0

## peer_id -> { account_id, character_id, character_data }
var _authenticated_players: Dictionary = {}
## Pending token validations: peer_id -> token
var _pending_auth: Dictionary = {}


func _ready() -> void:
	_parse_args()
	_http = HTTPRequest.new()
	add_child(_http)

	GameManager.is_dedicated_server = true
	GameManager.is_online_mode = true
	GameManager.dedicated_game_id = _game_id
	GameManager.dedicated_port = _port
	GameManager.dedicated_seed = _game_seed
	GameManager.dedicated_max_players = _max_players
	GameManager.dedicated_difficulty = _difficulty
	GameManager.dedicated_lobby_url = _lobby_url
	GameManager.dedicated_server_secret = _server_secret

	# Connect token received signal
	EventBus.game_token_received.connect(_on_game_token_received)
	EventBus.server_ready.connect(_notify_lobby_ready, CONNECT_ONE_SHOT)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	# Start ENet server
	var error := NetworkManager.host_game(_port)
	if error != OK:
		printerr("[GameServer] Failed to start on port ", _port)
		get_tree().quit(1)
		return

	print("[GameServer] Running: game_id=%d port=%d seed=%d max=%d difficulty=%s" % [
		_game_id, _port, _game_seed, _max_players, _difficulty
	])

	# Load the main game scene
	get_tree().change_scene_to_file("res://scenes/game/main_game.tscn")


func _process(delta: float) -> void:
	# Periodic save
	_save_timer += delta
	if _save_timer >= SAVE_INTERVAL:
		_save_timer = 0.0
		_save_all_players()

	# Heartbeat — keep lobby aware this server is alive + correct player count
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_update_player_count()

	# Idle shutdown
	if _authenticated_players.is_empty():
		_idle_timer += delta
		if _idle_timer >= IDLE_TIMEOUT:
			print("[GameServer] Idle timeout reached, shutting down.")
			_shutdown()
	else:
		_idle_timer = 0.0


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game-id="):
			_game_id = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--port="):
			_port = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seed="):
			_game_seed = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--max-players="):
			_max_players = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--difficulty="):
			_difficulty = arg.get_slice("=", 1)
		elif arg.begins_with("--lobby-url="):
			_lobby_url = arg.get_slice("=", 1)
		elif arg.begins_with("--server-secret="):
			_server_secret = arg.get_slice("=", 1)


# --- Player Authentication ---

func _on_game_token_received(peer_id: int, token: String) -> void:
	#print("[GameServer] Validating token for peer ", peer_id)
	_pending_auth[peer_id] = token
	_validate_token_with_lobby(peer_id, token)


func _validate_token_with_lobby(peer_id: int, token: String) -> void:
	var url := _lobby_url + "/games/internal/validate_token"
	var body := JSON.stringify({"game_token": token, "game_id": _game_id})
	var headers := PackedStringArray(["Content-Type: application/json"])

	# Use a separate HTTPRequest per validation to handle concurrent joins
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			http.queue_free()
			_on_token_validated(peer_id, code, body_bytes),
		CONNECT_ONE_SHOT)
	http.request(url, headers, HTTPClient.METHOD_POST, body)


func _on_token_validated(peer_id: int, code: int, body_bytes: PackedByteArray) -> void:
	_pending_auth.erase(peer_id)

	if code != 200:
		print("[GameServer] Token validation failed for peer ", peer_id, " (code ", code, ")")
		# Kick the player
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	var json := JSON.new()
	if json.parse(body_bytes.get_string_from_utf8()) != OK:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	var data: Dictionary = json.data
	var account_id: int = data.get("account_id", -1)
	var character_id: int = data.get("character_id", -1)
	var char_data: Dictionary = data.get("character_data", {})

	_authenticated_players[peer_id] = {
		"account_id": account_id,
		"character_id": character_id,
		"character_data": char_data,
		"join_time": Time.get_unix_time_from_system(),
	}

	print("[GameServer] Player authenticated: peer=%d account=%d char=%s" % [
		peer_id, account_id, char_data.get("character_name", "???")
	])

	# Send existing players to the new peer so they can spawn them
	for existing_id in _authenticated_players:
		if existing_id == peer_id:
			continue
		var existing_data: Dictionary = _authenticated_players[existing_id]["character_data"]
		NetworkManager._confirm_player_authenticated.rpc_id(peer_id, existing_id, existing_data)

	# Tell all peers (including the new one) this player is in
	NetworkManager._confirm_player_authenticated.rpc(peer_id, char_data)
	_update_player_count()


func _on_player_disconnected(peer_id: int) -> void:
	if peer_id in _authenticated_players:
		_save_player(peer_id)
		_authenticated_players.erase(peer_id)
		_update_player_count()
	_pending_auth.erase(peer_id)


# --- Character Saving ---

func _save_all_players() -> void:
	for peer_id in _authenticated_players:
		_save_player(peer_id)


func _save_player(peer_id: int) -> void:
	if peer_id not in _authenticated_players:
		return

	var info: Dictionary = _authenticated_players[peer_id]
	var character_id: int = info.get("character_id", -1)
	if character_id < 0:
		return

	# Get live state from the player node
	var player_container := get_tree().current_scene.get_node_or_null("PlayerContainer")
	if player_container == null:
		return
	var player_node := player_container.get_node_or_null(str(peer_id))
	if player_node == null:
		return

	var stats: PlayerStats = player_node.stats
	var inv: Inventory = player_node.inventory
	var sm: SkillManager = player_node.skill_manager

	# Subtract tree bonuses to save BASE stats (prevents drift)
	var tb: Dictionary = player_node.get_meta("_tree_bonuses", {})
	var hp_bonus: float = tb.get("max_health", 0.0) + tb.get("vitality", 0.0) * 5.0
	var mp_bonus: float = tb.get("max_mana", 0.0)

	# Subtract equipment bonuses from stats
	var eq_dmg := 0.0
	var eq_def := 0.0
	var eq_hp := 0.0
	var eq_mp := 0.0
	var eq_str := 0
	var eq_dex := 0
	var eq_int := 0
	for slot_name: String in inv.equipment:
		var eq_item: ItemData = inv.equipment[slot_name]
		if eq_item == null:
			continue
		eq_dmg += eq_item.bonus_damage
		eq_def += eq_item.bonus_defense
		eq_hp += eq_item.bonus_health
		eq_mp += eq_item.bonus_mana
		eq_str += eq_item.bonus_strength
		eq_dex += eq_item.bonus_dexterity
		eq_int += eq_item.bonus_intelligence
		for affix: Dictionary in eq_item.affixes:
			var stat: String = affix.get("stat", "")
			var val: float = float(affix.get("value", 0.0))
			match stat:
				"bonus_damage": eq_dmg += val
				"bonus_defense": eq_def += val
				"bonus_health": eq_hp += val
				"bonus_mana": eq_mp += val
				"bonus_strength": eq_str += int(val)
				"bonus_dexterity": eq_dex += int(val)
				"bonus_intelligence": eq_int += int(val)

	# Subtract resonance bonuses
	var res_bonuses: Dictionary = AffixDatabase.get_resonance_stat_bonuses(inv.get_active_resonances())
	eq_dmg += res_bonuses.get("bonus_damage", 0.0) + res_bonuses.get("attack_damage", 0.0)
	eq_def += res_bonuses.get("bonus_defense", 0.0)
	eq_hp += res_bonuses.get("bonus_health", 0.0)
	eq_mp += res_bonuses.get("bonus_mana", 0.0)

	var save_data := {
		"level": stats.level,
		"experience": stats.experience,
		"max_health": stats.max_health - hp_bonus - eq_hp,
		"max_mana": stats.max_mana - mp_bonus - eq_mp,
		"health": minf(stats.health, stats.max_health - hp_bonus - eq_hp),
		"mana": minf(stats.mana, stats.max_mana - mp_bonus - eq_mp),
		"strength": stats.strength - int(tb.get("strength", 0.0)) - eq_str,
		"dexterity": stats.dexterity - int(tb.get("dexterity", 0.0)) - eq_dex,
		"intelligence": stats.intelligence - int(tb.get("intelligence", 0.0)) - eq_int,
		"vitality": stats.vitality - int(tb.get("vitality", 0.0)),
		"attack_damage": stats.attack_damage - tb.get("attack_damage", 0.0) - eq_dmg,
		"attack_speed": stats.attack_speed,
		"defense": stats.defense - tb.get("defense", 0.0) - eq_def,
		"move_speed": stats.move_speed - tb.get("move_speed", 0.0),
		"gold": inv.gold,
		"health_potions": inv.health_potions,
		"mana_potions": inv.mana_potions,
		"inventory_items": inv.serialize_grid(),
		"equipment": {},
		"quest_data": player_node.get("_quest_data_cache") if player_node.get("_quest_data_cache") else [],
		"skill_points": sm.skill_points if sm else 0,
		"allocated_skill_points": sm.allocated_points.duplicate() if sm else {},
		"play_time_seconds": info["character_data"].get("play_time_seconds", 0.0) + (Time.get_unix_time_from_system() - info.get("join_time", Time.get_unix_time_from_system())),
	}

	for slot_name in inv.equipment:
		var eq_item: ItemData = inv.equipment[slot_name]
		if eq_item != null:
			save_data["equipment"][slot_name] = eq_item.to_dict()

	# Update cached data and reset join_time so next save doesn't double-count
	info["character_data"].merge(save_data, true)
	info["join_time"] = Time.get_unix_time_from_system()

	# POST to lobby server
	var url := _lobby_url + "/characters/internal/%d?server_secret=%s" % [character_id, _server_secret.uri_encode()]
	var body := JSON.stringify(save_data)
	var headers := PackedStringArray(["Content-Type: application/json"])

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray):
			http.queue_free()
			if code == 200:
				pass
			else:
				printerr("[GameServer] Failed to save character %d (code %d)" % [character_id, code]),
		CONNECT_ONE_SHOT)
	http.request(url, headers, HTTPClient.METHOD_PATCH, body)


# --- Lobby Communication ---

func _notify_lobby_ready() -> void:
	print("[GameServer] Town ready — notifying lobby")
	var url := _lobby_url + "/games/internal/ready"
	var body := JSON.stringify({
		"server_secret": _server_secret,
		"game_id": _game_id,
		"current_players": 0,
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(_result: int, _code: int, _h: PackedStringArray, _b: PackedByteArray):
			http.queue_free(),
		CONNECT_ONE_SHOT)
	http.request(url, headers, HTTPClient.METHOD_POST, body)


func _update_player_count() -> void:
	var url := _lobby_url + "/games/internal/player_count"
	var body := JSON.stringify({
		"server_secret": _server_secret,
		"game_id": _game_id,
		"current_players": _authenticated_players.size(),
	})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(_result: int, _code: int, _h: PackedStringArray, _b: PackedByteArray):
			http.queue_free(),
		CONNECT_ONE_SHOT)
	http.request(url, headers, HTTPClient.METHOD_POST, body)


func _notify_lobby_close() -> void:
	_save_all_players()
	# Tell the lobby this game is closed
	var url := _lobby_url + "/games/internal/close"
	var body := JSON.stringify({
		"server_secret": _server_secret,
		"game_id": _game_id,
		"current_players": 0,
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray):
			http.queue_free(), CONNECT_ONE_SHOT)
	http.request(url, headers, HTTPClient.METHOD_POST, body)


func _shutdown() -> void:
	## Graceful shutdown: notify lobby, wait briefly for HTTP to send, then quit.
	_notify_lobby_close()
	# Give the HTTP request a moment to actually send before exiting
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_all_players()
		_notify_lobby_close()
		# Brief delay so the close notification can be sent
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
