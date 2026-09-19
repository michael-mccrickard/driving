@tool
class_name BackdropPainter
extends Node2D
## Editor-visible drawing surface for a Backdrop's procedural scenery.

var backdrop: Backdrop

func _draw() -> void:
	if backdrop != null:
		backdrop._paint(self)
