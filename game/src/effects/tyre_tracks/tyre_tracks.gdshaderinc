// Tyre tracks, for the shaders of the ground the rovers drive on (regolith.gdshader's play tier,
// track_floor.gdshader): TyreTracks binds the textures TrackMap draws (track_raster.gd describes
// them). Only materials TyreTracks binds draw tracks (tracks_enabled): rovers, rocks, the workshop
// and everything else never sample them, so nothing driving through a track gets it painted on.
//
// tyre_tracks(p, footprint) at world x, z = p: the ground's height change (m), its slope (per m of
// x and z) and how compacted it is (0..1). Up close from the fine tiles (the print's depth, grouser
// prints and berms, drawn through the normals), faded out where a texel is smaller than the pixel
// (footprint: the pixel's size on the ground, m); beyond that, and where no fine tile is held, the
// coarse map's coverage (the tracks as darker ground to the horizon).

uniform bool tracks_enabled = false;
uniform sampler2DArray tracks_fine : filter_linear, repeat_disable;
uniform sampler2DArray tracks_coarse : filter_linear_mipmap, repeat_disable;
uniform sampler2D tracks_pages : filter_nearest, repeat_disable;
// Area: x, z of its corner, its size (m)
uniform vec3 tracks_area = vec3(-64.0, -64.0, 128.0);
// Fine tiles: size (m), texels a side (with margins), texel (m), tiles a side; coarse the same
uniform vec4 tracks_fine_info = vec4(8.0, 512.0, 0.0157, 16.0);
uniform vec4 tracks_coarse_info = vec4(64.0, 258.0, 0.25, 2.0);
// Compacted regolith reads a little darker (the decor's apron tracks: 0.85)
uniform float tracks_darkening = 0.15;
// Steepest slope the prints draw (their walls and the steps where prints overlap are steeper than
// a texel can show; past this a wall turned from a low sun went black in jagged notches)
uniform float tracks_max_slope = 0.35;

const float TRACKS_MARGIN = 1.0;
const float TRACKS_HEIGHT_MIN = -0.032;
const float TRACKS_HEIGHT_MAX = 0.016;

vec4 tyre_tracks(vec2 p, float footprint) {
	vec4 result = vec4(0.0);
	if (!tracks_enabled) {
		return result;
	}
	vec2 rel = p - tracks_area.xy;
	if (any(lessThan(rel, vec2(0.0))) || any(greaterThanEqual(rel, vec2(tracks_area.z)))) {
		return result;
	}
	// Coarse coverage
	vec2 coarse_tile = floor(rel / tracks_coarse_info.x);
	float coarse_layer = coarse_tile.y * tracks_coarse_info.w + coarse_tile.x;
	vec2 coarse_uv = ((rel - coarse_tile * tracks_coarse_info.x) / tracks_coarse_info.z + TRACKS_MARGIN) / tracks_coarse_info.y;
	float compaction = texture(tracks_coarse, vec3(coarse_uv, coarse_layer)).r;
	// Fine detail, where the tile is held and its texels are larger than the pixel
	float texel = tracks_fine_info.z;
	float fine_weight = 1.0 - smoothstep(1.5 * texel, 3.0 * texel, footprint);
	if (fine_weight > 0.0) {
		vec2 tile = floor(rel / tracks_fine_info.x);
		float page = texelFetch(tracks_pages, ivec2(tile), 0).r * 255.0;
		if (page > 0.5) {
			float layer = floor(page + 0.5) - 1.0;
			float n = tracks_fine_info.y;
			vec2 uv = ((rel - tile * tracks_fine_info.x) / texel + TRACKS_MARGIN) / n;
			vec2 here = texture(tracks_fine, vec3(uv, layer)).rg;
			// The slope across two texels (central differences: the margin texel covers the edges)
			float east = texture(tracks_fine, vec3(uv + vec2(1.0 / n, 0.0), layer)).r;
			float west = texture(tracks_fine, vec3(uv - vec2(1.0 / n, 0.0), layer)).r;
			float south = texture(tracks_fine, vec3(uv + vec2(0.0, 1.0 / n), layer)).r;
			float north = texture(tracks_fine, vec3(uv - vec2(0.0, 1.0 / n), layer)).r;
			float scale = TRACKS_HEIGHT_MAX - TRACKS_HEIGHT_MIN;
			float height = TRACKS_HEIGHT_MIN + here.r * scale;
			vec2 slope = vec2(east - west, south - north) * scale / (2.0 * texel);
			float steepness = length(slope);
			if (steepness > tracks_max_slope) {
				slope *= tracks_max_slope / steepness;
			}
			result.xyz = vec3(height, slope) * fine_weight;
			compaction = mix(compaction, here.g, fine_weight);
		}
	}
	result.w = compaction;
	return result;
}
