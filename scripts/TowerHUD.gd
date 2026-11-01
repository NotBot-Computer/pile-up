extends Control
class_name TowerHUD

## Pile Up's heads-up display: one card per player (colour, name, lives), the
## next brick, the controls for whoever is on the clock, and the transient
## "-1 LIFE" toast.
##
## Lives are the whole state of a Pile Up match, and on a shared tower they
## are the only thing on screen that says who is who — every landed brick
## looks the same regardless of who dropped it, by design. So this is drawn
## rather than laid out with Labels: TowerMode pushes its state into the
## fields below and calls queue_redraw(), same pattern as PlayerBoard's own
## _draw()-based bars.
##
## ## Why the lives are hearts and not circles
##
## They used to be flat filled/hollow circles, drawn here, while Don't Crash
## trailed the user's pixel-art heart behind each car. Two modes off one menu,
## sharing a colour per player and a countdown, drawing the same fact two
## different ways: a player who has just come from the other mode has to learn
## a second symbol for "a life" on a screen where lives are the entire score.
## The pip is now the same art through `HeartPips` — same PNG, same per-player
## recolour, same swell-and-fade when one is spent — and the only thing this
## file decides is how big it is drawn and where it sits.
##
## Drawn, not tweened: this HUD has no Sprite2D to hang a Tween on, so the
## spent pip is interpolated by hand in _draw() off `_loss_timer`. Both halves
## of that gesture (`HeartPips.LOSS_POP`, `loss_pose`) come out of the shared
## file precisely so "by hand" cannot quietly become "differently".
##
## ## Why it lives in the side columns
##
## The playfield is inherently a tall narrow shaft — a tower is five cells
## wide — while the viewport is 1500x800. Laid out as a strip across the top
## (the first version) the HUD left roughly 600px of empty background down
## each side and also squeezed the drop zone, forcing the held brick low
## enough that a vertical I piece collided with the player cards. Moving the
## panels into the columns the tower was never going to use fixes both at
## once: the dead space carries something worth reading, and the entire top
## of the screen goes back to being drop headroom.

const COL_W := 224.0
const COL_MARGIN := 24.0

const CARD_H := 74.0
const CARD_GAP := 10.0
const CARDS_Y := 96.0
const STRIPE_W := 6.0

# The pip is square art (18x18), so PIP_H is its width too. It is drawn a
# little larger than the 14px circles it replaces because a heart is a shape
# and a dot is not: the outline and the highlight are what make it read as a
# heart rather than as a blob, and both need room. PIP_GAP is centre to
# centre — slots are fixed, exactly as they are behind the car, so a spent pip
# leaves its gap behind instead of the row re-centring on what is left.
const PIP_H := 20.0
const PIP_GAP := 24.0
const PIP_ROW_UP := 22.0 # centre of the row, up from the bottom edge of a card
# A spent slot keeps a ghost of its own pip rather than going blank. Don't
# Crash can afford blank — the row sits under a car the player is already
# watching and its length is obvious — but a HUD card read from across the
# room needs to say "two of three", not "two".
const PIP_EMPTY_ALPHA := 0.22

const NEXT_H := 124.0
const PANEL_PAD := 14.0

# Team layout. A team's lives are one shared pool, so they are drawn once, on
# a header above the team's cards, rather than repeated on every member's
# card as if each had their own — which is the misreading a shared pool most
# invites. The cards under a header lose their pip row and get shorter for it.
const TEAM_HEAD_H := 54.0
const TEAM_CARD_H := 58.0
const TEAM_GAP := 12.0 # between one team's last card and the next team's header

# The compact layout, for a view too narrow for two side columns — each tower
# of a three- or four-player race gets 500 or 375px. Everything moves into one
# strip across the top (name, lives, charge, skills, next brick) with two
# short lines of keys and the incoming hexes under it. The strip is drop
# headroom the full layout deliberately keeps clear (a banner there once hit a
# vertical I), and it is affordable here only because a race tower's camera is
# pulled back to RACE_VISIBLE_CELLS: the tallest brick spawns with its top
# edge at about y=160 in the climbing shot, below the hex line's ~150.
const COMPACT_BELOW := 700.0
const STRIP_PAD := 8.0
const STRIP_H := 76.0
const STRIP_NEXT_W := 64.0

# The two skill slots on a card, right-hand side: a self slot and an opponent
# slot, each a small square the glyph sits in, with the cast key under it.
# The disc colours are Don't Crash's own (SKILL_ART_BRIEF: self on green,
# opponent on red) so a player coming from the other mode reads them cold.
const SLOT_SIZE := 28.0
const SLOT_GAP := 8.0
const SLOT_EMPTY := Color(1.0, 1.0, 1.0, 0.10)
const SLOT_SELF := Color(0.32, 0.82, 0.42, 0.95)
const SLOT_OPPONENT := Color(0.92, 0.28, 0.28, 0.95)
const SLOT_RING := Color(1.0, 1.0, 1.0, 0.85)
# The charge bar runs along the top edge of the card in the player's colour,
# in CHARGE_TO_SKILL segments so "one more clean drop" is readable at a glance.
const CHARGE_H := 3.0
const CHARGE_EMPTY := Color(1.0, 1.0, 1.0, 0.10)
const TAG_TEXT := Color(1.0, 0.86, 0.45, 0.95)
const HEX_TEXT := Color(1.0, 1.0, 1.0, 0.82)

const MESSAGE_HOLD := 1.6
const MESSAGE_FADE := 0.7

# Panels are dark plates, not white washes. They sit over a bright pixel-art
# sky now (TowerBackground), and the first version's white-at-5%-alpha fills
# were invisible against it — a HUD that only exists on a dark background is
# a HUD that stops existing the moment the background changes.
const CARD_BG := Color(0.05, 0.06, 0.14, 0.62)
const CARD_BG_ACTIVE := Color(0.07, 0.08, 0.20, 0.86)
const PANEL_BG := Color(0.05, 0.06, 0.14, 0.62)
const DIM_TEXT := Color(1.0, 1.0, 1.0, 0.72)
const LABEL_TEXT := Color(1.0, 1.0, 1.0, 0.5)
const OUT_TEXT := Color(1.0, 0.45, 0.42, 0.85)
# Backing plate for the centred toast, which has no panel of its own.
const MESSAGE_BG := Color(0.05, 0.06, 0.14, 0.72)

var slots: Array[Dictionary] = [] # {name, color, team, lives, ...}, indexed by slot
# Empty in free-for-all, which draws one full card per slot in seat order.
# Otherwise one entry per team: {team, title, color, lives, slots: [slot...]},
# drawn as a header carrying the team's lives over its members' cards.
var groups: Array[Dictionary] = []
var subtitle: String = "one tower, three lives each"
var heading: String = "PILE UP" # the column's title; a cup round names itself here
var max_lives: int = 3
var active_slot: int = 0
var crew_mate: int = -1 # co-pilot: the other half of the crew on the clock
var next_mate: int = -1 # co-pilot: the other half of the crew that is up next
var waiting: bool = false # true between the drop and the next turn, when nobody is on the clock
# Who the baton is passing to, set alongside `waiting`. The banner used to
# read "settling..." through the whole hand-off, which is a word the player
# cannot act on and which made every gap between turns read as the game
# stopping. Naming the next player instead turns the same gap into a hand-off
# they can see coming — the tower resolving is already visible on screen and
# does not need captioning.
var next_slot: int = 0
var next_index: int = 0
var controls: String = ""
# Skills. charge_max is TowerMode.CHARGE_TO_SKILL; each slot dict also carries
# charge / held_self / held_opponent / cast_label / tags (see _refresh_hud).
# `hexes` are opponent skills cast and waiting for their target's turn —
# listed under the banner so the whole table can see what is coming.
var charge_max: int = 2
var hexes: Array[Dictionary] = [] # {title, from, to, color}
# False in co-op: there is nobody on the tower to hex, so nobody is ever
# granted one, and an empty red slot with a key under it would advertise a
# button that does nothing.
var hex_slot: bool = true

var _message: String = ""
var _message_color: Color = Color.WHITE
var _message_timer: float = 0.0

# The pip currently on its way out, if any. One at a time is enough: only the
# team that just dropped can lose a life, and the next turn is a whole
# settle, a pause and a descent away — longer than HeartPips.LOSS_TOTAL.
# Keyed by team, which in free-for-all is the player's own slot.
var _loss_team: int = -1
var _loss_pip: int = -1
var _loss_timer: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func show_message(text: String, color: Color) -> void:
	_message = text
	_message_color = color
	_message_timer = MESSAGE_HOLD + MESSAGE_FADE

func clear_message() -> void:
	_message = ""
	_message_timer = 0.0

## `team` has just lost a life, and `pip_index` is the pip it spent — which is
## the life count that is *left*, since the row fills from the left. Called
## with the count already decremented, same as PlayerBoard._spend_heart().
## In free-for-all a team is one player and its index is their slot.
func spend_life(team: int, pip_index: int) -> void:
	_loss_team = team
	_loss_pip = pip_index
	_loss_timer = HeartPips.LOSS_TOTAL

## Everything transient, cleared. A new match reuses this node, and a pip left
## mid-pop from the last one would play out over a fresh row of three.
func reset() -> void:
	clear_message()
	_loss_team = -1
	_loss_pip = -1
	_loss_timer = 0.0

func tick(delta: float) -> void:
	var animating := false
	if _message_timer > 0.0:
		_message_timer = maxf(0.0, _message_timer - delta)
		animating = true
	if _loss_timer > 0.0:
		_loss_timer = maxf(0.0, _loss_timer - delta)
		animating = true
	if animating:
		queue_redraw()

func is_compact() -> bool:
	return size.x > 0.0 and size.x < COMPACT_BELOW

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	if is_compact():
		_draw_compact(font)
		_draw_message(font)
		return
	var right_x: float = size.x - COL_MARGIN - COL_W

	draw_rect(Rect2(COL_MARGIN - 10.0, 16.0, COL_W + 20.0, 62.0), PANEL_BG, true)
	# Shrunk to fit like the toast: "TEAM CUP · ROUND 4" is wider than the
	# column at the size "PILE UP" is drawn at.
	var head_size: int = 26
	while head_size > 14 and font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, head_size).x > COL_W:
		head_size -= 2
	draw_string(font, Vector2(COL_MARGIN, 44.0), heading, HORIZONTAL_ALIGNMENT_LEFT, COL_W, head_size, Color(1, 1, 1, 0.95))
	draw_string(font, Vector2(COL_MARGIN, 66.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, COL_W, 13, LABEL_TEXT)

	var bottom: float = _draw_column(font)
	_draw_next(font, right_x)
	_draw_controls(font, right_x)
	_draw_turn_banner(font, bottom)
	_draw_hexes(font, bottom)
	_draw_message(font)

# The left column: one card per player in free-for-all, or a header per team
# with its members' cards under it. Returns the y the column ends at, which
# the banner and the hex list stack under.
func _draw_column(font: Font) -> float:
	var y: float = CARDS_Y
	if groups.is_empty():
		for i in range(slots.size()):
			_draw_card(font, i, y, CARD_H, true)
			y += CARD_H + CARD_GAP
		return y
	for g: Dictionary in groups:
		if g.get("plain", false):
			for s: int in g["slots"]:
				_draw_card(font, s, y, CARD_H, true)
				y += CARD_H + CARD_GAP
			continue
		_draw_team_head(font, g, y)
		y += TEAM_HEAD_H + 4.0
		for s: int in g["slots"]:
			_draw_card(font, s, y, TEAM_CARD_H, false)
			y += TEAM_CARD_H + 4.0
		y += TEAM_GAP
	return y

# The whole HUD as one strip across the top of a narrow view — see
# COMPACT_BELOW. Drawn for the player on the clock: in the only variant that
# goes compact (the solo race, three or four towers) a tower has exactly one.
func _draw_compact(font: Font) -> void:
	if slots.is_empty():
		return
	var i: int = clampi(active_slot, 0, slots.size() - 1)
	var slot: Dictionary = slots[i]
	var color: Color = slot["color"]
	var alive: bool = int(slot["lives"]) > 0
	var x0: float = STRIP_PAD
	var w: float = size.x - STRIP_PAD * 2.0
	var y0: float = STRIP_PAD
	draw_rect(Rect2(x0, y0, w, STRIP_H), CARD_BG_ACTIVE if alive and not waiting else CARD_BG, true)
	draw_rect(Rect2(x0, y0, STRIPE_W, STRIP_H), color if alive else Color(color.r, color.g, color.b, 0.25), true)

	var tx: float = x0 + STRIPE_W + PANEL_PAD
	draw_string(font, Vector2(tx, y0 + 28.0), slot["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE if alive else OUT_TEXT)
	if not alive:
		draw_string(font, Vector2(tx + 48.0, y0 + 28.0), "OUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, OUT_TEXT)
	elif not slot.get("tags", []).is_empty():
		var tags: Array = slot["tags"]
		draw_string(font, Vector2(tx + 48.0, y0 + 28.0), " · ".join(tags), HORIZONTAL_ALIGNMENT_LEFT, 90.0, 12, TAG_TEXT)
	_draw_pips(tx, y0 + STRIP_H - 20.0, color, int(slot["lives"]), int(slot.get("team", i)))

	# The next brick in its own small box at the strip's right end, the skill
	# slots just left of it.
	var nb := Rect2(x0 + w - STRIP_NEXT_W - 6.0, y0 + 6.0, STRIP_NEXT_W, STRIP_H - 12.0)
	draw_rect(nb, PANEL_BG, true)
	var data: Dictionary = GameSettings.BRICKS[next_index]
	var tex: Texture2D = data["texture"]
	var tex_size: Vector2 = tex.get_size()
	var avail: Vector2 = nb.size - Vector2(12.0, 12.0)
	var s: float = minf(avail.x / tex_size.x, avail.y / tex_size.y)
	var draw_size: Vector2 = tex_size * s
	draw_texture_rect(tex, Rect2(nb.get_center() - draw_size * 0.5, draw_size), false, Color(1.0, 1.0, 1.0, 0.95))
	var bc: Color = data["color"]
	draw_rect(Rect2(nb.position.x, nb.end.y - 3.0, nb.size.x, 3.0), Color(bc.r, bc.g, bc.b, 0.85), true)
	if alive:
		_draw_charge(slot, x0 + STRIPE_W, w - STRIPE_W, y0, color)
		_draw_slots(font, slot, nb.position.x - 10.0, y0, STRIP_H)

	# Two short lines of keys, then whatever is on its way here. Indented past
	# the race's divider, which covers the outer 6px of each view, and on a
	# dark plate: light text straight on the backdrop vanishes into its clouds.
	var y: float = y0 + STRIP_H + 16.0
	var key_lines: int = controls.split("\n").size() if controls != "" else 0
	var lines: int = key_lines + hexes.size()
	if lines > 0:
		draw_rect(Rect2(x0, y0 + STRIP_H + 2.0, w, 6.0 + 15.5 * float(lines)), PANEL_BG, true)
	if controls != "":
		for part: String in controls.split("\n"):
			draw_string(font, Vector2(x0 + STRIPE_W + 4.0, y), part, HORIZONTAL_ALIGNMENT_LEFT, w, 12, DIM_TEXT)
			y += 15.0
	for h: Dictionary in hexes:
		var c: Color = h["color"]
		draw_rect(Rect2(x0, y - 11.0, STRIPE_W, 14.0), c, true)
		draw_string(font, Vector2(x0 + STRIPE_W + 6.0, y), "%s from %s" % [h["title"], h["from"]],
			HORIZONTAL_ALIGNMENT_LEFT, w, 12, HEX_TEXT)
		y += 16.0

# The team's name and its one row of lives — the pool both members spend.
func _draw_team_head(font: Font, g: Dictionary, y: float) -> void:
	var color: Color = g["color"]
	var alive: bool = int(g["lives"]) > 0
	draw_rect(Rect2(COL_MARGIN, y, COL_W, TEAM_HEAD_H), PANEL_BG, true)
	draw_rect(Rect2(COL_MARGIN, y + TEAM_HEAD_H - 3.0, COL_W, 3.0), Color(color.r, color.g, color.b, 0.85 if alive else 0.25), true)
	var tx: float = COL_MARGIN + PANEL_PAD
	draw_string(font, Vector2(tx, y + 20.0), g["title"], HORIZONTAL_ALIGNMENT_LEFT, COL_W, 15,
		Color(color.r, color.g, color.b, 1.0) if alive else OUT_TEXT)
	if not alive:
		draw_string(font, Vector2(tx + 120.0, y + 20.0), "OUT", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 15, OUT_TEXT)
	_draw_pips(tx, y + TEAM_HEAD_H - 17.0, color, int(g["lives"]), int(g["team"]))

func _draw_card(font: Font, i: int, y: float, h: float, with_pips: bool) -> void:
	var slot: Dictionary = slots[i]
	var color: Color = slot["color"]
	var alive: bool = slot["lives"] > 0
	var is_active: bool = (i == active_slot or i == crew_mate) and alive and not waiting

	var box := Rect2(COL_MARGIN, y, COL_W, h)
	draw_rect(box, CARD_BG_ACTIVE if is_active else CARD_BG, true)
	if is_active:
		draw_rect(box, Color(color.r, color.g, color.b, 0.9), false, 2.0)
	draw_rect(
		Rect2(COL_MARGIN, y, STRIPE_W, h),
		color if alive else Color(color.r, color.g, color.b, 0.25), true
	)

	var tx: float = COL_MARGIN + STRIPE_W + PANEL_PAD
	var name_y: float = y + (30.0 if with_pips else 34.0)
	draw_string(
		font, Vector2(tx, name_y), slot["name"], HORIZONTAL_ALIGNMENT_LEFT, COL_W, 20,
		Color.WHITE if alive else OUT_TEXT
	)
	if not alive:
		draw_string(font, Vector2(tx + 48.0, name_y), "OUT", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 15, OUT_TEXT)
	elif not slot.get("tags", []).is_empty():
		# What is being done to this player right now, in the skill's own
		# word. One fits between the name and the slots; more than one is
		# joined and clipped, which is the honest amount of room there is.
		var tags: Array = slot["tags"]
		draw_string(font, Vector2(tx + 48.0, name_y), " · ".join(tags), HORIZONTAL_ALIGNMENT_LEFT, 74.0, 12, TAG_TEXT)

	if alive:
		_draw_charge(slot, COL_MARGIN + STRIPE_W, COL_W - STRIPE_W, y, color)
		_draw_slots(font, slot, COL_MARGIN + COL_W - PANEL_PAD, y, h)

	# A team card has no pips: its lives are the team's, on the header above.
	if with_pips:
		_draw_pips(tx, y + h - PIP_ROW_UP, color, int(slot["lives"]), int(slot.get("team", i)))

# Lives as pips rather than a number — from across a couch, "two left"
# should not need reading. The pip is Don't Crash's heart, re-hued into the
# owner's colour by the same rule (HeartPips), so the two modes spell a life
# the same way. `x` is the left edge of the row, `pip_y` its centre line.
func _draw_pips(x: float, pip_y: float, color: Color, have: int, team: int) -> void:
	var pip: Vector2 = HeartPips.size_at(PIP_H)
	var pip_tex: Texture2D = HeartPips.tinted(color)
	for h in range(max_lives):
		var c := Vector2(x + pip.x * 0.5 + float(h) * PIP_GAP, pip_y)
		if h < have:
			_draw_pip(pip_tex, c, pip, 1.0, 1.0)
		elif h == _loss_pip and team == _loss_team and _loss_timer > 0.0:
			# The one just spent: it blinks, then swells out of its slot as it
			# fades — so it is seen to leave rather than being absent the next
			# time anyone happens to look at the card.
			var pose: Vector2 = HeartPips.loss_pose(HeartPips.LOSS_TOTAL - _loss_timer)
			_draw_pip(pip_tex, c, pip, pose.x, pose.y)
		else:
			_draw_pip(pip_tex, c, pip, 1.0, PIP_EMPTY_ALPHA)

# Centred on `at`, because the loss pop scales about the pip's own middle and
# a rect anchored by its corner would slide the pip down and right as it grew.
func _draw_pip(tex: Texture2D, at: Vector2, base: Vector2, scale_mult: float, alpha: float) -> void:
	var pip: Vector2 = base * scale_mult
	draw_texture_rect(tex, Rect2(at - pip * 0.5, pip), false, Color(1.0, 1.0, 1.0, alpha))

# Clean placements toward the next skill, as segments along the card's top
# edge. Inside the card rather than a bar of its own: it is a minor readout
# and the card is already the thing a player's eye goes to for their state.
#
# A charge_max of 0 means the round has no skills (FRAME), and then neither
# the bar nor the two slots are drawn.
func _draw_charge(slot: Dictionary, x0: float, w: float, y: float, color: Color) -> void:
	if charge_max <= 0:
		return
	var n: int = maxi(1, charge_max)
	var have: int = int(slot.get("charge", 0))
	var seg: float = (w - float(n - 1) * 2.0) / float(n)
	for i in range(n):
		var r := Rect2(x0 + float(i) * (seg + 2.0), y + 2.0, seg, CHARGE_H)
		draw_rect(r, Color(color.r, color.g, color.b, 0.9) if i < have else CHARGE_EMPTY, true)

# The two skill slots, side by side and ending at `right`, with their cast
# keys underneath. An empty slot is a faint square so the space reads as
# "nothing here yet" rather than as nothing; a full one is the glyph on its
# disc.
func _draw_slots(font: Font, slot: Dictionary, right: float, y: float, h: float) -> void:
	if charge_max <= 0:
		return
	var sy: float = y + (h - SLOT_SIZE) * 0.5 - 4.0
	var keys: PackedStringArray = str(slot.get("cast_label", "")).split("/")
	var entries := [
		[right - SLOT_SIZE * 2.0 - SLOT_GAP, slot.get("held_self", ""), SLOT_SELF, keys[0].strip_edges() if keys.size() > 0 else ""],
		[right - SLOT_SIZE, slot.get("held_opponent", ""), SLOT_OPPONENT, keys[1].strip_edges() if keys.size() > 1 else ""],
	]
	if not hex_slot:
		entries = [[right - SLOT_SIZE, slot.get("held_self", ""), SLOT_SELF, keys[0].strip_edges() if keys.size() > 0 else ""]]
	for entry in entries:
		var sx: float = entry[0]
		var id: String = entry[1]
		var disc: Color = entry[2]
		var key: String = entry[3]
		var box := Rect2(sx, sy, SLOT_SIZE, SLOT_SIZE)
		if id == "":
			draw_rect(box, SLOT_EMPTY, false, 1.0)
		else:
			var c: Vector2 = box.get_center()
			draw_circle(c, SLOT_SIZE * 0.5, disc)
			draw_arc(c, SLOT_SIZE * 0.5 - 0.5, 0.0, TAU, 24, SLOT_RING, 1.5)
			var glyph: Texture2D = TowerSkillCatalog.glyph_of(id)
			if glyph != null:
				var g: float = SLOT_SIZE * 0.68
				draw_texture_rect(glyph, Rect2(c - Vector2(g, g) * 0.5, Vector2(g, g)), false)
		draw_string(font, Vector2(sx, sy + SLOT_SIZE + 12.0), key, HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE, 10, LABEL_TEXT)


func _draw_next(font: Font, x: float) -> void:
	var data: Dictionary = GameSettings.BRICKS[next_index]
	var tex: Texture2D = data["texture"]
	var color: Color = data["color"]

	draw_rect(Rect2(x, CARDS_Y, COL_W, NEXT_H), PANEL_BG, true)
	draw_string(font, Vector2(x + PANEL_PAD, CARDS_Y + 24.0), "NEXT BRICK", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 14, LABEL_TEXT)

	# Fit inside the panel without distorting it — the sprites run from 3:2 to
	# 1:5, so a single flat scale would clip half of them.
	var avail := Vector2(COL_W - PANEL_PAD * 2.0, NEXT_H - 52.0)
	var tex_size: Vector2 = tex.get_size()
	var s: float = minf(avail.x / tex_size.x, avail.y / tex_size.y)
	var draw_size: Vector2 = tex_size * s
	var at := Vector2(x + (COL_W - draw_size.x) * 0.5, CARDS_Y + 38.0 + (avail.y - draw_size.y) * 0.5)
	draw_texture_rect(tex, Rect2(at, draw_size), false, Color(1.0, 1.0, 1.0, 0.95))
	draw_rect(Rect2(x, CARDS_Y + NEXT_H - 3.0, COL_W, 3.0), Color(color.r, color.g, color.b, 0.85), true)

func _draw_controls(font: Font, x: float) -> void:
	if controls == "" or slots.is_empty():
		return
	var y: float = CARDS_Y + NEXT_H + 26.0
	var lines: int = controls.split("\n").size()
	draw_rect(Rect2(x, y - 24.0, COL_W, 44.0 + 22.0 * float(lines)), PANEL_BG, true)
	draw_string(font, Vector2(x + PANEL_PAD, y), "YOUR KEYS", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 14, LABEL_TEXT)
	# One line per action: the column is too narrow for the single-line form,
	# and this is the only place a player can look up their own bindings.
	var line: float = y + 26.0
	for part: String in controls.split("\n"):
		draw_string(font, Vector2(x + PANEL_PAD, line), part, HORIZONTAL_ALIGNMENT_LEFT, COL_W, 15, DIM_TEXT)
		line += 22.0

# Deliberately in the left column rather than across the top centre: that
# strip is the descending brick's headroom now, and a banner there collided
# with a vertical I piece. In co-pilot it names the whole crew, at a size
# that fits two names in the column.
func _draw_turn_banner(font: Font, bottom: float) -> void:
	if slots.is_empty():
		return
	var y: float = bottom + 20.0
	draw_rect(Rect2(COL_MARGIN, y - 24.0, COL_W, 36.0), PANEL_BG, true)
	if waiting:
		var up: Dictionary = slots[clampi(next_slot, 0, slots.size() - 1)]
		var who: String = up["name"]
		if next_mate >= 0 and next_mate < slots.size():
			who = "%s + %s" % [up["name"], slots[next_mate]["name"]]
		draw_string(
			font, Vector2(COL_MARGIN + PANEL_PAD, y), "%s — GET READY" % who,
			HORIZONTAL_ALIGNMENT_LEFT, COL_W, 16 if next_mate >= 0 else 18,
			Color(up["color"].r, up["color"].g, up["color"].b, 0.75)
		)
		return
	var slot: Dictionary = slots[active_slot]
	var text: String = "%s — YOUR BRICK" % slot["name"]
	if crew_mate >= 0 and crew_mate < slots.size():
		text = "%s + %s — YOUR BRICK" % [slot["name"], slots[crew_mate]["name"]]
	draw_string(
		font, Vector2(COL_MARGIN + PANEL_PAD, y), text,
		HORIZONTAL_ALIGNMENT_LEFT, COL_W, 17 if crew_mate >= 0 else 20, slot["color"]
	)

# Opponent skills in flight: cast, and waiting for their target's next turn.
# Under the banner, so the player about to receive one sees it coming while
# they wait — a hex nobody could see would just read as the game glitching.
func _draw_hexes(font: Font, bottom: float) -> void:
	if hexes.is_empty() or slots.is_empty():
		return
	var y: float = bottom + 20.0 + 24.0
	draw_rect(Rect2(COL_MARGIN, y, COL_W, 10.0 + 20.0 * float(hexes.size())), PANEL_BG, true)
	var line: float = y + 18.0
	for h: Dictionary in hexes:
		var c: Color = h["color"]
		draw_rect(Rect2(COL_MARGIN, line - 12.0, STRIPE_W, 16.0), c, true)
		draw_string(font, Vector2(COL_MARGIN + PANEL_PAD, line), "%s → %s   %s" % [h["from"], h["to"], h["title"]],
			HORIZONTAL_ALIGNMENT_LEFT, COL_W - PANEL_PAD, 13, HEX_TEXT)
		line += 20.0

func _draw_message(font: Font) -> void:
	if _message_timer <= 0.0 or _message == "":
		return
	var a: float = clampf(_message_timer / MESSAGE_FADE, 0.0, 1.0)
	var c := Color(_message_color.r, _message_color.g, _message_color.b, a)
	var y: float = size.y * 0.5 - 30.0
	draw_rect(
		Rect2(0.0, y - 34.0, size.x, 52.0),
		Color(MESSAGE_BG.r, MESSAGE_BG.g, MESSAGE_BG.b, MESSAGE_BG.a * a), true
	)
	# At 32 the longest toasts are ~700px, which is wider than a race tower.
	# Shrunk to fit rather than wrapped: a two-line toast covers the brick.
	var font_size: int = 32
	while font_size > 14 and font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 16.0:
		font_size -= 2
	draw_string(font, Vector2(0.0, y), _message, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, c)
