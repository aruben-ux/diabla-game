extends Node

## Central game state manager.
## Handles game-wide state, player registry, and game flow.

signal player_registered(peer_id: int, player_data: Dictionary)
signal player_unregistered(peer_id: int)
signal game_state_changed(new_state: GameState)

enum GameState { MENU, LOBBY, LOADING, PLAYING, PAUSED }

var current_state: GameState = GameState.MENU
var players: Dictionary = {} # peer_id -> player_data
var is_online_mode: bool = false
var is_dedicated_server: bool = false  # True when running as headless game server

## Set by headless server on startup
var dedicated_game_id: int = -1
var dedicated_port: int = 9000
var dedicated_seed: int = 0
var dedicated_max_players: int = 8
var dedicated_difficulty: String = "normal"
var dedicated_lobby_url: String = "http://127.0.0.1:8080"
var dedicated_server_secret: String = ""

## Maps peer_id -> { account_id, character_id, character_data }
var online_players: Dictionary = {}


func register_player(peer_id: int, player_data: Dictionary) -> void:
	players[peer_id] = player_data
	player_registered.emit(peer_id, player_data)


func unregister_player(peer_id: int) -> void:
	players.erase(peer_id)
	player_unregistered.emit(peer_id)


func change_state(new_state: GameState) -> void:
	current_state = new_state
	game_state_changed.emit(new_state)


func get_player_data(peer_id: int) -> Dictionary:
	return players.get(peer_id, {})
