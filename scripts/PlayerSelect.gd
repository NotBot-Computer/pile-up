extends Control

## Player count. Which cup we are heading into was decided on the main menu
## (GameSettings.tower_cup, and its first round's GameSettings.tower_variant),
## and only the counts it allows are offered.

const PixelUI := preload("res://scripts/PixelUI.gd")
const ModeCard := preload("res://scripts/ModeCard.gd")

# One card per count on offer, picked like the main menu's (CardRow:
# left/right, Enter, Esc back). Each card's preview shows that many players:
# that many strips with one brick falling in each.
@onready var row: Control = $Cards
var _counts: Array[int] = []

func _ready() -> void:
	PixelUI.apply(self)
	add_child(PixelUI.key_badge("ESC  BACK"))
	add_child(PixelUI.key_badge("← →  CHOOSE   ENTER  OK", true))

	# There is no AI for Pile Up, so every seat is a person. Co-op is the
	# only variant with no opponent, so a count of one is a lone builder,
	# offered only where the variant allows it.
	var info: Dictionary = GameSettings.tower_pick_info()
	$Title.text = "%s — HOW MANY BUILDERS?" % info["title"]
	$Hint.text = _cup_hint() if GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE else _seating_hint(GameSettings.tower_variant)
	for n in [1, 2, 3, 4]:
		if (info["counts"] as Array).has(n):
			_add_option("1 BUILDER" if n == 1 else "%d PLAYERS" % n, n)
	row.chosen.connect(func(i: int): _select(_counts[i]))
	row.back.connect(_on_back)
	row.select(0)

func _add_option(title: String, count: int) -> void:
	var card: Control = ModeCard.new()
	card.title = title
	card.count = count
	card.kind = ModeCard.Kind.TOWERS
	card.one_at_a_time = true
	_counts.append(count)
	row.add_card(card)

# Teams are seats (GameSettings.tower_team_of), so the count screen is where a
# group finds out who they are playing with — before they pick colours.
func _seating_hint(variant: int) -> String:
	match variant:
		GameSettings.TOWER_TEAMS:
			return "Left team: P1 + P3      Right team: P2 + P4  (with three, P2 holds the right alone)"
		GameSettings.TOWER_COPILOT:
			return "Left crew: P1 + P3      Right crew: P2 + P4 — you swap steering and turning every brick"
		GameSettings.TOWER_COOP:
			return "Everyone builds one tower together, sharing one pool of lives"
		GameSettings.TOWER_RACE:
			return "Left tower: P1 (+ P3)      Right tower: P2 (+ P4)"
		GameSettings.TOWER_RACE_SOLO:
			return "A tower each, side by side, in seat order — and a hex always lands on whoever is highest"
		GameSettings.TOWER_FRAME_SOLO:
			return "A tower each, side by side, in seat order — the same frame and the same bricks for everyone"
		GameSettings.TOWER_FRAME:
			return "Left frame: P1 (+ P3)      Right frame: P2 (+ P4)"
		GameSettings.TOWER_DEADLINE_SOLO:
			return "A tower each, side by side, in seat order — and the same red line rising under all of them"
		GameSettings.TOWER_DEADLINE:
			return "Left tower: P1 (+ P3)      Right tower: P2 (+ P4)"
	return "Every builder for themselves"

# A cup is several variants, so the line says what it is made of instead of
# how one of them is seated — and, in the team cup, the seats, which do not
# change between its rounds.
func _cup_hint() -> String:
	if GameSettings.tower_cup == GameSettings.TOWER_CUP_TEAM:
		return "Left team: P1 + P3      Right team: P2 + P4 — winning a round is 3 trophies, losing it none, first to %d" % GameSettings.CUP_TARGET
	return "Free for all, a race, co-op, the frame, the deadline, and round again — 1st 3 trophies, 2nd 2, 3rd 1, first to %d" % GameSettings.CUP_TARGET

func _select(count: int) -> void:
	GameSettings.player_count = count
	get_tree().change_scene_to_file("res://scenes/SkinSelect.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
