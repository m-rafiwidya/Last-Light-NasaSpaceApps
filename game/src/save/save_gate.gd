class_name SaveGate

extends RefCounted

## Whether the game may be saved right now, and if not, why (the pause menu says it, SaveIndex obeys).
## Not while the player is out on EVA (a snapshot of the world with the suit's oxygen running and
## maybe Kite in their hands isn't a safe place to come back to), and not while Kite's claw holds
## or is lifting something (the held part isn't part of the saved loadout).
##
## Deliberately untyped (nodes found by group / name, called by duck typing): SaveIndex is loaded by
## the autoloads, so this file mustn't pull the level scripts into their compile.

const ON_EVA: String = "Return to the habitat to save"
const CLAW_HOLDING: String = "Release the claw to save"


## "" when saving is allowed, else the sentence that says what to do first
static func block_reason(tree: SceneTree = null) -> String:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	var eva: Node = tree.get_first_node_in_group(&"eva_rescue")
	if eva != null and eva.call(&"on_eva"):
		return ON_EVA
	var loader: Node = tree.root.get_node_or_null("SceneLoader")
	var scene: Node = loader.get("current_scene") if loader else null
	if scene:
		for robot in scene.find_children("*", "RigidBody3D", true, false):
			if claw_holds(robot):
				return CLAW_HOLDING
	return ""


## True while `robot`'s manual claw holds a part or its assisted pick is lifting one
static func claw_holds(robot: Node) -> bool:
	var claw: Node = robot.get_node_or_null("ManualClaw")
	var pick: Node = robot.get_node_or_null("ClawPick")
	return (claw != null and claw.get("held") != null) or (pick != null and pick.call(&"is_busy"))
