class_name FollowCamera
extends Camera2D
## Chase camera that leads the target in its direction of travel and pulls back
## as it speeds up.

@export var target: Node2D
## How far ahead of the target the camera looks, in pixels at full speed.
@export var lead_distance := 260.0
## Speed (px/s) at which lead and zoom-out reach their maximum.
@export var reference_speed := 900.0
@export var zoom_near := 1.0
@export var zoom_far := 0.62
## Seconds for the lead offset and zoom to catch up. Larger is lazier.
@export var response_time := 0.45

var _lead := Vector2.ZERO
var _zoom_level := 1.0


func _ready() -> void:
	_zoom_level = zoom_near
	# Rotation stays locked so the horizon reads level even when the car flips.
	ignore_rotation = true


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var velocity := _target_velocity()
	var speed_ratio: float = clampf(velocity.length() / reference_speed, 0.0, 1.0)
	var wanted_lead := Vector2(signf(velocity.x) * lead_distance * speed_ratio, 0.0)
	var wanted_zoom: float = lerpf(zoom_near, zoom_far, speed_ratio)

	# Exponential smoothing, framerate independent.
	var weight: float = 1.0 - exp(-delta / maxf(response_time, 0.0001))
	_lead = _lead.lerp(wanted_lead, weight)
	_zoom_level = lerpf(_zoom_level, wanted_zoom, weight)

	global_position = target.global_position + _lead
	zoom = Vector2.ONE * _zoom_level


func _target_velocity() -> Vector2:
	if target is RigidBody2D:
		return (target as RigidBody2D).linear_velocity
	if target is Car:
		return (target as Car).chassis.linear_velocity
	return Vector2.ZERO
