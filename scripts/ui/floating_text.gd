extends Control

## Floating damage/text numbers that rise and fade out.

@onready var label: Label = $Label

var rise_speed := 60.0
var fade_speed := 2.0
var lifetime := 1.0
var timer := 0.0


func setup(text: String, color: Color = Color.WHITE) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)


func _process(delta: float) -> void:
	timer += delta
	position.y -= rise_speed * delta
	modulate.a = lerpf(1.0, 0.0, timer / lifetime)
	if timer >= lifetime:
		queue_free()
