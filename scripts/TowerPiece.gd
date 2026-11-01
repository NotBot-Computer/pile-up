extends RigidBody2D
class_name TowerPiece

## One brick in Pile Up — a tetromino or a
## pentomino, whichever GameSettings.BRICKS entry it was built from.
##
## This is a real `RigidBody2D` and nothing about it snaps to a grid — the
## whole mode is built on the bricks actually toppling, sliding and settling,
## so a brick's resting place is wherever the solver puts it. The only time
## its transform is written by hand is on the way down, while the active
## player is still steering it (`set_held(true)`), and even then the body is
## taken out of the collision world entirely so a descending brick can't
## shove the tower it is about to land on. TowerMode resolves its contacts
## by shape query instead — see that script's header.
##
## The art comes from GameSettings.BRICKS, whose sprites are normalised to
## exact square cells by scripts/dev/extract_blocks.py — so the collision
## boxes below, which are specified in cell units, line up with what is drawn
## without any per-piece correction. See that script's header for why the
## source sheets needed normalising.

const MASS_PER_CELL := 1.0
# Bricks are meant to grip: a tower that slides apart under its own weight is
# a physics bug to a player, not drama. Bounce stays at zero for the same
# reason — a brick that hops on landing shakes everything it lands on.
const FRICTION := 0.94
const BOUNCE := 0.0
# Deliberately light. Damping is not how a stack is meant to settle (that is
# what can_sleep is for); it is here only to take the ring out of a hard
# landing so a tower stops quivering in a second rather than five. Raising
# these makes the fall feel like it is happening in syrup — if settling is
# ever too slow, TowerMode's SETTLE_* thresholds are the knob, not these.
const LINEAR_DAMP := 0.15
const ANGULAR_DAMP := 0.6

# Terminal velocity.
#
# This used to be the mode's single most important number, back when a brick
# was released from a height and arrived under plain gravity at ~670px/s —
# fast enough that it demolished the tower rather than stacking on it, which
# TowerProbe caught by measuring careful drops losing bricks at the same rate
# as terrible ones. Landings are no longer that: a brick now descends under
# the player's control at DESCEND_SPEED and is handed to the physics engine
# at the instant it touches, with no velocity at all.
#
# So what this governs now is everything *after* a landing — bricks shoved
# off a collapsing tower, and the tower falling in on itself. Keeping it
# means a collapse reads as heavy but never ballistic. It is scaled to the
# cell size (about 6 cells per second), so it must be re-derived if CELL
# changes, or a collapse at a new scale will feel like a different game.
const MAX_FALL_SPEED := 225.0

# Held-brick tint: the owning player's colour, washed over the piece so you
# can tell whose shot is in the air on a shared tower where every landed
# brick looks the same. Fades out once it lands (see GLOW_FADE).
const GLOW_FADE := 2.6 # per second
const GLOW_FILL_ALPHA := 0.20
const GLOW_LINE_ALPHA := 0.85
const GLOW_LINE_WIDTH := 3.0

@onready var sprite: Sprite2D = $Sprite2D

var shape_index: int = 0
var cell: float = 46.0
var cols: int = 1
var rows: int = 1
var boxes: Array[Rect2] = [] # collision rects in cell units, from the piece's own top-left
var piece_color: Color = Color.WHITE
var owner_slot: int = -1
var owner_color: Color = Color.WHITE
var held: bool = true
# Set by TowerMode the moment this brick passes below the platform, which is
# the moment it is definitively off the tower. It keeps falling and stays on
# screen after that — it is only *counted* early, so the turn does not have
# to wait for debris to finish its journey. See TowerMode.LOST_Y.
var doomed: bool = false
var glow: float = 1.0
# 0 -> 1 over APPEAR_TIME from the moment it is dealt, so a new brick comes
# in rather than blinking into existence between two frames (session AM).
const APPEAR_TIME := 0.18
var appear: float = 0.0
# The CollisionShape2D children built in setup(). TowerMode queries these
# directly (see its _blocked()) to decide whether a move is legal, because a
# brick under the player's control is not in the collision world and so
# generates no contacts of its own.
var shapes: Array[CollisionShape2D] = []

# Query geometry for TowerMode, as plain resources plus their local
# transforms rather than as nodes. They are never part of the body and never
# enter the tree, so making them CollisionShape2Ds would orphan two Nodes and
# two shape RIDs per brick — which is exactly what the first version did, and
# Godot reported it as leaks at exit.
#
# `body_*` mirrors the real collision. `foot_shapes` are thin probes placed
# just under each box, used to ask the different question "is anything
# holding this brick up?" — refusing a move and landing a brick are not the
# same event, and treating them as one is what made a brick go limp the
# moment it brushed the flank of a taller stack. They are inset horizontally
# (FOOT_INSET) precisely so a wall pressed flat against the brick's side
# cannot register as support, and only a surface actually beneath it can.
#
# Note the feet carry no baked transform, unlike body_xforms. "Underneath" is
# a question about the *world*, not about the brick: a foot offset stored in
# the brick's own frame rotates with it, so a brick turned a half turn ends
# up probing the sky. (That is not hypothetical — it shipped that way, and
# three quarters of landings silently stopped detecting their own support.)
# TowerMode._supported() therefore sizes and places these against the world
# axes at query time; they are scratch resources, reused every call.
const FOOT_INSET := 6.0
const FOOT_DEPTH := 5.0
var body_shapes: Array[Shape2D] = []
var body_xforms: Array[Transform2D] = []
var foot_shapes: Array[RectangleShape2D] = []
# Scratch copies of the body boxes, shrunk by a contact tolerance at query
# time so that merely *touching* the tower is not the same as being inside
# it. They exist because every command in this mode lands on an exact
# half-cell lattice, which makes a zero-depth face-to-face contact with the
# stack the ordinary case rather than a freak one — see TowerMode.QUERY_SKIN.
# Reused every call, like foot_shapes, rather than allocated per query.
var query_shapes: Array[RectangleShape2D] = []

func setup(index: int, cell_size: float, slot: int, color: Color) -> void:
	var data: Dictionary = GameSettings.BRICKS[index]
	shape_index = index
	cell = cell_size
	cols = data["cols"]
	rows = data["rows"]
	piece_color = data["color"]
	owner_slot = slot
	owner_color = color

	boxes = []
	for b: Rect2 in data["boxes"]:
		boxes.append(b)

	var tex: Texture2D = data["texture"]
	sprite.texture = tex
	# Every sheet cell is exported square, so one uniform factor is correct
	# for both axes — no aspect correction belongs here.
	sprite.scale = Vector2.ONE * (float(cols) * cell / tex.get_width())

	shapes = []
	body_shapes = []
	body_xforms = []
	foot_shapes = []
	query_shapes = []
	var half := Vector2(float(cols), float(rows)) * cell * 0.5
	for b: Rect2 in boxes:
		var centre: Vector2 = (b.position + b.size * 0.5) * cell - half
		var rect := RectangleShape2D.new()
		rect.size = b.size * cell
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = centre
		add_child(cs)
		shapes.append(cs)
		body_shapes.append(rect)
		body_xforms.append(Transform2D(0.0, centre))

		# One foot per box rather than one for the whole brick, so an L or a
		# J is asked about the undersides it actually has. Sized at query
		# time — see the field comment.
		foot_shapes.append(RectangleShape2D.new())
		query_shapes.append(RectangleShape2D.new())

	var mat := PhysicsMaterial.new()
	mat.friction = FRICTION
	mat.bounce = BOUNCE
	mat.rough = true
	physics_material_override = mat

	mass = cell_count() * MASS_PER_CELL
	linear_damp = LINEAR_DAMP
	angular_damp = ANGULAR_DAMP
	# A brick shrugged off a collapsing tower can cover a lot of ground in
	# one physics frame. Shape casting is the only setting that reliably
	# stops it stepping straight past a thin resting brick, and a tunnelled
	# brick does not read as a physics quirk — it reads as the tower being
	# cheated. (A brick's *own* descent never needs this: it is stepped by
	# TowerMode a pixel at a time with a shape query per step.)
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	can_sleep = true
	set_held(true)
	modulate.a = 0.0

func cell_count() -> int:
	var n := 0.0
	for b: Rect2 in boxes:
		n += b.size.x * b.size.y
	return int(round(n))

# While held the brick is both frozen *and* out of the collision world. The
# freeze alone is not enough: a frozen body is still solid, so writing its
# transform each frame (which is what steering does) would bulldoze the top
# of the tower. Being out of the world is also what lets TowerMode step the
# brick in exact half cells — it can put it anywhere a shape query says is
# empty, with no solver in the way.
func set_held(value: bool) -> void:
	held = value
	if value:
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true
		collision_layer = 0
		collision_mask = 0
	else:
		freeze = false
		collision_layer = 1
		collision_mask = 1

# Hand the brick to the physics engine, exactly where the player left it and
# at rest. There is deliberately no launch velocity: TowerMode only calls
# this at the instant a downward move was refused, so the brick is already
# touching whatever it landed on, and any initial speed would be momentum it
# never actually had.
func release() -> void:
	set_held(false)
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	sleeping = false

# Half the brick's width at a 90°-step rotation, used to clamp aiming so a
# brick can always still be lined up with at least part of the platform. Only
# valid for right-angle steps, which is all aiming ever uses — once released
# the body rotates freely and nothing asks this again.
func aim_half_width(steps: int) -> float:
	var horizontal: bool = (steps % 2) == 0
	return (float(cols) if horizontal else float(rows)) * cell * 0.5

func _box_corners(b: Rect2) -> Array[Vector2]:
	var half := Vector2(float(cols), float(rows)) * cell * 0.5
	var p := b.position * cell - half
	var s := b.size * cell
	return [p, p + Vector2(s.x, 0.0), p + s, p + Vector2(0.0, s.y)]

# The brick's own outline, as one closed loop per collision box, placed at an
# arbitrary transform. Used to draw the dash afterimage — the ghost has to be
# the brick's real silhouette rather than a bounding box, or an L or an S
# leaves a trail the wrong shape behind it.
func box_outlines(xform: Transform2D) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for b: Rect2 in boxes:
		var corners: Array[Vector2] = _box_corners(b)
		var pts := PackedVector2Array()
		for c: Vector2 in corners:
			pts.append(xform * c)
		pts.append(xform * corners[0])
		out.append(pts)
	return out

# The brick's highest point in world space. TowerMode sums these into the
# stack height that drives the camera and the next spawn, so it has to be the
# real rotated silhouette — a leaning brick's corner is genuinely higher than
# its own origin, and using the origin made the camera lag behind the tower.
func top_y() -> float:
	var xf := global_transform
	var best := INF
	for b: Rect2 in boxes:
		for c: Vector2 in _box_corners(b):
			best = min(best, (xf * c).y)
	return best

# Applied in the physics step rather than by setting linear_velocity from
# _process: this is the only place the value can be clamped after the solver
# has integrated gravity but before it is used, so the brick never spends a
# frame moving faster than the cap.
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if held:
		return
	if state.linear_velocity.y > MAX_FALL_SPEED:
		state.linear_velocity.y = MAX_FALL_SPEED

func _process(delta: float) -> void:
	if appear < 1.0:
		appear = minf(1.0, appear + delta / APPEAR_TIME)
		modulate.a = appear * appear * (3.0 - 2.0 * appear)
	if held:
		return
	if glow > 0.0:
		glow = max(0.0, glow - delta * GLOW_FADE)
		queue_redraw()

func _draw() -> void:
	if glow <= 0.0:
		return
	var fill := Color(owner_color.r, owner_color.g, owner_color.b, GLOW_FILL_ALPHA * glow)
	var line := Color(owner_color.r, owner_color.g, owner_color.b, GLOW_LINE_ALPHA * glow)
	var half := Vector2(float(cols), float(rows)) * cell * 0.5
	for b: Rect2 in boxes:
		var r := Rect2(b.position * cell - half, b.size * cell)
		draw_rect(r, fill, true)
		draw_rect(r, line, false, GLOW_LINE_WIDTH)
