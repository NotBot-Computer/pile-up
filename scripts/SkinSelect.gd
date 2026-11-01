extends Control

## Each player cycles and locks a colour. The look is PixelUI's: each player
## is a framed panel, and the frame takes the player's colour once they lock
## it in, so who is still choosing reads from across the room.

const PixelUI := preload("res://scripts/PixelUI.gd")

@onready var panels_row: HBoxContainer = $PanelsRow
@onready var hint: Label = $Hint

var indices: Array[int] = []
var ready_flags: Array[bool] = []
var panel_refs: Array[Dictionary] = []
# Latched the moment every slot is ready, because _refresh() waits a beat
# before changing scene and any further keypress in that window would call it
# again — which with bot slots (which are ready the instant they are toggled)
# is far easier to hit than it used to be.
var starting: bool = false
# Every player needs a colour: it identifies whose brick is in the air and
# whose lives are whose, since every brick already on the pile looks the same.

func _ready() -> void:
	var count: int = GameSettings.player_count
	indices.resize(count)
	ready_flags.resize(count)
	for i in range(count):
		indices[i] = i % GameSettings.PLAYER_SKINS.size()
		ready_flags[i] = false
	_build_panels()
	PixelUI.apply(self)
	_refresh()

func _build_panels() -> void:
	for child in panels_row.get_children():
		child.queue_free()
	panel_refs.clear()

	for i in range(GameSettings.player_count):
		var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[i]

		var frame := PanelContainer.new()
		panels_row.add_child(frame)
		var panel := VBoxContainer.new()
		panel.custom_minimum_size = Vector2(246, 0)
		panel.add_theme_constant_override("separation", 15)
		frame.add_child(panel)

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 24)
		panel.add_child(name_label)

		var swatch_wrap := CenterContainer.new()
		panel.add_child(swatch_wrap)
		var swatch := TextureRect.new()
		swatch.custom_minimum_size = Vector2(100, 175)
		swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		swatch_wrap.add_child(swatch)

		var status_label := Label.new()
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		status_label.custom_minimum_size = Vector2(246, 72)
		panel.add_child(status_label)

		panel_refs.append({
			"cfg": cfg,
			"frame": frame,
			"ready_look": Color(0, 0, 0, 0),
			"name_label": name_label,
			"swatch": swatch,
			"status_label": status_label,
		})

func _cycle(current: int, taken: Array[int], delta: int) -> int:
	var count := GameSettings.PLAYER_SKINS.size()
	var next := current
	for _n in range(count):
		next = (next + delta + count) % count
		if not taken.has(next):
			break
	return next

func _is_ready(slot: int) -> bool:
	return ready_flags[slot]

func _refresh() -> void:
	var all_ready := true
	for i in range(panel_refs.size()):
		var ref: Dictionary = panel_refs[i]
		var skin: Dictionary = GameSettings.PLAYER_SKINS[indices[i]]
		ref["swatch"].texture = skin["texture"]
		ref["name_label"].text = skin["name"]
		_frame_panel(ref, _is_ready(i), skin["color"])
		var cfg: Dictionary = ref["cfg"]
		if ready_flags[i]:
			ref["status_label"].text = _team_line(i) + "READY!"
		else:
			ref["status_label"].text = _team_line(i) + "%s to change, %s to lock in" % [cfg["steer_label"], cfg["confirm_label"]]
			all_ready = false
	if all_ready:
		hint.text = "Starting..."
	else:
		hint.text = "Choose your color — it marks your brick and your lives"

	if all_ready and not starting:
		starting = true
		var chosen: Array[Texture2D] = []
		var chosen_colors: Array[Color] = []
		for idx in indices:
			chosen.append(GameSettings.PLAYER_SKINS[idx]["texture"])
			chosen_colors.append(GameSettings.PLAYER_SKINS[idx]["color"])
		GameSettings.skins = chosen
		GameSettings.skin_colors = chosen_colors
		await get_tree().create_timer(0.4).timeout
		get_tree().change_scene_to_file(_next_scene())

# A locked-in panel is ringed in its own colour. Only rebuilt when that
# changes.
func _frame_panel(ref: Dictionary, locked: bool, color: Color) -> void:
	var look: Color = color if locked else Color(0, 0, 0, 0)
	if ref["ready_look"] == look:
		return
	ref["ready_look"] = look
	var frame: PanelContainer = ref["frame"]
	if locked:
		frame.add_theme_stylebox_override("panel", PixelUI.panel_frame(color))
	else:
		frame.remove_theme_stylebox_override("panel")

func _next_scene() -> String:
	# A cup opens on its standings — every count at zero and the first
	# round's mode named — and that screen starts round one.
	if GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE:
		GameSettings.cup_reset()
		return "res://scenes/TowerCup.tscn"
	return GameSettings.tower_scene()

# Which team this seat is on, for the Pile Up variants that have teams. Teams
# are seats rather than a choice (GameSettings.tower_team_of), so this screen
# only has to say so — the colour is still yours to pick.
func _team_line(slot: int) -> String:
	var v: int = GameSettings.tower_variant
	if v == GameSettings.TOWER_FFA or v == GameSettings.TOWER_COOP or v == GameSettings.TOWER_RACE_SOLO or v == GameSettings.TOWER_FRAME_SOLO \
			or v == GameSettings.TOWER_DEADLINE_SOLO:
		return ""
	return GameSettings.tower_team_name(GameSettings.tower_team_of(slot)) + "\n"

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if starting:
		return
	var key: int = event.keycode
	var changed := false

	for i in range(panel_refs.size()):
		if _is_ready(i):
			continue
		var cfg: Dictionary = panel_refs[i]["cfg"]
		var taken: Array[int] = []
		for j in range(indices.size()):
			if j != i:
				taken.append(indices[j])

		if key == cfg["left"]:
			indices[i] = _cycle(indices[i], taken, -1)
			changed = true
		elif key == cfg["right"]:
			indices[i] = _cycle(indices[i], taken, 1)
			changed = true
		elif key == cfg["confirm"]:
			ready_flags[i] = true
			changed = true

	if changed:
		_refresh()
