extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/FrameProbe.tscn
##   ... -- --only=frames|perfect|rounds   (one part)
##   ... -- --perfect=N                    (build N frames, not 100)
##
## FRAME (GameSettings.tower_is_frame, TowerFrame), checked in three parts:
##
##   frames  — TowerFrame.generate() over many deals: the same deal always
##             makes the same frame, every frame is inside the platform's
##             five columns, its cells are exactly its bricks' cells (none
##             overlapping), and how many frames have a hole — a window, a
##             cave no vertical drop could fill. Whether a frame *stands* is
##             not judged here but by building it, below: the grid's own
##             one-brick-at-a-time rule passed frames that fell apart.
##   perfect — the claim the whole mode rests on: every frame can actually be
##             built, under the real physics, with the bricks the tower deals.
##             A real tower is played by flying each brick to exactly where
##             the frame's own plan put it (aim_x and aim_steps, as a player
##             would on the half-cell lattice), checking each dealt brick is
##             the planned one, and the mark at the end should be 100%. A
##             frame that topples or slides when built right shows up here as
##             a fit under 100% or a dropped brick.
##   rounds  — whole FRAME rounds under TowerRace, solo at 2/3/4 and the team
##             version at 4, blind aim (spread 0.3, as TeamProbe) on every
##             tower but one, which plays perfectly: every tower stops after
##             exactly FRAME_BRICKS, nothing is decided until the last one is
##             in, the order is best fit first, and the perfect tower wins.
##
## It cannot see anything drawn — the outline, the fit bar, the HUD — and it
## sets aim directly rather than pressing keys.

const TOWER := preload("res://scenes/TowerMode.tscn")
const RACE := preload("res://scenes/TowerRace.tscn")
const TowerFrame := preload("res://scripts/TowerFrame.gd")

const FRAMES := 400
const FRAME_BRICKS := 10 # TowerMode.FRAME_BRICKS; TowerMode has no class_name to read it from
const PERFECT := 100
const SPREAD := 0.3
const TIMEOUT := 300.0

var _rng := RandomNumberGenerator.new()
var _perfect_count: int = PERFECT
var _failures: Array[String] = []

func _ready() -> void:
	GameSettings.tower_cup = GameSettings.TOWER_CUP_NONE
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
		elif arg.begins_with("--perfect="):
			_perfect_count = int(arg.substr(10))
	if only == "" or only == "frames":
		print("=== frames ===")
		_frames()
	if only == "" or only == "perfect":
		print("=== perfect ===")
		await _perfect()
	if only == "" or only == "rounds":
		print("=== rounds ===")
		await _round(2, GameSettings.TOWER_FRAME_SOLO, 11)
		await _round(3, GameSettings.TOWER_FRAME_SOLO, 22)
		await _round(4, GameSettings.TOWER_FRAME_SOLO, 33)
		await _round(4, GameSettings.TOWER_FRAME, 44)
	print("=== verdict ===")
	if _failures.is_empty():
		print("  OK — every frame is buildable and every round was decided on fit.")
	else:
		for f in _failures:
			print("  FAIL: " + f)
	get_tree().quit()

func _fail(what: String) -> void:
	_failures.append(what)
	print("  <-- " + what)

func _skins(count: int) -> void:
	GameSettings.player_count = count
	var cols: Array[Color] = []
	var skins: Array[Texture2D] = []
	for i in range(count):
		cols.append(GameSettings.PLAYER_SKINS[i]["color"])
		skins.append(GameSettings.PLAYER_SKINS[i]["texture"])
	GameSettings.skin_colors = cols
	GameSettings.skins = skins

# --- frames ---------------------------------------------------------------------

func _frames() -> void:
	var cols := 5
	var holed := 0
	var heights := {}
	var build_us := 0
	var build_sum := 0
	var sizes := 0
	for n in range(FRAMES):
		var seed_value: int = 1000 + n * 7919
		var t0: int = Time.get_ticks_usec()
		var a: Dictionary = TowerFrame.build(seed_value, FRAME_BRICKS, cols, 16.0)
		build_us = maxi(build_us, Time.get_ticks_usec() - t0)
		build_sum += Time.get_ticks_usec() - t0
		var b: Dictionary = TowerFrame.build(seed_value, FRAME_BRICKS, cols, 16.0)
		if a["cells"].keys() != b["cells"].keys() or str(a["plan"]) != str(b["plan"]):
			_fail("deal %d made two different frames" % seed_value)
		var want := 0
		for e: Dictionary in a["plan"]:
			want += TowerFrame.turned_cells(int(e["index"]), int(e["steps"])).size()
		if a["cells"].size() != want:
			_fail("deal %d: frame has %d cells, its bricks %d" % [seed_value, a["cells"].size(), want])
		var top := 0
		for k: Vector2i in a["cells"]:
			if k.x < 0 or k.x >= cols or k.y < 0:
				_fail("deal %d: cell %s is off the platform" % [seed_value, k])
			top = maxi(top, k.y + 1)
		heights[top] = heights.get(top, 0) + 1
		sizes += a["cells"].size()
		var has_hole := false
		for x in range(cols):
			var seen_above := false
			for y in range(top - 1, -1, -1):
				if a["cells"].has(Vector2i(x, y)):
					seen_above = true
				elif seen_above:
					has_hole = true
		if has_hole:
			holed += 1
	var hs: Array = heights.keys()
	hs.sort()
	var dist: Array[String] = []
	for h in hs:
		dist.append("%d:%d" % [h, heights[h]])
	print("  %d deals: %.1f cells a frame, heights %s" % [FRAMES, float(sizes) / float(FRAMES), " ".join(dist)])
	print("  frames with a hole        : %d   (a window in the frame — allowed, see TowerFrame)" % holed)
	print("  time to make one          : %.0f ms mean, %.0f ms worst (once a round — the towers share it)" % [
		float(build_sum) / float(FRAMES) / 1000.0, float(build_us) / 1000.0])
	var s1: Dictionary = TowerFrame.generate(4242, FRAME_BRICKS, cols, 16.0)
	if TowerFrame.generate(4242, FRAME_BRICKS, cols, 16.0) != s1:
		_fail("the memo handed back a different frame for the same deal")

# --- perfect ----------------------------------------------------------------------

func _perfect() -> void:
	_skins(1)
	GameSettings.tower_variant = GameSettings.TOWER_FRAME_SOLO
	var full := 0
	var worst := 1.0
	var sum := 0.0
	var dropped := 0
	for n in range(_perfect_count):
		var seed_value: int = 5000 + n * 104729
		var mode = TOWER.instantiate()
		mode.variant = GameSettings.TOWER_FRAME_SOLO
		mode.brick_seed = seed_value
		add_child(mode)
		var flown := 0
		var aimed = null
		var t := 0.0
		while mode.state != "gameover" and t < TIMEOUT:
			if mode.state == "piloting" and mode.active_piece != null and aimed != mode.active_piece:
				aimed = mode.active_piece
				_fly_plan(mode, flown, "deal %d" % seed_value)
				flown += 1
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		if mode.state != "gameover":
			_fail("deal %d: the frame round never ended" % seed_value)
		if mode.bricks_placed != mode.FRAME_BRICKS:
			_fail("deal %d: %d bricks placed, not %d" % [seed_value, mode.bricks_placed, mode.FRAME_BRICKS])
		var lost := 0
		for s in mode.bricks_dropped:
			lost += s
		dropped += lost
		var fit: float = mode.frame_score
		sum += fit
		worst = minf(worst, fit)
		if mode.frame_pct() == 100:
			full += 1
		else:
			print("    deal %d built to plan: %d%% fit, %d dropped" % [seed_value, mode.frame_pct(), lost])
		mode.queue_free()
		await get_tree().physics_frame
	print("  %d frames built to plan: %d at 100%%, mean %.1f%%, worst %.1f%%, %d bricks dropped" % [
		_perfect_count, full, sum / float(_perfect_count) * 100.0, worst * 100.0, dropped])
	if full < _perfect_count:
		_fail("%d of %d frames could not be built to 100%% by following their own plan" % [_perfect_count - full, _perfect_count])

# The brick the tower is flying now is plan entry `k`: check it is the brick
# the frame was made with, then put it where the frame put it.
func _fly_plan(mode, k: int, where: String) -> void:
	if k >= mode.frame_plan.size():
		_fail("%s: a brick dealt after the frame's last" % where)
		return
	var e: Dictionary = mode.frame_plan[k]
	if mode.active_piece.shape_index != int(e["index"]):
		_fail("%s brick %d: dealt %s, the frame was made with %s" % [
			where, k + 1, GameSettings.BRICKS[mode.active_piece.shape_index]["name"], GameSettings.BRICKS[int(e["index"])]["name"]])
	mode.aim_steps = int(e["steps"])
	mode.aim_x = TowerFrame.plan_aim_x(e, int(mode.PLATFORM_CELLS), mode.CELL)

func _aim_blind(mode) -> void:
	var piece = mode.active_piece
	mode.aim_steps = _rng.randi_range(0, 3)
	var limit: float = maxf(0.0,
		mode.PLATFORM_CELLS * mode.CELL * 0.5
		+ mode.AIM_BOUND_CELLS * mode.CELL
		- piece.aim_half_width(mode.aim_steps))
	# Snapped to the half-cell lattice, as the keyboard would be.
	var half: float = mode.CELL * 0.5
	mode.aim_x = round(_rng.randf_range(-limit, limit) * SPREAD / half) * half

# --- rounds -----------------------------------------------------------------------

func _round(count: int, variant: int, seed_value: int) -> void:
	seed(seed_value)
	_rng.seed = seed_value
	_skins(count)
	GameSettings.tower_variant = variant
	var race = RACE.instantiate()
	add_child(race)
	var label: String = "%s %dp (%d towers)" % [GameSettings.tower_variant_info(variant)["title"], count, race.towers.size()]
	var perfect: int = race.towers.size() - 1 # the last tower plays the plan
	var aimed := {}
	var flown := {}
	var early := false
	var t := 0.0
	while not race.over and t < TIMEOUT:
		for i in range(race.towers.size()):
			var tw = race.towers[i]
			if tw.state == "piloting" and tw.active_piece != null and aimed.get(tw) != tw.active_piece:
				aimed[tw] = tw.active_piece
				if i == perfect:
					_fly_plan(tw, flown.get(tw, 0), label)
				else:
					_aim_blind(tw)
				flown[tw] = flown.get(tw, 0) + 1
		if race.over:
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if race.over and race.done.has(false):
			early = true
	if not race.over:
		_fail("%s: no result after %.0fs" % [label, t])
		race.queue_free()
		return
	if early or race.done.has(false):
		_fail("%s: decided before every tower had finished (%s)" % [label, race.done])
	var fits: Array[int] = []
	for tw in race.towers:
		fits.append(tw.frame_pct())
		if tw.bricks_placed != tw.FRAME_BRICKS:
			_fail("%s: a tower placed %d bricks" % [label, tw.bricks_placed])
		if tw.state != "gameover":
			_fail("%s: a tower is still '%s' after the result" % [label, tw.state])
	var order: Array[int] = race.placements()
	for k in range(1, order.size()):
		if fits[order[k]] > fits[order[k - 1]]:
			_fail("%s: placed %s with fits %s" % [label, order, fits])
	var best: int = fits.max()
	if race.winner >= 0 and fits[race.winner] != best:
		_fail("%s: %d won at %d%%, best was %d%%" % [label, race.winner, fits[race.winner], best])
	if fits[perfect] != 100:
		_fail("%s: the tower built to plan fit %d%%" % [label, fits[perfect]])
	elif race.winner != perfect and fits.count(100) == 1:
		_fail("%s: the tower built to plan did not win" % label)
	print("  %-26s fits %s   order %s   places %s   winner %s   %.0fs" % [
		label, fits, order, race.placement_places(order), race._name_of(race.winner) if race.winner >= 0 else "draw", t])
	race.queue_free()
	await get_tree().physics_frame
