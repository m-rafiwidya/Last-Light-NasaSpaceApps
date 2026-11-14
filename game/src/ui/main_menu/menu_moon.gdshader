// The main menu's Moon: the LROC colour map on a sphere, lit by a fixed light in view space
// (upper left, towards the viewer) so the light stays put while the Moon turns. Unshaded: the
// lighting is computed here, no light nodes needed.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Direction towards the light in view space (x right, y up, z towards the camera); the design's
uniform vec3 light_dir = vec3(-0.5, 0.42, 0.76);
uniform float ambient = 0.1;
// How far past the terminator the light wraps (0 = hard Lambert edge)
uniform float terminator_softness = 0.15;
uniform float brightness = 1.0;

varying vec3 local_dir;

void vertex() {
	local_dir = VERTEX;
}

void fragment() {
	// Texture coordinates from the object-space direction: longitude 0 (the near side's centre)
	// at +Z, east towards +X, north up. Equirectangular map, u = 0.5 at longitude 0.
	vec3 d = normalize(local_dir);
	float lon = atan(d.x, d.z);
	float lat = asin(clamp(d.y, -1.0, 1.0));
	vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	// The longitude wraps at 180 degrees; pick the derivative of a copy that wraps at 0 there,
	// so the mip level doesn't jump and draw a seam line (Tarini's trick)
	float u_alt = fract(lon / TAU);
	vec2 ddx = dFdx(uv);
	vec2 ddy = dFdy(uv);
	float alt_dx = dFdx(u_alt);
	float alt_dy = dFdy(u_alt);
	if (abs(alt_dx) + abs(alt_dy) < abs(ddx.x) + abs(ddy.x)) {
		ddx.x = alt_dx;
		ddy.x = alt_dy;
	}
	vec3 albedo = textureGrad(albedo_map, uv, ddx, ddy).rgb;

	float n_dot_l = dot(normalize(NORMAL), normalize(light_dir));
	float lit = max((n_dot_l + terminator_softness) / (1.0 + terminator_softness), 0.0);
	ALBEDO = albedo * (ambient + lit) * brightness;
}
