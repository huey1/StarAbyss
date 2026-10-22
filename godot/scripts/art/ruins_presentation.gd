class_name RuinsPresentation
extends Node3D
## Visual dressing only. Static collisions and baked navigation remain authoritative.


func _ready() -> void:
	ToonPalette.apply_to(self, false)
