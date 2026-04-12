## Juice — makes everything feel satisfying with tweens, shakes, and pulses.
##
## Autoloaded. Provides global functions for visual feedback.
## Call Juice.pop(node) to make a node bounce, Juice.shake() for screen shake, etc.
extends Node


## Pop a node (scale up then back) — for button clicks, item pickups
func pop(node: Control, intensity: float = 1.2, duration: float = 0.2) -> void:
	if not is_instance_valid(node):
		return
	var tween := node.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", Vector2(intensity, intensity), duration * 0.4)
	tween.tween_property(node, "scale", Vector2.ONE, duration * 0.6)


## Pulse a node's modulate color — for discovery, alerts
func pulse_color(node: Control, color: Color, duration: float = 0.5) -> void:
	if not is_instance_valid(node):
		return
	var original := node.modulate
	var tween := node.create_tween()
	tween.tween_property(node, "modulate", color, duration * 0.3)
	tween.tween_property(node, "modulate", original, duration * 0.7)


## Shake the screen — for exploit fails, detection spikes
func screen_shake(viewport: Viewport, intensity: float = 5.0, duration: float = 0.3) -> void:
	if not viewport:
		return
	var camera := viewport.get_camera_2d()
	if not camera:
		# Create temporary offset on the root
		return

	var original_offset := camera.offset
	var tween := camera.create_tween()
	var steps := int(duration / 0.03)
	for i in range(steps):
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
		) * (1.0 - float(i) / steps)  # Decay
		tween.tween_property(camera, "offset", original_offset + offset, 0.03)
	tween.tween_property(camera, "offset", original_offset, 0.05)


## Float a label up from a position — for XP gains, status changes
func float_text(parent: Control, text: String, pos: Vector2, color: Color = Color(0.2, 0.9, 0.4)) -> void:
	if not is_instance_valid(parent):
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.position = pos
	label.z_index = 100
	parent.add_child(label)

	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 40, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


## Glow border on a control — for correct connections, target acquired
func glow_border(node: Control, color: Color = Color(0.2, 0.9, 0.4), duration: float = 1.0) -> void:
	if not is_instance_valid(node):
		return
	var glow := ColorRect.new()
	glow.anchors_preset = Control.PRESET_FULL_RECT
	glow.color = Color(color.r, color.g, color.b, 0.15)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(glow)

	var tween := glow.create_tween()
	tween.tween_property(glow, "color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.tween_callback(glow.queue_free)
