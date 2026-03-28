extends Resource
class_name SkillData

## Defines a single player skill/ability.

enum TargetType { SELF, POINT, DIRECTION, AREA }

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_color: Color = Color.WHITE
@export var target_type: TargetType = TargetType.POINT
@export var cooldown: float = 3.0
@export var mana_cost: float = 10.0
@export var damage: float = 20.0
@export var radius: float = 3.0
@export var range_dist: float = 8.0
@export var duration: float = 0.0  # For buffs/DoTs
