extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/DeadlineProbe.tscn
##   ... -- --only=line|rules|rounds   (one part)
##
## DEADLINE (GameSettings.tower_is_deadline, TowerMode.DEADLINE_*), checked
## in three parts:
##
##   line   — the line on its own: where it is over time, that it only ever
##            climbs and only ever climbs faster, and when it reaches the
##            platform's top and the heights a tower needs.
##   rules  — the rule, with towers made to do exactly one thing. Towers
##            stalled at GO (their brick taken away, so nothing is ever
##            built) go under the line together and must go out together, on
##            the same physics frame, DEADLINE_GRACE after the line passed the
##            platform — a dead heat, both 1st. A tower pulled back over the
##            line part way through its grace must start the count again. And
##            with one tower stalled and two building, the stalled one goes
##            first and the race runs on without it.
##   rounds — whole rounds under TowerRace with blind aim (spread 0.3, as
##            TeamProbe, and 0.1, a player who is trying), solo at 2/3/4 and
##            the team version at 3 and 4. Every frame: every line still in
##            play is at the same height, and climbing; no tower goes out
##            unless this probe saw its top under the line for the whole grace
##            first. At the end: one result, every tower halted, the order the
##            last one standing and then the rest last-out-first, and a shared
##            place only for towers that went out on the same frame. It
##            prints how long towers last and how high they were — the numbers
##            DEADLINE_SPEED and DEADLINE_ACCEL were set against.
##
## Blind aim is a floor on what people manage (TowerProbe's header): it says
## the line is beatable for a while and then is not, and nothing about how a
## round feels. It cannot see anything drawn — the line, the wash, the bar,
## the warning — and it never presses a key or casts a skill.

const RACE := preload("res://scenes/TowerRace.tscn")
const TOWER := preload("res://scenes/TowerMode.tscn")

const TIMEOUT := 400.0
const SEEDS := 4

var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []

func _ready() -> void:
	GameSettings.tower_cup = GameSettings.TOWER_CUP_NONE
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	if only == "" or only == "line":
		print("=== line ===")
		_line()
	if only == "" or only == "rules":
		print("=== rules ===")
		await _stalled_tie()
		await _grace_resets()
		await _one_stalled()
	if only == "" or only == "rounds":
		print("=== rounds ===")
		for policy: String in ["blind 0.3", "blind 0.1", "flat 0.1"]:
			var spread: float = float(policy.split(" ")[1])
			var flat: bool = policy.begins_with("flat")
			var lasted: Array[float] = []
			var heights: Array[float] = []
			var lengths: Array[float] = []
			for count in [2, 3, 4]:
				for k in range(SEEDS):
					await _round(count, GameSettings.TOWER_DEADLINE_SOLO, spread, flat, 1000 * count + 17 * k, lasted, heights, lengths)
			for count in [3, 4]:
				await _round(count, GameSettings.TOWER_DEADLINE, spread, flat, 5000 + 100 * count, lasted, heights, lengths)
			print("  %s: a tower lasts %s s (out at %s cells), a round %s s" % [
				policy, _spread_of(lasted), _spread_of(heights), _spread_of(lengths)])
	print("=== verdict ===")
	if _failures.is_empty():
		print("  OK — the line only climbs, takes a tower only after the grace, and every round had one result.")
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

# min / mean / max, for a line of the summary.
func _spread_of(xs: Array[float]) -> String:
	if xs.is_empty():
		return "-"
	var sum := 0.0
	for x in xs:
		sum += x
	return "%.1f / %.1f / %.1f" % [xs.min(), sum / float(xs.size()), xs.max()]

# `flat` lays every brick on its long side, the one thing a person stacking
# against a clock does that random turns do not — still a guess at people, but
# a less pessimistic one.
func _aim(mode, spread: float, flat := false) -> void:
	var piece = mode.active_piece
	if piece == null:
		return
	mode.aim_steps = _rng.randi_range(0, 3)
	if flat and (piece.cols >= piece.rows) != (mode.aim_steps % 2 == 0):
		mode.aim_steps = (mode.aim_steps + 1) % 4
	var limit: float = maxf(0.0,
		mode.PLATFORM_CELLS * mode.CELL * 0.5
		+ mode.AIM_BOUND_CELLS * mode.CELL
		- piece.aim_half_width(mode.aim_steps))
	# Snapped to the half-cell lattice, as the keyboard would be.
	var half: float = mode.CELL * 0.5
	mode.aim_x = round(_rng.randf_range(-limit, limit) * spread / half) * half

# Takes the brick in the air away and leaves the tower waiting for it, for
# ever: piloting with nothing to pilot. The line does not wait.
func _stall(mode) -> void:
	var p = mode.active_piece
	if p == null:
		return
	mode.pieces.remove_child(p)
	p.queue_free()
	mode.active_piece = null

func _new_race(count: int, variant: int, seed_value: int):
	seed(seed_value)
	_rng.seed = seed_value
	_skins(count)
	GameSettings.tower_variant = variant
	var race = RACE.instantiate()
	add_child(race)
	return race

# When the line is first at `cells`, solved from TowerMode's own formula.
func _when_at(mode, cells: float) -> float:
	var a: float = 0.5 * mode.DEADLINE_ACCEL
	var b: float = mode.DEADLINE_SPEED
	var c: float = mode.DEADLINE_START_CELLS - cells
	return (-b + sqrt(b * b - 4.0 * a * c)) / (2.0 * a)

# --- line -----------------------------------------------------------------------

func _line() -> void:
	_skins(2)
	GameSettings.tower_variant = GameSettings.TOWER_DEADLINE_SOLO
	var mode = TOWER.instantiate()
	add_child(mode)
	var dt := 1.0 / 240.0
	var last: float = mode._deadline_at(0.0)
	var last_step := -1.0
	var t := 0.0
	while t < 120.0:
		t += dt
		var y: float = mode._deadline_at(t)
		var step: float = y - last
		if step <= 0.0 or step < last_step - 1e-9:
			_fail("line: at %.2fs it moved %.6f cells after %.6f — it must climb, and faster" % [t, step, last_step])
			break
		last = y
		last_step = step
	var at := []
	for s in [0, 10, 20, 30, 40, 50, 60, 75, 90]:
		at.append("%ds %.1f" % [s, mode._deadline_at(float(s))])
	print("  the line, cells over the platform: " + "   ".join(at))
	var speeds := []
	for s in [0, 15, 30, 45, 60]:
		speeds.append("%ds %.2f" % [s, mode.DEADLINE_SPEED + mode.DEADLINE_ACCEL * float(s)])
	print("  its speed, cells/s: " + "   ".join(speeds))
	var when := []
	for h in [0, 5, 10, 15, 20, 25, 30]:
		when.append("%d at %.1fs" % [h, _when_at(mode, float(h))])
	print("  it reaches: " + "   ".join(when))
	if absf(mode._deadline_at(mode.deadline_time) - mode.deadline_cells) > 1e-6:
		_fail("line: a fresh tower's line is at %.3f, not where the formula starts it" % mode.deadline_cells)
	mode.queue_free()

# --- rules ----------------------------------------------------------------------

# Two towers that never build: the line takes both on one frame, GRACE after it
# passes the platform's top, and nobody won.
func _stalled_tie() -> void:
	var race = _new_race(2, GameSettings.TOWER_DEADLINE_SOLO, 31)
	var t := 0.0
	while not race.over and t < TIMEOUT:
		for tw in race.towers:
			if tw.state == "piloting" and tw.active_piece != null:
				_stall(tw)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var label := "two stalled towers"
	if not race.over:
		_fail("%s: no result after %.0fs" % [label, t])
		race.queue_free()
		return
	var a = race.towers[0]
	var b = race.towers[1]
	var want: float = _when_at(a, 0.0) + a.DEADLINE_GRACE
	var frame_s: float = 1.0 / float(Engine.physics_ticks_per_second)
	for tw in race.towers:
		if absf(tw.deadline_out_at - want) > 2.0 * frame_s:
			_fail("%s: out after %.3fs of play, expected %.3f (line at the platform, plus the grace)" % [label, tw.deadline_out_at, want])
	if race.out_frame[0] != race.out_frame[1]:
		_fail("%s: out on frames %s, expected the same frame" % [label, race.out_frame])
	if race.winner != -1:
		_fail("%s: %s won a dead heat" % [label, race._name_of(race.winner)])
	var order: Array[int] = race.placements()
	var places: Array[int] = race.placement_places(order)
	if places != [0, 0]:
		_fail("%s: placed %s, expected both 1st" % [label, places])
	print("  %-34s out at %.3fs and %.3fs (expected %.3f), frames %s, %s, places %s" % [
		label, a.deadline_out_at, b.deadline_out_at, want, race.out_frame,
		race.overlay_title.text, places])
	race.queue_free()
	await get_tree().physics_frame

# One stalled tower, pulled back over the line half way through its grace:
# the count must start again, and the line take it a full grace after it is
# under again — not at the first count's end. The other tower builds with its
# own line held at the ground, so it cannot be the one to go first.
func _grace_resets() -> void:
	var race = _new_race(2, GameSettings.TOWER_DEADLINE_SOLO, 32)
	var tw = race.towers[0]
	var label := "pulled back over the line"
	var pulled := false
	var first_under_at := -1.0
	var t := 0.0
	while not race.over and t < TIMEOUT:
		race.towers[1].deadline_time = 0.0
		for k in range(race.towers.size()):
			var m = race.towers[k]
			if m.state == "piloting" and m.active_piece != null:
				if k == 0:
					_stall(m)
				else:
					_aim(m, 0.1)
		if not pulled and tw.under_time >= tw.DEADLINE_GRACE * 0.5:
			first_under_at = tw.deadline_time - tw.under_time
			# Back to GO!: the line drops under the platform again, so the
			# empty tower is over it on the very next frame.
			tw.deadline_time = 0.0
			pulled = true
		elif pulled and tw.deadline_time < 1.0 and tw.under_time > 0.0:
			_fail("%s: still counting %.2fs under after the line went back down" % [label, tw.under_time])
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if not race.over or not race.dropped_out[0]:
		_fail("%s: the stalled tower never went out" % label)
	else:
		var want: float = _when_at(tw, 0.0) + tw.DEADLINE_GRACE
		if absf(tw.deadline_out_at - want) > 2.0 / float(Engine.physics_ticks_per_second):
			_fail("%s: out %.3fs into its second line, expected %.3f" % [label, tw.deadline_out_at, want])
		if race.winner != 1:
			_fail("%s: %s won, expected the tower still building" % [label, race._name_of(race.winner)])
		print("  %-34s first under at %.2fs, pulled back at %.1fs under, out %.3fs into the second line (expected %.3f)" % [
			label, first_under_at, tw.DEADLINE_GRACE * 0.5, tw.deadline_out_at, want])
	race.queue_free()
	await get_tree().physics_frame

# Three towers, the last one stalled: it is out first, alone, on time, and the
# two that are building race on until one of them goes under.
func _one_stalled() -> void:
	var race = _new_race(3, GameSettings.TOWER_DEADLINE_SOLO, 33)
	var label := "three towers, P3 stalled"
	var first_out := -1
	var t := 0.0
	while not race.over and t < TIMEOUT:
		for k in range(race.towers.size()):
			var m = race.towers[k]
			if m.state == "piloting" and m.active_piece != null:
				if k == 2:
					_stall(m)
				else:
					_aim(m, 0.1)
		if first_out < 0:
			for k in range(race.towers.size()):
				if race.dropped_out[k]:
					first_out = k
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if not race.over:
		_fail("%s: no result after %.0fs" % [label, t])
		race.queue_free()
		return
	var p3 = race.towers[2]
	var want: float = _when_at(p3, 0.0) + p3.DEADLINE_GRACE
	if first_out != 2:
		_fail("%s: %s went out first" % [label, race._name_of(first_out)])
	if absf(p3.deadline_out_at - want) > 2.0 / float(Engine.physics_ticks_per_second):
		_fail("%s: P3 out at %.3fs, expected %.3f" % [label, p3.deadline_out_at, want])
	var order: Array[int] = race.placements()
	if order.back() != 2:
		_fail("%s: placed %s, P3 should be last" % [label, order])
	if race.winner < 0 or race.winner == 2:
		_fail("%s: won by %d" % [label, race.winner])
	print("  %-34s P3 out at %.3fs (expected %.3f), then the rest raced to %.1fs: %s, order %s" % [
		label, p3.deadline_out_at, want, t, race.overlay_title.text, order])
	race.queue_free()
	await get_tree().physics_frame

# --- rounds -----------------------------------------------------------------------

func _round(count: int, variant: int, spread: float, flat: bool, seed_value: int,
		lasted: Array[float], heights: Array[float], lengths: Array[float]) -> void:
	var race = _new_race(count, variant, seed_value)
	var n: int = race.towers.size()
	var label: String = "%s %dp %s %.1f #%d" % [GameSettings.tower_variant_info(variant)["title"], count,
		"flat" if flat else "blind", spread, seed_value]
	var aimed := {}
	var streak: Array[float] = []
	var last_line: Array[float] = []
	var seen_out: Array[int] = [] # per tower: the probe's frame count when it was first seen out
	for _i in range(n):
		streak.append(0.0)
		last_line.append(-INF)
		seen_out.append(-1)
	var frames := 0
	var t := 0.0
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	while not race.over and t < TIMEOUT:
		for tw in race.towers:
			if tw.state == "piloting" and tw.active_piece != null and aimed.get(tw) != tw.active_piece:
				aimed[tw] = tw.active_piece
				_aim(tw, spread, flat)
		await get_tree().physics_frame
		frames += 1
		t += dt
		# Every line still in play at one height, climbing.
		var lo := INF
		var hi := -INF
		for i in range(n):
			var tw = race.towers[i]
			if race.dropped_out[i]:
				if seen_out[i] < 0:
					seen_out[i] = frames
					# The grace, as this probe watched it: the top under the
					# line for all of it, up to the frame the tower went out.
					if streak[i] < tw.DEADLINE_GRACE - 2.0 * dt:
						_fail("%s: %s out after %.3fs under the line" % [label, race._name_of(i), streak[i]])
					lasted.append(tw.deadline_out_at)
					heights.append(tw.deadline_top)
				continue
			if tw.state == "countdown":
				continue
			lo = minf(lo, tw.deadline_cells)
			hi = maxf(hi, tw.deadline_cells)
			if tw.deadline_cells < last_line[i]:
				_fail("%s: %s's line went down, %.3f -> %.3f" % [label, race._name_of(i), last_line[i], tw.deadline_cells])
			last_line[i] = tw.deadline_cells
			streak[i] = streak[i] + dt if tw.deadline_top < tw.deadline_cells else 0.0
		if hi > lo + 1e-6:
			_fail("%s: lines out of step, %.4f to %.4f" % [label, lo, hi])
			break
	if not race.over:
		_fail("%s: no result after %.0fs" % [label, t])
		race.queue_free()
		return
	for tw in race.towers:
		if tw.state != "gameover":
			_fail("%s: a tower is still '%s' after the result" % [label, tw.state])
	var order: Array[int] = race.placements()
	var places: Array[int] = race.placement_places(order)
	# The order this probe watched: whoever was never seen out, then the rest
	# by when they were seen out, last first, the same frame a shared place.
	var watched: Array[int] = []
	for i in range(n):
		if seen_out[i] < 0:
			watched.append(i)
	var outs: Array[int] = []
	for i in range(n):
		if seen_out[i] >= 0:
			outs.append(i)
	outs.sort_custom(func(a: int, b: int) -> bool:
		return seen_out[a] > seen_out[b] or (seen_out[a] == seen_out[b] and race.out_order.find(a) > race.out_order.find(b)))
	if race.winner >= 0 and watched.is_empty():
		watched.append(race.winner) # lasted longest, alone on the last frame
		outs.erase(race.winner)
	watched.append_array(outs)
	if order != watched:
		_fail("%s: placed %s, watched %s" % [label, order, watched])
	for k in range(1, order.size()):
		var same_frame: bool = race.out_frame[order[k]] >= 0 and race.out_frame[order[k]] == race.out_frame[order[k - 1]]
		if (places[k] == places[k - 1]) != (same_frame and order[k - 1] != race.winner):
			_fail("%s: places %s for order %s, out frames %s" % [label, places, order, race.out_frame])
			break
	if race.winner >= 0:
		lasted.append(race.towers[race.winner].deadline_time)
	lengths.append(race.towers[0].deadline_time if race.winner < 0 else race.towers[race.winner].deadline_time)
	var outs_at: Array[String] = []
	for i in range(n):
		var tw = race.towers[i]
		outs_at.append("%s %s" % [race._name_of(i).replace(" TEAM", ""),
			"%.0fs@%.0f" % [tw.deadline_out_at, tw.deadline_top] if tw.deadline_out_at >= 0.0 else "won@%.0f" % tw.deadline_top])
	print("  %-34s %-46s %-24s places %s" % [label, "  ".join(outs_at), race.overlay_title.text, places])
	race.queue_free()
	await get_tree().physics_frame
