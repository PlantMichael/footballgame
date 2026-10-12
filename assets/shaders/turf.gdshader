shader_type canvas_item;

// Menu backdrop: a mowed football field. Alternating light/dark mow stripes,
// broad patchy clumps, a fine grain of grass blades, and chalk yard lines on
// every other stripe boundary. All procedural - no texture to load - and
// measured in the Control's own canvas units (not screen pixels), so it
// looks the same at any window size. See UIKit.background.

uniform vec4 base_color : source_color = vec4(0.141, 0.333, 0.184, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.169, 0.384, 0.216, 1.0);
uniform vec4 chalk_color : source_color = vec4(0.91, 0.94, 0.92, 1.0);
// Height of one mow stripe; a yard line sits every two of them.
uniform float stripe_px = 90.0;
uniform float line_alpha = 0.32;
// Overall darkening, so menu text and panels on top stay readable.
uniform float shade = 0.72;
// Stadium night: floodlight glow pooling down from the two top corners, and
// a vignette darkening the edges. Both 0 (off) except on the title screen.
uniform float floodlight = 0.0;
uniform float vignette = 0.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// Dave Hoskins' hash12 - no sin(), so it holds up at the lower float
// precision of the web build.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = local;
	float band = mod(floor(p.y / stripe_px), 2.0);
	vec3 col = mix(base_color.rgb, stripe_color.rgb, band);

	// Broad patches where the grass grows a little lighter or darker.
	float clumps = noise(p / 140.0) * 0.6 + noise(p / 47.0) * 0.4;
	col *= 0.88 + 0.24 * clumps;

	// Blades: noise stretched tall, so it reads as grass rather than static.
	float blades = noise(vec2(p.x / 1.7, p.y / 5.5));
	col *= 0.84 + 0.32 * blades;

	// Chalk yard lines, worn in places where the blades poke through.
	float yard = stripe_px * 2.0;
	float d = abs(mod(p.y + yard * 0.5, yard) - yard * 0.5);
	float line = 1.0 - smoothstep(1.0, 2.6, d);
	col = mix(col, chalk_color.rgb, line * line_alpha * (0.7 + 0.3 * blades));

	col *= shade;

	if (floodlight > 0.0) {
		vec3 warm = vec3(1.0, 0.96, 0.82);
		float glow = exp(-distance(UV, vec2(0.12, -0.06)) * 2.6) + exp(-distance(UV, vec2(0.88, -0.06)) * 2.6);
		col += warm * glow * 0.42 * floodlight;
	}
	if (vignette > 0.0) {
		float vd = distance(UV, vec2(0.5, 0.45));
		col *= 1.0 - vignette * smoothstep(0.3, 0.85, vd);
	}

	COLOR = vec4(col, 1.0);
}
