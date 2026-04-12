shader_type canvas_item;

// CRT / Palantir monitor effect — subtle scanlines + vignette + slight chromatic aberration
// Designed to be atmospheric, not distracting

uniform float scanline_intensity : hint_range(0.0, 0.3) = 0.06;
uniform float scanline_frequency : hint_range(200.0, 1200.0) = 600.0;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;
uniform float aberration_amount : hint_range(0.0, 3.0) = 0.4;
uniform float flicker_intensity : hint_range(0.0, 0.05) = 0.008;
uniform float noise_intensity : hint_range(0.0, 0.1) = 0.015;
uniform float curvature : hint_range(0.0, 0.1) = 0.0;  // 0 = flat, >0 = barrel distortion

// Simple hash for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Optional barrel distortion (CRT curvature)
	if (curvature > 0.0) {
		vec2 centered = uv * 2.0 - 1.0;
		float r2 = dot(centered, centered);
		centered *= 1.0 + curvature * r2;
		uv = centered * 0.5 + 0.5;
	}

	// Chromatic aberration
	float offset = aberration_amount / 1000.0;
	vec4 col;
	col.r = texture(SCREEN_TEXTURE, uv + vec2(offset, 0.0)).r;
	col.g = texture(SCREEN_TEXTURE, uv).g;
	col.b = texture(SCREEN_TEXTURE, uv - vec2(offset, 0.0)).b;
	col.a = 1.0;

	// Scanlines
	float scanline = sin(uv.y * scanline_frequency * 3.14159) * 0.5 + 0.5;
	scanline = pow(scanline, 1.5);
	col.rgb -= scanline_intensity * scanline;

	// Vignette
	vec2 vig_uv = uv * (1.0 - uv);
	float vig = vig_uv.x * vig_uv.y * 15.0;
	vig = pow(vig, vignette_softness);
	col.rgb *= mix(1.0 - vignette_intensity, 1.0, vig);

	// Subtle flicker
	float flicker = 1.0 - flicker_intensity * sin(TIME * 8.0) * sin(TIME * 13.0);
	col.rgb *= flicker;

	// Film grain / noise
	float noise = hash(uv * 1000.0 + vec2(TIME * 7.0, TIME * 3.0));
	col.rgb += (noise - 0.5) * noise_intensity;

	COLOR = col;
}
