extends Control

## Pile Up's races — several towers side by side, built at the same time.
## TEAM RACE has two, one per team; RACE (the free-for-all one) has one per
## player, two to four. First tower to settle over the line wins. A tower
## that runs out of lives drops out where it stands and the rest race on; the
## last one left wins. Hexes cast on one tower land on another
## (TowerMode.receive_hex), on that tower's next brick.
##
## It also hosts FRAME (GameSettings.tower_is_frame), which is not a race at
## all but needs exactly this: a tower per team, side by side, the same deal
## on each. There nobody is out and nothing is first — every tower stops
## after its frame's bricks (TowerMode.FRAME_BRICKS), waits for the others,
## and the best fit wins. Everything FRAME does differently here is behind
## `frame_round`.
##
## ## Why several TowerModes rather than one with several platforms
##
## A TowerMode is one turn loop: one brick in the air, one settle, one
## resolve. Teams building *at once* is several of those loops, and the
## mode's whole fault rule is built on there being exactly one — so a race is
## several complete, unmodified-in-spirit TowerModes, not a TowerMode taught
## to juggle. Each sits in its own SubViewport, and a SubViewport has its own
## World2D: its own physics space, its own current camera, its own canvas
## layers. A brick on one tower cannot touch another because they are not in
## the same world, not because anything checks.
##
## What a hosted tower does differently is small and lives behind
## `TowerMode.host`: it takes no input of its own (this script forwards every
## key to every tower, so none depends on which viewport Godot would deliver
## an event to), shows no game-over overlay, and reports its result here the
## frame it is known.
##
## ## Who a hex hits
##
## With two towers, the other one. With more, **the tallest rival** — ties to
## whoever is next in seat order after the caster. A hex aimed at a random
## rival is noise, and one aimed at the next seat is a feud between
## neighbours; aimed at the leader it is the race's catch-up rule, and one
## everyone can see coming because the progress bars say who is ahead.
##
## ## Why TextureRects and not SubViewportContainers
##
## The project stretches its 1500x800 canvas to the window ("canvas_items"),
## so on a high-DPI screen the root renders at the window's real resolution. A
## SubViewport renders at whatever size it is given, and a container sizes it
## in the root's *logical* pixels — so the towers would be drawn at their
## logical size and scaled up, visibly softer than everything else in the
## game. Instead each viewport is sized to the window's real pixels and told,
## through size_2d_override, to lay its 2D out at the logical size anyway; a
## TextureRect shows it. The tower cannot tell the difference —
## get_visible_rect() reports the override.
##
## At three or four towers a view is 500 or 375px wide, too narrow for the
## HUD's two side columns, and TowerHUD switches to its compact strip on its
## own (TowerHUD.COMPACT_BELOW).

const TOWER := preload("res://scenes/TowerMode.tscn")

# Dividers between the towers. Two towers keep the wide seam the team race
# shipped with; three or four are narrow enough that every pixel is play
# column or HUD, so theirs are thin.
const SEAM_W_TWO := 30.0
const SEAM_W_MORE := 12.0
const SEAM_BG := Color(0.05, 0.06, 0.14, 0.85)

# Each tower's progress to the line, as a bar along the bottom of its own
# view — every bar on one baseline, so who is ahead reads straight across the
# screen. The bottom of a view is the earth band under the ground for most of
# a race (the camera only climbs past ~7 cells), so the bar covers soil, not
# bricks, until the very end.
const BAR_H := 10.0
const BAR_UP := 22.0 # from the bottom of the screen to the bar's top
const BAR_MARGIN := 18.0
const BAR_EMPTY := Color(1.0, 1.0, 1.0, 0.14)
const BAR_PLATE := Color(0.05, 0.06, 0.14, 0.72)
const OUT_DIM := Color(0.04, 0.04, 0.09, 0.62)
const OUT_TEXT := Color(1.0, 0.45, 0.42, 0.95)

@onready var screens: Control = $Screens
@onready var frame: Control = $Frame
@onready var overlay: Control = $Layer/Overlay
@onready var overlay_title: Label = $Layer/Overlay/OverlayTitle
@onready var overlay_body: Label = $Layer/Overlay/OverlayBody
@onready var overlay_hint: Label = $Layer/Overlay/OverlayHint

var variant: int = GameSettings.TOWER_RACE
var towers: Array = [] # left to right; untyped, TowerMode has no class_name
var dropped_out: Array[bool] = [] # per tower: ran out of lives, race goes on without it
var done: Array[bool] = [] # FRAME, per tower: placed all its bricks, waiting for the rest
var frame_round := false
var viewports: Array[SubViewport] = []
var view_w: float = 0.0
var over := false
var winner: int = -1 # the tower that won the race just decided; -1 for nobody
# Towers in the order they dropped out, first out first — what ranks the
# rest of the field when a cup asks for every place, not just the winner.
var out_order: Array[int] = []
var _cup_leave_in: float = 0.0 # cup only: see TowerMode.CUP_RESULT_HOLD

func _ready() -> void:
	frame.draw.connect(_draw_frame)
	variant = GameSettings.tower_variant if GameSettings.tower_is_hosted() else GameSettings.TOWER_RACE
	frame_round = GameSettings.tower_is_frame(variant)
	var full := size
	if full.x <= 0.0:
		full = get_viewport().get_visible_rect().size
	var count: int = _tower_count()
	view_w = floorf(full.x / float(count))
	var view := Vector2(view_w, full.y)
	var deal: int = _new_deal()
	for side in range(count):
		var vp := SubViewport.new()
		vp.size_2d_override = Vector2i(view)
		vp.size_2d_override_stretch = true
		vp.size = _pixel_size(view)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)

		var shown := TextureRect.new()
		shown.texture = vp.get_texture()
		shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shown.stretch_mode = TextureRect.STRETCH_SCALE
		shown.position = Vector2(view_w * float(side), 0.0)
		shown.size = view
		shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screens.add_child(shown)

		# Everything the tower reads in _ready() is set before it enters the
		# tree: which variant, who builds on it, how far back the camera sits.
		var tower = TOWER.instantiate()
		tower.host = self
		tower.variant = variant
		tower.visible_cells = tower.RACE_VISIBLE_CELLS
		tower.brick_seed = deal
		var crew: Array[int] = []
		for s in range(GameSettings.player_count):
			if GameSettings.tower_team_of(s, variant) == side:
				crew.append(s)
		tower.members = crew
		vp.add_child(tower)
		towers.append(tower)
		viewports.append(vp)
		dropped_out.append(false)
		done.append(false)
	get_tree().root.size_changed.connect(_on_window_resized)

# One tower per team: two in the team race, one per player in the solo one.
func _tower_count() -> int:
	var n := 0
	for s in range(GameSettings.player_count):
		n = maxi(n, GameSettings.tower_team_of(s, variant) + 1)
	return maxi(1, n)

# The window's real pixels behind `logical` — see the header. At least the
# logical size, so a window smaller than 1500x800 is never rendered below it.
func _pixel_size(logical: Vector2) -> Vector2i:
	var s: float = maxf(1.0, get_tree().root.get_final_transform().get_scale().x)
	return Vector2i(ceili(logical.x * s), ceili(logical.y * s))

func _on_window_resized() -> void:
	for vp in viewports:
		vp.size = _pixel_size(Vector2(vp.size_2d_override))

func _process(delta: float) -> void:
	frame.queue_redraw()
	if _cup_leave_in > 0.0:
		_cup_leave_in -= delta
		if _cup_leave_in <= 0.0:
			_leave_for_cup()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	if over:
		if event.keycode == KEY_ENTER:
			if GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE:
				_leave_for_cup()
			else:
				_restart()
		return
	# Every tower hears every key; each only acts on its own builders' keys.
	for t in towers:
		t.handle_key(event)

func _restart() -> void:
	over = false
	winner = -1
	out_order = []
	overlay.visible = false
	var deal: int = _new_deal()
	for i in range(towers.size()):
		dropped_out[i] = false
		done[i] = false
		towers[i].brick_seed = deal
		towers[i]._start_match()

# Every tower gets the same bricks in the same order (TowerMode.brick_seed),
# and a fresh order every race. Never 0, which means "no deal".
func _new_deal() -> int:
	return (randi() & 0x7fffffff) | 1

func _still_racing(i: int) -> bool:
	return not dropped_out[i] and towers[i].state != "gameover"

# --- Called by the towers ---------------------------------------------------

# A hex cast on `from`, handed to a rival tower — the tallest, see the header
# — or to every rival, for a skill that `affects_all_opponents()`. Returns who
# it landed on.
func relay_hex(from, id: String, caster: int) -> Array[int]:
	var out: Array[int] = []
	var i: int = towers.find(from)
	if i < 0 or over:
		return out
	var probe: TowerSkill = TowerSkillCatalog.make(id, from, caster, caster)
	if probe == null:
		return out
	if probe.affects_all_opponents():
		for j in range(towers.size()):
			if j != i and _still_racing(j):
				out.append_array(towers[j].receive_hex(id, caster))
		return out
	var target: int = hex_target(i)
	if target >= 0:
		out = towers[target].receive_hex(id, caster)
	return out

# Which tower an ordinary hex from tower `from` lands on: the tallest rival
# still racing, ties to the next in seat order after the caster. -1 if none.
func hex_target(from: int) -> int:
	var best := -1
	for k in range(1, towers.size()):
		var j: int = (from + k) % towers.size()
		if not _still_racing(j):
			continue
		if best == -1 or towers[j]._height_cells() > towers[best]._height_cells() + 0.01:
			best = j
	return best

# A tower's match is decided — it reached the line, or ran out of lives. The
# line ends the race on the spot. Running out only ends it for that tower,
# unless that leaves one standing, which then wins.
func tower_finished(tower) -> void:
	if over:
		return
	var i: int = towers.find(tower)
	if i < 0:
		return
	if frame_round:
		_frame_finished(i)
		return
	if tower.winner_team >= 0:
		_declare(i, "%s reached the line first" % _name_of(i))
		return
	dropped_out[i] = true
	out_order.append(i)
	tower.halt()
	var left: Array[int] = []
	for j in range(towers.size()):
		if not dropped_out[j]:
			left.append(j)
	if left.size() == 1:
		var why: String = "%s ran out of lives" % _name_of(i) if towers.size() == 2 else "%s is the last one standing" % _name_of(left[0])
		_declare(left[0], why)
	elif left.is_empty():
		_declare(-1, "everybody ran out of lives")

# FRAME: one tower has laid its last brick. It stops where it is (halt() is
# what keeps its own end-of-match from reporting a second time), and once the
# last tower is in, the best fit wins — level fits (to the percent, as shown)
# are a draw for 1st, which a cup pays as a shared place.
func _frame_finished(i: int) -> void:
	if done[i]:
		return
	done[i] = true
	towers[i].halt()
	if done.has(false):
		return
	var order: Array[int] = placements()
	var best: int = order[0]
	var level: int = 0
	for j in order:
		if towers[j].frame_pct() == towers[best].frame_pct():
			level += 1
	if level > 1:
		_declare(-1, "a dead heat at %d%% fit" % towers[best].frame_pct())
	else:
		_declare(best, "the best fit, %d%%" % towers[best].frame_pct())

func _declare(won: int, why: String) -> void:
	over = true
	winner = won
	for t in towers:
		t.halt()
	overlay_title.text = ("IT'S A DRAW" if frame_round else "NOBODY WINS") if won < 0 else "%s WINS" % _name_of(won)
	var lines: Array[String] = [why, ""]
	for t in towers:
		lines.append(t.team_summary())
	overlay_body.text = "\n".join(lines)
	if frame_round:
		overlay_hint.text = "ENTER to play again      ESC for the menu"
	if GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE:
		var order: Array[int] = placements()
		GameSettings.cup_record(order, placement_places(order))
		overlay_hint.text = "ENTER for the trophies      ESC for the menu"
		_cup_leave_in = towers[0].CUP_RESULT_HOLD if not towers.is_empty() else 3.0
	overlay.visible = true

# The towers from 1st to last, for a cup — tower i is team i, which in the
# solo race is player i. The winner first; then whoever was still building
# when the line was crossed, tallest first (lives left breaks a tie, then
# seat order), since being in the race at the end beats having left it; then
# the drop-outs, the last one out highest.
func placements() -> Array[int]:
	if frame_round:
		# Best fit first; a level fit goes to the earlier seat in the order,
		# and placement_places() gives the two the same place.
		var by_fit: Array[int] = []
		for j in range(towers.size()):
			by_fit.append(j)
		by_fit.sort_custom(func(a: int, b: int) -> bool:
			var fa: int = towers[a].frame_pct()
			var fb: int = towers[b].frame_pct()
			return fa > fb or (fa == fb and a < b))
		return by_fit
	var order: Array[int] = []
	if winner >= 0:
		order.append(winner)
	var racing: Array[int] = []
	for j in range(towers.size()):
		if j != winner and not dropped_out[j]:
			racing.append(j)
	racing.sort_custom(func(a: int, b: int) -> bool:
		var ha: float = towers[a]._height_cells()
		var hb: float = towers[b]._height_cells()
		if absf(ha - hb) > 0.01:
			return ha > hb
		var la: int = towers[a].lives[a]
		var lb: int = towers[b].lives[b]
		return la > lb or (la == lb and a < b))
	order.append_array(racing)
	for k in range(out_order.size() - 1, -1, -1):
		if not order.has(out_order[k]):
			order.append(out_order[k])
	return order

# Each entry of placements()' 0-based place: its index, except in FRAME,
# where the same fit is the same place — 1st, 1st, 3rd.
func placement_places(order: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for k in range(order.size()):
		if frame_round and k > 0 and towers[order[k]].frame_pct() == towers[order[k - 1]].frame_pct():
			out.append(out[k - 1])
		else:
			out.append(k)
	return out

func _leave_for_cup() -> void:
	_cup_leave_in = 0.0
	get_tree().change_scene_to_file(towers[0].CUP_SCENE if not towers.is_empty() else "res://scenes/TowerCup.tscn")

func _name_of(i: int) -> String:
	return GameSettings.tower_team_name(i, variant)

# --- The frame: dividers, progress bars, and who has dropped out --------------

func _draw_frame() -> void:
	var n: int = towers.size()
	if n == 0:
		return
	var h: float = size.y
	var seam: float = SEAM_W_TWO if n == 2 else SEAM_W_MORE
	for k in range(1, n):
		var x: float = view_w * float(k)
		frame.draw_rect(Rect2(x - seam * 0.5, 0.0, seam, h), SEAM_BG, true)

	var font: Font = ThemeDB.fallback_font
	var goal: float = towers[0].goal_cells
	for i in range(n):
		var t = towers[i]
		var x0: float = view_w * float(i)
		if dropped_out[i] and not over:
			frame.draw_rect(Rect2(x0, 0.0, view_w, h), OUT_DIM, true)
			frame.draw_string(font, Vector2(x0, h * 0.5), "%s OUT" % _name_of(i),
				HORIZONTAL_ALIGNMENT_CENTER, view_w, 30, OUT_TEXT)
		if frame_round:
			_draw_fit_bar(i, x0, h)
			continue
		if goal <= 0.0:
			continue
		var bx: float = x0 + BAR_MARGIN
		var bw: float = view_w - BAR_MARGIN * 2.0 - 52.0
		var by: float = h - BAR_UP
		frame.draw_rect(Rect2(bx - 6.0, by - 8.0, view_w - BAR_MARGIN * 2.0 + 12.0, BAR_H + 16.0), BAR_PLATE, true)
		frame.draw_rect(Rect2(bx, by, bw, BAR_H), BAR_EMPTY, true)
		var frac: float = clampf(t._height_cells() / goal, 0.0, 1.0)
		frame.draw_rect(Rect2(bx, by, bw * frac, BAR_H), t._team_color(i), true)
		frame.draw_rect(Rect2(bx + bw - 2.0, by - 3.0, 3.0, BAR_H + 6.0), t.GOAL_COLOR, true)
		frame.draw_string(font, Vector2(bx + bw + 8.0, by + BAR_H), "%d / %d" % [int(round(t._height_cells())), int(goal)],
			HORIZONTAL_ALIGNMENT_LEFT, 52.0, 13, Color(1.0, 1.0, 1.0, 0.9))

# FRAME's bar: the fit so far, out of 100%, in the same place and on the same
# baseline as the race's progress bar — over it, how many bricks are left, or
# a DONE tag on a tower that has laid its last brick and is waiting for the
# others.
func _draw_fit_bar(i: int, x0: float, h: float) -> void:
	var t = towers[i]
	var font: Font = ThemeDB.fallback_font
	var bx: float = x0 + BAR_MARGIN
	var bw: float = view_w - BAR_MARGIN * 2.0 - 52.0
	var by: float = h - BAR_UP
	frame.draw_rect(Rect2(bx - 6.0, by - 8.0, view_w - BAR_MARGIN * 2.0 + 12.0, BAR_H + 16.0), BAR_PLATE, true)
	frame.draw_rect(Rect2(bx, by, bw, BAR_H), BAR_EMPTY, true)
	frame.draw_rect(Rect2(bx, by, bw * clampf(t.frame_score, 0.0, 1.0), BAR_H), t._team_color(i), true)
	frame.draw_string(font, Vector2(bx + bw + 8.0, by + BAR_H), "%d%%" % t.frame_pct(),
		HORIZONTAL_ALIGNMENT_LEFT, 52.0, 13, Color(1.0, 1.0, 1.0, 0.9))
	if done[i] and not over:
		frame.draw_string(font, Vector2(x0, by - 18.0), "DONE — waiting for the others",
			HORIZONTAL_ALIGNMENT_CENTER, view_w, 15, Color(1.0, 1.0, 1.0, 0.85))
	elif not over:
		# The round is a fixed number of bricks, so how many are left is said
		# outright, where the fit is, rather than only in the HUD's small print.
		var left: int = maxi(0, t.FRAME_BRICKS - t.bricks_placed)
		frame.draw_string(font, Vector2(x0, by - 18.0), "%d %s LEFT" % [left, "BRICK" if left == 1 else "BRICKS"],
			HORIZONTAL_ALIGNMENT_CENTER, view_w, 15, Color(1.0, 1.0, 1.0, 0.85))
