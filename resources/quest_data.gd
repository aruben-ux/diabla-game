extends Resource
class_name QuestData

## Defines a quest with objectives and rewards.

enum QuestStatus { AVAILABLE, ACTIVE, COMPLETED, TURNED_IN }
enum ObjectiveType { KILL_ANY, KILL_TYPE }

var quest_id: String = ""
var title: String = ""
var description: String = ""
var giver_npc_id: String = ""       # NPC who gives and accepts turn-in

## Objective
var objective_type: ObjectiveType = ObjectiveType.KILL_ANY
var target_enemy_type: int = -1     # Enemy.EnemyType value, -1 = any
var target_count: int = 1
var current_count: int = 0

## Rewards
var reward_gold: int = 0
var reward_xp: float = 0.0

## State
var status: QuestStatus = QuestStatus.AVAILABLE


func is_objective_complete() -> bool:
	return current_count >= target_count


func to_dict() -> Dictionary:
	return {
		"quest_id": quest_id,
		"objective_type": objective_type,
		"target_enemy_type": target_enemy_type,
		"target_count": target_count,
		"current_count": current_count,
		"reward_gold": reward_gold,
		"reward_xp": reward_xp,
		"status": status,
	}


static func from_dict(d: Dictionary) -> QuestData:
	var q := QuestData.new()
	q.quest_id = d.get("quest_id", "")
	q.objective_type = d.get("objective_type", ObjectiveType.KILL_ANY) as ObjectiveType
	q.target_enemy_type = d.get("target_enemy_type", -1)
	q.target_count = d.get("target_count", 1)
	q.current_count = d.get("current_count", 0)
	q.reward_gold = d.get("reward_gold", 0)
	q.reward_xp = d.get("reward_xp", 0.0)
	q.status = d.get("status", QuestStatus.AVAILABLE) as QuestStatus
	# Title/description/giver are populated from the quest definitions
	return q
