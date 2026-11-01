extends Node2D

## Pile Up — the game itself.
##
## Every player builds the *same* tower, one brick at a time, on one narrow
## platform. Whoever is on the clock steers a brick down onto the
## stack; once everything has stopped moving, anything that fell off the
## platform during that turn costs the player who dropped it a life. Last
## player with a life left wins. That is the whole rule set, and the shared
## tower is what makes it different from Tricky Towers' survival mode, which
## it is otherwise modelled on: you are not racing your own pile, you are
## inheriting whatever the last player left you, and knocking someone else's
## brick off is your problem, not theirs.
##
## ## Why it is turn-based
##
## The fault rule ("the one who drops a brick loses a life") only has an
## answer if exactly one player can be responsible for the state of the tower
## at a time. With everyone dropping at once onto one stack, a collapse has
## no author. So turns are not a simplification of the design — they are what
## makes the scoring rule well-defined.
##
## ## How a brick is flown down
##
## The brick descends on its own from the moment it appears, slowly, and the
## turn ends when it touches something. There is no "release" button: the
## player's job is to steer and turn it during the fall, and `down` makes it
## fall faster once they are happy with the line.
##
## Sideways movement is **discrete**, not a slide — a press moves the brick
## exactly half a cell, and the dash button moves it exactly one, faster and
## with an afterimage so the two can be told apart. Since a brick starts at
## x=0 and every command is a multiple of half a cell, it stays on an exact
## half-cell lattice for its whole descent, which is what makes it possible
## to line an edge up with the tower below by counting presses instead of by
## eye.
##
## While it is under the player's control the brick is frozen AND out of the
## collision world (see TowerPiece.set_held), so it can never shove the tower
## it is about to land on. Contact is instead resolved by *asking*: every
## move — sideways, rotational, downward — is tested with `intersect_shape`
## against where the brick would be, and refused if that space is occupied. A
## refused downward move is what "landed" means, and at that instant the
## brick is handed to the physics engine exactly where it stopped.
##
## That is also why exact discrete movement is possible at all. A brick that
## was really falling could not be stepped a half cell sideways without
## risking it ending up inside the tower; a brick whose every move is
## permission-checked can be put anywhere that is empty, precisely.
##
## ## Structure
##
## Nothing here is shared with Don't Crash except GameSettings, the menu flow
## and the key bindings. That mode is N independent scrolling boards with
## Area2D traffic and no rigid bodies at all; this one is a single world with
## real RigidBody2D physics. They have no geometry, camera model or update
## loop in common, so this is a separate scene and script rather than a
## variant of Main/PlayerBoard — see docs/PROJECT_STATE.md.

const PIECE_SCENE := preload("res://scenes/TowerPiece.tscn")

# --- Playfield -------------------------------------------------------------
# The world origin IS the platform's top surface, so the tower grows toward
# -y and "how tall is it" is just -stack_top_y. Every constant below is in
# those units.
#
# Cell size used to be set by the *vertical* budget — how much of the tower
# fits on screen — because the camera sat at zoom 1 and a world pixel was a
# screen pixel. It is not any more: VISIBLE_CELLS owns that question and the
# camera pulls back to satisfy it, which is the only knob that can change how
# much tower you see without changing what a brick weighs, how fast it falls
# or how far a dash carries it. Every speed, tolerance and threshold in this
# file is in world units and tuned against this number, so **changing CELL
# means re-deriving all of them** (MAX_FALL_SPEED says so in as many words);
# changing VISIBLE_CELLS means changing nothing else.
#
# 38 is kept for that reason and not because 38 is special. The first version
# was 58 and could show only five and a half cells of tower beneath the brick
# in play, so the tower kept scrolling out from under itself — that was fixed
# here before there was a camera knob to fix it with.
const CELL := 38.0

# How much likelier a classic brick is than an odd one, per brick.
#
# GameSettings.BRICKS holds two categories — the seven Tetris pieces, flagged
# `classic`, and the twelve pentominoes — and a uniform draw over all nineteen
# made two bricks in three a five-cell piece. That is backwards: the odd
# shapes are the surprise in this mode, and a surprise that arrives twice a
# turn is just the game. At 16 the seven classics carry 7x16 = 112 of the 124
# weight against the twelve odd ones' 12, so **90% of bricks are classic and
# 10% are not** — 12.9% each for a classic, 0.8% each for an odd one, and
# about one brick in ten something you have to think about.
#
# It was 4.0 (70/30, one odd brick in three) from session AC until session
# AI, when the user, having played it, asked for the odd ones to come "a lot"
# less often.
#
# This is the only number that decides the mix; the pool itself is not
# re-ordered or trimmed to change it, and every brick keeps a real chance of
# turning up. 1.0 restores the uniform draw exactly.
const CLASSIC_BIAS := 16.0

const PLATFORM_CELLS := 5.0
const PLATFORM_THICKNESS := 30.0 # the collision slab; the drawn outcrop runs much deeper

# World y of the near ground — the grass shelf the outcrop grows out of, and
# the surface the whole scene is anchored to. TowerGround draws the band here
# and TowerBackground lines its own ground line up with it, so the outcrop
# stands in real ground instead of on a table. Also the height of the
# outcrop, since the tower's surface is y = 0.
const GROUND_Y := 120.0
const OUTCROP_FLARE := 26.0 # how much wider the rock is where it meets the ground
const OUTCROP_BURY := 40.0 # how far it continues below the ground line, so it never floats

# How far past the platform's own edge a brick's outer edge may be steered.
# This is the mode's main difficulty knob: it is what lets a player choose to
# overhang deliberately, and it is measured against the brick's *rotated*
# width so a long piece cannot be walked further out than a short one.
#
# Note this bound keeps the half-cell lattice exact rather than truncating
# it: the limit works out to (2.5 + AIM_BOUND_CELLS - half the brick's width
# in cells) cells, and a brick's half-width is always a whole number of half
# cells, so as long as this constant stays a multiple of 0.5, clamping lands
# on the lattice instead of somewhere between two steps. It is not free to be
# any number.
#
# 2.0 → 2.5 on request, for a little more room to the sides. It widens the
# shaded play column and the height guides with it, since both are drawn from
# this constant, and it does not touch PLATFORM_CELLS — the platform is the
# same size, there is just more air either side of it that a brick may be
# steered over. Measured cost with TowerProbe, which aims as a fraction of
# the legal range and so models a player using all of the new room: matches
# shorten from 23.3 to 20.8 turns at spread 0.3 and 19.7 to 18.3 at 1.0.
# That is the difficulty this knob is documented to buy (§9) — more ways to
# put a brick somewhere it cannot be saved — and a real player only spends
# the extra reach when they want it, so it is an upper bound on the cost.
const AIM_BOUND_CELLS := 2.5

# Sideways movement is stepped, not slid. A press is half a cell; holding a
# direction repeats that step after a delay, so long travel doesn't mean
# mashing. A whole cell is the dash, on its own button.
#
# The dash was a double-tap first — Don't Crash's lane-dash gesture, reused
# because it was already this game's vocabulary for "one discrete unit over".
# It is a button now because a double-tap and two deliberate half-steps are
# the same keypresses, so the game had to guess which one was meant from
# timing alone, and guessed wrong often enough to be worth removing. A
# separate key cannot be misread.
const STEP_CELLS := 0.5
const DASH_CELLS := 1.0
# The dash key and the direction keys are a chord, and either one may be the
# one you hold: hold a direction and press dash, or hold dash and press a
# direction. Both spell the same thing, which is what lets a player pick the
# order that suits the hand they have on the keyboard.
const HOLD_REPEAT_DELAY := 0.30
const HOLD_REPEAT_INTERVAL := 0.08
# How fast the brick chases the commanded position. High enough that a step
# reads as a snap rather than a glide, low enough that it is still a movement
# and not a teleport — and every frame of it is still collision-checked.
const FOLLOW_SPEED := 620.0

# A dash has to be *perceptible*, and the first version of it was not.
#
# It moved the brick a whole cell, correctly — but it got there by adding the
# second half of a cell to the half the first tap had already moved, at the
# same speed. So a double-tap and two ordinary taps produced the same
# distance at the same pace, and a measurement of both came back 1.00 cells
# and 1.00 cells. There was nothing to feel, which is indistinguishable from
# the input not working, and that is exactly what it was reported as.
#
# The distance was never the problem — the *sameness* was. So the dash moves
# a whole cell where a press moves half, covers that ground about twice as
# fast, and leaves an afterimage. The window is also a little wider than it was,
# since a double-tap nobody can confirm landed is a double-tap people give
# up on.
const DASH_FOLLOW_SPEED := 1400.0
const DASH_GHOST_TIME := 0.22
const DASH_GHOST_COPIES := 4
const DASH_STREAKS := 4 # speed lines drawn back along the path
const DASH_RIM_WIDTH := 7.0 # outline flash at the landing position; only its outer half shows

const ROTATE_LERP := 18.0

# Spawn height above the stack, and the speed it comes down at. They look
# like the same knob and they are not — this is the mistake that got made
# here, so it is written down.
#
# The turn was too slow: measured (PaceProbe), a 7.7s turn spent 3.8s on the
# descent, 2.5s of that with the brick still more than two cells above
# everything, against 2.6s settling and a 1.2s pause. Both numbers were cut
# to fix it — 7 cells to 5.5, and 58px/s to 105 — on the reasoning that they
# are the same second approached from two directions.
#
# They are not. **Speed is the pace knob; height is a readability one.** The
# distance above the stack is how much of the fall the player can see coming
# and plan against — where the brick is relative to the tower, whether the
# rotation is right, how far across it still has to travel — and shortening
# it does not make the turn feel quicker, it makes the brick feel like it
# appears already half-way down. Reported immediately from play as bricks
# starting too low, so the height went back to 7 cells and the speed stayed.
# The descent still costs about 2.2s against the original 3.8s, and all of
# that saving came from the half of the change that was actually about time.
#
# The floor on the height is the tallest half-extent any brick can have (the
# I pentomino reaches 2.5 cells below its own centre); the ceiling is the
# top of the screen, since the camera holds the stack top at
# CAM_STACK_TOP_FRAC and the brick appears a fixed distance above that. 7
# cells puts the I pentomino's top edge at roughly y=122 on screen in the
# climbing shot, and lower than that in the resting one — the tightest case
# in the set, with room to spare.
#
# That margin was 23px until VISIBLE_CELLS pulled the camera back: this is a
# world distance and the ceiling it is measured against is a screen one, so
# every cell of extra zoom-out buys headroom here for free. It was 42px when
# the tallest brick was a vertical I tetromino, and the pentominoes spent
# half a cell of it — which is the reason the number is written down.
const SPAWN_CLEARANCE := CELL * 7.0
const DESCEND_SPEED := 105.0 # px/s, ~2.8 cells/s
const SOFT_DROP_SPEED := 430.0 # px/s while `down` is held

# Contact tolerance for the three move queries. A move is refused only if it
# would put the brick *meaningfully* inside something, never for merely
# grazing it.
#
# This exists because of the lattice. Every command is a multiple of half a
# cell from x=0, so a brick's faces line up *exactly* with the faces of the
# bricks already stacked — and Godot counts two exactly-touching rectangles
# as a hit (measured: a 0.00px gap intersects, a 0.05px gap does not). So a
# brick descending flush past its neighbour had its next step down refused by
# a contact of literally zero depth, went limp in mid-air with nothing under
# it, and only started falling again when the player steered sideways.
# Settling makes it worse rather than better: a landed brick picks up a
# thousandth of a radian of lean, which pokes a corner a fraction of a pixel
# across the line into the column beside it. The case that was caught was
# refused by an overlap 0.23px wide.
#
# The skin comes off *across* the direction of travel and never along it, so
# a landing is still detected at the exact pixel of contact: on the way down
# a brick ignores what it grazes to its sides, but nothing it is coming down
# on. Rotation has no direction of travel, so it is trimmed on both axes.
#
# It is half FOOT_INSET on purpose and the two must stay in step. The feet
# that decide whether a brick is supported are inset by half of FOOT_INSET
# per side, so an overlap deep enough to refuse a descent is also deep enough
# for the feet to find. That is what keeps "blocked on the way down" and
# "something is underneath" the same event, instead of two events with a gap
# between them for a brick to hang in.
const QUERY_SKIN := TowerPiece.FOOT_INSET * 0.5
# An anti-deadlock backstop, and deliberately NOT a gameplay rule.
#
# The rule is: a turn ends when something is underneath the brick, never
# before. A brick pressed against the flank of a taller stack is touching
# something, but nothing is holding it up, so the player keeps steering and
# can always back out of it — every wedged position has an exit, since the
# brick got there by descending and can move back the way it came.
#
# This exists only for the case that exit is somehow unavailable, so a turn
# cannot hang forever. At 1.5s it was short enough to fire during ordinary
# play and take the brick away mid-placement, which is exactly the complaint
# it was supposed to fix. Six seconds is long enough that reaching it means
# someone is holding a direction into a wall on purpose.
const WEDGE_GRACE := 6.0

# --- Turn structure --------------------------------------------------------
const START_LIVES := 3
# A team's shared pool, in every variant that has teams. Per *team*, not per
# member: lives are spent per turn, a team takes the same number of turns
# whether it has one member or two, and so a 2v1 is two heads against one on
# the same clock and the same pool. Six is a 2v2's three each, pooled.
# Measured with TeamProbe's blind aim (spread 0.3): 18.0 turns a 2v2 match
# against free-for-all's 22.5 at four players; five lives made it 15.4, which
# is under four bricks a player. A first guess at what plays well; unplayed.
const TEAM_LIVES := 6
# The storm is co-op's opponent and casts hexes like a player, as slot -1.
# A cold blue-grey, because every real colour on the skin table is somebody's.
const STORM_COLOR := Color(0.62, 0.70, 0.86)

# --- Goal lines: co-op and the race ------------------------------------------
# The two variants with one team per tower cannot end on "last one standing"
# — there is nobody to outlast — so they end on height instead: settle the
# tower with its top over the line and you have won; run out of lives first
# and you have not. The line is drawn across the play column and is on screen
# from the first brick (the resting shot shows ~20 cells above the platform),
# so the target is something you can see rather than a number to remember.
#
# COOP_GOAL_CELLS and COOP_LIVES are set against TeamProbe's blind aim, which
# is a floor on what people manage (TowerProbe's header): see the co-op
# section of docs/PROJECT_STATE.md for the measurement. Both unplayed.
const COOP_LIVES := 5
const COOP_GOAL_CELLS := 14.0
# A settled tower's top sits a hair under where its bricks' cells would put
# it, because landed bricks lean and sink a fraction of a pixel. A tenth of a
# cell — four pixels — is less than anyone can see against the line.
const GOAL_SLACK_CELLS := 0.1
const GOAL_COLOR := Color(1.0, 0.80, 0.22, 0.95)
const GOAL_SHADOW := Color(0.06, 0.08, 0.20, 0.55)

# The race: one team per tower, both towers building at once, first to settle
# over the line wins — and a team that runs out of lives first loses it. The
# line is lower than co-op's because the race has no second chance at it and
# no storm pushing the pace: the clock is the other team. Each tower gets
# half the screen, so the camera pulls back from 29 cells to 34 to keep the
# play column (ten cells, aim bound included) clear of the HUD columns in a
# 750px-wide view. Both unplayed; see the race section of PROJECT_STATE.
const RACE_LIVES := 5
const RACE_GOAL_CELLS := 15.0 # was 10 until session AM: "put the goal line higher"
const RACE_VISIBLE_CELLS := 34.0

# FRAME (GameSettings.tower_is_frame): an outline on the platform built from
# the first FRAME_BRICKS bricks of the deal (TowerFrame), and exactly those
# bricks to fill it with. The tower stops after the last one has settled and
# is marked; the host compares the marks. There are no lives — a brick that
# falls is simply area the frame does not get — and no skills, because a
# skill that changes or scales a brick would make the frame unbuildable.
# Ten bricks is a frame about eight to ten cells tall on the five-cell
# platform. It was six (five or six tall) for one playtest, and the user
# asked for a bigger, taller shape (session AM).
const FRAME_BRICKS := 10
const FRAME_LINE := Color(1.0, 0.92, 0.55, 0.95)
const FRAME_FILL := Color(1.0, 0.92, 0.55, 0.16)
const FRAME_SHADOW := Color(0.06, 0.08, 0.20, 0.60)
const TowerFrame := preload("res://scripts/TowerFrame.gd")

# DEADLINE (GameSettings.tower_is_deadline): a red line across the tower that
# starts at the ground and climbs for the whole round, faster all the time. A
# tower whose top stays under it for DEADLINE_GRACE seconds in a row is out;
# get back over it in time and the count starts again. The host declares the
# last tower left in the winner. Asked for from a sketch, in Turkish:
# a line under everyone's tower, rising faster as time goes on, and whoever's
# top stays under it for a while is eliminated (session AN).
#
# After t seconds of play the line is DEADLINE_START_CELLS + DEADLINE_SPEED·t
# + ½·DEADLINE_ACCEL·t² cells up: 0.15 cells/s at GO!, 0.45 after 25s, 0.75
# after 50s — faster than anyone stacks for long, so no round can go on for
# ever. Every tower runs its line off its own clock, and the clocks agree
# because every tower's countdown ends on the same physics frame.
#
# No lives: a fallen brick costs the height it did not add, which is exactly
# what the line reads, and a second way out would blur the one rule. Skills
# stay on — a hex that slows the leader down is what the line rewards.
# Unplayed; the speeds are first guesses checked against DeadlineProbe's
# blind aim, see docs/PROJECT_STATE.md §5 session AN.
const DEADLINE_START_CELLS := -GROUND_Y / CELL # the ground line, under the outcrop
const DEADLINE_SPEED := 0.15 # cells/s at GO!
const DEADLINE_ACCEL := 0.012 # cells/s the line gains every second
const DEADLINE_GRACE := 3.0 # seconds a top may stay under the line
const DEADLINE_COLOR := Color(1.0, 0.24, 0.20, 0.95)
const DEADLINE_SHADOW := Color(0.20, 0.02, 0.04, 0.60)
# The sky under the line is washed red, strongest just under it, so the part
# of the tower that is already under is seen to be under.
const DEADLINE_WASH_NEAR := Color(1.0, 0.16, 0.10, 0.30)
const DEADLINE_WASH := Color(0.90, 0.10, 0.08, 0.13)
const DEADLINE_WASH_BAND := 2.0 # cells over which the wash fades from near to far

# The storm casts a random hex from the opponent pool at whoever is up next,
# every STORM_EVERY turns — and every STORM_EVERY_HIGH once the tower is past
# half the goal, so the last stretch is the stormy one. Queued at the end of
# a turn rather than the start of the next, so it is listed under the banner
# through the whole hand-off, exactly like a hex a rival sent.
const STORM_EVERY := 3
const STORM_EVERY_HIGH := 2

# The beat between "everything stopped" and the next brick. There used to be
# two — 1.1s after a turn that cost a life, so its banner could be read, and
# 0.35s otherwise — until the user asked for the banner to go (the heart's
# blink says it now, HeartPips.LOSS_BLINKS) and for a more seamless hand-off
# between players (session AM). With nothing on screen to read there is
# nothing to wait for, so it is one short beat for every turn: just enough
# that the next brick does not appear on the same frame the last one is
# judged.
const RESOLVE_PAUSE := 0.2

# A new brick appears SPAWN_CLEARANCE above the stack, and for most of the
# way down there is nothing near it to steer against — PaceProbe measured
# 1.5s of every 2.4s descent spent more than two cells clear of anything.
# Until its bottom is within APPROACH_GAP_CELLS of the stack it falls at
# APPROACH_MULT times the descent speed, still fully steerable; from there on
# it is the ordinary descent, so the part where aim matters is unchanged.
# Soft drop is faster still and wins. Session AM.
const APPROACH_MULT := 2.2
const APPROACH_GAP_CELLS := 3.5

# A turn ends when the whole world is at rest, not when the brick lands: the
# interesting case is a brick that lands cleanly and then shoves the tower
# over three seconds later, and resolving on contact would score that against
# the wrong player. SETTLE_TIMEOUT is the backstop for a tower that has found
# some slow perpetual wobble it will not come out of.
#
# SETTLE_LINEAR and SETTLE_ANGULAR are the fault rule's guard and are
# deliberately not the pace knob: measured, the tower is genuinely still
# moving for most of the settle (72% of settling frames fail the linear test,
# with tumbles up to 5.3 rad/s), so loosening these would resolve turns on
# towers that are still falling and bill the collapse to the next player.
# SETTLE_HOLD is a different thing — it is the quiet period required *after*
# the motion has already stopped, and half a second of it was pure padding on
# top of a test the tower passes within 0.36s of a landing.
const SETTLE_LINEAR := 16.0
const SETTLE_ANGULAR := 0.18
const SETTLE_HOLD := 0.25
const SETTLE_TIMEOUT := 9.0

# Losing a brick and removing a brick are two different moments, and
# conflating them cost six seconds a turn.
#
# LOST_* is where a brick stops counting: below the underside of the slab
# there is nothing but sky, so a brick past it can never rejoin the tower and
# is scored as fallen immediately. DESPAWN_* is where it is finally freed,
# long after it has left the screen.
#
# Splitting them matters because a brick shrugged off a twenty-cell tower has
# to fall about 900px before it is anywhere near gone, which at MAX_FALL_SPEED
# is roughly six seconds — and a turn ends when everything is at rest, so
# waiting for that debris meant the settle timeout firing on 6.5% of turns
# (twelve times in one measured match) with the player watching "settling..."
# the whole time. Counted early and freed late, the turn ends when the *tower*
# has stopped, which is what the rule was always about.
#
# Both are fixed world values rather than camera-relative on purpose: the
# camera pans up with the tower, so a camera-relative floor would eventually
# rise above the platform itself and cull the bricks the tower stands on.
const LOST_Y := PLATFORM_THICKNESS + 40.0
const LOST_X := 900.0
const DESPAWN_Y := 600.0 # under the ground band and off screen; TowerGround hides the moment it goes
const DESPAWN_X := 1600.0

# --- Camera ----------------------------------------------------------------
# Two framings, and the camera takes whichever sits lower.
#
# CAM_GROUND_FRAC is the resting shot: the platform low in frame with the
# ground under it, which is where a match starts and stays while the tower is
# short. CAM_STACK_TOP_FRAC is the climbing shot, which only takes over once
# the tower is tall enough that the resting shot would push the descending
# brick off the top of the screen.
#
# They have to be separate. A single fraction has to be low enough to sit the
# platform on the ground *and* high enough to leave the brick room to fall,
# and no one number is both — the first version used 0.48 for everything,
# which is why the platform floated in the middle of the screen.
const CAM_GROUND_FRAC := 0.70
const CAM_STACK_TOP_FRAC := 0.48
const CAM_LERP := 3.5

# How much tower is on screen at once, in cells. The camera zooms out until
# this much of the world's height fits, so this is the whole of "how big is a
# brick" as the player experiences it.
#
# 29 against the 21 that a zoom of 1 gives, asked for after a side-by-side
# with Tricky Towers: the reference fits far more of its tower in frame, and
# the difference is entirely camera distance — its bricks are not a different
# shape, they are further away. Deliberately done here rather than by shrinking
# CELL, which would have been the same picture and a different game: every
# speed in this file is px/s against a 38px cell, so a smaller cell silently
# speeds up the descent, the dash and the fall in the units that matter.
#
# Everything reading the viewport for a *world* size has to divide by the
# resulting zoom — that is what _view_world() is for, and the two camera
# framings and the foreground both go through it. Screen-space work (the HUD
# and the backdrop, both CanvasLayers) is unaffected by design.
#
# Two knock-on effects, both accepted rather than overlooked. The near ground
# keeps its exact on-screen size, because TowerGround scales its art to the
# *world* width it is handed and the camera then scales it back down — so the
# landscape is unchanged and only the tower shrank, which is what the
# reference looks like. And the backdrop now moves 0.39 of the tower's
# on-screen travel rather than 0.28, because BACKDROP_PARALLAX is applied to
# the camera's world climb: that constant's stated job is to walk the picture
# from bottom to top over a twenty-cell tower, and it still does exactly that.
const VISIBLE_CELLS := 29.0
# How much of the camera's climb the backdrop follows. Anything below 1 reads
# as depth; this value takes a twenty-cell tower almost exactly to the top of
# the backdrop art, so a full-height tower has climbed the whole picture
# rather than a fraction of it.
const BACKDROP_PARALLAX := 0.28

# --- Foreground ------------------------------------------------------------
# Everything drawn over the backdrop is dark, not light. The first version of
# this mode drew white guide lines against the project's dark clear colour;
# over a bright sky they were invisible.
const GUIDE_SPACING_CELLS := 4.0
const GUIDE_COLOR := Color(0.10, 0.13, 0.28, 0.10)
const EDGE_LINE_COLOR := Color(0.10, 0.12, 0.26, 0.26)
# The outcrop is built from the backdrop's own earth band rather than painted
# in flat colours. Flat fills were the first attempt and they read as a prop
# sitting in front of a painting: everything around them is detailed pixel
# art, so a smooth tan trapezoid is the one object on screen with no texture.
# Cutting it from the same image the ground is cut from makes it the same
# stone as the world it stands in — the §7 "derive new art from the existing
# art" rule, applied to something drawn rather than to a sprite.
#
# The source window is the stone/dirt layer under the near grass: full-width
# in the art, so any horizontal slice of it is usable, and already the
# material this world's ground is made of.
const ROCK_SRC := Rect2(600.0, 962.0, 260.0, 62.0)
const ROCK_SLICE := 8.0 # px of outcrop per drawn slice; small enough to follow the taper
const ROCK_SHADE_RIGHT := Color(0.0, 0.0, 0.0, 0.22)
const ROCK_SHADE_LEFT := Color(1.0, 0.94, 0.82, 0.13)
const GRASS := Color8(101, 169, 30)
const GRASS_LIGHT := Color8(139, 198, 44)
const GRASS_DARK := Color8(38, 120, 23)
const DROP_GUIDE_ALPHA := 0.13
# A soft shaded band marking the column the tower lives in — the same job the
# per-player lane tints do in Tricky Towers. Two reasons: the backdrop is
# busy pixel art and the bricks need something quieter directly behind them,
# and the band is the only thing that shows where the legal play area ends
# once the platform has scrolled off the bottom. Kept dark rather than light,
# because a light wash disappears against a bright sky.
const COLUMN_SHADE := Color(0.06, 0.08, 0.20, 0.10)

# --- Skills ----------------------------------------------------------------
# Pile Up's skills are earned by *charge* and cast on the caster's own turn.
# Everything about how one behaves lives in scripts/tower_skills/ (TowerSkill
# is the contract, TowerSkillCatalog the table); what lives here is only the
# plumbing — who has what, when a cast is legal, and where in the turn loop
# each hook is consulted.
#
# A clean placement (the brick landed and nothing fell that turn) adds one
# charge; at CHARGE_TO_SKILL the player is handed a skill into whichever of
# their two slots is empty — one `self` slot, one `opponent` slot, each with
# its own key. A player holding both keeps the charge banked until a slot
# frees. Two, because at three a skill arrives once a match for a player who
# is losing bricks, and the mode is meant to be about the skills as much as
# the stacking; at one every turn is a cast and the tower never gets to be a
# tower. Unplayed, and the first number to move.
const CHARGE_TO_SKILL := 2

# --- Cups --------------------------------------------------------------------
# In a cup (GameSettings.tower_cup) a match is one round of several: its
# result pays out trophies by place and the next round is a different
# variant, on the tally screen in between (TowerCup). So the end of a match
# goes there rather than to a replay — on Enter, or on its own after
# CUP_RESULT_HOLD, long enough to read who won the round over the tower they
# built and short enough that nobody has to reach for the keyboard.
const CUP_RESULT_HOLD := 3.0
const CUP_SCENE := "res://scenes/TowerCup.tscn"

@onready var camera: Camera2D = $Camera2D
@onready var platform: StaticBody2D = $Platform
@onready var platform_shape: CollisionShape2D = $Platform/CollisionShape2D
@onready var pieces: Node2D = $PiecesContainer
@onready var backdrop: TowerBackground = $Backdrop/Sky
@onready var ground: TowerGround = $Foreground/Ground
@onready var hud: TowerHUD = $HUD/Board
@onready var overlay: Control = $HUD/Overlay
@onready var overlay_title: Label = $HUD/Overlay/OverlayTitle
@onready var overlay_body: Label = $HUD/Overlay/OverlayBody
@onready var overlay_hint: Label = $HUD/Overlay/OverlayHint
@onready var countdown: Countdown = $HUD/Countdown
@onready var skill_overlay: TowerSkillOverlay = $Foreground/SkillOverlay
@onready var skill_screen: TowerSkillScreen = $HUD/SkillScreen

var state := "piloting" # countdown -> piloting -> settling -> resolving -> piloting, or gameover
# Per TEAM, not per player — see "Teams" below. In free-for-all every player is
# a team of one with the same index as their slot, so `lives[slot]` still
# means exactly what it always did there, and the probes that read it do too.
var lives: Array[int] = []
var active_slot: int = 0

# --- Teams -------------------------------------------------------------------
# Every variant is one idea applied to the same loop: a turn belongs to a
# *team*, a team is a set of slots sharing a life pool, and the team's turns
# rotate through its members. Free-for-all is every player alone on a team of
# one, which is why it needed no special case and plays exactly as it did.
#
# Turn order is round-robin over the living teams, and inside a team over its
# members — so 2v2 goes left, right, left, right with each side alternating
# who flies, and 2v1 gives the lone player every other turn rather than every
# third. The fault rule is unchanged in spirit: a turn's falls cost the team
# that was on the clock.
var variant: int = -1 # GameSettings.TOWER_*; read in _ready() unless a host set it first
# The race host (TowerRace) when this tower is one of two side by side, and
# null when it is the whole game. A hosted tower takes no input of its own,
# shows no game-over overlay and reports its result upward instead.
var host = null
var members: Array[int] = [] # slots building on THIS tower; every slot unless a host says otherwise
var visible_cells: float = VISIBLE_CELLS # a host may pull the camera back further
var team_of: Array[int] = [] # per slot
var team_count: int = 0
var team_cursor: Array[int] = [] # per team: how many turns it has taken, i.e. whose go it is next
var turn_team: int = -1 # the team on the clock (or the last one to be)
var crew_mate: int = -1 # co-pilot only: the player turning the brick; -1 everywhere else
var winner_team: int = -1 # set when a goal line decides the match rather than a last survivor
# Teams in the order they ran out of lives, first out first. Nothing in a
# match reads it; it is what ranks the losers when a cup asks for 1st to 4th
# rather than just a winner (placements()).
var out_order: Array[int] = []
var _cup_leave_in: float = 0.0 # cup only: counts down to the tally once the round is over
var _cup_round_shown: int = 0 # cup only: this round's number, fixed before the result is recorded
var turns_flown: Array[int] = [] # per slot, for the end screen
var bricks_dropped: Array[int] = [] # per slot, for the end screen
# The race deals both towers the same bricks in the same order, so it is a
# building contest and not a draw: the host hands both the same non-zero
# seed and each tower draws from its own generator. Zero — every variant
# but the race — draws from the global RNG exactly as the mode always has,
# which is what keeps every other probe's brick sequence where it was.
var brick_seed: int = 0
var _brick_rng: RandomNumberGenerator = null
var goal_cells: float = 0.0 # 0 = no goal line (free-for-all, teams, co-pilot)
var frame_cells: Dictionary = {} # FRAME only: Vector2i(col from the platform's left, row up) -> true
var frame_plan: Array = [] # FRAME only: how the frame was built, brick by brick (TowerFrame.generate)
var frame_score: float = 0.0 # FRAME only: the last mark, 0..1 (TowerFrame.mark)
var deadline_time: float = 0.0 # DEADLINE only: seconds of play so far, which the line's height is read off
var deadline_cells: float = 0.0 # DEADLINE only: the line, in cells over the platform's top (under it at first)
var deadline_top: float = 0.0 # DEADLINE only: the tower's top as the line last measured it (_top_cells())
var under_time: float = 0.0 # DEADLINE only: how long the top has been under the line, this time round
var deadline_out_at: float = -1.0 # DEADLINE only: deadline_time when the line took this tower; -1 while it has not
var deadline_layer: Node2D = null # DEADLINE only: the canvas the line is drawn on, over the bricks
var storm_in: int = 0 # co-op: resolved turns until the storm casts again
var storms: int = 0 # co-op: hexes the storm has sent this match
var active_piece: TowerPiece = null
var next_index: int = 0

var aim_x := 0.0 # the commanded x; the brick chases it at FOLLOW_SPEED
var aim_steps := 0 # quarter turns; free rotation only starts once the brick lands
var dash_active := false # true while a dash is still travelling, for the faster follow
var dash_target_x := 0.0 # where it is headed; the fast follow ends here, not at aim_x
var dash_dir := 0
var dash_ghost_x := 0.0
var dash_ghost_timer := 0.0
var hold_dir := 0
var hold_timer := 0.0

var settle_timer := 0.0
var wedge_timer := 0.0
var fall_timer := 0.0
var resolve_timer := 0.0
var fallen_this_turn := 0

var stack_top_y := 0.0
var cam_y := 0.0
var cam_zoom := 1.0 # set in _ready() from VISIBLE_CELLS; see _view_world()
var cam_start_y := 0.0
var best_height := 0
var bricks_placed := 0

# Per slot. `charge` counts clean placements toward the next skill; the two
# `held_*` arrays are skill ids, "" for an empty slot.
var charge: Array[int] = []
var held_self: Array[String] = []
var held_opponent: Array[String] = []
# Live effects (TowerSkill), any target, in the order they were applied; and
# opponent effects waiting for their target's turn to come round. An effect
# is in exactly one of these at a time, or in neither once retired.
var active_effects: Array = []
var queued_effects: Array = []

func _ready() -> void:
	countdown.finished.connect(_on_countdown_finished)
	if variant < 0:
		variant = GameSettings.tower_variant
	if members.is_empty():
		for s in range(GameSettings.player_count):
			members.append(s)

	var rect := RectangleShape2D.new()
	rect.size = Vector2(PLATFORM_CELLS * CELL, PLATFORM_THICKNESS)
	platform_shape.shape = rect
	platform_shape.position = Vector2(0.0, PLATFORM_THICKNESS * 0.5)

	# The platform grips exactly as hard as a brick does. A slicker base
	# would make the first brick of every tower the hardest one to place,
	# which is backwards.
	var mat := PhysicsMaterial.new()
	mat.friction = TowerPiece.FRICTION
	mat.bounce = TowerPiece.BOUNCE
	mat.rough = true
	platform.physics_material_override = mat

	var screen: Vector2 = get_viewport().get_visible_rect().size
	cam_zoom = screen.y / (visible_cells * CELL)
	camera.zoom = Vector2.ONE * cam_zoom
	camera.make_current()

	# The near ground and the far backdrop are cut from one image and have to
	# agree about where the ground is: TowerGround puts it at GROUND_Y in the
	# world, and the backdrop is told where that lands on screen in the
	# resting shot, which is the only place they are required to line up.
	# `configure` takes a *world* size — TowerGround draws in world space,
	# under the camera — while `set_ground_screen_y` takes a screen position,
	# since the backdrop is a CanvasLayer the camera never touches. GROUND_Y
	# is a world distance, so it crosses that boundary scaled by the zoom.
	ground.configure(GROUND_Y, _view_world())
	backdrop.set_ground_screen_y(GROUND_Y * cam_zoom + CAM_GROUND_FRAC * screen.y)

	skill_overlay.mode = self
	skill_screen.mode = self

	# DEADLINE's line goes over the bricks and the ground — Foreground draws
	# after PiecesContainer — so a tower under it is seen to be under it; and
	# under the skills' overlay, so a night that hides the tower hides the
	# line too. Only made in that round: every other one keeps the scene tree
	# it always had.
	if is_deadline():
		deadline_layer = Node2D.new()
		deadline_layer.name = "Deadline"
		ground.add_sibling(deadline_layer)
		deadline_layer.draw.connect(_draw_deadline)

	_start_match()

# --- Match / turn flow -----------------------------------------------------

func _start_match() -> void:
	for c in pieces.get_children():
		pieces.remove_child(c)
		c.queue_free()
	active_piece = null

	# Before the arrays below are rebuilt: a deactivate() may look at
	# the slot it was attached to.
	_clear_skill_effects()
	_setup_teams()
	lives = []
	team_cursor = []
	for t in range(team_count):
		# A team with nobody on this tower (the other side of a race) is
		# simply never alive here, so turn order and the end check skip it
		# without having to know why.
		lives.append(_start_lives() if not _team_members(t).is_empty() else 0)
		team_cursor.append(0)
	charge = []
	held_self = []
	held_opponent = []
	turns_flown = []
	bricks_dropped = []
	for _i in range(GameSettings.player_count):
		charge.append(0)
		held_self.append("")
		held_opponent.append("")
		turns_flown.append(0)
		bricks_dropped.append(0)
	turn_team = team_count - 1 # so the first _begin_turn() advances onto team 0
	crew_mate = -1
	winner_team = -1
	out_order = []
	_cup_leave_in = 0.0
	_cup_round_shown = GameSettings.cup_round + 1
	goal_cells = _goal_for_variant()
	storm_in = STORM_EVERY
	storms = 0
	frame_cells = {}
	frame_plan = []
	frame_score = 0.0
	deadline_time = 0.0
	deadline_cells = _deadline_at(0.0)
	deadline_top = 0.0
	under_time = 0.0
	deadline_out_at = -1.0
	if is_frame():
		# A frame is made from the deal, so it needs one even off the host.
		if brick_seed == 0:
			brick_seed = (randi() & 0x7fffffff) | 1
		var made: Dictionary = TowerFrame.generate(brick_seed, FRAME_BRICKS, int(PLATFORM_CELLS), CLASSIC_BIAS)
		frame_cells = made["cells"]
		frame_plan = made["plan"]
	_brick_rng = null
	if brick_seed != 0:
		_brick_rng = RandomNumberGenerator.new()
		_brick_rng.seed = brick_seed

	stack_top_y = 0.0
	best_height = 0
	bricks_placed = 0
	fallen_this_turn = 0
	cam_y = _camera_target()
	cam_start_y = cam_y
	camera.position = Vector2(0.0, cam_y)
	backdrop.set_scroll(0.0)
	next_index = _next_brick()
	overlay.visible = false
	# Not just the toast: a pip left mid-pop by the last match would play out
	# over this one's fresh row of three.
	hud.reset()

	# Nobody is on the clock yet; this is only what the HUD reads during the
	# countdown, and _begin_turn() picks the real first player from turn_team.
	active_slot = members.back()

	# `countdown` is a state of its own rather than a paused `piloting`:
	# _physics_process's match has no branch for it, so the descent, the
	# shape queries and the settle checks are all simply not running, and
	# _unhandled_input's `state != "piloting"` gate already refuses every key
	# but Esc. Nothing had to learn the word "paused".
	state = "countdown"
	_refresh_hud() # lives and "P1 — GET READY" up before the first brick
	countdown.start()

func _on_countdown_finished() -> void:
	_begin_turn()

func _begin_turn() -> void:
	if _decided():
		_end_match()
		return
	var team: int = _next_living_team(turn_team)
	if team == -1:
		_end_match()
		return

	# The team's next member flies, and the rotation moves on for next time.
	var crew: Array[int] = _team_members(team)
	var go: int = team_cursor[team]
	team_cursor[team] = go + 1
	turn_team = team
	active_slot = crew[go % crew.size()]
	crew_mate = crew[(go + 1) % crew.size()] if variant == GameSettings.TOWER_COPILOT and crew.size() > 1 else -1
	turns_flown[active_slot] += 1
	_follow_the_crew(team)
	_recompute_stack_top()

	# Hexes queued against this player join the live list *before* the spawn
	# — their brick_scale()/spawn_index_override() have to be consulted for
	# the brick about to appear — but activate() only runs *after* it, so
	# the effect can see the brick it is attached to. Those two hooks are
	# therefore read before activate() on an effect's first turn, and
	# TowerSkill's header tells authors to keep them constant.
	var arriving: Array = []
	for e in queued_effects:
		if e.target == active_slot:
			arriving.append(e)
	for e in arriving:
		queued_effects.erase(e)
		active_effects.append(e)

	var piece: TowerPiece = PIECE_SCENE.instantiate()
	pieces.add_child(piece) # before setup(): it reaches its @onready Sprite2D
	piece.setup(_effect_spawn_index(next_index), CELL * _effect_brick_scale(), active_slot, _slot_color(active_slot))
	next_index = _next_brick()

	aim_steps = 0
	aim_x = 0.0
	dash_active = false
	dash_target_x = 0.0
	dash_dir = 0
	dash_ghost_timer = 0.0
	wedge_timer = 0.0
	hold_dir = 0
	hold_timer = 0.0
	piece.rotation = 0.0
	piece.global_position = Vector2(aim_x, _spawn_y())
	active_piece = piece

	fallen_this_turn = 0
	state = "piloting"

	# Now the brick exists: first-turn effects come alive, and effects already
	# live on this player from an earlier turn are told a new one has begun.
	for e in arriving:
		e.activate()
		if e.is_done():
			_retire(e) # an instant (duration_turns 0) has already done everything
	for e in _live_for(active_slot):
		if not arriving.has(e):
			e.on_turn_start()
	_refresh_hud()

# The brick has touched something. It stops being steered and becomes an
# ordinary rigid body exactly where it stopped — with no velocity, because
# the descent was never real momentum. Everything dramatic from here on is
# the solver's doing, not the player's.
func _land() -> void:
	if active_piece == null:
		return
	active_piece.release()
	# Permanent, by design: this is a landed brick now, and a heavy one stays
	# heavy in the tower for everyone who builds on it after.
	var live: Array = _live_for(active_slot)
	if not live.is_empty():
		active_piece.mass *= _effect_mass_mult()
		active_piece.gravity_scale *= _effect_gravity_mult()
		var friction: float = _effect_friction()
		if friction >= 0.0:
			var mat := PhysicsMaterial.new()
			mat.friction = friction
			mat.bounce = TowerPiece.BOUNCE
			mat.rough = true
			active_piece.physics_material_override = mat
		for e in live:
			e.on_release(active_piece)
	state = "settling"
	settle_timer = 0.0
	fall_timer = 0.0
	_refresh_hud()

func _resolve_turn() -> void:
	_cull_fallen()
	# Clear this *before* recomputing: the brick just placed is part of the
	# stack now, and _recompute_stack_top() skips whatever active_piece
	# points at (so the camera doesn't chase a brick on its way down).
	active_piece = null
	_recompute_stack_top()

	bricks_placed += 1
	best_height = max(best_height, int(round(-stack_top_y / CELL)))

	var team: int = team_of[active_slot]
	if is_frame():
		_update_frame_mark()
	if is_frame() or is_deadline():
		# Neither has lives to spend on a fall: it costs fit, or the height it
		# did not add — which is exactly what the line reads.
		bricks_dropped[active_slot] += fallen_this_turn
	elif fallen_this_turn > 0:
		lives[team] = max(0, lives[team] - 1)
		bricks_dropped[active_slot] += fallen_this_turn
		# The count is already down, so it indexes the pip just spent — the
		# same convention PlayerBoard._spend_heart() uses on the other mode's
		# row. The HUD swells it out of its slot rather than blanking it.
		hud.spend_life(team, lives[team])
		if lives[team] <= 0:
			out_order.append(team)

	# A clean placement is the charge. Deliberately not "any placement": a
	# skill has to be earned by building, or the player who is knocking the
	# tower over every turn is the one being handed the tools. In co-pilot both
	# pairs of hands built it, so both are paid.
	if fallen_this_turn == 0 and lives[team] > 0 and not is_frame():
		charge[active_slot] = mini(CHARGE_TO_SKILL, charge[active_slot] + 1)
		_try_grant(active_slot)
		if crew_mate >= 0:
			charge[crew_mate] = mini(CHARGE_TO_SKILL, charge[crew_mate] + 1)
			_try_grant(crew_mate)

	# The turn is over for every effect riding it, and the ones that have run
	# their turns out leave here — after the falls were counted, so an effect
	# whose whole point is what happens to the tower on landing gets to see
	# the verdict in on_turn_end().
	var finished: Array = []
	for e in _live_for(active_slot):
		e.on_turn_end()
		e.turns_left -= 1
		if e.is_done():
			finished.append(e)
	for e in finished:
		_retire(e)
	if lives[team] <= 0:
		for s in _team_members(team):
			_drop_slot_skills(s)

	# Height decides a goal-line variant, but only on a tower that is at rest
	# — which this is, since a turn only resolves once the world has stopped.
	# _begin_turn() sees winner_team and ends the match from there.
	if goal_cells > 0.0 and lives[team] > 0 and _height_cells() >= goal_cells - GOAL_SLACK_CELLS:
		winner_team = team
	elif variant == GameSettings.TOWER_COOP and lives[team] > 0:
		_storm_tick()

	state = "resolving"
	resolve_timer = RESOLVE_PAUSE
	_refresh_hud()
	# In the race the result is reported the frame it is known, not after the
	# resolve pause: that pause is longer after a turn that cost a life, and
	# a race must not be decided by which tower's toast was longer. Last, so
	# the host's halt() is the final word on `state`.
	if host != null and _decided():
		host.tower_finished(self)

func _end_match() -> void:
	state = "gameover"
	_clear_skill_effects()
	if active_piece != null and active_piece.held:
		pieces.remove_child(active_piece)
		active_piece.queue_free()
	active_piece = null

	# A tower in the race does not announce anything: one result covers both
	# towers, so the host owns the overlay. It is told unless it is the one
	# stopping us (halt()), which is how the second tower ends.
	if host != null:
		_refresh_hud()
		if not _halting:
			host.tower_finished(self)
		return

	# A goal line decides a match outright; otherwise the winner is whoever
	# is left standing, and only on a tower that had more than one team on it.
	var winner: int = winner_team
	if winner == -1 and _teams_here().size() > 1:
		for t in _teams_here():
			if lives[t] > 0:
				winner = t
				break

	if variant == GameSettings.TOWER_FFA:
		overlay_title.text = "NOBODY WINS" if winner == -1 else "%s WINS" % GameSettings.PLAYER_CONFIGS[winner]["name"]
		var lines: String = "Tower reached %d bricks high — %d placed\n\n" % [best_height, bricks_placed]
		for i in range(lives.size()):
			var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[i]
			lines += "%s: %s\n" % [cfg["name"], "OUT" if lives[i] <= 0 else "%d lives left" % lives[i]]
		overlay_body.text = lines.strip_edges()
	else:
		overlay_title.text = _result_title(winner)
		overlay_body.text = _result_body()
	if GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE:
		var order: Array[int] = placements()
		GameSettings.cup_record(order, placement_places(order))
		overlay_hint.text = "ENTER for the trophies      ESC for the menu"
		_cup_leave_in = CUP_RESULT_HOLD
	overlay.visible = true
	_refresh_hud()

# This match's teams from 1st to last — what a cup pays out on. Whoever is
# still standing first (the winner, then by lives left, which only matters
# once a goal line can end a match with more than one team alive), then the
# eliminated in reverse: the last one out came 2nd. Within a match only one
# team can lose a life per turn, so nobody is ever eliminated level with
# anybody else and the order is never a coin toss.
#
# Co-op has one team and nobody to beat, so it is placed by player instead —
# which is the solo cup's competitor anyway — and by who dropped the fewest
# bricks; the crew won or lost together, so that is the only thing in it that
# was anybody's own. Equal counts are equal places (placement_places()).
func placements() -> Array[int]:
	if variant == GameSettings.TOWER_COOP:
		var crew: Array[int] = members.duplicate()
		crew.sort_custom(func(a: int, b: int) -> bool:
			return bricks_dropped[a] < bricks_dropped[b] or (bricks_dropped[a] == bricks_dropped[b] and a < b))
		return crew
	var order: Array[int] = []
	for t in _teams_here():
		if lives[t] > 0:
			order.append(t)
	order.sort_custom(func(a: int, b: int) -> bool:
		return lives[a] > lives[b] or (lives[a] == lives[b] and a < b))
	if winner_team >= 0 and order.has(winner_team):
		order.erase(winner_team)
		order.push_front(winner_team)
	for i in range(out_order.size() - 1, -1, -1):
		if not order.has(out_order[i]):
			order.append(out_order[i])
	for t in _teams_here():
		if not order.has(t):
			order.append(t)
	return order

# Each entry of placements()' 0-based place: its index, except in co-op,
# where the same number of bricks dropped is the same place — 1st, 1st, 3rd.
func placement_places(order: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for i in range(order.size()):
		if variant == GameSettings.TOWER_COOP and i > 0 \
				and bricks_dropped[order[i]] == bricks_dropped[order[i - 1]]:
			out.append(out[i - 1])
		else:
			out.append(i)
	return out

func _leave_for_cup() -> void:
	_cup_leave_in = 0.0
	get_tree().change_scene_to_file(CUP_SCENE)

var _halting := false

# The race host stopping this tower, because the race was decided — on this
# tower or on the other one. Mid-descent is fine: _end_match() takes the held
# brick away and clears every skill, same as any game over.
func halt() -> void:
	if state == "gameover":
		return
	_halting = true
	_end_match()
	_halting = false

# A hex cast on the other tower in the race, arriving here. It goes to
# whoever flies this tower's next brick — the turn in progress, if there is
# one, is somebody else's and is left alone, exactly as a hex never lands on
# the turn it was cast in. Returns who it was queued on; empty if refused.
func receive_hex(id: String, caster: int) -> Array[int]:
	var out: Array[int] = []
	if state == "gameover":
		return out
	var probe: TowerSkill = TowerSkillCatalog.make(id, self, caster, caster)
	if probe == null:
		return out
	if probe.affects_all_opponents():
		for s in members:
			if lives[team_of[s]] > 0:
				out.append(s)
	else:
		var next: int = _next_turn_slot()
		if next >= 0:
			out.append(next)
	if out.is_empty():
		return out
	_queue_hex(id, caster, out)
	var names: Array[String] = []
	for t in out:
		names.append(slot_name(t))
	var c: Color = _slot_color(caster)
	hud.show_message("%s → %s — %s" % [slot_name(caster), " + ".join(names), TowerSkillCatalog.title_of(id)], Color(c.r, c.g, c.b, 1.0))
	_refresh_hud()
	return out

# One line for the race's result screen: this tower's team, how high it got
# and how it got there.
func team_summary() -> String:
	var t: int = _teams_here()[0] if not _teams_here().is_empty() else 0
	var crew: Array[int] = _team_members(t)
	if is_frame():
		var dropped := 0
		for s in crew:
			dropped += bricks_dropped[s]
		var who: String = slot_name(crew[0]) if crew.size() == 1 else GameSettings.tower_team_name(t, variant)
		return "%s — %d%% fit, %d %s dropped" % [who, frame_pct(), dropped, "brick" if dropped == 1 else "bricks"]
	if is_deadline():
		var lost := 0
		for s in crew:
			lost += bricks_dropped[s]
		var who: String = slot_name(crew[0]) if crew.size() == 1 else GameSettings.tower_team_name(t, variant)
		# "Still in", not "above the line": the winner is often under it too,
		# with time left on its count, when the last rival's runs out.
		var held: String = ("out after %ds" % roundi(deadline_out_at)) if deadline_out_at >= 0.0 \
			else ("still in after %ds" % roundi(deadline_time))
		return "%s — %s, %d high, %d %s dropped" % [who, held, roundi(_top_cells()), lost, "brick" if lost == 1 else "bricks"]
	var standing: String = "OUT" if lives[t] <= 0 else "%d %s left" % [lives[t], "life" if lives[t] == 1 else "lives"]
	# A tower of one (the solo race) is named once, not as a team and again
	# as its only member.
	if crew.size() == 1:
		var s: int = crew[0]
		return "%s — %d high, %s, %d flown, %d dropped" % [
			slot_name(s), int(round(_height_cells())), standing, turns_flown[s], bricks_dropped[s]]
	var parts: Array[String] = []
	for s in crew:
		parts.append("%s %d flown, %d dropped" % [slot_name(s), turns_flown[s], bricks_dropped[s]])
	return "%s — %d high, %s — %s" % [
		GameSettings.tower_team_name(t, variant),
		int(round(_height_cells())),
		standing,
		"  ·  ".join(parts),
	]

func _result_title(winner: int) -> String:
	if variant == GameSettings.TOWER_COOP:
		return "TOWER COMPLETE!" if winner >= 0 else "THE STORM WINS"
	if winner == -1:
		return "NOBODY WINS"
	return "%s WINS" % GameSettings.tower_team_name(winner, variant)

# One line per team — its pool, then each member's own tally — and the
# wrecking ball. The tally is the point of the line: a shared pool hides who
# spent it, and on a couch that is exactly the thing everybody wants to know.
func _result_body() -> String:
	var lines: String = "Tower reached %d bricks high — %d placed\n\n" % [best_height, bricks_placed]
	if variant == GameSettings.TOWER_COOP:
		lines = "Tower reached %d of the %d needed — %d bricks placed, %d %s from the storm\n\n" % [
			best_height, int(goal_cells), bricks_placed, storms, "hex" if storms == 1 else "hexes"]
	# In co-pilot a turn is credited to whoever steered it, so the tally
	# answers the question a crew actually argues about: which way round
	# were we better?
	var flew: String = "steered" if variant == GameSettings.TOWER_COPILOT else "flown"
	for t in _teams_here():
		var parts: Array[String] = []
		for s in _team_members(t):
			parts.append("%s %d %s, %d dropped" % [slot_name(s), turns_flown[s], flew, bricks_dropped[s]])
		lines += "%s — %s — %s\n" % [
			GameSettings.tower_team_name(t, variant),
			"OUT" if lives[t] <= 0 else "%d %s left" % [lives[t], "life" if lives[t] == 1 else "lives"],
			"  ·  ".join(parts),
		]
	var worst: int = -1
	for s in members:
		if bricks_dropped[s] > 0 and (worst == -1 or bricks_dropped[s] > bricks_dropped[worst]):
			worst = s
	if worst >= 0:
		lines += "\nWrecking ball: %s, %d %s dropped" % [
			slot_name(worst), bricks_dropped[worst], "brick" if bricks_dropped[worst] == 1 else "bricks"]
	if variant == GameSettings.TOWER_COOP and GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE:
		lines += "\nFor the cup: fewest bricks dropped places first"
	return lines.strip_edges()

# --- Per-frame -------------------------------------------------------------

# Camera, backdrop and HUD only. Everything that touches the physics world
# lives in _physics_process, because the shape queries the piloting model is
# built on are only valid there.
func _process(delta: float) -> void:
	cam_y = lerp(cam_y, _camera_target(), 1.0 - exp(-CAM_LERP * delta))
	camera.position = Vector2(0.0, cam_y)
	backdrop.set_scroll(maxf(0.0, (cam_start_y - cam_y) * BACKDROP_PARALLAX))
	hud.tick(delta)
	if _cup_leave_in > 0.0:
		_cup_leave_in -= delta
		if _cup_leave_in <= 0.0:
			_leave_for_cup()
	queue_redraw()
	if deadline_layer != null:
		deadline_layer.queue_redraw()
	# Every frame, live effects or not: a CanvasItem keeps its last draw list
	# until asked again, so the frame after the last effect leaves needs a
	# redraw too, and asking unconditionally is cheaper than tracking that.
	skill_overlay.queue_redraw()
	skill_screen.queue_redraw()

func _physics_process(delta: float) -> void:
	_recompute_stack_top()
	if state == "piloting" or state == "settling" or state == "resolving":
		for e in _live_for(active_slot):
			e.tick(delta)
		if is_deadline():
			_update_deadline(delta)
	match state:
		"countdown":
			# Advanced here, not from the node's own _process: the first
			# brick is then created on a physics frame, like every other
			# thing a turn does. See Countdown's header.
			countdown.advance(delta)
		"piloting":
			_update_piloting(delta)
		"settling":
			_update_settling(delta)
		"resolving":
			_cull_fallen()
			resolve_timer -= delta
			if resolve_timer <= 0.0:
				_begin_turn()
		"gameover":
			_cull_fallen()

# Each axis is a separate request: move sideways if that space is free, turn
# if that space is free, descend if that space is free. Only the last one
# ends the turn — being unable to step sideways into the tower is an ordinary
# thing that happens all the way down, and treating it as a landing would
# drop bricks against walls they merely brushed.
func _update_piloting(delta: float) -> void:
	if active_piece == null:
		return

	_update_hold_repeat(delta)

	var pos: Vector2 = active_piece.global_position
	var rot: float = active_piece.rotation

	# A dash owns the brick only as far as the cell it was aimed at, which is
	# why it chases `dash_target_x` rather than `aim_x`. Those two come apart
	# whenever a hold-repeat tick lands mid-dash and pushes the command
	# further on: chasing `aim_x` would then carry the extra half cell at
	# dash speed too, and holding a direction would quietly become a
	# permanent fast mode. (The old guard against that was to cancel the
	# dash outright on every repeat tick, which cost the dash its fast
	# frames instead — measured as the first fast frames landing, then the
	# remainder of the same cell crawling at FOLLOW_SPEED.)
	var follow_mult: float = _effect_follow_mult()
	var follow: float = FOLLOW_SPEED * follow_mult
	var goal: float = aim_x
	if dash_active:
		if signf(dash_target_x - pos.x) == float(dash_dir):
			follow = DASH_FOLLOW_SPEED * follow_mult
			goal = dash_target_x
		else:
			dash_active = false # arrived; the ordinary follow takes it from here
	var step: float = clampf(goal - pos.x, -follow * delta, follow * delta)
	if absf(step) > 0.001:
		var want := Vector2(pos.x + step, pos.y)
		if _blocked(Transform2D(rot, want), Vector2(signf(step), 0.0)):
			aim_x = pos.x # give up on the command rather than grinding against it
			dash_active = false
		else:
			pos = want
	dash_ghost_timer = maxf(0.0, dash_ghost_timer - delta)

	var target_rot: float = float(aim_steps) * PI * 0.5
	if absf(angle_difference(rot, target_rot)) > 0.001:
		var want_rot: float = lerp_angle(rot, target_rot, 1.0 - exp(-ROTATE_LERP * delta))
		if not _blocked(Transform2D(want_rot, pos)):
			rot = want_rot

	var soft: bool = _soft_drop_held() and not _effect_soft_drop_locked()
	var fall: float = SOFT_DROP_SPEED * _effect_soft_drop_mult() if soft else DESCEND_SPEED * _effect_descend_mult()
	if not soft and _approaching(pos):
		fall *= APPROACH_MULT
	var want_down := Vector2(pos.x, pos.y + fall * delta)
	var landed := false
	if _blocked(Transform2D(rot, want_down), Vector2.DOWN):
		# Blocked is not the same as landed. If something is genuinely under
		# the brick the turn is over; if it has merely come up against the
		# side of a taller stack the player keeps steering, for as long as
		# they like — WEDGE_GRACE is an anti-deadlock backstop, not a clock.
		if _supported(Transform2D(rot, pos)):
			landed = true
		else:
			wedge_timer += delta
			if wedge_timer >= WEDGE_GRACE:
				landed = true
	else:
		pos = want_down
		wedge_timer = 0.0
		# Steered clean past the edge of the platform: there is nothing below
		# to land on, so it has missed everything. Without this the brick
		# would descend forever and the turn would never end — the aim bound
		# genuinely allows a brick to be walked entirely off the slab.
		if pos.y > LOST_Y:
			landed = true

	active_piece.global_position = pos
	active_piece.rotation = rot
	if landed:
		_land()
	else:
		_refresh_hud()

# Still in the open sky over the stack: the brick's lowest point more than
# APPROACH_GAP_CELLS above the top of the tower. The half-height is the
# brick's at its commanded turn, which is what it is turning toward.
func _approaching(pos: Vector2) -> bool:
	var bottom: float = pos.y + active_piece.aim_half_width(aim_steps + 1)
	return stack_top_y - bottom > APPROACH_GAP_CELLS * CELL

# Holding a direction repeats the half-cell step, after a delay long enough
# that a deliberate single tap never accidentally becomes two.
func _update_hold_repeat(delta: float) -> void:
	var dir: int = _aim_held()
	if dir == 0 or dir != hold_dir:
		hold_dir = dir
		hold_timer = HOLD_REPEAT_DELAY
		return
	hold_timer -= delta
	if hold_timer <= 0.0:
		hold_timer = HOLD_REPEAT_INTERVAL
		_command_move(dir, STEP_CELLS)

# Steps the *command*, not the brick's live position. Doing it this way is
# what keeps the half-cell lattice exact: pressing again while the brick is
# still travelling adds a clean half cell to where it was already going,
# rather than half a cell from wherever it happens to have got to.
func _command_move(dir: int, cells: float) -> void:
	if active_piece == null:
		return
	_command_to(aim_x + float(dir) * CELL * cells)

func _command_to(x: float) -> void:
	if active_piece == null:
		return
	var limit: float = maxf(
		0.0,
		PLATFORM_CELLS * CELL * 0.5 + AIM_BOUND_CELLS * CELL - active_piece.aim_half_width(aim_steps)
	)
	aim_x = clampf(x, -limit, limit)

# The brick is out of the collision world while it is being flown (see
# TowerPiece.set_held), so these ask the space directly rather than relying
# on contacts. Only valid from _physics_process.
func _query_hits(shape_list: Array[Shape2D], local: Array[Transform2D], xform: Transform2D) -> bool:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.margin = 0.0
	for i in range(shape_list.size()):
		q.shape = shape_list[i]
		q.transform = xform * local[i]
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false

# "Can the brick be here?" — used for every move, in all three axes.
#
# `along` is the world direction the brick is trying to move in, and it is
# what decides where the contact tolerance is taken off (see QUERY_SKIN).
# Vector2.ZERO means "no direction" — used for rotation, which trims both
# axes instead.
func _blocked(xform: Transform2D, along: Vector2 = Vector2.ZERO) -> bool:
	if active_piece == null:
		return false
	return _query_hits(_skinned_shapes(xform, along), active_piece.body_xforms, xform)

# The brick's collision boxes, trimmed by QUERY_SKIN across the direction of
# travel. The boxes are stored in the brick's own frame, so the world axis to
# trim has to be brought back into that frame first — at a quarter-turn that
# is an exact swap of the two axes, and part way through a rotation it splits
# the skin between them, which is the honest answer for a brick that is
# moving diagonally in its own terms.
func _skinned_shapes(xform: Transform2D, along: Vector2) -> Array[Shape2D]:
	var trim := Vector2(QUERY_SKIN, QUERY_SKIN)
	if along != Vector2.ZERO:
		var across: Vector2 = xform.basis_xform_inv(Vector2(-along.y, along.x)).normalized()
		trim = Vector2(QUERY_SKIN * absf(across.x), QUERY_SKIN * absf(across.y))
	var out: Array[Shape2D] = []
	for i in range(active_piece.query_shapes.size()):
		var size_px: Vector2 = active_piece.boxes[i].size * active_piece.cell
		var r: RectangleShape2D = active_piece.query_shapes[i]
		r.size = Vector2(
			maxf(2.0, size_px.x - trim.x * 2.0),
			maxf(2.0, size_px.y - trim.y * 2.0)
		)
		out.append(r)
	return out

# "Is anything holding the brick up?" — a different question, and the one
# that decides whether a turn is over. A brick pressed against the flank of a
# taller stack is blocked from descending but is not resting on anything, and
# ending its turn there is what made it go limp in mid-air with a visible
# void underneath. See TowerPiece.foot_shapes.
func _supported(xform: Transform2D) -> bool:
	if active_piece == null:
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.margin = 0.0

	# Built against the world axes, not the brick's. A foot stored in the
	# brick's own frame rotates with it, so a brick turned a half turn probes
	# upward and never finds the floor it is sitting on — which is exactly
	# what happened, on every brick that was not upright.
	var rot: float = xform.get_rotation()
	var c: float = absf(cos(rot))
	var sn: float = absf(sin(rot))
	for i in range(active_piece.foot_shapes.size()):
		var size_px: Vector2 = active_piece.boxes[i].size * active_piece.cell
		var world_w: float = size_px.x * c + size_px.y * sn
		var world_h: float = size_px.x * sn + size_px.y * c
		var rect: RectangleShape2D = active_piece.foot_shapes[i]
		rect.size = Vector2(maxf(4.0, world_w - TowerPiece.FOOT_INSET), TowerPiece.FOOT_DEPTH)
		var centre: Vector2 = xform * active_piece.body_xforms[i].origin
		q.shape = rect
		q.transform = Transform2D(
			0.0, centre + Vector2(0.0, world_h * 0.5 + TowerPiece.FOOT_DEPTH * 0.4)
		)
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false

func _update_settling(delta: float) -> void:
	fall_timer += delta
	_cull_fallen()
	if _everything_at_rest():
		settle_timer += delta
	else:
		settle_timer = 0.0
	if settle_timer >= SETTLE_HOLD or fall_timer >= SETTLE_TIMEOUT:
		_resolve_turn()

# Held bricks are skipped (they are frozen by definition) and sleeping bodies
# are taken at their word — a body Godot has put to sleep is by definition
# below its own rest thresholds, and re-testing its stale velocities would
# keep a settled tower from ever counting as settled.
func _everything_at_rest() -> bool:
	for c in pieces.get_children():
		var p := c as TowerPiece
		# Doomed bricks are excluded: they are already scored, they are below
		# the platform with nothing to hit, and whether they have finished
		# falling has no bearing on whether the tower has stopped.
		if p == null or p.held or p.doomed or p.sleeping:
			continue
		if p.linear_velocity.length() > SETTLE_LINEAR or absf(p.angular_velocity) > SETTLE_ANGULAR:
			return false
	return true

func _cull_fallen() -> void:
	for c in pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held:
			continue
		var pos: Vector2 = p.global_position
		if not p.doomed and (pos.y > LOST_Y or absf(pos.x) > LOST_X):
			p.doomed = true
			if p == active_piece:
				active_piece = null
			fallen_this_turn += 1
		if pos.y > DESPAWN_Y or absf(pos.x) > DESPAWN_X:
			pieces.remove_child(p)
			p.queue_free()

func _recompute_stack_top() -> void:
	var top := 0.0
	for c in pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed or p == active_piece:
			continue
		top = minf(top, p.top_y())
	stack_top_y = top

func _spawn_y() -> float:
	return stack_top_y - SPAWN_CLEARANCE

# The visible area in *world* units. Only equal to the viewport size at a
# zoom of 1, which this mode has not used since VISIBLE_CELLS landed.
func _view_world() -> Vector2:
	return get_viewport().get_visible_rect().size / cam_zoom

# A line width in *screen* pixels, for the foreground.
#
# Everything TowerMode draws is in world space and so shrinks with the zoom,
# which is right for the tower and wrong for the marks drawn over it: the
# height guides sit at alpha 0.10 and the play column's edges at 0.26,
# thicknesses chosen to be only just visible, and 28% off a hairline is the
# difference between subtle and absent. The brick is meant to look further
# away; the guide to it is not.
func _px(width: float) -> float:
	return width / cam_zoom

# One brick, drawn against CLASSIC_BIAS. Linear over nineteen entries, once a
# turn — there is nothing here worth precomputing a table for, and a table
# would be a second place for the split to be wrong.
#
# The pick itself is TowerFrame.pick_brick(), shared so that a frame drawn
# from a deal and the bricks dealt from it cannot disagree.
func _next_brick() -> int:
	return TowerFrame.pick_brick(_brick_rng.randf() if _brick_rng != null else randf(), CLASSIC_BIAS)

func _camera_target() -> float:
	var view_h: float = _view_world().y
	var resting: float = -(CAM_GROUND_FRAC - 0.5) * view_h
	var climbing: float = stack_top_y - (CAM_STACK_TOP_FRAC - 0.5) * view_h
	# minf, not maxf: -y is up, so the smaller value is the higher camera, and
	# the climbing shot only wins once it actually needs to.
	return minf(resting, climbing)

# --- Players and teams -----------------------------------------------------

func _setup_teams() -> void:
	team_of = []
	team_count = 0
	for s in range(GameSettings.player_count):
		var t: int = GameSettings.tower_team_of(s, variant)
		team_of.append(t)
		team_count = maxi(team_count, t + 1)

func _start_lives() -> int:
	match variant:
		GameSettings.TOWER_FFA:
			return START_LIVES
		GameSettings.TOWER_COOP:
			return COOP_LIVES
		GameSettings.TOWER_RACE, GameSettings.TOWER_RACE_SOLO:
			return RACE_LIVES
		GameSettings.TOWER_FRAME, GameSettings.TOWER_FRAME_SOLO:
			return 1 # never spent: a fallen brick costs fit, not a life
		GameSettings.TOWER_DEADLINE, GameSettings.TOWER_DEADLINE_SOLO:
			return 1 # never spent on a fall: only the line takes it
	return TEAM_LIVES

func _goal_for_variant() -> float:
	match variant:
		GameSettings.TOWER_COOP:
			return COOP_GOAL_CELLS
		GameSettings.TOWER_RACE, GameSettings.TOWER_RACE_SOLO:
			return RACE_GOAL_CELLS
	return 0.0

# The settled tower's height, in cells, from the platform to its top.
func _height_cells() -> float:
	return -stack_top_y / CELL

func is_frame() -> bool:
	return GameSettings.tower_is_frame(variant)

# The fit as a whole percentage — what the HUD shows, and what decides the
# round, so that two towers the screen calls level are level.
func frame_pct() -> int:
	return int(round(frame_score * 100.0))

# Marks the tower as it stands. Called once a turn, on a tower at rest.
func _update_frame_mark() -> void:
	var settled: Array = []
	for c in pieces.get_children():
		var p := c as TowerPiece
		if p != null and not p.held and not p.doomed:
			settled.append(p)
	var reach: float = PLATFORM_CELLS * CELL * 0.5 + AIM_BOUND_CELLS * CELL + CELL
	frame_score = TowerFrame.mark(frame_cells, settled, int(PLATFORM_CELLS), CELL, reach)["score"]

func is_deadline() -> bool:
	return GameSettings.tower_is_deadline(variant)

# Where the line is after `t` seconds of play, in cells over the platform's
# top — see DEADLINE_SPEED.
func _deadline_at(t: float) -> float:
	return DEADLINE_START_CELLS + DEADLINE_SPEED * t + 0.5 * DEADLINE_ACCEL * t * t

# How far the top is over the line, in cells; negative while it is under.
func deadline_margin() -> float:
	return deadline_top - deadline_cells

# The top the line is measured against, in cells: every brick on the tower,
# the one just let go included — it is part of the tower from the moment it
# lands, while it is still settling — and never the one still being flown, or
# a brick held up in the air would count as height. The platform's own top
# (0) with nothing on it. Not stack_top_y, which leaves the settling brick out
# so the camera does not chase a brick on its way down.
func _top_cells() -> float:
	var top := 0.0
	for c in pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed:
			continue
		top = minf(top, p.top_y())
	return -top / CELL

# DEADLINE, every physics frame of play: the line climbs, and a top under it
# runs its time out. Being back over it, even for a frame, starts the count
# again. When the time is up the tower is out on the spot — mid-descent too,
# since the line does not wait for a turn to end — and _end_match() tells the
# host, which declares a winner once only one tower is left above.
func _update_deadline(delta: float) -> void:
	deadline_time += delta
	deadline_cells = _deadline_at(deadline_time)
	deadline_top = _top_cells()
	if deadline_top >= deadline_cells:
		under_time = 0.0
		return
	under_time += delta
	if under_time < DEADLINE_GRACE:
		return
	deadline_out_at = deadline_time
	# A hosted tower has one team on it. Played on its own, the line takes
	# everyone on the tower together — they were all under it.
	for t in _teams_here():
		if lives[t] > 0:
			lives[t] = 0
			out_order.append(t)
	_end_match()

# Co-op only, once per resolved turn the crew survived. Counts down, and at
# zero sends a random hex at whoever flies next — as slot -1, which every
# name and colour lookup reads as THE STORM.
func _storm_tick() -> void:
	storm_in -= 1
	if storm_in > 0:
		return
	storm_in = STORM_EVERY_HIGH if _height_cells() >= goal_cells * 0.5 else STORM_EVERY
	var pool: Array[String] = TowerSkillCatalog.ids_in("opponent")
	var target: int = _next_turn_slot()
	if pool.is_empty() or target < 0:
		return
	var id: String = pool[randi() % pool.size()]
	_queue_hex(id, -1, [target])
	storms += 1
	# Only on a quiet turn: a turn that cost a life already has a toast up,
	# and the hex is listed under the banner either way.
	if fallen_this_turn == 0:
		hud.show_message("THE STORM SENDS %s AT %s" % [TowerSkillCatalog.title_of(id), slot_name(target)], STORM_COLOR)

# A team's members on THIS tower, in seat order — which is also the order
# they take the team's turns in.
func _team_members(team: int) -> Array[int]:
	var out: Array[int] = []
	for s in members:
		if team_of[s] == team:
			out.append(s)
	return out

func _teams_here() -> Array[int]:
	var out: Array[int] = []
	for s in members:
		if not out.has(team_of[s]):
			out.append(team_of[s])
	out.sort()
	return out

# The next team after `from` in turn order that still has lives and somebody
# on this tower to spend them. Wraps round to `from` itself, which is what a
# one-team tower (co-op, either side of a race) needs.
func _next_living_team(from: int) -> int:
	if team_count == 0:
		return -1
	for step in range(1, team_count + 1):
		var t: int = (from + step + team_count) % team_count
		if lives[t] > 0 and not _team_members(t).is_empty():
			return t
	return -1

# Co-pilot only. An effect is attached to a slot, and every hook is read off
# the slot on the clock — but a crew swaps who that is every turn, so an
# effect on the crew would otherwise skip every other one of its turns (a
# two-turn Tailor would measure on P1's turn and then wait for P1 to steer
# again, two crew turns later). Moving every effect on the crew onto this
# turn's pilot, before the queue is read and before the brick spawns, makes
# the crew the thing a skill is attached to. Skills only ever compare
# `target` with `mode.active_slot` (and Rubble names it in a toast), so a
# target that moves between turns is invisible to them.
func _follow_the_crew(team: int) -> void:
	if crew_mate < 0:
		return
	for e in active_effects + queued_effects:
		if e.target >= 0 and team_of[e.target] == team:
			e.target = active_slot

# Who will fly `team`'s next brick, without moving the rotation.
func _pilot_of(team: int) -> int:
	var crew: Array[int] = _team_members(team)
	if crew.is_empty():
		return -1
	return crew[team_cursor[team] % crew.size()]

# Whoever is up after the current turn — the HUD's "GET READY", and the
# target of an ordinary hex.
func _next_turn_slot() -> int:
	var t: int = _next_living_team(turn_team)
	return _pilot_of(t) if t >= 0 else -1

func _living_teams() -> int:
	var n := 0
	for t in _teams_here():
		if lives[t] > 0:
			n += 1
	return n

# Over when a goal line has been reached, when nobody is left, or — on a tower
# with rivals on it — when only one team is. A one-team tower (co-op, a side
# of the race) is never "won" by being the last one standing; it was always
# the only one.
func _decided() -> bool:
	if winner_team >= 0:
		return true
	if is_frame():
		return bricks_placed >= FRAME_BRICKS
	var alive: int = _living_teams()
	if alive == 0:
		return true
	return _teams_here().size() > 1 and alive <= 1

func _slot_color(slot: int) -> Color:
	if slot < 0:
		return STORM_COLOR
	if slot < GameSettings.skin_colors.size():
		return GameSettings.skin_colors[slot]
	return Color(0.8, 0.8, 0.85)

# A team is drawn in its first member's colour. Teams are seats rather than a
# pick, so there is no separate team colour to choose — and the first member's
# colour is already on the screen, on their card and their brick.
func _team_color(team: int) -> Color:
	var crew: Array[int] = _team_members(team)
	return _slot_color(crew[0]) if not crew.is_empty() else Color(0.8, 0.8, 0.85)

# What the HUD and the toasts call a slot. -1 is the storm in co-op, which
# casts hexes like a player but is not one.
func slot_name(slot: int) -> String:
	if slot < 0:
		return "THE STORM"
	return GameSettings.PLAYER_CONFIGS[slot]["name"]

# --- Input -----------------------------------------------------------------

# Piloting reads the held keys straight, the same way PlayerBoard's steering
# does. Unlike PlayerBoard there is no bot to keep compatible here, so the
# §7 "everything goes through _steer_held()" rule doesn't apply — but this is
# still funnelled through these functions so a future tower bot has a single
# place to plug into. Both keys down reads as neutral with no tiebreak: this
# is stepped positioning, not momentum steering, so PlayerBoard's
# steer_priority problem doesn't arise.
func _aim_held() -> int:
	var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[active_slot]
	var l: bool = Input.is_physical_key_pressed(cfg["left"])
	var r: bool = Input.is_physical_key_pressed(cfg["right"])
	if l == r:
		return 0
	return _effect_steer_dir(-1 if l else 1)

# A mirrored player's left is right. Applied where the *keys* are read —
# here and in _unhandled_input — and nowhere deeper, so the probes that steer
# through _press_steer() on the lattice are never lied to.
func _effect_steer_dir(dir: int) -> int:
	return -dir if _effect_steer_flipped() else dir

func _soft_drop_held() -> bool:
	return Input.is_physical_key_pressed(GameSettings.PLAYER_CONFIGS[active_slot]["down"])

func _dash_held() -> bool:
	return Input.is_physical_key_pressed(GameSettings.PLAYER_CONFIGS[active_slot]["confirm"])

# A direction press is half a cell — unless the dash key is being held, in
# which case the direction key is what *chooses the way* and the press is the
# dash itself.
#
# This is the same chord as "hold a direction, press dash" read from the
# other end, and having both is the point: which key ends up under a finger
# first depends on where the brick already is and which way the hand was
# going, and a player should not have to plan that. It also retires the
# nastiest corner this input had. The dash key alone has no direction to go
# on, and the two previous answers to that were both bad — guess from the
# last key pressed (surprises the player), or do nothing at all (reads as a
# broken button, and is exactly how this mechanic was first reported: "i
# cant dash", §5 session S). With a chord there is a third answer: pressing
# the dash key on its own is not a dash yet, it is the first half of one,
# and the direction key that follows finishes it. Nothing is guessed and
# nothing is swallowed.
func _press_direction(dir: int) -> void:
	if active_piece == null:
		return
	if _dash_held() and not _effect_dash_locked():
		_dash(dir)
		# Keep the repeat armed anyway: a player who holds both keys down is
		# still asking to keep moving after the dash lands.
		hold_dir = dir
		hold_timer = HOLD_REPEAT_DELAY
	else:
		_press_steer(dir)

# The plain half-cell step, with no dash key involved. Kept as its own entry
# point rather than folded into _press_direction() because StallProbe steers
# through it to walk a brick down the real half-cell lattice (§5 session T).
func _press_steer(dir: int) -> void:
	if active_piece == null:
		return
	if dash_active and dir != dash_dir:
		dash_active = false # steering back the other way ends the dash there
	_command_move(dir, STEP_CELLS)
	hold_dir = dir
	hold_timer = HOLD_REPEAT_DELAY

# The dash key: dashes the way you are already holding. Pressed on its own it
# does nothing *yet* — it is holding down the other half of the chord, and
# the direction key that follows dashes through _press_direction().
func _press_dash() -> void:
	if active_piece == null or _effect_dash_locked():
		return
	var dir: int = _aim_held()
	if dir != 0:
		_dash(dir)

# One whole cell sideways, fast, with an afterimage.
func _dash(dir: int) -> void:
	if active_piece == null or dir == 0:
		return
	# A dash hard against the aim bound cannot move the brick. Starting one
	# anyway would leave the fast follow armed with nowhere to go and arm
	# the afterimage for a move that never happens.
	var before: float = aim_x
	_command_move(dir, DASH_CELLS)
	if is_equal_approx(aim_x, before):
		return
	dash_ghost_x = active_piece.global_position.x
	dash_ghost_timer = DASH_GHOST_TIME
	dash_active = true
	dash_target_x = aim_x
	dash_dir = dir

func _unhandled_input(event: InputEvent) -> void:
	# A tower in the race is one of two on screen and both have to hear every
	# key, so the host forwards them to handle_key() itself rather than
	# relying on which SubViewport Godot happens to deliver an event to.
	if host != null:
		return
	handle_key(event)

func handle_key(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode

	if key == KEY_ESCAPE:
		if host == null:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	if state == "gameover":
		if key == KEY_ENTER and host == null:
			if GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE:
				_leave_for_cup()
			else:
				_start_match()
		return

	# Cast keys from everyone on this tower, not just whoever is flying: a
	# teammate's self skill can be cast *for* the player on the clock (see
	# _may_cast), which is the one thing a player can do on somebody else's
	# turn. Every key here is unique across the four clusters, so reading all
	# of them cannot shadow anything.
	for s in members:
		var c: Dictionary = GameSettings.PLAYER_CONFIGS[s]
		if key == c["cast_self"]:
			_cast(s, "self")
			return
		if key == c["cast_opponent"]:
			_cast(s, "opponent")
			return
	if state != "piloting" or active_piece == null:
		return

	# Rotation reuses the two skill-choice buttons rather than the confirm
	# key: they are the only bindings every player already has that aren't
	# needed for moving or dropping, and they flank confirm on the keyboard
	# so "left of drop / right of drop" turns left / right. In co-pilot they
	# are read off the *other* member of the crew — see _turner_slot().
	var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[active_slot]
	var turner: Dictionary = GameSettings.PLAYER_CONFIGS[_turner_slot()]
	if key == turner["skill_self"]:
		if not _effect_rotation_locked():
			aim_steps += 1
	elif key == turner["skill_opponent"]:
		if not _effect_rotation_locked():
			aim_steps -= 1
	elif key == cfg["confirm"]:
		_press_dash()
	elif key == cfg["left"]:
		_press_direction(_effect_steer_dir(-1))
	elif key == cfg["right"]:
		_press_direction(_effect_steer_dir(1))

# Whose rotate keys turn the brick: the pilot's own, except in co-pilot,
# where the crew splits one brick between two people.
func _turner_slot() -> int:
	return crew_mate if crew_mate >= 0 else active_slot

# --- Skills ----------------------------------------------------------------
# The plumbing only. What a skill *does* is entirely inside its TowerSkill.

# Hand `slot` a skill straight into the matching slot, ignoring charge. The
# grant path and the probe both come through here.
func _grant(slot: int, id: String) -> void:
	if not TowerSkillCatalog.has_skill(id):
		return
	if TowerSkillCatalog.category_of(id) == "self":
		held_self[slot] = id
	else:
		held_opponent[slot] = id

# At CHARGE_TO_SKILL, a random skill into an empty slot. Both empty: a coin
# toss between the categories. Neither empty: the charge stays banked, full,
# and converts the moment a slot frees. A category with nothing in the
# catalogue is skipped rather than granting "".
func _try_grant(slot: int) -> void:
	if charge[slot] < CHARGE_TO_SKILL:
		return
	var open: Array[String] = []
	if held_self[slot] == "" and not TowerSkillCatalog.ids_in("self").is_empty():
		open.append("self")
	if held_opponent[slot] == "" and _has_rivals() and not TowerSkillCatalog.ids_in("opponent").is_empty():
		open.append("opponent")
	if open.is_empty():
		return
	var category: String = open[randi() % open.size()]
	var pool: Array[String] = TowerSkillCatalog.ids_in(category)
	var id: String = pool[randi() % pool.size()]
	_grant(slot, id)
	charge[slot] = 0
	var who: String = GameSettings.PLAYER_CONFIGS[slot]["name"]
	var c: Color = _slot_color(slot)
	hud.show_message("%s EARNED %s" % [who, TowerSkillCatalog.title_of(id)], Color(c.r, c.g, c.b, 1.0))

# Is there anyone a hex could ever land on? Not in co-op, where everyone on
# the tower is on one side — the storm is the only one casting hexes there,
# so a player is never handed one they could not use.
func _has_rivals() -> bool:
	return host != null or _teams_here().size() > 1

# Who may cast what, right now. The player on the clock always may, and in
# co-pilot so may the crew member turning the brick, since the turn is both
# of theirs. A teammate may also cast a SELF skill on the flyer's behalf — a
# support cast, the one thing anybody can do on somebody else's turn — but
# never a hex: a hex is aimed at the next team up, and choosing when to send
# it is the flyer's call. In free-for-all nobody has a teammate, so this
# reduces to "only on your own turn", exactly as before.
func _may_cast(slot: int, category: String) -> bool:
	if not members.has(slot):
		return false
	if slot == active_slot or slot == crew_mate:
		return true
	return category == "self" and team_of[slot] == team_of[active_slot] and lives[team_of[slot]] > 0

# Only during a piloting, with a brick in the air. A self skill goes live
# now, on whoever is flying; an opponent skill is queued for its target's
# next turn (see TowerSkill's header for why never sooner). Refused, and
# kept, when there is no one to hex — the match is ending on that turn anyway.
func _cast(slot: int, category: String) -> bool:
	if state != "piloting" or active_piece == null or not _may_cast(slot, category):
		return false
	var id: String = held_self[slot] if category == "self" else held_opponent[slot]
	if id == "":
		return false
	var who: String = slot_name(slot)
	var c: Color = _slot_color(slot)
	var title: String = TowerSkillCatalog.title_of(id)
	if category == "self":
		# Attached to whoever is flying, whoever cast it: the hooks are all
		# read off the player on the clock (see _live_for), so this is what
		# makes a support cast land on the brick it was cast for.
		var e: TowerSkill = TowerSkillCatalog.make(id, self, slot, active_slot)
		if e == null:
			return false
		held_self[slot] = ""
		_go_live(e)
		if slot == active_slot:
			hud.show_message("%s — %s" % [who, title], Color(c.r, c.g, c.b, 1.0))
		else:
			hud.show_message("%s → %s — %s" % [who, slot_name(active_slot), title], Color(c.r, c.g, c.b, 1.0))
	else:
		var probe: TowerSkill = TowerSkillCatalog.make(id, self, slot, slot)
		if probe == null:
			return false
		# In the race the rivals are on the other tower, so the hex is handed
		# across and queued there, on that tower's own clock.
		var targets: Array[int] = []
		if host != null:
			targets = host.relay_hex(self, id, slot)
		else:
			targets = _hex_targets(team_of[slot], probe.affects_all_opponents())
			if not targets.is_empty():
				_queue_hex(id, slot, targets)
		if targets.is_empty():
			return false
		held_opponent[slot] = ""
		var names: Array[String] = []
		for t in targets:
			names.append(slot_name(t))
		hud.show_message("%s → %s — %s" % [who, " + ".join(names), title], Color(c.r, c.g, c.b, 1.0))
	_refresh_hud()
	return true

# Who a hex cast by `from_team` lands on. An ordinary one goes to the next
# rival team in turn order, on whichever member flies its next brick; one
# that `affects_all_opponents()` goes to every living rival player — except
# in co-pilot, where a crew is one pair of hands and gets one copy. In
# free-for-all a team is a player, so this is the next living player, or
# every other living one, exactly as it always was.
func _hex_targets(from_team: int, all: bool) -> Array[int]:
	var out: Array[int] = []
	if all:
		for t in _teams_here():
			if t == from_team or lives[t] <= 0:
				continue
			if variant == GameSettings.TOWER_COPILOT:
				out.append(_pilot_of(t))
			else:
				out.append_array(_team_members(t))
	else:
		var t: int = _next_living_team(from_team)
		if t >= 0 and t != from_team:
			out.append(_pilot_of(t))
	return out

func _queue_hex(id: String, caster: int, targets: Array[int]) -> void:
	for t in targets:
		var e: TowerSkill = TowerSkillCatalog.make(id, self, caster, t)
		e.turns_left = e.duration_turns()
		queued_effects.append(e)

# Listed BEFORE activate() runs, so anything activate() asks — a multiplier,
# a redraw — is answered with this effect counted. Same contract as
# PlayerBoard._apply_skill_effect.
func _go_live(e: TowerSkill) -> void:
	e.turns_left = e.duration_turns()
	active_effects.append(e)
	e.activate()
	if e.is_done():
		_retire(e)

# Out of the list first, then deactivate() — the mirror of _go_live, so a
# deactivate() that asks the mode to recompute anything is not answered by
# the very effect being retired.
func _retire(e: TowerSkill) -> void:
	active_effects.erase(e)
	queued_effects.erase(e)
	e.deactivate()

# Every live and queued effect put back, in one place. Called from both
# ends a match can stop at (restart, game over) and from the probe.
func _clear_skill_effects() -> void:
	var all: Array = active_effects + queued_effects
	active_effects = []
	queued_effects = []
	for e in all:
		e.deactivate()

# An eliminated player takes nothing with them: their held skills go, the
# hexes waiting for a turn they will never have go, and anything live on
# them ends now.
func _drop_slot_skills(slot: int) -> void:
	held_self[slot] = ""
	held_opponent[slot] = ""
	charge[slot] = 0
	var gone: Array = []
	for e in active_effects + queued_effects:
		if e.target == slot:
			gone.append(e)
	for e in gone:
		_retire(e)

func _live_for(slot: int) -> Array:
	var out: Array = []
	for e in active_effects:
		if e.target == slot:
			out.append(e)
	return out

# --- The hooks, combined. Multipliers multiply, flags OR, claims first-wins;
# --- always over the effects attached to whoever is on the clock.

func _effect_descend_mult() -> float:
	var m := 1.0
	for e in _live_for(active_slot):
		m *= float(e.descend_speed_mult())
	return m

func _effect_soft_drop_mult() -> float:
	var m := 1.0
	for e in _live_for(active_slot):
		m *= float(e.soft_drop_speed_mult())
	return m

func _effect_follow_mult() -> float:
	var m := 1.0
	for e in _live_for(active_slot):
		m *= float(e.follow_speed_mult())
	return m

func _effect_mass_mult() -> float:
	var m := 1.0
	for e in _live_for(active_slot):
		m *= float(e.mass_mult())
	return m

func _effect_gravity_mult() -> float:
	var m := 1.0
	for e in _live_for(active_slot):
		m *= float(e.gravity_scale_mult())
	return m

func _effect_friction() -> float:
	for e in _live_for(active_slot):
		var f: float = e.friction_override()
		if f >= 0.0:
			return f
	return -1.0

func _effect_steer_flipped() -> bool:
	for e in _live_for(active_slot):
		if e.steer_flipped():
			return true
	return false

func _effect_rotation_locked() -> bool:
	for e in _live_for(active_slot):
		if e.rotation_locked():
			return true
	return false

func _effect_dash_locked() -> bool:
	for e in _live_for(active_slot):
		if e.dash_locked():
			return true
	return false

func _effect_soft_drop_locked() -> bool:
	for e in _live_for(active_slot):
		if e.soft_drop_locked():
			return true
	return false

func _effect_brick_scale() -> float:
	for e in _live_for(active_slot):
		var sc: float = e.brick_scale()
		if not is_equal_approx(sc, 1.0):
			return sc
	return 1.0

func _effect_spawn_index(rolled: int) -> int:
	for e in _live_for(active_slot):
		var idx: int = e.spawn_index_override()
		if idx >= 0 and idx < GameSettings.BRICKS.size():
			return idx
	return rolled

# --- HUD -------------------------------------------------------------------

func _refresh_hud() -> void:
	var slots: Array[Dictionary] = []
	for i in range(GameSettings.player_count):
		var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[i]
		var tags: Array[String] = []
		# The crew's roles lead the tags, so a co-pilot card says which pair
		# of keys is live on it before it says what is being done to it.
		if state == "piloting" and crew_mate >= 0:
			if i == active_slot:
				tags.append("STEER")
			elif i == crew_mate:
				tags.append("TURN")
		for e in _live_for(i):
			var tag: String = e.hud_tag()
			if tag != "":
				tags.append(tag)
		var team: int = team_of[i] if i < team_of.size() else i
		slots.append({
			"name": cfg["name"],
			"color": _slot_color(i),
			"team": team,
			"lives": lives[team] if team < lives.size() else 0,
			"charge": charge[i] if i < charge.size() else 0,
			"held_self": held_self[i] if i < held_self.size() else "",
			"held_opponent": held_opponent[i] if i < held_opponent.size() else "",
			"cast_label": cfg.get("cast_label", ""),
			"tags": tags,
		})
	hud.slots = slots
	hud.groups = _hud_groups()
	hud.subtitle = _hud_subtitle()
	hud.heading = _hud_heading()
	hud.charge_max = 0 if is_frame() else CHARGE_TO_SKILL
	var hexes: Array[Dictionary] = []
	for e in queued_effects:
		hexes.append({
			"title": TowerSkillCatalog.title_of(e.id),
			"from": slot_name(e.caster),
			"to": slot_name(e.target),
			"color": _slot_color(e.caster),
		})
	hud.hexes = hexes
	hud.hex_slot = _has_rivals()
	hud.max_lives = 0 if is_frame() or is_deadline() else _start_lives()
	hud.active_slot = active_slot
	hud.crew_mate = crew_mate
	hud.waiting = (state != "piloting")
	# Whose brick is next, so the banner can name them through the hand-off
	# instead of captioning the wait. -1 (no one left) falls back to the
	# current slot; the match is ending anyway on that frame.
	var up: int = _next_turn_slot()
	hud.next_slot = up if up >= 0 else active_slot
	hud.next_mate = _next_crew_mate()
	hud.next_index = next_index
	hud.controls = _controls_text()
	hud.queue_redraw()

# Free-for-all draws one card per player in seat order, exactly as before;
# every other variant groups the cards under their team, with the team's one
# shared row of lives on the group's header instead of on each card.
func _hud_groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if variant == GameSettings.TOWER_FFA:
		return out
	for t in _teams_here():
		out.append({
			"team": t,
			"title": GameSettings.tower_team_name(t, variant),
			"color": _team_color(t),
			"lives": lives[t],
			"slots": _team_members(t),
			# A tower of one in the solo race: a team header naming the same
			# player as the card under it would say everything twice, so it
			# draws as a free-for-all card, pips and all.
			"plain": variant == GameSettings.TOWER_RACE_SOLO or variant == GameSettings.TOWER_FRAME_SOLO \
				or variant == GameSettings.TOWER_DEADLINE_SOLO,
		})
	return out

# In a cup the HUD's title says which round this is, since the variant is
# no longer something the players picked and the tally is a screen away.
func _hud_heading() -> String:
	if GameSettings.tower_cup == GameSettings.TOWER_CUP_NONE:
		return "PILE UP"
	return "%s · ROUND %d" % [GameSettings.tower_cup_info()["title"], _cup_round_shown]

func _hud_subtitle() -> String:
	match variant:
		GameSettings.TOWER_TEAMS:
			return "two teams, %d lives a team" % TEAM_LIVES
		GameSettings.TOWER_COPILOT:
			return "one brick, two pairs of hands"
		GameSettings.TOWER_COOP:
			return "height %d / %d  ·  storm in %d" % [int(round(_height_cells())), int(goal_cells), storm_in]
		GameSettings.TOWER_RACE, GameSettings.TOWER_RACE_SOLO:
			return "race to %d  ·  height %d" % [int(goal_cells), int(round(_height_cells()))]
		GameSettings.TOWER_FRAME, GameSettings.TOWER_FRAME_SOLO:
			# Short: the column is 230px at 13px, and "fill the frame" plus a
			# three-digit fit ran off the end of it.
			return "frame  ·  %d%% fit  ·  brick %d/%d" % [frame_pct(), mini(bricks_placed + 1, FRAME_BRICKS), FRAME_BRICKS]
		GameSettings.TOWER_DEADLINE, GameSettings.TOWER_DEADLINE_SOLO:
			# The rule rather than the line's height, which starts under the
			# platform ("line -3") — how far over it you are is on the bar.
			return "stay over the line  ·  height %d" % roundi(deadline_top)
	return "one tower, three lives each"

# The navigator for the turn after this one, so the co-pilot banner can name
# the whole crew through the hand-off. -1 outside co-pilot.
func _next_crew_mate() -> int:
	if variant != GameSettings.TOWER_COPILOT:
		return -1
	var t: int = _next_living_team(turn_team)
	if t < 0:
		return -1
	var crew: Array[int] = _team_members(t)
	if crew.size() < 2:
		return -1
	return crew[(team_cursor[t] + 1) % crew.size()]

# FRAME has no skills, so its list is the same less the skill keys: a line
# of its own goes, and the compact strip's trailing " · keys skills" is cut.
func _controls_text() -> String:
	var txt: String = _controls_text_all()
	if not is_frame():
		return txt
	var keep: Array[String] = []
	for line in txt.split("\n"):
		if line.ends_with("skills") and line.contains(" · "):
			keep.append(line.substr(0, line.rfind(" · ")))
		elif not line.contains("skill"):
			keep.append(line)
	return "\n".join(keep)

func _controls_text_all() -> String:
	if state != "piloting":
		return ""
	# One action per line — TowerHUD splits on newlines because the side
	# column is too narrow for the single-line form.
	var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[active_slot]
	if hud.is_compact():
		# A three- or four-tower race gives each tower 500 or 375px and the
		# HUD a strip along the top, with two short lines of keys under it.
		# Raw key names, because "Left / Right   half a block" is the long
		# form this has no room for. The widest player (P2) is about 290px.
		return "%s/%s move · %s+dir dash · %s fall\n%s/%s turn · %s %s" % [
			OS.get_keycode_string(cfg["left"]), OS.get_keycode_string(cfg["right"]),
			OS.get_keycode_string(cfg["confirm"]),
			OS.get_keycode_string(cfg["down"]),
			OS.get_keycode_string(cfg["skill_opponent"]), OS.get_keycode_string(cfg["skill_self"]),
			cfg.get("cast_label", "").replace(" ", ""), "skills",
		]
	if crew_mate >= 0:
		# Two people, two halves of the same list. Named, because a crew
		# swaps halves every brick and the panel is how they find out who has
		# which this time.
		var mate: Dictionary = GameSettings.PLAYER_CONFIGS[crew_mate]
		return "%s steers   %s\n%s + a direction   a block\n%s   fall faster\n%s turns   %s / %s\nskills   %s  ·  %s" % [
			cfg["name"], cfg["steer_label"],
			cfg["confirm_label"],
			OS.get_keycode_string(cfg["down"]),
			mate["name"], OS.get_keycode_string(mate["skill_opponent"]), OS.get_keycode_string(mate["skill_self"]),
			cfg.get("cast_label", ""), mate.get("cast_label", ""),
		]
	# "a block" rather than "a whole block", and "a direction" rather than the
	# steer label spelled out again: the column gives 196px at font 15, and
	# P2's "Up + Left / Right   dash a whole block" measures 266. This form's
	# widest player is 178.
	return "%s   half a block\n%s + a direction   a block\n%s / %s   rotate\n%s   fall faster\n%s   %s" % [
		cfg["steer_label"],
		cfg["confirm_label"],
		OS.get_keycode_string(cfg["skill_opponent"]),
		OS.get_keycode_string(cfg["skill_self"]),
		OS.get_keycode_string(cfg["down"]),
		# No rivals, no hex key worth listing (see TowerHUD.hex_slot).
		cfg.get("cast_label", "") if _has_rivals() else OS.get_keycode_string(cfg["cast_self"]),
		"skills" if _has_rivals() else "skill",
	]

# --- Foreground ------------------------------------------------------------

func _draw() -> void:
	var view: Vector2 = _view_world()
	var top: float = cam_y - view.y * 0.5
	var bottom: float = cam_y + view.y * 0.5
	var half_w: float = PLATFORM_CELLS * CELL * 0.5

	_draw_play_column(top, half_w)
	_draw_height_guides(top, bottom, half_w)
	_draw_goal_line(half_w)
	_draw_frame_outline()
	_draw_outcrop(half_w)
	_draw_drop_guide(half_w)
	_draw_dash_ghost()
	for e in active_effects:
		e.draw_under()

func _draw_play_column(top: float, half_w: float) -> void:
	var reach: float = half_w + AIM_BOUND_CELLS * CELL
	draw_rect(Rect2(-reach, top, reach * 2.0, -top), COLUMN_SHADE, true)

# The backdrop's parallax carries most of the sense of climbing, but it moves
# at a fraction of the camera, so these are what actually tick past at the
# tower's own rate. Every fourth cell, so they read as courses of brickwork
# rather than as a grid the bricks are supposed to snap to — the bricks move
# on a half-cell lattice on the way down but land wherever physics puts them.
func _draw_height_guides(top: float, bottom: float, half_w: float) -> void:
	var spacing: float = GUIDE_SPACING_CELLS * CELL
	var reach: float = half_w + AIM_BOUND_CELLS * CELL + CELL
	var y: float = -spacing
	while y > top:
		y -= spacing
	while y < minf(bottom, 0.0):
		draw_line(Vector2(-reach, y), Vector2(reach, y), GUIDE_COLOR, _px(2.0))
		y += spacing

	# The platform's own footprint, carried upward: the line you are trying
	# to keep the tower inside, and the only reference left once the platform
	# itself has scrolled off the bottom.
	for side: float in [-1.0, 1.0]:
		var x: float = side * half_w
		draw_line(Vector2(x, 0.0), Vector2(x, top), EDGE_LINE_COLOR, _px(2.0))

# The finish line, across the whole play column. Gold dashes on a dark
# underlay rather than gold alone: everything drawn over this backdrop has to
# survive a bright sky (§7), and a light line on its own disappears into it.
# Under the bricks, like every other guide — a brick that has crossed the
# line covers it, which reads as having crossed it.
func _draw_goal_line(half_w: float) -> void:
	if goal_cells <= 0.0:
		return
	var y: float = -goal_cells * CELL
	var reach: float = half_w + AIM_BOUND_CELLS * CELL
	draw_line(Vector2(-reach, y), Vector2(reach, y), GOAL_SHADOW, _px(7.0))
	var dash: float = CELL * 0.5
	var x: float = -reach
	while x < reach:
		draw_line(Vector2(x, y), Vector2(minf(x + dash * 0.6, reach), y), GOAL_COLOR, _px(3.0))
		x += dash
	var font: Font = ThemeDB.fallback_font
	var size: int = int(round(14.0 / cam_zoom))
	var at := Vector2(-reach + _px(6.0), y - _px(8.0))
	draw_rect(Rect2(at + Vector2(-_px(4.0), -_px(15.0)), Vector2(_px(44.0), _px(19.0))), GOAL_SHADOW, true)
	draw_string(font, at, "GOAL", HORIZONTAL_ALIGNMENT_LEFT, -1, size, GOAL_COLOR)

# FRAME's outline: a faint fill over every cell of the frame and a line round
# its edge — every side of a frame cell whose neighbour is not one — on the
# same dark underlay as the goal line, so it survives a bright sky. Under the
# bricks like every guide here, so a brick laid in it covers the fill, and
# what still shows is what is left to fill.
func _draw_frame_outline() -> void:
	if frame_cells.is_empty():
		return
	var left: float = -PLATFORM_CELLS * CELL * 0.5
	for k: Vector2i in frame_cells:
		draw_rect(Rect2(left + float(k.x) * CELL, -float(k.y + 1) * CELL, CELL, CELL), FRAME_FILL, true)
	var edges: Array[PackedVector2Array] = []
	for k: Vector2i in frame_cells:
		var x0: float = left + float(k.x) * CELL
		var y0: float = -float(k.y + 1) * CELL
		var x1: float = x0 + CELL
		var y1: float = y0 + CELL
		if not frame_cells.has(k + Vector2i(0, 1)):
			edges.append(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0)]))
		if not frame_cells.has(k + Vector2i(0, -1)) and k.y > 0:
			edges.append(PackedVector2Array([Vector2(x0, y1), Vector2(x1, y1)]))
		if not frame_cells.has(k + Vector2i(-1, 0)):
			edges.append(PackedVector2Array([Vector2(x0, y0), Vector2(x0, y1)]))
		if not frame_cells.has(k + Vector2i(1, 0)):
			edges.append(PackedVector2Array([Vector2(x1, y0), Vector2(x1, y1)]))
	for e in edges:
		draw_line(e[0], e[1], FRAME_SHADOW, _px(7.0))
	for e in edges:
		draw_line(e[0], e[1], FRAME_LINE, _px(3.0))

# DEADLINE's line, on its own canvas over the bricks and the ground (see
# _ready()): a red wash over everything under it, strongest just under the
# line, and the line itself across the whole view on a dark underlay, so it
# survives a bright sky (§7) the way the goal line does. While the top is
# under it the line pulses; how long is left is the host's to say, over the
# view, where the other towers' players can read it too.
func _draw_deadline() -> void:
	var view: Vector2 = _view_world()
	var bottom: float = cam_y + view.y * 0.5
	var y: float = -deadline_cells * CELL
	if y > bottom:
		return
	var half: float = view.x * 0.5
	var band: float = DEADLINE_WASH_BAND * CELL
	deadline_layer.draw_polygon(
		PackedVector2Array([Vector2(-half, y), Vector2(half, y), Vector2(half, y + band), Vector2(-half, y + band)]),
		PackedColorArray([DEADLINE_WASH_NEAR, DEADLINE_WASH_NEAR, DEADLINE_WASH, DEADLINE_WASH]))
	if bottom > y + band:
		deadline_layer.draw_rect(Rect2(-half, y + band, half * 2.0, bottom - y - band), DEADLINE_WASH, true)
	var c: Color = DEADLINE_COLOR
	var w: float = 3.5
	if under_time > 0.0 and state != "gameover":
		var pulse: float = 0.5 + 0.5 * cos(under_time * TAU * 2.5)
		c = c.lerp(Color(1.0, 0.86, 0.80, 1.0), pulse * 0.6)
		w += 2.5 * pulse
	deadline_layer.draw_line(Vector2(-half, y), Vector2(half, y), DEADLINE_SHADOW, _px(w + 5.0))
	deadline_layer.draw_line(Vector2(-half, y), Vector2(half, y), c, _px(w))

# The tower stands on a rock outcrop growing out of the ground, not on a
# platform on legs. Same silhouette language as the cliffs in the backdrop: a
# grass-capped top, a body that flares as it descends, and a base buried in
# the grass shelf TowerGround draws over it.
func _draw_outcrop(half_w: float) -> void:
	var art: Texture2D = TowerGround.ART
	var base_w: float = half_w + OUTCROP_FLARE
	var foot: float = GROUND_Y + OUTCROP_BURY

	# Body, as horizontal slices: a texture can only be drawn into a rect, so
	# the taper is made by narrowing each slice rather than by one polygon.
	# The source scrolls through its own band and wraps, which tiles the
	# stone vertically at its native scale instead of stretching one copy
	# over the whole height and smearing it.
	var y: float = 0.0
	while y < foot:
		var h: float = minf(ROCK_SLICE, foot - y)
		var w: float = lerp(half_w, base_w, y / foot)
		var src_y: float = ROCK_SRC.position.y + fmod(y, ROCK_SRC.size.y - h)
		draw_texture_rect_region(
			art,
			Rect2(-w, y, w * 2.0, h),
			Rect2(ROCK_SRC.position.x, src_y, ROCK_SRC.size.x, h)
		)
		y += h

	# Form: one lit face and one shadowed face over the texture, so the rock
	# has a direction rather than reading as a flat wall of rubble.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half_w, 0.0), Vector2(-half_w * 0.42, 0.0),
		Vector2(-base_w * 0.42, foot), Vector2(-base_w, foot),
	]), ROCK_SHADE_LEFT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(half_w * 0.36, 0.0), Vector2(half_w, 0.0),
		Vector2(base_w, foot), Vector2(base_w * 0.36, foot),
	]), ROCK_SHADE_RIGHT)

	# Grass cap. Entirely at y >= 0, and the bricks rest at y <= 0 and are
	# drawn after this, so the cap can never poke through the bottom brick.
	var cap_w: float = half_w + 5.0
	draw_rect(Rect2(-cap_w, 0.0, cap_w * 2.0, 13.0), GRASS, true)
	draw_rect(Rect2(-cap_w, 0.0, cap_w * 2.0, 4.0), GRASS_LIGHT, true)
	draw_rect(Rect2(-cap_w, 13.0, cap_w * 2.0, 3.0), GRASS_DARK, true)
	# Tufts hanging over the lip, so the cap doesn't end on a ruled line.
	for t: float in [-0.82, -0.44, 0.1, 0.52, 0.88]:
		var tx: float = t * half_w
		draw_colored_polygon(PackedVector2Array([
			Vector2(tx - 7.0, 12.0), Vector2(tx + 7.0, 12.0), Vector2(tx, 25.0),
		]), GRASS_DARK)

# The afterimage a dash leaves behind it — the same trick Don't Crash's lane
# dash uses, and here it is doing more than decoration. A dash covers one
# cell in about 27ms, which is over almost before it registers; the trail is
# most of what tells the player the gesture landed at all, as opposed to
# having been read as two ordinary taps.
func _draw_dash_ghost() -> void:
	if dash_ghost_timer <= 0.0 or active_piece == null:
		return
	var fade: float = dash_ghost_timer / DASH_GHOST_TIME
	var c: Color = active_piece.owner_color
	var here: Vector2 = active_piece.global_position
	var rot: float = active_piece.rotation
	var travelled: float = dash_ghost_x - here.x
	if absf(travelled) < 1.0:
		return

	# Everything here draws *behind* the brick: TowerMode paints before its
	# own children, and PiecesContainer is a child. That is what makes the
	# rim flash work — only the half of the stroke that falls outside the
	# brick's silhouette is visible, so it reads as an edge light rather than
	# as a box drawn on top of the art.
	var half_h: float = active_piece.aim_half_width(aim_steps + 1)

	# Speed lines, trailing back along the path the brick came down.
	for i in range(DASH_STREAKS):
		var fy: float = (float(i) / float(DASH_STREAKS - 1) - 0.5) * 1.4 * half_h
		var t0: float = 0.15 + 0.2 * float(i % 2)
		var x0: float = here.x + travelled * t0
		var x1: float = here.x + travelled * (t0 + 0.45)
		draw_line(
			Vector2(x0, here.y + fy), Vector2(x1, here.y + fy),
			Color(c.r, c.g, c.b, fade * 0.5), _px(2.0)
		)

	# Afterimages, brightest nearest the brick so the trail reads as
	# direction rather than as a smear.
	for i in range(DASH_GHOST_COPIES):
		var t: float = float(i + 1) / float(DASH_GHOST_COPIES + 1)
		var at := Vector2(lerp(here.x, dash_ghost_x, t), here.y)
		var a: float = fade * (1.0 - t) * 0.7
		for pts: PackedVector2Array in active_piece.box_outlines(Transform2D(rot, at)):
			draw_polyline(pts, Color(c.r, c.g, c.b, a), _px(2.0))

	# Rim flash where it landed.
	for pts: PackedVector2Array in active_piece.box_outlines(Transform2D(rot, here)):
		draw_polyline(pts, Color(1.0, 1.0, 1.0, fade * 0.8), _px(DASH_RIM_WIDTH))

# A translucent column under the descending brick, down to whatever it would
# land on. Judging a drop on a leaning tower from the brick alone is
# guesswork; this makes the line of the shot readable without snapping
# anything.
func _draw_drop_guide(half_w: float) -> void:
	if state != "piloting" or active_piece == null:
		return
	var w: float = active_piece.aim_half_width(aim_steps) * 2.0
	var x: float = active_piece.global_position.x
	var y0: float = active_piece.global_position.y
	var c: Color = active_piece.owner_color
	draw_rect(Rect2(x - w * 0.5, y0, w, -y0), Color(c.r, c.g, c.b, DROP_GUIDE_ALPHA), true)
	draw_line(
		Vector2(x - w * 0.5, stack_top_y), Vector2(x + w * 0.5, stack_top_y),
		Color(c.r, c.g, c.b, 0.65), _px(2.0)
	)
	for side: float in [-1.0, 1.0]:
		draw_line(
			Vector2(side * half_w, stack_top_y - CELL * 0.4), Vector2(side * half_w, 0.0),
			EDGE_LINE_COLOR, _px(2.0)
		)
