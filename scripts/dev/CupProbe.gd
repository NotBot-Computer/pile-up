extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/CupProbe.tscn
##
## Pile Up's cups (GameSettings.tower_cup), checked by playing them: whole
## cups, round after round, every round a real match with blind aim (spread
## 0.3, as TeamProbe), until somebody wins. Two parts:
##
##   sums   — the arithmetic on its own: which variants a cup cycles through
##            at each count (co-pilot only with four), 3/2/1/0 by place, tied
##            places sharing an award and skipping the next (1st, 1st, 3rd), a
##            result missing somebody still paying every place, the champion
##            rule when two cross the target in one round, and whose car each
##            trophy is — the round winner's, a winning team's alternating.
##   cups   — the solo cup at 2, 3 and 4 and the team cup at 3 and 4. Per
##            round: the variant is the next in the rotation, the match pays
##            out exactly once, every competitor is placed exactly once, and
##            the order is the one this probe *watched* happen — the winner
##            first, then (one tower) whoever ran out of lives last, or (a
##            race) whoever was still building, tallest first, then the
##            drop-outs, last out highest; or (frame) best fit first, an
##            equal fit an equal place; or (deadline) the last one left, then
##            the rest last-out-first, towers seen going out on the same frame
##            sharing a place; or (co-op, a round of the solo cup)
##            fewest bricks dropped first, counted here turn by turn, with an
##            equal count an equal place. Every trophy a round hands out, to
##            every row, is a car of that round's winner. The tally screen is instantiated
##            after every round and must split the totals back into before
##            and this round's award, and name the same champion.
##
## It never changes scene: a finished round's own timer to the tally is
## cancelled here, and the tally is added as a child rather than loaded,
## because loading either would replace this probe. So the scene-to-scene
## hand-off itself is not covered — nor the keys, nor anything drawn.

const TOWER := preload("res://scenes/TowerMode.tscn")
const RACE := preload("res://scenes/TowerRace.tscn")
const CUP := preload("res://scenes/TowerCup.tscn")

const MAX_ROUNDS := 30
const SPREAD := 0.3
const MATCH_TIMEOUT := 900.0

var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []
# Per competitor, the places a co-op round was watched to earn; empty for
# every other round, whose places are just its order.
var watched_places: Array[int] = []

func _ready() -> void:
	print("=== sums ===")
	_sums()
	print("=== cups ===")
	await _cup(GameSettings.TOWER_CUP_SOLO, 2, 101)
	await _cup(GameSettings.TOWER_CUP_SOLO, 3, 202)
	await _cup(GameSettings.TOWER_CUP_SOLO, 4, 303)
	await _cup(GameSettings.TOWER_CUP_TEAM, 3, 404)
	await _cup(GameSettings.TOWER_CUP_TEAM, 4, 505)
	print("=== verdict ===")
	if _failures.is_empty():
		print("  OK — every round paid out once, in the order it was played.")
	else:
		for f in _failures:
			print("  FAIL: " + f)
	GameSettings.tower_cup = GameSettings.TOWER_CUP_NONE
	get_tree().quit()

func _fail(what: String) -> void:
	_failures.append(what)
	print("  <-- " + what)

func _setup(cup: int, count: int) -> void:
	GameSettings.tower_cup = cup
	GameSettings.player_count = count
	var cols: Array[Color] = []
	var skins: Array[Texture2D] = []
	for i in range(count):
		cols.append(GameSettings.PLAYER_SKINS[i]["color"])
		skins.append(GameSettings.PLAYER_SKINS[i]["texture"])
	GameSettings.skin_colors = cols
	GameSettings.skins = skins
	GameSettings.cup_reset()

# --- Sums ----------------------------------------------------------------------

func _sums() -> void:
	var want_rounds := {
		"solo 2": [GameSettings.TOWER_FFA, GameSettings.TOWER_RACE_SOLO, GameSettings.TOWER_COOP, GameSettings.TOWER_FRAME_SOLO, GameSettings.TOWER_DEADLINE_SOLO],
		"solo 4": [GameSettings.TOWER_FFA, GameSettings.TOWER_RACE_SOLO, GameSettings.TOWER_COOP, GameSettings.TOWER_FRAME_SOLO, GameSettings.TOWER_DEADLINE_SOLO],
		"team 3": [GameSettings.TOWER_TEAMS, GameSettings.TOWER_RACE, GameSettings.TOWER_FRAME, GameSettings.TOWER_DEADLINE],
		"team 4": [GameSettings.TOWER_TEAMS, GameSettings.TOWER_RACE, GameSettings.TOWER_COPILOT, GameSettings.TOWER_FRAME, GameSettings.TOWER_DEADLINE],
	}
	for k: String in want_rounds:
		var cup: int = GameSettings.TOWER_CUP_SOLO if k.begins_with("solo") else GameSettings.TOWER_CUP_TEAM
		_setup(cup, int(k.split(" ")[1]))
		var got: Array = []
		for i in range(6):
			got.append(GameSettings.cup_variant(i))
		var want: Array = want_rounds[k]
		for i in range(6):
			if got[i] != want[i % want.size()]:
				_fail("%s cup plays %s, expected %s repeating" % [k, got, want])
				break
		print("  %s: %d competitors, rounds %s" % [k, GameSettings.cup_competitors(), _titles(got.slice(0, want.size()))])

	_setup(GameSettings.TOWER_CUP_SOLO, 4)
	GameSettings.cup_record([2, 0, 3, 1])
	_expect("4p 3/2/1/0", GameSettings.cup_scores, [2, 0, 3, 1])
	_expect_cars("P3 wins: everyone's trophies are P3's car", [[2, 2], [], [2, 2, 2], [2]])
	GameSettings.cup_record([1]) # the rest unplaced: seat order after P2
	_expect("missing places", GameSettings.cup_scores, [4, 3, 4, 1])
	_expect("missing places' order", GameSettings.cup_last_order, [1, 0, 2, 3])
	_expect_cars("then P2 wins: that round's are P2's", [[2, 2, 1, 1], [1, 1, 1], [2, 2, 2, 1], [2]])

	# Two over the line in one round: the higher total, then the better place.
	GameSettings.cup_scores = [13, 14, 0, 0]
	GameSettings.cup_record([0, 1, 2, 3])
	_expect_champion("16 against 16, P1 placed 1st", 0)
	GameSettings.cup_scores = [13, 14, 0, 0]
	GameSettings.cup_record([1, 0, 2, 3])
	_expect_champion("17 against 15", 1)
	GameSettings.cup_scores = [11, 14, 0, 0]
	GameSettings.cup_record([0, 2, 3, 1])
	_expect_champion("14 + 0 and 11 + 3, both 14", -1)

	# A co-op round with ties: P2 and P4 dropped nothing, P1 one, P3 two.
	_setup(GameSettings.TOWER_CUP_SOLO, 4)
	GameSettings.cup_record([1, 3, 0, 2], [0, 0, 2, 3])
	_expect("tied 1st: 3, 3, 1, 0", GameSettings.cup_scores, [1, 3, 0, 3])
	_expect("tied places", GameSettings.cup_last_places, [2, 0, 3, 0])
	_expect_cars("tied winners' cars alternate", [[1], [1, 3, 1], [], [1, 3, 1]])
	_expect("tied winners", GameSettings.cup_round_winners(), [1, 3])
	GameSettings.cup_record([0, 1, 2, 3], [0, 1, 1, 1])
	_expect("tied 2nd: 3, 2, 2, 2", GameSettings.cup_scores, [4, 5, 2, 5])
	# A careless `places` cannot put anyone above the entry before it.
	GameSettings.cup_record([0, 1, 2, 3], [0, 0, 0, 0])
	_expect("everyone level", GameSettings.cup_last_places, [0, 0, 0, 0])
	GameSettings.cup_record([0, 1, 2, 3], [3, 0, 1, 0])
	_expect("nonsense places normalised", GameSettings.cup_last_places, [0, 0, 2, 2])
	# Level on total and on place: the earlier in the round's order takes it.
	GameSettings.cup_scores = [12, 12, 0, 0]
	GameSettings.cup_record([1, 0, 2, 3], [0, 0, 2, 3])
	_expect_champion("15 against 15, both 1st, P2 listed first", 1)

	_setup(GameSettings.TOWER_CUP_TEAM, 3)
	_expect("team cup 3p members of the left", GameSettings.cup_members(0), [0, 2])
	_expect("team cup 3p members of the right", GameSettings.cup_members(1), [1])
	GameSettings.cup_record([1, 0])
	_expect("team cup 3/0", GameSettings.cup_scores, [0, 3])
	_expect_cars("team cup 3p, the right (P2 alone) wins", [[], [1, 1, 1]])
	_setup(GameSettings.TOWER_CUP_TEAM, 4)
	GameSettings.cup_record([0, 1])
	_expect_cars("team cup 4p, the left (P1 + P3) wins", [[0, 2, 0], []])
	print("  awards %s (team cup %s), target %d" % [GameSettings.CUP_AWARDS, GameSettings.CUP_TEAM_AWARDS, GameSettings.CUP_TARGET])

func _expect(what: String, got: Array, want: Array) -> void:
	if got != want:
		_fail("sums: %s gave %s, expected %s" % [what, got, want])

func _expect_cars(what: String, want: Array) -> void:
	var got: Array = []
	for cars in GameSettings.cup_trophy_cars:
		got.append(Array(cars))
	if got != want:
		_fail("sums: %s — trophy cars %s, expected %s" % [what, got, want])

func _expect_champion(what: String, want: int) -> void:
	var got: int = GameSettings.cup_champion()
	if got != want:
		_fail("sums: %s crowned %d, expected %d" % [what, got, want])

func _titles(variants: Array) -> String:
	var out: Array[String] = []
	for v in variants:
		out.append(GameSettings.tower_variant_info(v)["title"])
	return " → ".join(out)

# --- Whole cups ------------------------------------------------------------------

func _cup(cup: int, count: int, seed_base: int) -> void:
	_setup(cup, count)
	var label: String = "%s %dp" % [GameSettings.tower_cup_info()["title"], count]
	var played: Array = []
	var round_no := 0
	while GameSettings.cup_champion() < 0 and round_no < MAX_ROUNDS:
		var variant: int = GameSettings.cup_variant(GameSettings.cup_round)
		if variant != GameSettings.cup_variant(round_no):
			_fail("%s round %d: the cup is on round %d" % [label, round_no + 1, GameSettings.cup_round + 1])
		GameSettings.tower_variant = variant
		played.append(variant)
		seed(seed_base + round_no * 31)
		_rng.seed = seed_base + round_no * 31
		var before: Array[int] = GameSettings.cup_scores.duplicate()
		var cars_before: Array[int] = []
		for cars in GameSettings.cup_trophy_cars:
			cars_before.append(cars.size())
		var watched: Array[int]
		watched_places = []
		if GameSettings.tower_is_frame(variant):
			watched = await _play_frame()
		elif GameSettings.tower_is_deadline(variant):
			watched = await _play_deadline()
		elif GameSettings.tower_is_race(variant):
			watched = await _play_race()
		else:
			watched = await _play_tower()
		var where: String = "%s round %d (%s)" % [label, round_no + 1, GameSettings.tower_variant_info(variant)["title"]]
		round_no += 1

		if GameSettings.cup_round != round_no:
			_fail("%s: paid out %d times" % [where, GameSettings.cup_round - (round_no - 1)])
			GameSettings.cup_round = round_no
		var order: Array[int] = GameSettings.cup_last_order
		var seen: Array[int] = order.duplicate()
		seen.sort()
		var everyone: Array[int] = []
		for c in range(GameSettings.cup_competitors()):
			everyone.append(c)
		if seen != everyone:
			_fail("%s: placed %s, not every competitor once" % [where, order])
		if not watched.is_empty() and order != watched:
			_fail("%s: placed %s, but the round was played %s" % [where, order, watched])
		if not watched_places.is_empty() and GameSettings.cup_last_places != watched_places:
			_fail("%s: places %s, but the round was played %s" % [where, GameSettings.cup_last_places, watched_places])
		var winners: Array[int] = []
		for w in GameSettings.cup_round_winners():
			winners.append_array(GameSettings.cup_members(w))
		for i in range(order.size()):
			var c: int = order[i]
			var place: int = GameSettings.cup_last_places[c]
			if GameSettings.cup_scores[c] - before[c] != GameSettings.cup_award(place):
				_fail("%s: %s came %d and got %d" % [where, GameSettings.cup_name(c), place + 1, GameSettings.cup_scores[c] - before[c]])
			# Every new trophy on this row is a car of the round's winner.
			var cars: Array = GameSettings.cup_trophy_cars[c]
			if cars.size() != GameSettings.cup_scores[c]:
				_fail("%s: %s has %d trophies and %d trophy cars" % [where, GameSettings.cup_name(c), GameSettings.cup_scores[c], cars.size()])
			for k in range(cars_before[c], cars.size()):
				if not winners.has(int(cars[k])):
					_fail("%s: %s's new trophy %d is P%d's car, but %s won the round" % [
						where, GameSettings.cup_name(c), k + 1, int(cars[k]) + 1, GameSettings.cup_name(order[0])])
					break

		# The tally splits it back out.
		var tally = CUP.instantiate()
		add_child(tally)
		for c in range(GameSettings.cup_competitors()):
			if tally.before[c] != before[c] or tally.before[c] + tally.award[c] != GameSettings.cup_scores[c]:
				_fail("%s: the tally shows %s %d + %d, the cup has %d -> %d" % [
					where, GameSettings.cup_name(c), tally.before[c], tally.award[c], before[c], GameSettings.cup_scores[c]])
		if tally.champion != GameSettings.cup_champion():
			_fail("%s: the tally crowns %d, the cup %d" % [where, tally.champion, GameSettings.cup_champion()])
		tally.queue_free()
		await get_tree().physics_frame

	var champ: int = GameSettings.cup_champion()
	if champ < 0:
		_fail("%s: nobody won in %d rounds" % [label, round_no])
	print("  %-12s won by %-10s in %2d rounds   final %s   played %s" % [
		label, GameSettings.cup_name(champ) if champ >= 0 else "NOBODY", round_no,
		GameSettings.cup_scores, _titles(played.slice(0, mini(played.size(), 4))) + (" …" if played.size() > 4 else "")])

func _aim(mode, spread: float) -> void:
	var piece = mode.active_piece
	if piece == null:
		return
	mode.aim_steps = _rng.randi_range(0, 3)
	var limit: float = maxf(0.0,
		mode.PLATFORM_CELLS * mode.CELL * 0.5
		+ mode.AIM_BOUND_CELLS * mode.CELL
		- piece.aim_half_width(mode.aim_steps))
	mode.aim_x = _rng.randf_range(-limit, limit) * spread

# One tower, one match, watched: returns the order this probe saw — the team
# standing at the end, then the eliminated, last out first.
func _play_tower() -> Array[int]:
	var mode = TOWER.instantiate()
	add_child(mode)
	var out_seen: Array[int] = []
	var was_alive := {}
	var aimed = null
	var t := 0.0
	# Co-op: bricks lost, per player, counted the frame each turn stops settling.
	var dropped := {}
	var was_settling := false
	while mode.state != "gameover" and t < MATCH_TIMEOUT:
		if mode.state == "piloting" and mode.active_piece != null and aimed != mode.active_piece:
			aimed = mode.active_piece
			_aim(mode, SPREAD)
		if was_settling and mode.state != "settling":
			dropped[mode.active_slot] = dropped.get(mode.active_slot, 0) + int(mode.fallen_this_turn)
		was_settling = mode.state == "settling"
		for team in mode._teams_here():
			var alive: bool = int(mode.lives[team]) > 0
			if was_alive.get(team, true) and not alive:
				out_seen.append(team)
			was_alive[team] = alive
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var watched: Array[int] = []
	if mode.state != "gameover":
		_fail("a %s round had no result after %.0fs" % [GameSettings.tower_variant_info(mode.variant)["title"], t])
	elif mode.variant == GameSettings.TOWER_COOP:
		if was_settling:
			dropped[mode.active_slot] = dropped.get(mode.active_slot, 0) + int(mode.fallen_this_turn)
		var crew: Array[int] = []
		for s in range(GameSettings.player_count):
			crew.append(s)
		crew.sort_custom(func(a: int, b: int) -> bool:
			return dropped.get(a, 0) < dropped.get(b, 0) or (dropped.get(a, 0) == dropped.get(b, 0) and a < b))
		watched = crew
		watched_places = []
		for _s in crew:
			watched_places.append(0)
		for i in range(crew.size()):
			var same: bool = i > 0 and dropped.get(crew[i], 0) == dropped.get(crew[i - 1], 0)
			watched_places[crew[i]] = watched_places[crew[i - 1]] if same else i
		var tally: Array = []
		for s in range(GameSettings.player_count):
			tally.append(dropped.get(s, 0))
		print("    co-op round: dropped %s -> places %s" % [tally, watched_places])
		if mode._cup_leave_in <= 0.0:
			_fail("a finished co-op cup round is not on its way to the tally")
	else:
		for team in mode._teams_here():
			if int(mode.lives[team]) > 0:
				watched.append(team)
			elif not out_seen.has(team):
				out_seen.append(team) # out on the very frame the match ended
		out_seen.reverse()
		watched.append_array(out_seen)
		if mode._cup_leave_in <= 0.0:
			_fail("a finished cup round is not on its way to the tally")
		if not str(mode.overlay_hint.text).contains("trophies"):
			_fail("a finished cup round's hint says '%s'" % mode.overlay_hint.text)
	mode._cup_leave_in = 0.0 # this probe is the current scene; do not leave it
	mode.queue_free()
	await get_tree().physics_frame
	return watched

# A race, watched: the winner, then whoever was still building at the end by
# height, then the towers in the reverse of the order they were seen dropping out.
func _play_race() -> Array[int]:
	var race = RACE.instantiate()
	add_child(race)
	var aimed := {}
	var out_seen: Array[int] = []
	var t := 0.0
	while not race.over and t < MATCH_TIMEOUT:
		for tw in race.towers:
			if tw.state == "piloting" and tw.active_piece != null and aimed.get(tw) != tw.active_piece:
				aimed[tw] = tw.active_piece
				_aim(tw, SPREAD)
		for i in range(race.towers.size()):
			if race.dropped_out[i] and not out_seen.has(i):
				out_seen.append(i)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var watched: Array[int] = []
	if not race.over:
		_fail("a race round had no result after %.0fs" % t)
	else:
		for i in range(race.towers.size()):
			if race.dropped_out[i] and not out_seen.has(i):
				out_seen.append(i)
		var winner: int = -1
		for i in range(race.towers.size()):
			if race.towers[i].winner_team >= 0:
				winner = i
		if winner < 0:
			for i in range(race.towers.size()):
				if not race.dropped_out[i]:
					winner = i
		if winner >= 0:
			watched.append(winner)
		var racing: Array[int] = []
		for i in range(race.towers.size()):
			if i != winner and not race.dropped_out[i]:
				racing.append(i)
		# Tallest first; level (within a hundredth of a cell) goes to more
		# lives left, then to the earlier seat.
		var key := func(i: int) -> Array:
			return [snappedf(race.towers[i]._height_cells(), 0.01), int(race.towers[i].lives[i]), -i]
		racing.sort_custom(func(a: int, b: int) -> bool:
			var ka: Array = key.call(a)
			var kb: Array = key.call(b)
			for j in range(ka.size()):
				if ka[j] != kb[j]:
					return ka[j] > kb[j]
			return false)
		watched.append_array(racing)
		out_seen.reverse()
		for i in out_seen:
			if not watched.has(i):
				watched.append(i)
		if race._cup_leave_in <= 0.0:
			_fail("a finished cup race is not on its way to the tally")
	race._cup_leave_in = 0.0
	race.queue_free()
	await get_tree().physics_frame
	return watched

# A DEADLINE round, watched: the tower still in at the end, then the rest in
# the reverse of the frame this probe saw each go out — the same frame a
# shared place, and the one later in the host's own out order listed first,
# as placements() lists them. Every tower may be out at the end: a dead heat,
# or one that went under alone on the last frame and so lasted longest.
func _play_deadline() -> Array[int]:
	var race = RACE.instantiate()
	add_child(race)
	var aimed := {}
	var seen := {} # tower -> the probe's frame count when it was first seen out
	var frames := 0
	var t := 0.0
	while not race.over and t < MATCH_TIMEOUT:
		for tw in race.towers:
			if tw.state == "piloting" and tw.active_piece != null and aimed.get(tw) != tw.active_piece:
				aimed[tw] = tw.active_piece
				_aim(tw, SPREAD)
		await get_tree().physics_frame
		frames += 1
		t += get_physics_process_delta_time()
		for i in range(race.towers.size()):
			if race.dropped_out[i] and not seen.has(i):
				seen[i] = frames
	var watched: Array[int] = []
	if not race.over:
		_fail("a deadline round had no result after %.0fs" % t)
	else:
		var outs: Array[int] = []
		for i in range(race.towers.size()):
			if seen.has(i):
				outs.append(i)
			else:
				watched.append(i)
		outs.sort_custom(func(a: int, b: int) -> bool:
			return seen[a] > seen[b] or (seen[a] == seen[b] and race.out_order.find(a) > race.out_order.find(b)))
		var level_first := watched.is_empty() # nobody still in: the last frame's towers lead
		watched.append_array(outs)
		watched_places = []
		for _i in watched:
			watched_places.append(0)
		for k in range(watched.size()):
			var same: bool = k > 0 and seen.has(watched[k]) and seen.has(watched[k - 1]) \
				and seen[watched[k]] == seen[watched[k - 1]]
			watched_places[watched[k]] = watched_places[watched[k - 1]] if same else k
		var lasted: Array[String] = []
		for tw in race.towers:
			lasted.append("%.0fs" % (tw.deadline_out_at if tw.deadline_out_at >= 0.0 else tw.deadline_time))
		print("    deadline round: lasted %s -> places %s%s" % [lasted, watched_places, " (everybody out)" if level_first else ""])
		if race._cup_leave_in <= 0.0:
			_fail("a finished cup deadline round is not on its way to the tally")
	race._cup_leave_in = 0.0
	race.queue_free()
	await get_tree().physics_frame
	return watched

# A FRAME round, watched: every tower's fit as this probe reads it once the
# round is over, best first, seat order on a level fit — which is also a
# shared place.
func _play_frame() -> Array[int]:
	var race = RACE.instantiate()
	add_child(race)
	var aimed := {}
	var t := 0.0
	while not race.over and t < MATCH_TIMEOUT:
		for tw in race.towers:
			if tw.state == "piloting" and tw.active_piece != null and aimed.get(tw) != tw.active_piece:
				aimed[tw] = tw.active_piece
				_aim(tw, SPREAD)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var watched: Array[int] = []
	if not race.over:
		_fail("a frame round had no result after %.0fs" % t)
	else:
		var fits: Array[int] = []
		for i in range(race.towers.size()):
			watched.append(i)
			fits.append(race.towers[i].frame_pct())
		watched.sort_custom(func(a: int, b: int) -> bool:
			return fits[a] > fits[b] or (fits[a] == fits[b] and a < b))
		watched_places = []
		for _i in watched:
			watched_places.append(0)
		for k in range(watched.size()):
			var same: bool = k > 0 and fits[watched[k]] == fits[watched[k - 1]]
			watched_places[watched[k]] = watched_places[watched[k - 1]] if same else k
		print("    frame round: fits %s -> places %s" % [fits, watched_places])
		if race._cup_leave_in <= 0.0:
			_fail("a finished cup frame round is not on its way to the tally")
	race._cup_leave_in = 0.0
	race.queue_free()
	await get_tree().physics_frame
	return watched
