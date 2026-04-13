## CRT overlay — applies subtle scanline + vignette + chromatic aberration.
##
## Add as a child of the root scene. Uses a full-screen ColorRect with
## a shader that reads SCREEN_TEXTURE.
extends ColorRect


func _ready() -> void:
	# Full screen, always on top, doesn't block input
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0, 0, 0, 0)  # Transparent by default — shader overrides this

	var shader = load("res://assets/shaders/crt_effect.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("scanline_intensity", 0.015)
		mat.set_shader_parameter("scanline_frequency", 350.0)
		mat.set_shader_parameter("vignette_intensity", 0.05)
		mat.set_shader_parameter("vignette_softness", 0.7)
		mat.set_shader_parameter("aberration_amount", 0.15)
		mat.set_shader_parameter("flicker_intensity", 0.002)
		mat.set_shader_parameter("noise_intensity", 0.003)
		mat.set_shader_parameter("curvature", 0.0)  # Flat — set to 0.02 for subtle curve
		material = mat
