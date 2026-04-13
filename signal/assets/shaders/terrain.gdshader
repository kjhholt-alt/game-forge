shader_type canvas_item;

// Procedural tactical terrain — dark satellite-style map background
// Multiple noise layers create terrain-like features (coastlines, elevation, roads)

uniform float scale : hint_range(0.5, 10.0) = 1.2;
uniform float detail : hint_range(1.0, 8.0) = 6.0;
uniform vec2 offset = vec2(0.0, 0.0);
uniform float zoom_level : hint_range(0.3, 3.0) = 1.0;

// Colors — dark military satellite palette
uniform vec4 color_deep : source_color = vec4(0.08, 0.09, 0.14, 1.0);     // Deep
uniform vec4 color_low : source_color = vec4(0.14, 0.16, 0.22, 1.0);     // Low
uniform vec4 color_mid : source_color = vec4(0.30, 0.34, 0.42, 1.0);     // Mid
uniform vec4 color_high : source_color = vec4(0.46, 0.50, 0.60, 1.0);    // High
uniform vec4 color_water : source_color = vec4(0.05, 0.07, 0.13, 1.0);   // Water — dark
uniform vec4 color_road : source_color = vec4(0.35, 0.38, 0.46, 1.0);    // Roads — bright lines

// Simplex-like noise
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
	               dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
	           mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
	               dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return value;
}

void fragment() {
	vec2 uv = (UV + offset / 1000.0) * scale / zoom_level;

	// Base terrain elevation — more dramatic with warping
	float warp = noise(uv * 0.7) * 0.3;
	float elevation = fbm(uv + vec2(warp), int(detail));
	elevation = elevation * 0.5 + 0.5;

	// Apply contrast curve — push mid values apart
	elevation = smoothstep(0.2, 0.8, elevation);

	// Water mask — bigger threshold = more water
	float water_threshold = 0.35;
	float is_water = smoothstep(water_threshold, water_threshold - 0.04, elevation);

	// Road network
	float road_noise = abs(noise(uv * 14.0));
	float is_road = smoothstep(0.015, 0.0, road_noise) * step(water_threshold, elevation);

	// Urban areas — more prominent clusters
	float urban = smoothstep(0.55, 0.65, elevation) * smoothstep(0.25, 0.0, abs(noise(uv * 6.0)));

	// Color mixing
	vec4 terrain_color;
	if (elevation < water_threshold) {
		terrain_color = color_water;
	} else if (elevation < 0.45) {
		terrain_color = mix(color_low, color_mid, (elevation - water_threshold) / 0.07);
	} else if (elevation < 0.6) {
		terrain_color = mix(color_mid, color_high, (elevation - 0.45) / 0.15);
	} else {
		terrain_color = color_high;
	}

	// Coastline edge — VERY VISIBLE bright border between water and land
	float coast_edge = abs(elevation - water_threshold);
	float is_coastline = smoothstep(0.05, 0.0, coast_edge) * step(water_threshold - 0.03, elevation);
	terrain_color.rgb += is_coastline * vec3(0.16, 0.18, 0.24);

	// Apply road overlay — thick and visible
	terrain_color = mix(terrain_color, color_road, is_road * 0.9);

	// Apply urban cluster brightening — VERY visible bright patches
	terrain_color.rgb += urban * 0.20;

	// Add subtle river/valley lines in low terrain
	float river = smoothstep(0.01, 0.0, abs(noise(uv * 15.0 + vec2(3.7, 1.2))));
	float is_river = river * (1.0 - step(water_threshold + 0.1, elevation));
	terrain_color = mix(terrain_color, color_water, is_river * 0.5);

	// Texture grain
	float grain = noise(uv * 40.0) * 0.012;
	terrain_color.rgb += grain;

	COLOR = terrain_color;
}
