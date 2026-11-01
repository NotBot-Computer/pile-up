extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/PaceProbe.tscn
##
## Where a Pile Up turn's seconds actually go, split into the three phases a
## player experiences differently: the descent they are steering through, the
## settle they are watching, and the pause before the next brick appears.
##
## It exists because "the hand-off takes too long" is a complaint about a
## total, and a total cannot be tuned — the first run of this probe found a
## 7.66s turn made of 3.84s of descent (2.51s of it before the brick was
## within two cells of anything), 2.62s of settling and a 1.20s pause, which
## is three different fixes wearing one symptom.
##
## The split that matters most is the last one it prints: **settling costs
## 1.25s when nothing fell and 3.74s when something did.** That difference is
## a brick tumbling the whole height of the tower to reach LOST_Y, and it is
## not padding — a turn ends when the world stops precisely so that a
## collapse is billed to whoever caused it. See §5 session T for the measured
## reason it cannot simply be skipped.

const TOWER := preload("res://scenes/TowerMode.tscn")
const TURNS := 40

var _mode = null
var _rng := RandomNumberGenerator.new()
var _piloted = null
var _turns := 0
var _t := 0.0
var _approach := -1.0
var _last_state := ""
var _fell := 0
var _pilot: Array[float] = []
var _dead: Array[float] = []
var _settle_fell: Array[float] = []
var _settle_clean: Array[float] = []

func _ready() -> void:
	seed(20260828)
	_rng.seed = 5150
	GameSettings.player_count = 4
	var cols: Array[Color] = [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW]
	GameSettings.skin_colors = cols
	_mode = TOWER.instantiate()
	add_child(_mode)

func _physics_process(delta: float) -> void:
	if _mode == null:
		return
	if _mode.state == "gameover" or _turns > TURNS:
		_report()
		return

	if _mode.state != _last_state:
		if _last_state == "piloting":
			_pilot.append(_t)
			# A descent with no _approach recorded never got near anything —
			# it was steered off the platform — so all of it was dead.
			_dead.append(_approach if _approach >= 0.0 else _t)
		elif _last_state == "settling":
			if _fell > 0:
				_settle_fell.append(_t)
			else:
				_settle_clean.append(_t)
		_last_state = _mode.state
		_t = 0.0
		_approach = -1.0
	_t += delta
	if _mode.state == "settling":
		_fell = _mode.fallen_this_turn

	if _mode.state != "piloting" or _mode.active_piece == null:
		return
	var p = _mode.active_piece
	if p != _piloted:
		_piloted = p
		_turns += 1
		# Lives topped up: this probe measures the pace of a turn, not how
		# many turns a match lasts.
		for i in range(_mode.lives.size()):
			_mode.lives[i] = 3
		_mode.aim_steps = _rng.randi_range(0, 3)
		_mode.aim_x = _rng.randf_range(-1.0, 1.0) * _mode.CELL * 2.0
		return
	# "Dead" descent: the brick's underside is still more than two cells above
	# everything, so there is nothing yet to line it up against.
	if _approach < 0.0:
		var low := -INF
		for loop in p.box_outlines(p.global_transform):
			for v: Vector2 in loop:
				low = maxf(low, v.y)
		if low > _mode.stack_top_y - _mode.CELL * 2.0:
			_approach = _t

func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / float(a.size())

func _report() -> void:
	var pilot := _mean(_pilot)
	var dead := _mean(_dead)
	var s_fell := _mean(_settle_fell)
	var s_clean := _mean(_settle_clean)
	var n := float(_settle_fell.size() + _settle_clean.size())
	var settle := (s_fell * _settle_fell.size() + s_clean * _settle_clean.size()) / maxf(1.0, n)
	# Explicitly typed: _mode is untyped (TowerMode has no class_name), so
	# anything read off it defeats `:=` inference — see PROJECT_STATE §8.
	var pause: float = _mode.RESOLVE_PAUSE

	print("PaceProbe — %d turns\n" % _pilot.size())
	print("  descent (piloting)   : %5.2f s   of which %5.2f s before the brick" % [pilot, dead])
	print("                                     is within two cells of anything")
	print("  settling             : %5.2f s   (%.2f s when a brick fell, %.2f s when none did)"
		% [settle, s_fell, s_clean])
	print("  pause before next    : %5.2f s   (one beat for every turn since session AM)" % pause)
	print("  -----------------------------------")
	print("  whole turn           : %5.2f s" % (pilot + settle + pause))
	print("  hand-off             : %5.2f s   (landing -> next brick in reach)"
		% (settle + pause + dead))
	print("")
	print("  quiet turn, end to end : %5.2f s" % (pilot + s_clean + pause))
	print("  constants: DESCEND_SPEED %.0f  SPAWN_CLEARANCE %.1f cells  SETTLE_HOLD %.2f  APPROACH x%.1f until %.1f cells" % [
		_mode.DESCEND_SPEED, _mode.SPAWN_CLEARANCE / _mode.CELL, _mode.SETTLE_HOLD, _mode.APPROACH_MULT, _mode.APPROACH_GAP_CELLS])
	get_tree().quit()
