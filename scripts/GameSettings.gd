extends Node

# Which way Pile Up is played: each round of a cup sets it (the cup is picked
# on MainMenu). Plain ints rather than an enum because this autoload loads
# before every gameplay script, so it must not name a type that lives in one.
#
# Every variant is the same TowerMode underneath, and they differ in exactly
# one idea: **who a turn belongs to**. In free-for-all that is one player, and
# everything else is a generalisation of it — a team is a set of players who
# share a life pool and take the team's turns in rotation, so free-for-all is
# just every player on a team of one. That is why the original mode is still
# the default and why its probes still mean what they did.
const TOWER_FFA := 0     # every builder for themselves — the original Pile Up
const TOWER_TEAMS := 1   # two teams on one tower, a shared life pool each
const TOWER_COPILOT := 2 # two crews of two: one steers the brick, the other turns it
const TOWER_COOP := 3    # everyone against the storm, building to a goal line
const TOWER_RACE := 4    # two towers side by side, first team to the line
const TOWER_RACE_SOLO := 5 # a tower per player, side by side, first one to the line
const TOWER_FRAME_SOLO := 6 # a tower per player, one outline to fill, best fit wins
const TOWER_FRAME := 7      # the same, a tower per team
const TOWER_DEADLINE_SOLO := 8 # a tower per player, a red line rising under every one of them
const TOWER_DEADLINE := 9      # the same, a tower per team
var tower_variant: int = TOWER_FFA

# Both races are hosted by TowerRace and share every race rule; they differ
# only in who shares a tower — a team, or nobody.
func tower_is_race(variant: int = tower_variant) -> bool:
	return variant == TOWER_RACE or variant == TOWER_RACE_SOLO

# FRAME: every tower gets the same outline on its platform, built from the
# same bricks it is about to be dealt (TowerFrame), and fills it at once with
# the others. Nobody is out and nothing is a race: each tower stops after
# TowerMode.FRAME_BRICKS, and the best fit — frame covered, minus whatever
# spills outside it — wins.
func tower_is_frame(variant: int = tower_variant) -> bool:
	return variant == TOWER_FRAME or variant == TOWER_FRAME_SOLO

# DEADLINE: a red line across every tower, starting at the ground and rising
# for the whole round, faster all the time. A tower whose top stays under it
# for TowerMode.DEADLINE_GRACE is out, and the last one left in wins.
# Asked for from a sketch: two towers side by side, a red line across each.
func tower_is_deadline(variant: int = tower_variant) -> bool:
	return variant == TOWER_DEADLINE or variant == TOWER_DEADLINE_SOLO

# Several towers side by side under TowerRace: the races, FRAME and DEADLINE.
func tower_is_hosted(variant: int = tower_variant) -> bool:
	return tower_is_race(variant) or tower_is_frame(variant) or tower_is_deadline(variant)

# Every variant, and the player counts each one is playable at. `counts` is
# what a cup checks before playing a variant as one of its rounds: a count
# missing here is not a quieter version of the variant, it is a variant that
# does not exist at that count (co-pilot needs two crews of two, and a team
# needs a second player).
#
# Nobody picks one of these directly any more. The picker offers only the two
# cups (TOWER_CUPS below), and every variant is played as a cup's round —
# asked for so that whether you play alone or in teams it is always a cup,
# with a different mode every round. Variants are still played on their own
# by the probes, with tower_cup left at TOWER_CUP_NONE.
const TOWER_VARIANTS: Array[Dictionary] = [
	{"id": TOWER_FFA, "title": "FREE FOR ALL", "hint": "one tower, three lives each — drop a brick and it costs you", "counts": [2, 3, 4]},
	{"id": TOWER_RACE_SOLO, "title": "RACE", "hint": "a tower each, everyone at once — first to the line wins, and hexes hit the leader", "counts": [2, 3, 4]},
	{"id": TOWER_TEAMS, "title": "TEAMS", "hint": "one tower — a shared pool of lives per team, turns alternate sides", "counts": [3, 4]},
	{"id": TOWER_COPILOT, "title": "CO-PILOT", "hint": "two crews of two, one brick per crew — one of you steers it, the other turns it", "counts": [4]},
	{"id": TOWER_COOP, "title": "CO-OP: THE STORM", "hint": "build to the goal line together while the storm throws hexes — fewest bricks dropped wins the round", "counts": [1, 2, 3, 4]},
	{"id": TOWER_RACE, "title": "TEAM RACE", "hint": "a tower each, side by side — first to the line wins, and hexes cross over", "counts": [2, 3, 4]},
	{"id": TOWER_FRAME_SOLO, "title": "FRAME", "hint": "the same outline and the same bricks for everyone — fill it best, and spilling over it costs you", "counts": [2, 3, 4]},
	{"id": TOWER_FRAME, "title": "TEAM FRAME", "hint": "a frame per team, the same bricks both sides — best fit wins, spill costs you", "counts": [2, 3, 4]},
	{"id": TOWER_DEADLINE_SOLO, "title": "DEADLINE", "hint": "a tower each and a red line rising under them all, faster and faster — stay under it too long and you are out", "counts": [2, 3, 4]},
	{"id": TOWER_DEADLINE, "title": "TEAM DEADLINE", "hint": "a tower per team and the same rising line under both — stay under it too long and your team is out", "counts": [2, 3, 4]},
]

func tower_variant_info(variant: int = tower_variant) -> Dictionary:
	for v: Dictionary in TOWER_VARIANTS:
		if v["id"] == variant:
			return v
	return TOWER_VARIANTS[0]

# Which scene plays a variant: a race is several TowerModes under a host of
# its own, every other variant is one TowerMode that reads the variant itself.
func tower_scene(variant: int = tower_variant) -> String:
	if tower_is_hosted(variant):
		return "res://scenes/TowerRace.tscn"
	return "res://scenes/TowerMode.tscn"

# --- Pile Up's cups ----------------------------------------------------------
# A cup is a run of rounds, each one a *different* variant in turn — the
# solo cup goes free-for-all (last builder standing), the race, co-op, frame,
# deadline, the team cup teams, team race, co-pilot, team frame, team
# deadline — scored by where you finished:
# 3 trophies for 1st, 2 for 2nd, 1 for 3rd, none for 4th. First to
# CUP_TARGET wins the cup. TowerCup is the tally screen between rounds.
#
# A trophy is drawn as a car, and the car is the round's *winner's*, not the
# row owner's: when blue wins a round, blue takes three blue cars, 2nd takes
# two blue cars and 3rd one; when purple wins the next, that round's trophies
# are all purple. So a row is its own history, read left to right — whose
# rounds you were placing in, as well as how well — and the winner of every
# round is on every row that scored in it. Asked for exactly like that.
#
# It lives here because it is the one thing in Pile Up that outlives a scene:
# every round is a fresh TowerMode or TowerRace, and this autoload is what is
# still there when the next one loads. Plain data only, same rule as above.
#
# A *competitor* is whoever a round is decided between, and it is always a
# team index of the round's variant: in the solo cup that is the player's
# own slot (tower_team_of() is the slot in free-for-all and the solo race),
# and in the team cup it is the side — slot parity — which is the same pair of
# teams in all three team variants. So a round's result is just its teams
# from best to worst, and nothing here has to know which variant produced it.
const TOWER_CUP_NONE := 0
const TOWER_CUP_SOLO := 1
const TOWER_CUP_TEAM := 2
var tower_cup: int = TOWER_CUP_NONE

const CUP_TARGET := 15
# Trophies by place, 1st first — exactly as asked. Note what that means with
# only two players in the solo cup: the loser still banks 2 a round, so the
# gap only ever opens by 1 and the cup is in effect decided over a fixed five
# or six rounds. Unplayed; this is the line to change.
const CUP_AWARDS: Array[int] = [3, 2, 1, 0]
# The team cup's, which always has exactly two sides: the winners take 3 and
# the losers nothing, so it is first to five round wins. It used the table
# above at first, and that made it the same fixed six-round series — the
# user asked for this instead.
const CUP_TEAM_AWARDS: Array[int] = [3, 0]

# The picker's rows — the only two — in TOWER_VARIANTS' format plus `rounds`:
# the variants the cup cycles through, in order. A round whose variant cannot
# be played at this player count is skipped (co-pilot needs four), never
# played short-handed.
#
# Every variant is in one of them. Co-op is a round of the solo cup even
# though nobody plays against anybody in it: the crew builds together, and the
# round is placed by who dropped the fewest bricks (TowerMode.placements()),
# with an equal count an equal place. It is not in the team cup, because a
# side of one against a side of two would be counting different numbers of
# turns.
const TOWER_CUPS: Array[Dictionary] = [
	# The hints are one unwrapped line of 16px Press Start 2P on the picker, 16px
	# a character: past ~90 characters they run off the screen.
	{"id": TOWER_CUP_SOLO, "title": "SOLO CUP", "hint": "everyone for themselves — free for all, race, co-op, frame, deadline, round and round", "counts": [2, 3, 4], "rounds": [TOWER_FFA, TOWER_RACE_SOLO, TOWER_COOP, TOWER_FRAME_SOLO, TOWER_DEADLINE_SOLO]},
	{"id": TOWER_CUP_TEAM, "title": "TEAM CUP", "hint": "left half of the keyboard vs the right — teams, race, co-pilot, frame, deadline in turn", "counts": [3, 4], "rounds": [TOWER_TEAMS, TOWER_RACE, TOWER_COPILOT, TOWER_FRAME, TOWER_DEADLINE]},
]

var cup_scores: Array[int] = [] # per competitor
var cup_round: int = 0 # rounds finished so far
var cup_last_order: Array[int] = [] # the last round's competitors, best to worst
# Per competitor, its 0-based place in the last round. Usually its index in
# cup_last_order, but a round can place two the same (co-op, equal bricks
# dropped): then both take that place's award and the next place is skipped,
# the way a sports table does it — 1st, 1st, 3rd.
var cup_last_places: Array[int] = []
var cup_last_awards: Array[int] = [] # what each competitor got for it
# Per competitor, one entry per trophy in the order they were won: the player
# slot whose car that trophy is drawn as — a member of whoever won its round.
# Untyped outer Array because GDScript has no nested typed arrays.
var cup_trophy_cars: Array = []

func tower_cup_info(cup: int = tower_cup) -> Dictionary:
	for c: Dictionary in TOWER_CUPS:
		if c["id"] == cup:
			return c
	return TOWER_CUPS[0]

# What the picker and the player count describe: the cup, while one is
# picked, otherwise the variant.
func tower_pick_info() -> Dictionary:
	return tower_cup_info() if tower_cup != TOWER_CUP_NONE else tower_variant_info()

func cup_rounds() -> Array[int]:
	var out: Array[int] = []
	for v: int in tower_cup_info()["rounds"]:
		if tower_variant_info(v)["counts"].has(player_count):
			out.append(v)
	return out

# The variant round `index` (0-based) is played as.
func cup_variant(index: int) -> int:
	var rounds: Array[int] = cup_rounds()
	return rounds[index % rounds.size()] if not rounds.is_empty() else TOWER_FFA

func cup_competitors() -> int:
	if tower_cup == TOWER_CUP_TEAM:
		return 2
	return player_count

# The slots a competitor is made of, in seat order.
func cup_members(competitor: int) -> Array[int]:
	var out: Array[int] = []
	for s in range(player_count):
		if (s % 2 if tower_cup == TOWER_CUP_TEAM else s) == competitor:
			out.append(s)
	return out

func cup_name(competitor: int) -> String:
	if tower_cup == TOWER_CUP_TEAM:
		return tower_team_name(competitor, TOWER_TEAMS)
	return PLAYER_CONFIGS[competitor]["name"] if competitor < PLAYER_CONFIGS.size() else "?"

func cup_awards() -> Array[int]:
	return CUP_TEAM_AWARDS if tower_cup == TOWER_CUP_TEAM else CUP_AWARDS

func cup_award(place: int) -> int:
	var table: Array[int] = cup_awards()
	return table[place] if place >= 0 and place < table.size() else 0

# A fresh cup for the players and colours already chosen.
func cup_reset() -> void:
	cup_scores = []
	for _c in range(cup_competitors()):
		cup_scores.append(0)
	cup_round = 0
	cup_last_order = []
	cup_last_places = []
	cup_last_awards = []
	cup_trophy_cars = []
	for _c in range(cup_competitors()):
		var cars: Array[int] = []
		cup_trophy_cars.append(cars)
	tower_variant = cup_variant(0)

# One round's result, best to worst. Anyone missing from `order` is put last
# in seat order rather than dropped, so a round always pays out every place.
# `places`, if given, is each entry of `order`'s 0-based place, for a round
# with ties (co-op); without it every entry is its own place.
func cup_record(order: Array[int], places: Array[int] = []) -> void:
	var full: Array[int] = []
	var full_places: Array[int] = []
	for i in range(order.size()):
		var c: int = order[i]
		if c >= 0 and c < cup_scores.size() and not full.has(c):
			full.append(c)
			full_places.append(places[i] if i < places.size() else i)
	for c in range(cup_scores.size()):
		if not full.has(c):
			full.append(c)
			full_places.append(full.size() - 1)
	# An entry either ties the one before it or takes its own index — 1st,
	# 1st, 3rd, never 1st, 1st, 2nd — so a short or careless `places` can
	# neither reorder anybody nor invent a place.
	full_places[0] = 0
	for i in range(1, full_places.size()):
		full_places[i] = full_places[i - 1] if full_places[i] <= full_places[i - 1] else i
	cup_last_order = full
	cup_last_awards = []
	cup_last_places = []
	for _c in range(cup_scores.size()):
		cup_last_awards.append(0)
		cup_last_places.append(0)
	# Every trophy this round is the winner's car. A winning team's cars take
	# turns between its members, the same way on every row, so the pair is
	# on everyone's row rather than only its first member — and so do the
	# cars of everyone sharing 1st.
	var winners: Array[int] = []
	for i in range(full.size()):
		if full_places[i] == 0:
			winners.append_array(cup_members(full[i]))
	if winners.is_empty():
		winners = [0]
	while cup_trophy_cars.size() < cup_scores.size():
		var cars: Array[int] = []
		cup_trophy_cars.append(cars)
	for i in range(full.size()):
		var got: int = cup_award(full_places[i])
		cup_last_places[full[i]] = full_places[i]
		cup_last_awards[full[i]] = got
		cup_scores[full[i]] += got
		for k in range(got):
			cup_trophy_cars[full[i]].append(winners[k % winners.size()])
	cup_round += 1

# Whoever the last round placed first — more than one after a tie.
func cup_round_winners() -> Array[int]:
	var out: Array[int] = []
	for i in range(cup_last_order.size()):
		var c: int = cup_last_order[i]
		if c < cup_last_places.size() and cup_last_places[c] == 0:
			out.append(c)
	return out

# The player slot whose car competitor `c`'s trophy number `k` (0-based) is
# drawn as; -1 if the cup has no record of it (a total set by hand).
func cup_trophy_car(c: int, k: int) -> int:
	if c < 0 or c >= cup_trophy_cars.size():
		return -1
	var cars: Array = cup_trophy_cars[c]
	return int(cars[k]) if k >= 0 and k < cars.size() else -1

# Whoever has won the cup, or -1. Two can cross the line in the same round;
# the higher total takes it, and a dead heat goes to whoever placed better in
# that round — the one that got them there.
func cup_champion() -> int:
	var best := -1
	for c in range(cup_scores.size()):
		if cup_scores[c] < CUP_TARGET:
			continue
		if best == -1 or cup_scores[c] > cup_scores[best] \
				or (cup_scores[c] == cup_scores[best] and _cup_place(c) < _cup_place(best)) \
				or (cup_scores[c] == cup_scores[best] and _cup_place(c) == _cup_place(best) \
					and cup_last_order.find(c) < cup_last_order.find(best)):
			best = c
	return best

func _cup_place(c: int) -> int:
	return cup_last_places[c] if c < cup_last_places.size() else cup_last_order.find(c)

# Teams are seats, not a choice. P1 (WASD) and P3 (TFGH) sit on the left
# half of the keyboard and P2 (arrows) and P4 (IJKL) on the right, so the
# halves are the teams — nobody has to reach across an opponent to play, and
# the default turn order P1, P2, P3, P4 alternates the teams on its own.
func tower_team_of(slot: int, variant: int = tower_variant) -> int:
	match variant:
		TOWER_FFA, TOWER_RACE_SOLO, TOWER_FRAME_SOLO, TOWER_DEADLINE_SOLO:
			return slot
		TOWER_COOP:
			return 0
	return slot % 2

func tower_team_name(team: int, variant: int = tower_variant) -> String:
	match variant:
		TOWER_FFA, TOWER_RACE_SOLO, TOWER_FRAME_SOLO, TOWER_DEADLINE_SOLO:
			return PLAYER_CONFIGS[team]["name"] if team < PLAYER_CONFIGS.size() else "?"
		TOWER_COOP:
			return "THE CREW"
		TOWER_COPILOT:
			return "LEFT CREW" if team == 0 else "RIGHT CREW"
	return "LEFT TEAM" if team == 0 else "RIGHT TEAM"

var player_count: int = 2

# Selectable player colours: shown in SkinSelect as each player's car (the
# game this was split from was a racing game too, docs/PROJECT_STATE.md §0),
# and drawn as the trophies on the cup's count. Order matters for the default
# index (P1=0, P2=1...). "color" is a flat approximation of each texture's
# dominant hue — it is what marks a player's brick, HUD card and lives.
const PLAYER_SKINS: Array[Dictionary] = [
	{"name": "Blue", "texture": preload("res://sprites/cars/sedan_blue.png"), "color": Color(0.25, 0.48, 0.92)},
	{"name": "Red", "texture": preload("res://sprites/cars/sedan_red.png"), "color": Color(0.88, 0.22, 0.22)},
	{"name": "Green", "texture": preload("res://sprites/cars/sedan_green.png"), "color": Color(0.24, 0.68, 0.32)},
	{"name": "Yellow", "texture": preload("res://sprites/cars/sedan_yellow.png"), "color": Color(0.95, 0.78, 0.12)},
	{"name": "Purple", "texture": preload("res://sprites/cars/sedan_purple.png"), "color": Color(0.58, 0.32, 0.78)},
	{"name": "Orange", "texture": preload("res://sprites/cars/sedan_orange.png"), "color": Color(0.92, 0.52, 0.14)},
]

# Chosen texture/color per player, filled in by SkinSelect before a round starts.
var skins: Array[Texture2D] = [PLAYER_SKINS[0]["texture"], PLAYER_SKINS[1]["texture"]]
var skin_colors: Array[Color] = [PLAYER_SKINS[0]["color"], PLAYER_SKINS[1]["color"]]

# One steering + confirm binding per player slot. Keeps 4 players on a single
# keyboard: three WASD-shaped clusters (A/D+W, F/H+T, J/L+I) plus arrows.
#
# `down` is Pile Up's soft drop — hold it and the descending brick falls
# faster. Each one is the key physically below that player's confirm key and
# between their two steering keys (A-S-D, F-G-H, J-K-L, and the arrow
# cluster's own Down), so "down" means down on the keyboard as well as in
# the game.
# skill_opponent/skill_self rotate the brick (the names are from the racing
# game this was split from, docs/PROJECT_STATE.md §0, where they picked a
# skill). `cast_self` / `cast_opponent` are Pile Up's two skill keys, placed on the row under each
# player's own cluster (Z/X under A/S, V/B under F/G) or beside it (N/M left
# of P2's comma, ;/' right of P4's L), all keys nothing else in the project
# reads. This project targets
# PS5 eventually (steering -> stick, skill_opponent/self -> a pair of
# shoulder/face buttons), so these keyboard bindings are just a placeholder
# stand-in and don't need to be especially ergonomic — chosen to flank each
# player's own confirm key on the keyboard (Q/W/E, ,/Up/., R/T/Y, U/I/O) only
# as a mnemonic, not because that positioning matters long-term.
const PLAYER_CONFIGS: Array[Dictionary] = [
	{"name": "P1", "left": KEY_A, "right": KEY_D, "down": KEY_S, "confirm": KEY_W, "skill_opponent": KEY_Q, "skill_self": KEY_E, "cast_self": KEY_Z, "cast_opponent": KEY_X, "steer_label": "A / D", "confirm_label": "W", "cast_label": "Z / X"},
	{"name": "P2", "left": KEY_LEFT, "right": KEY_RIGHT, "down": KEY_DOWN, "confirm": KEY_UP, "skill_opponent": KEY_COMMA, "skill_self": KEY_PERIOD, "cast_self": KEY_N, "cast_opponent": KEY_M, "steer_label": "Left / Right", "confirm_label": "Up", "cast_label": "N / M"},
	{"name": "P3", "left": KEY_F, "right": KEY_H, "down": KEY_G, "confirm": KEY_T, "skill_opponent": KEY_R, "skill_self": KEY_Y, "cast_self": KEY_V, "cast_opponent": KEY_B, "steer_label": "F / H", "confirm_label": "T", "cast_label": "V / B"},
	{"name": "P4", "left": KEY_J, "right": KEY_L, "down": KEY_K, "confirm": KEY_I, "skill_opponent": KEY_U, "skill_self": KEY_O, "cast_self": KEY_SEMICOLON, "cast_opponent": KEY_APOSTROPHE, "steer_label": "J / L", "confirm_label": "I", "cast_label": "; / '"},
]


# --- Bricks ----------------------------------------------------------------------

# The nineteen bricks Pile Up drops: the seven tetrominoes and all twelve
# pentominoes, extracted from the user's tat1.png - tat6.png by
# scripts/dev/extract_blocks.py. Every sprite is normalised there to an exact
# `cols x rows` grid of square cells, so one scale factor (cell / 100) fits
# any of them and nothing here needs a per-piece fudge.
#
# These entries follow the art rather than the other way round. The previous
# sheet drew each cell as its own upright little panel (a wheel, a battery),
# so its pieces could not be rotated to fit a footprint and the extractor had
# to re-lay their cells instead; this art is flat colour inside an outline and
# has no up, so the shapes here are simply the shapes as drawn. `cols`/`rows`
# and `boxes` still have to agree with the art exactly — extract_blocks.py's
# GRID table is where that agreement is checked, and nothing checks it at
# runtime.
#
# `boxes` is the piece's collision, in cell units measured from the top-left
# of its own bounding box. It is deliberately *merged rectangles* rather than
# one box per cell: a stack of four separate unit boxes presents internal
# edges that a neighbouring brick's corner can catch on, which reads as a
# tower snagging on nothing. Every shape here covers in two or three
# rectangles, so the merged form costs nothing and is strictly more stable.
# They are generated by extract_blocks.py's decompose(), not written by hand.
#
# `color` is a flat approximation of each sprite's body hue, for the UI bits
# that need a plain Color rather than the texture (the next-piece card, the
# landing flash) — same role, and same caveat about not updating itself, as
# PLAYER_SKINS' own "color" entry.
#
# `classic` is the brick's *category*, and it is the one field here that is
# about the draw rather than about the brick. True for the seven Tetris
# pieces, false for the twelve pentominoes. The draw is not uniform: a
# classic is TowerMode.CLASSIC_BIAS times likelier than an odd one, per
# brick, because a uniform draw over nineteen shapes made two bricks in three
# a five-cell piece and the odd ones stopped reading as odd. The split is
# stated in one place — that constant — and this flag is only the input to
# it, so the ordering of this array still carries no weight.
const BRICKS: Array[Dictionary] = [
	# --- tetrominoes -------------------------------------------------------
	{
		"name": "I", "classic": true, "cols": 1, "rows": 4, "color": Color(0.00, 0.85, 1.00),
		"texture": preload("res://sprites/blocks/piece_i.png"),
		"boxes": [Rect2(0, 0, 1, 4)],
	},
	{
		"name": "O", "classic": true, "cols": 2, "rows": 2, "color": Color(1.00, 0.96, 0.10),
		"texture": preload("res://sprites/blocks/piece_o.png"),
		"boxes": [Rect2(0, 0, 2, 2)],
	},
	{
		"name": "S", "classic": true, "cols": 3, "rows": 2, "color": Color(0.93, 0.09, 0.14),
		"texture": preload("res://sprites/blocks/piece_s.png"),
		"boxes": [Rect2(1, 0, 2, 1), Rect2(0, 1, 2, 1)],
	},
	{
		"name": "Z", "classic": true, "cols": 3, "rows": 2, "color": Color(0.12, 0.74, 0.27),
		"texture": preload("res://sprites/blocks/piece_z.png"),
		"boxes": [Rect2(0, 0, 2, 1), Rect2(1, 1, 2, 1)],
	},
	{
		"name": "L", "classic": true, "cols": 2, "rows": 3, "color": Color(1.00, 0.53, 0.00),
		"texture": preload("res://sprites/blocks/piece_l.png"),
		"boxes": [Rect2(0, 0, 1, 3), Rect2(1, 2, 1, 1)],
	},
	{
		"name": "J", "classic": true, "cols": 2, "rows": 3, "color": Color(0.99, 0.41, 0.73),
		"texture": preload("res://sprites/blocks/piece_j.png"),
		"boxes": [Rect2(1, 0, 1, 3), Rect2(0, 2, 1, 1)],
	},
	{
		"name": "T", "classic": true, "cols": 3, "rows": 2, "color": Color(0.61, 0.13, 0.64),
		"texture": preload("res://sprites/blocks/piece_t.png"),
		"boxes": [Rect2(0, 0, 3, 1), Rect2(1, 1, 1, 1)],
	},
	# --- pentominoes -------------------------------------------------------
	{
		"name": "L5", "classic": false, "cols": 2, "rows": 4, "color": Color(1.00, 0.83, 0.01),
		"texture": preload("res://sprites/blocks/piece_l5.png"),
		"boxes": [Rect2(0, 0, 1, 4), Rect2(1, 3, 1, 1)],
	},
	{
		"name": "N", "classic": false, "cols": 2, "rows": 4, "color": Color(0.99, 0.24, 0.75),
		"texture": preload("res://sprites/blocks/piece_n.png"),
		"boxes": [Rect2(1, 1, 1, 3), Rect2(0, 0, 1, 2)],
	},
	{
		"name": "I5", "classic": false, "cols": 1, "rows": 5, "color": Color(0.01, 0.61, 0.27),
		"texture": preload("res://sprites/blocks/piece_i5.png"),
		"boxes": [Rect2(0, 0, 1, 5)],
	},
	{
		"name": "Y", "classic": false, "cols": 2, "rows": 4, "color": Color(0.36, 0.90, 0.06),
		"texture": preload("res://sprites/blocks/piece_y.png"),
		"boxes": [Rect2(0, 0, 1, 4), Rect2(1, 1, 1, 1)],
	},
	{
		"name": "F", "classic": false, "cols": 3, "rows": 3, "color": Color(0.00, 0.70, 0.96),
		"texture": preload("res://sprites/blocks/piece_f.png"),
		"boxes": [Rect2(0, 1, 3, 1), Rect2(1, 0, 1, 1), Rect2(0, 2, 1, 1)],
	},
	{
		"name": "V", "classic": false, "cols": 3, "rows": 3, "color": Color(0.95, 0.07, 0.17),
		"texture": preload("res://sprites/blocks/piece_v.png"),
		"boxes": [Rect2(0, 2, 3, 1), Rect2(2, 0, 1, 2)],
	},
	{
		"name": "U", "classic": false, "cols": 3, "rows": 2, "color": Color(1.00, 0.47, 0.00),
		"texture": preload("res://sprites/blocks/piece_u.png"),
		"boxes": [Rect2(0, 0, 3, 1), Rect2(0, 1, 1, 1), Rect2(2, 1, 1, 1)],
	},
	{
		"name": "P", "classic": false, "cols": 2, "rows": 3, "color": Color(0.09, 0.49, 0.99),
		"texture": preload("res://sprites/blocks/piece_p.png"),
		"boxes": [Rect2(0, 0, 2, 2), Rect2(1, 2, 1, 1)],
	},
	{
		"name": "T5", "classic": false, "cols": 3, "rows": 3, "color": Color(0.00, 0.91, 1.00),
		"texture": preload("res://sprites/blocks/piece_t5.png"),
		"boxes": [Rect2(0, 2, 3, 1), Rect2(1, 0, 1, 2)],
	},
	{
		"name": "Z5", "classic": false, "cols": 3, "rows": 3, "color": Color(0.01, 0.84, 0.86),
		"texture": preload("res://sprites/blocks/piece_z5.png"),
		"boxes": [Rect2(0, 1, 3, 1), Rect2(2, 0, 1, 1), Rect2(0, 2, 1, 1)],
	},
	{
		"name": "X", "classic": false, "cols": 3, "rows": 3, "color": Color(0.59, 0.16, 0.79),
		"texture": preload("res://sprites/blocks/piece_x.png"),
		"boxes": [Rect2(0, 1, 3, 1), Rect2(1, 0, 1, 1), Rect2(1, 2, 1, 1)],
	},
	{
		"name": "W", "classic": false, "cols": 3, "rows": 3, "color": Color(1.00, 0.51, 0.03),
		"texture": preload("res://sprites/blocks/piece_w.png"),
		"boxes": [Rect2(0, 1, 2, 1), Rect2(1, 2, 2, 1), Rect2(0, 0, 1, 1)],
	},
]
