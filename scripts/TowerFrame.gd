extends RefCounted

## FRAME, Pile Up's shape-matching mode: an outline on the platform, and the
## bricks to fill it. This file is the two halves of that which are pure
## arithmetic — making a frame, and marking a tower against one — so that
## TowerMode only has to carry them, and a probe can call them directly.
##
## ## Where a frame comes from
##
## It is built out of the very bricks the players are about to be dealt. The
## deal is a seed (TowerMode.brick_seed, the same on every tower of a
## TowerRace), so this draws the first `count` bricks from that seed exactly
## the way TowerMode._next_brick() will, and stacks them Tetris-fashion into
## a tidy pile on a grid as wide as the platform: each brick, in deal order,
## tried in every rotation at every column, dropped straight down, and the
## best-looking landing taken. The pile's cells are the frame.
##
## So every frame is solvable by construction, with exactly the bricks dealt,
## in the order dealt — nobody is ever asked for a shape the deal cannot make.
## And the answer is reachable with the keyboard: a brick moves on a half-cell
## lattice from x = 0, and every landing here puts a brick's centre on that
## lattice (an odd-width brick centres on a whole cell, an even-width one on a
## half), so a player can line a brick up with the frame exactly.
##
## "Best-looking" is: no brick tipping under its own weight and whatever is
## stacked on it (the pile has to stand under real physics, not just on the
## grid — see _tipping),
## low and wide over tall and thin, flat over jagged, and few holes — plus a
## little noise, so the same bricks do not always make the same frame.
##
## Holes are discouraged, not forbidden. The deal is used in order, and some
## orders cannot avoid one (an S onto flat ground, exactly as in Tetris); a
## frame that refused would have to stack the S on end instead, which makes
## the tall, thin frames this used to make. A hole is harmless to the mode:
## it is a window in the frame, not part of it, and building to plan leaves
## the same window, since the plan only ever drops a brick straight down.
##
## ## How a tower is marked
##
## By area, sampled: SUB x SUB points per cell over the whole play column.
## A point inside a settled brick counts for you if it is inside the frame
## and against you if it is outside, and the mark is (inside - outside) over
## the frame's own area, floored at zero. A perfect build is 100%; covering
## the frame by burying it under a heap is not, which is the rule that was
## asked for (spill costs you). Bricks that fell are not on the tower and do
## not count either way; their area is simply missing from the frame.

const SUB := 4 # samples per cell, each way

# Landing score weights: lower is better.
const W_HOLE := 3.0 # per empty cell left under a brick
const W_TOPPLE := 100.0 # per brick of the pile that would tip (_tipping)
const W_HEIGHT := 4.0 # per row of the tallest column
const W_AGG := 0.6 # per row, summed over every column
const W_BUMP := 0.5 # per row of step between neighbouring columns
const W_NOISE := 2.0

# One brick drawn against `bias` (TowerMode.CLASSIC_BIAS), from a uniform
# `r` in [0, 1). TowerMode._next_brick() calls this too, so the frame's
# bricks and the dealt bricks are the same function of the same numbers.
static func pick_brick(r: float, bias: float) -> int:
	var total := 0.0
	for b: Dictionary in GameSettings.BRICKS:
		total += bias if b["classic"] else 1.0
	var pick: float = r * total
	for i in range(GameSettings.BRICKS.size()):
		pick -= bias if GameSettings.BRICKS[i]["classic"] else 1.0
		if pick < 0.0:
			return i
	return GameSettings.BRICKS.size() - 1

# A brick's cells turned `steps` quarter turns, the way TowerPiece turns:
# Godot's rotation, clockwise on screen with y pointing down. Returned with
# y down, shifted so the smallest x and y are 0.
static func turned_cells(index: int, steps: int) -> Array[Vector2i]:
	var data: Dictionary = GameSettings.BRICKS[index]
	var raw: Array[Vector2i] = []
	for b: Rect2 in data["boxes"]:
		for y in range(int(b.position.y), int(b.position.y + b.size.y)):
			for x in range(int(b.position.x), int(b.position.x + b.size.x)):
				raw.append(Vector2i(x, y))
	var out: Array[Vector2i] = []
	var min_x := 1 << 30
	var min_y := 1 << 30
	for c in raw:
		var v := Vector2i(c.x, c.y)
		for _k in range(posmod(steps, 4)):
			v = Vector2i(-v.y, v.x) # (x, y) -> (-y, x): +90 degrees, y down
		out.append(v)
		min_x = mini(min_x, v.x)
		min_y = mini(min_y, v.y)
	for i in range(out.size()):
		out[i] -= Vector2i(min_x, min_y)
	return out

static func _extent(cells: Array[Vector2i]) -> Vector2i:
	var e := Vector2i.ZERO
	for c in cells:
		e.x = maxi(e.x, c.x + 1)
		e.y = maxi(e.y, c.y + 1)
	return e

# A frame for the deal `seed`: {cells: {Vector2i(col, row): true}, plan:
# [{index, steps, col, row, w, h}]}. `col` counts from the platform's left
# edge, `row` up from its top; a plan entry's col/row is its bounding box's
# bottom-left cell. `cols` is the platform's width in cells.
#
# Built ATTEMPTS times with different noise and the best whole frame kept:
# one brick at a time, the best landing can still lead somewhere bad — a
# brick two later with nowhere to go but hung off an edge — and a frame with
# a brick that would tip over is not buildable under physics at all. Every
# attempt uses the same deal; only the choices differ. Still a pure function
# of `seed`, so every tower makes the same frame.
const ATTEMPTS := 3
const MAX_ATTEMPTS := 12
const Q_TOPPLE := 1000.0
const Q_HOLE := 7.0
const Q_HEIGHT := 9.0 # taller piles drift more under physics before the top is laid
const Q_BUMP := 1.0

# The last few frames made, by their arguments. Every tower of a round makes
# the same frame from the same deal, and a frame is tens of milliseconds of
# beam search, so the second to fourth tower are handed the first one's
# (read-only — TowerMode never writes to it). A static var as in HeartPips'
# texture cache: a pure function's results cannot go stale.
static var _memo: Dictionary = {}
const MEMO_SIZE := 8

static func generate(seed: int, count: int, cols: int, bias: float) -> Dictionary:
	var key: String = "%d:%d:%d:%s" % [seed, count, cols, bias]
	if _memo.has(key):
		return _memo[key]
	var made: Dictionary = build(seed, count, cols, bias)
	if _memo.size() >= MEMO_SIZE:
		_memo.clear()
	_memo[key] = made
	return made

# generate() without the memo — what a check of determinism has to call.
static func build(seed: int, count: int, cols: int, bias: float) -> Dictionary:
	var best: Dictionary = {}
	var best_q := INF
	var attempt := 0
	# Past ATTEMPTS only while every frame so far has a brick that tips, up
	# to MAX_ATTEMPTS; if none ever stands, the least bad one is kept.
	while attempt < ATTEMPTS or (int(best["topples"]) > 0 and attempt < MAX_ATTEMPTS):
		var made: Dictionary = _build(seed, attempt, count, cols, bias)
		var q: float = _quality(made, cols)
		if q < best_q:
			best_q = q
			best = made
		attempt += 1
	best.erase("topples")
	return best

static func _quality(made: Dictionary, cols: int) -> float:
	var cells: Dictionary = made["cells"]
	var heights: Array[int] = []
	for _c in range(cols):
		heights.append(0)
	for k: Vector2i in cells:
		heights[k.x] = maxi(heights[k.x], k.y + 1)
	var holes := 0
	var top := 0
	var bump := 0
	for x in range(cols):
		holes += heights[x] - _count_in_column(cells, x)
		top = maxi(top, heights[x])
		if x > 0:
			bump += absi(heights[x] - heights[x - 1])
	return Q_TOPPLE * float(made["topples"]) + Q_HOLE * float(holes) + Q_HEIGHT * float(top) + Q_BUMP * float(bump)

static func _count_in_column(cells: Dictionary, x: int) -> int:
	var n := 0
	for k: Vector2i in cells:
		if k.x == x:
			n += 1
	return n

# One attempt, as a beam search: after each brick, the BEAM best partial
# frames so far are kept, not just the single best. Choosing one brick at a
# time could walk into a corner — every landing for some later brick tips —
# and then the least bad frame was kept, tipping brick and all (session AM:
# 1 of 400 ten-brick frames). A partial frame with a brick that tips is
# dropped whenever any without one survives, so a frame tips only when no
# order of choices within the beam avoids it.
const BEAM := 12

static func _build(seed: int, attempt: int, count: int, cols: int, bias: float) -> Dictionary:
	var deal := RandomNumberGenerator.new()
	deal.seed = seed
	var noise := RandomNumberGenerator.new()
	noise.seed = seed ^ (0x5a17 + attempt * 7919)
	var heights0: Array[int] = []
	for _c in range(cols):
		heights0.append(0)
	var states: Array = [{"filled": {}, "owner": {}, "placed": [], "heights": heights0, "plan": [], "score": 0.0, "topples": 0}]
	for _n in range(count):
		var index: int = pick_brick(deal.randf(), bias)
		var options: Array = [] # {state, entry, at, tips, score}
		var seen := {}
		var shapes: Array = []
		for steps in range(4):
			var cells: Array[Vector2i] = turned_cells(index, steps)
			var ext: Vector2i = _extent(cells)
			# Rotations that make the same footprint are one option, not two,
			# so a symmetric brick is not twice as likely to lie a given way.
			var key: String = str(_sorted(cells))
			if seen.has(key) or ext.x > cols:
				continue
			seen[key] = true
			shapes.append([steps, cells, ext])
		for st: Dictionary in states:
			for sh in shapes:
				var cells: Array[Vector2i] = sh[1]
				var ext: Vector2i = sh[2]
				for col in range(cols - ext.x + 1):
					var row: int = _drop_row(cells, ext, col, st["heights"])
					var at: Array[Vector2i] = _place(cells, col, row, ext.y)
					var tips: int = _tipping_with(st["placed"], st["owner"], at)
					var score: float = float(st["score"]) + _landing_score(cells, ext, col, row, st["heights"]) \
						+ W_TOPPLE * float(tips) + noise.randf() * W_NOISE
					options.append({"state": st, "steps": sh[0], "col": col, "row": row, "w": ext.x, "h": ext.y, "at": at, "tips": tips, "score": score})
		var steady: Array = options.filter(func(o: Dictionary) -> bool: return int(o["tips"]) == 0)
		if not steady.is_empty():
			options = steady
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) < float(b["score"]))
		var next: Array = []
		for o: Dictionary in options.slice(0, BEAM):
			var st: Dictionary = o["state"]
			var filled: Dictionary = st["filled"].duplicate()
			var owner: Dictionary = st["owner"].duplicate()
			var placed: Array = st["placed"].duplicate()
			var heights: Array[int] = st["heights"].duplicate()
			var id: int = placed.size()
			placed.append(o["at"])
			for c: Vector2i in o["at"]:
				filled[c] = true
				owner[c] = id
				heights[c.x] = maxi(heights[c.x], c.y + 1)
			var plan: Array = st["plan"].duplicate()
			plan.append({"index": index, "steps": o["steps"], "col": o["col"], "row": o["row"], "w": o["w"], "h": o["h"]})
			# Summed over every step, not read off the finished frame: a brick
			# can tip the moment it lands and only be propped by a counterweight
			# laid later, and the player builds it in that order.
			next.append({"filled": filled, "owner": owner, "placed": placed, "heights": heights, "plan": plan,
				"score": o["score"], "topples": int(st["topples"]) + int(o["tips"])})
		states = next
	var best: Dictionary = {}
	var best_q := INF
	for st: Dictionary in states:
		var made := {"cells": st["filled"], "plan": st["plan"], "topples": st["topples"]}
		var q: float = _quality(made, cols)
		if q < best_q:
			best_q = q
			best = made
	return best

# A brick's cells on the grid, with its bounding box's bottom-left at (col, row).
static func _place(cells: Array[Vector2i], col: int, row: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(Vector2i(col + c.x, row + h - 1 - c.y))
	return out

static func _tipping_with(placed: Array, owner: Dictionary, at: Array[Vector2i]) -> int:
	var all: Array = placed.duplicate()
	all.append(at)
	var own: Dictionary = owner.duplicate()
	for c in at:
		own[c] = placed.size()
	return _tipping(all, own)

# How many bricks of this pile would tip over. Not each brick on its own: a
# brick that sits fine by itself can still be pushed over by what is stacked
# on its overhanging end, and checking bricks one at a time let exactly that
# through — five frames in a hundred of ten bricks fell apart when built to
# plan (session AM). So each brick is checked carrying its load: its own
# weight plus whatever rests on it, and that load's centre has to be over the
# cells it stands on, with TIP_MARGIN to spare.
#
# Loads are passed down top first. A brick can only rest on bricks placed
# before it — a straight drop cannot get under anything — so walking the
# pile from the last brick to the first meets every brick after everything
# above it. A brick standing on one thing hands it its whole load at the
# load's own centre; one standing on several splits it between the outermost
# two by the lever rule. Not exact statics (three supports are statically
# indeterminate), but it never mistakes a bridge's weight for leverage on
# either pier, which counting the whole load on both would.
const TIP_MARGIN := 0.1 # cells the load's centre must be inside the span it stands on

static func _tipping(placed: Array, owner: Dictionary) -> int:
	var n: int = placed.size()
	var mass: Array[float] = []
	var moment: Array[float] = []
	for b in range(n):
		var m := 0.0
		var mo := 0.0
		for p: Vector2i in placed[b]:
			m += 1.0
			mo += float(p.x) + 0.5
		mass.append(m)
		moment.append(mo)
	var bad := 0
	for b in range(n - 1, -1, -1):
		var groups := {} # what it stands on (a brick, or -1 for the platform) -> [sum of x, cells]
		var lo: int = 1 << 30
		var hi := -1
		for p: Vector2i in placed[b]:
			var under := -2
			if p.y == 0:
				under = -1
			else:
				var below := Vector2i(p.x, p.y - 1)
				if owner.has(below) and int(owner[below]) != b:
					under = int(owner[below])
			if under == -2:
				continue
			lo = mini(lo, p.x)
			hi = maxi(hi, p.x + 1)
			var g: Array = groups.get(under, [0.0, 0])
			g[0] = float(g[0]) + float(p.x) + 0.5
			g[1] = int(g[1]) + 1
			groups[under] = g
		var com: float = moment[b] / mass[b]
		if hi < 0 or com < float(lo) + TIP_MARGIN or com > float(hi) - TIP_MARGIN:
			bad += 1
		if groups.is_empty():
			continue
		var keys: Array = groups.keys()
		if keys.size() == 1:
			# One thing under it: the whole load bears down on it at the
			# load's own centre. Passing it on at the contact instead was the
			# bug that let two stacked T's balance exactly on a cell edge.
			if int(keys[0]) >= 0:
				mass[keys[0]] += mass[b]
				moment[keys[0]] += moment[b]
			continue
		# Several: by the lever rule between the outermost two, which keeps
		# the load's centre where it is; anything between them takes a share
		# at its own contact only when there are three or more.
		keys.sort_custom(func(u, v) -> bool:
			return float(groups[u][0]) / float(groups[u][1]) < float(groups[v][0]) / float(groups[v][1]))
		var left: int = keys[0]
		var right: int = keys[keys.size() - 1]
		var xl: float = float(groups[left][0]) / float(groups[left][1])
		var xr: float = float(groups[right][0]) / float(groups[right][1])
		var t: float = clampf((com - xl) / maxf(0.001, xr - xl), 0.0, 1.0)
		for pair in [[left, xl, 1.0 - t], [right, xr, t]]:
			var under: int = pair[0]
			if under < 0:
				continue
			mass[under] += mass[b] * float(pair[2])
			moment[under] += mass[b] * float(pair[2]) * float(pair[1])
	return bad

static func _sorted(cells: Array[Vector2i]) -> Array:
	var a: Array = []
	for c in cells:
		a.append(c.x * 100 + c.y)
	a.sort()
	return a

# Straight down from above, onto whatever each of its columns meets first.
static func _drop_row(cells: Array[Vector2i], ext: Vector2i, col: int, heights: Array[int]) -> int:
	var row := 0
	for x in range(ext.x):
		# The lowest cell this brick has in column x, counted up from its own
		# bottom edge.
		var low: int = 1 << 30
		for c in cells:
			if c.x == x:
				low = mini(low, ext.y - 1 - c.y)
		row = maxi(row, heights[col + x] - low)
	return row

static func _landing_score(cells: Array[Vector2i], ext: Vector2i, col: int, row: int, heights: Array[int]) -> float:
	var h: Array[int] = heights.duplicate()
	var holes := 0
	for x in range(ext.x):
		var low: int = 1 << 30
		for c in cells:
			if c.x == x:
				low = mini(low, row + ext.y - 1 - c.y)
		holes += low - heights[col + x] # empty cells left under this column
		h[col + x] = maxi(h[col + x], row + ext.y)
	var top := 0
	var agg := 0
	var bump := 0
	for x in range(h.size()):
		top = maxi(top, h[x])
		agg += h[x]
		if x > 0:
			bump += absi(h[x] - h[x - 1])
	return W_HOLE * float(holes) + W_HEIGHT * float(top) + W_AGG * float(agg) + W_BUMP * float(bump)

# Where a plan entry's brick has to be flown to: the x of its centre, for
# TowerMode.aim_x, with `cols` and `cell` as the platform's.
static func plan_aim_x(entry: Dictionary, cols: int, cell: float) -> float:
	return (-float(cols) * 0.5 + float(entry["col"]) + float(entry["w"]) * 0.5) * cell

# The mark: {inside, outside, area, score (0..1)}. `bricks` are the settled
# TowerPieces to count; the caller leaves out the one being flown and any
# already lost. `reach` is half the width of the play column, in px.
static func mark(cells: Dictionary, bricks: Array, cols: int, cell: float, reach: float) -> Dictionary:
	var area: int = cells.size() * SUB * SUB
	var top := 0.0
	var boxes: Array[Dictionary] = [] # {inv, rect}, every box of every brick
	for p in bricks:
		top = minf(top, p.top_y())
		var inv: Transform2D = p.global_transform.affine_inverse()
		var half: Vector2 = Vector2(float(p.cols), float(p.rows)) * p.cell * 0.5
		for b: Rect2 in p.boxes:
			boxes.append({"inv": inv, "rect": Rect2(b.position * p.cell - half, b.size * p.cell)})
	var inside := 0
	var outside := 0
	var step: float = cell / float(SUB)
	var left: float = -float(cols) * 0.5 * cell
	var y: float = -step * 0.5
	while y > top - step:
		var x: float = -reach + step * 0.5
		while x < reach:
			var pt := Vector2(x, y)
			for bx in boxes:
				if (bx["rect"] as Rect2).has_point((bx["inv"] as Transform2D) * pt):
					var at := Vector2i(int(floor((x - left) / cell)), int(floor(-y / cell)))
					if cells.has(at):
						inside += 1
					else:
						outside += 1
					break
			x += step
		y -= step
	var score: float = clampf(float(inside - outside) / float(maxi(1, area)), 0.0, 1.0)
	return {"inside": inside, "outside": outside, "area": area, "score": score}
