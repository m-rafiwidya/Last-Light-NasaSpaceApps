# Astronaut kit provenance

The astronaut is an original design. `tools/blender/scripts/astronaut/make_astronaut.py`
generates it in Blender 5.2 from the numbers in `tools/blender/ASTRONAUT_KIT.md`: geometry,
skeleton, weights, poses and exports. There are no borrowed, traced or AI-generated meshes, no
textures and no third-party assets.

The general style (a modern white suit with hard knee and shin armour, a chest control box, a
large backpack, a rounded helmet with a dark visor, chunky gloves and boots) was checked against a
private concept image by another artist. That image is not part of this repository and is not
distributed. No shapes, text, logos, patches, numbers or faces were taken from it.

| File | What | Generator |
|---|---|---|
| `astronaut.glb` | rigged T-pose (45 bones, Godot humanoid names), no animations | `make_astronaut.py` |
| `astronaut_seated.glb` | static, seated at the workshop console | `make_astronaut.py` |
| `astronaut_rack.glb` | static, the empty suit on its stand, with its helmet | `make_astronaut.py` |

The source is `tools/blender/parts/astronaut/astronaut.blend`. The Mixamo-ready mesh is
`tools/blender/parts/astronaut/astronaut_mixamo.fbx`. Scale, clearances and poses were reviewed
by the generator's own checks (its `ASTRONAUT_KIT ...` report lines).
