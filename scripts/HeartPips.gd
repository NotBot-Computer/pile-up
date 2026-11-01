extends RefCounted
class_name HeartPips

## The life pip both modes draw, and the rule that turns one red PNG into six
## players' colours.
##
## Lives arrived as a Don't Crash mechanic (session W) and the pip was built
## inside `PlayerBoard`. Pile Up already had lives of its own and drew them as
## flat circles — a different visual language for the same fact, in a game
## whose two modes share a menu flow, a colour per player and a countdown, and
## which therefore should not disagree about what "a life" looks like. Rather
## than copy the recolour loop into `TowerHUD` — the mistake `SpeedRamp`'s
## header records for the difficulty ramp, where two hand-synced copies of the
## same numbers eventually shipped a visible desync — the art, the recolour
## and the two numbers its loss animation is made of live here, and both
## callers reach in.
##
## What is deliberately NOT here: how many lives a mode grants, where the row
## sits, and how big a pip is drawn. Those are layout and balance rather than
## identity, they genuinely differ between a 620px-wide board and a 224px HUD
## card, and Pile Up's life count is a difficulty knob of its own
## (`TowerMode.START_LIVES`).

const TEXTURE := preload("res://sprites/ui/heart.png")

## Only the *saturated* pixels are re-hued. The heart's black outline and its
## white highlight carry no hue of their own, and leaving them alone is what
## keeps a tinted pip legible instead of flattening it into one blob of
## colour: modulating the whole image by the player's colour turns the red body
## muddy and the highlight into a wash of that same hue, and the outline
## survives only because black times anything is black.
const BODY_SAT := 0.25
## Floor on a skin colour's own brightness. Green (v 0.68) is the one skin dark
## enough to smudge into an unreadable blob at pip size.
const MIN_VALUE := 0.85

## A spent pip swells out of its slot and fades rather than simply vanishing:
## at pip size, one that disappears between two frames is one nobody sees
## leave, and "wait, how many did I have?" is the single question this readout
## exists to answer. Don't Crash animates this with a Tween on a real Sprite2D
## and Pile Up's drawn HUD interpolates it by hand, so the numbers — and the
## curve, see `loss_pose` — live here and the two stay one gesture.
const LOSS_POP := 2.2
const LOSS_DURATION := 0.45
## Before it goes, it blinks: LOSS_BLINKS times over LOSS_BLINK_TIME, lit a
## size up and then nearly out. The blink is the announcement now — the
## "P1 DROPPED A BRICK −1 LIFE" banner that used to cover the playfield was
## taken out at the user's request (session AM), so the heart has to be
## caught by the eye on its own, and a pip that only swells for under half a
## second at the side of the screen was easy to miss.
const LOSS_BLINKS := 4
const LOSS_BLINK_TIME := 1.0
const LOSS_BLINK_SCALE := 1.35
const LOSS_BLINK_LOW := 0.12 # alpha in the off half of a blink
const LOSS_TOTAL := LOSS_BLINK_TIME + LOSS_DURATION

# One texture per colour, kept for the life of the process. Pile Up's HUD is
# drawn rather than laid out, so it asks for its pips from inside _draw() —
# walking an 18x18 image once per card per frame would be silly — and the
# result cannot go stale, being a pure function of a colour and a preloaded
# PNG. Four players, six skins: this holds at most six 18x18 textures.
static var _cache: Dictionary = {}

## The pip re-hued into `body_color`, so a glance at a row says whose lives
## they are without reading a name off it. Each body pixel keeps its own
## brightness so the art's shading survives the swap — `extract_heart.py`
## normalises the brightest body pixel to 1.0 for exactly that multiply, which
## is why nothing here knows anything about this particular PNG.
static func tinted(body_color: Color) -> ImageTexture:
	var key: int = body_color.to_rgba32()
	if _cache.has(key):
		return _cache[key]

	var src: Image = TEXTURE.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	var value: float = max(body_color.v, MIN_VALUE)
	for y in range(src.get_height()):
		for x in range(src.get_width()):
			var px: Color = src.get_pixel(x, y)
			if px.a > 0.0 and px.s >= BODY_SAT:
				px = Color.from_hsv(body_color.h, body_color.s, px.v * value, px.a)
			out.set_pixel(x, y, px)

	var tex := ImageTexture.create_from_image(out)
	_cache[key] = tex
	return tex

## A pip's drawn size at `height` px, taken from the source art's own aspect
## ratio rather than a second constant that could drift away from the PNG.
static func size_at(height: float) -> Vector2:
	var tex_size: Vector2 = TEXTURE.get_size()
	return Vector2(height * (tex_size.x / tex_size.y), height)

## Where a pip is `elapsed` seconds into losing itself: `x` is the scale
## multiplier and `y` the alpha. The scale is a cubic ease-out and the alpha is
## linear, which is precisely what `PlayerBoard._spend_heart()`'s parallel
## Tween does — the point of this function is that a hand-driven redraw and a
## Tween can be read side by side and seen to agree.
##
## Over LOSS_TOTAL: the blinks first, then that swell-and-fade.
static func loss_pose(elapsed: float) -> Vector2:
	if elapsed < LOSS_BLINK_TIME:
		var period: float = LOSS_BLINK_TIME / float(LOSS_BLINKS)
		var lit: bool = fmod(elapsed, period) < period * 0.5
		return Vector2(LOSS_BLINK_SCALE, 1.0) if lit else Vector2(1.0, LOSS_BLINK_LOW)
	var t: float = clampf((elapsed - LOSS_BLINK_TIME) / LOSS_DURATION, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	return Vector2(lerpf(1.0, LOSS_POP, eased), 1.0 - t)
