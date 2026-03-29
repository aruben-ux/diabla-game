extends Node

## Manages quest definitions, active quests, and progress tracking.
## Listens for enemy kills and updates quest objectives.

## All quest definitions keyed by quest_id
var _definitions: Dictionary = {}

## Active / completed quests for the local player: quest_id -> QuestData
var quests: Dictionary = {}


func _ready() -> void:
	_register_quests()
	EventBus.enemy_killed.connect(_on_enemy_killed)


## ─── QUEST DEFINITIONS ───

func _register_quests() -> void:
	_define("kill_10_enemies", {
		"title": "Thin the Herd",
		"description": "Slay 10 creatures in the dungeon.",
		"giver": "elder",
		"type": QuestData.ObjectiveType.KILL_ANY,
		"count": 10,
		"gold": 150,
		"xp": 200.0,
	})
	_define("kill_5_grunts", {
		"title": "Grunt Cleanup",
		"description": "Kill 5 Grunts lurking in the depths.",
		"giver": "elder",
		"type": QuestData.ObjectiveType.KILL_TYPE,
		"enemy_type": Enemy.EnemyType.GRUNT,
		"count": 5,
		"gold": 100,
		"xp": 120.0,
	})
	_define("kill_3_mages", {
		"title": "Silence the Casters",
		"description": "Defeat 3 enemy Mages.",
		"giver": "healer",
		"type": QuestData.ObjectiveType.KILL_TYPE,
		"enemy_type": Enemy.EnemyType.MAGE,
		"count": 3,
		"gold": 120,
		"xp": 150.0,
	})
	_define("kill_3_brutes", {
		"title": "Brute Force",
		"description": "Take down 3 Brutes.",
		"giver": "healer",
		"type": QuestData.ObjectiveType.KILL_TYPE,
		"enemy_type": Enemy.EnemyType.BRUTE,
		"count": 3,
		"gold": 140,
		"xp": 180.0,
	})
	_define("kill_25_enemies", {
		"title": "Dungeon Sweep",
		"description": "Slay 25 creatures of any kind.",
		"giver": "elder",
		"type": QuestData.ObjectiveType.KILL_ANY,
		"count": 25,
		"gold": 350,
		"xp": 500.0,
	})


func _define(quest_id: String, d: Dictionary) -> void:
	_definitions[quest_id] = d


## ─── QUEST LIFECYCLE ───

func get_available_quests(npc_id: String) -> Array[QuestData]:
	## Returns quests this NPC can offer that the player hasn't accepted or completed.
	var result: Array[QuestData] = []
	for qid in _definitions:
		var def: Dictionary = _definitions[qid]
		if def["giver"] != npc_id:
			continue
		if qid in quests:
			continue  # Already accepted or done
		var q := _make_quest(qid)
		result.append(q)
	return result


func get_turn_in_quests(npc_id: String) -> Array[QuestData]:
	## Returns quests this NPC can accept turn-in for (objective complete).
	var result: Array[QuestData] = []
	for qid in quests:
		var q: QuestData = quests[qid]
		if q.giver_npc_id != npc_id:
			continue
		if q.status == QuestData.QuestStatus.COMPLETED:
			result.append(q)
	return result


func get_active_quests() -> Array[QuestData]:
	var result: Array[QuestData] = []
	for qid in quests:
		var q: QuestData = quests[qid]
		if q.status == QuestData.QuestStatus.ACTIVE:
			result.append(q)
	return result


func accept_quest(quest_id: String) -> bool:
	if quest_id in quests:
		return false
	if quest_id not in _definitions:
		return false
	var q := _make_quest(quest_id)
	q.status = QuestData.QuestStatus.ACTIVE
	quests[quest_id] = q
	EventBus.quest_updated.emit()
	return true


func turn_in_quest(quest_id: String) -> Dictionary:
	## Returns reward dict { "gold": int, "xp": float } or empty if can't turn in.
	if quest_id not in quests:
		return {}
	var q: QuestData = quests[quest_id]
	if q.status != QuestData.QuestStatus.COMPLETED:
		return {}
	q.status = QuestData.QuestStatus.TURNED_IN
	EventBus.quest_updated.emit()
	return { "gold": q.reward_gold, "xp": q.reward_xp }


## ─── KILL TRACKING ───

func _on_enemy_killed(enemy_type: int) -> void:
	var changed := false
	for qid in quests:
		var q: QuestData = quests[qid]
		if q.status != QuestData.QuestStatus.ACTIVE:
			continue
		var matches := false
		if q.objective_type == QuestData.ObjectiveType.KILL_ANY:
			matches = true
		elif q.objective_type == QuestData.ObjectiveType.KILL_TYPE:
			matches = (q.target_enemy_type == enemy_type)
		if matches and q.current_count < q.target_count:
			q.current_count += 1
			changed = true
			if q.is_objective_complete():
				q.status = QuestData.QuestStatus.COMPLETED
	if changed:
		EventBus.quest_updated.emit()


## ─── SAVE / LOAD ───

func save_to_array() -> Array:
	var arr: Array = []
	for qid in quests:
		var q: QuestData = quests[qid]
		arr.append(q.to_dict())
	return arr


func load_from_array(arr: Array) -> void:
	quests.clear()
	for d in arr:
		var q := QuestData.from_dict(d)
		# Re-populate metadata from definitions
		if q.quest_id in _definitions:
			var def: Dictionary = _definitions[q.quest_id]
			q.title = def.get("title", q.quest_id)
			q.description = def.get("description", "")
			q.giver_npc_id = def.get("giver", "")
		quests[q.quest_id] = q
	EventBus.quest_updated.emit()


func reset() -> void:
	quests.clear()


## ─── HELPERS ───

func _make_quest(quest_id: String) -> QuestData:
	var def: Dictionary = _definitions[quest_id]
	var q := QuestData.new()
	q.quest_id = quest_id
	q.title = def.get("title", quest_id)
	q.description = def.get("description", "")
	q.giver_npc_id = def.get("giver", "")
	q.objective_type = def.get("type", QuestData.ObjectiveType.KILL_ANY) as QuestData.ObjectiveType
	q.target_enemy_type = def.get("enemy_type", -1)
	q.target_count = def.get("count", 1)
	q.reward_gold = def.get("gold", 0)
	q.reward_xp = def.get("xp", 0.0)
	q.status = QuestData.QuestStatus.AVAILABLE
	return q
