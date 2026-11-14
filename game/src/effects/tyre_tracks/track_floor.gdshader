shader_type spatial;
// The test level's floor (TrackFloor) with tyre tracks: the dev grid exactly as the
// StandardMaterial3D drew it (triplanar in the box's own space, blend sharpness 1, 1 m a tile),
// plus the tracks (tyre_tracks.gdshaderinc): darker where compacted (the level sets 0.3: 0.15 hardly
// shows on the dark grid), the prints through the normals.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

#include "res://src/effects/tyre_tracks/tyre_tracks.gdshaderinc"

varying vec3 triplanar_position;
varying vec3 triplanar_weights;
varying vec3 world_position;

void vertex() {
	vec3 weights = abs(NORMAL);
	triplanar_weights = weights / (weights.x + weights.y + weights.z);
	triplanar_position = VERTEX * vec3(1.0, -1.0, 1.0);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 t = triplanar_position;
	vec4 albedo = texture(albedo_texture, t.xy) * triplanar_weights.z
		+ texture(albedo_texture, t.xz) * triplanar_weights.y
		+ texture(albedo_texture, t.zy * vec2(-1.0, 1.0)) * triplanar_weights.x;
	vec2 p = world_position.xz;
	float footprint = sqrt(abs(determinant(mat2(dFdx(p), dFdy(p)))));
	vec4 tracks = tyre_tracks(p, footprint);
	ALBEDO = albedo.rgb * (1.0 - tracks_darkening * tracks.w);
	ROUGHNESS = 1.0;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Only the floor's top takes prints
	if (tracks.yz != vec2(0.0) && world_normal.y > 0.9) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(world_normal - vec3(tracks.y, 0.0, tracks.z)), 0.0)).xyz);
	}
}
