extends Node3D

signal request_idle

const GameApi = preload("res://scripts/game_api.gd")
const CITY_TILES := [1, 3, 6, 8, 9, 11, 13, 14, 16, 18, 19, 21, 23, 24, 26, 27, 29, 31, 32, 34, 37, 39]
const COLORS := [Color("d9483b"), Color("4383bc"), Color("bd8b32"), Color("986ab6"), Color("408558"), Color("bc617b")]
const PROPERTY_GROUPS := [[1, 3], [6, 8, 9], [11, 13, 14], [16, 18, 19], [21, 23, 24], [26, 27, 29], [31, 32, 34], [37, 39]]
const GROUP_COLORS := [Color("905b42"), Color("91cbdc"), Color("d54b94"), Color("ed9136"), Color("d94343"), Color("efd352"), Color("29905b"), Color("3164ab")]
const DEFAULT_PRICES := {1: 60, 3: 60, 5: 200, 6: 100, 8: 100, 9: 120, 11: 140, 12: 150, 13: 140, 14: 160, 15: 200, 16: 180, 18: 180, 19: 200, 21: 220, 23: 220, 24: 240, 25: 200, 26: 260, 27: 260, 28: 150, 29: 280, 31: 300, 32: 300, 34: 320, 35: 200, 37: 350, 39: 400}
const DEFAULT_NAMES := ["Départ", "Chefchaouen", "Caisse commune", "Tétouan", "Impôts", "Gare de Fès", "Oujda", "Chance", "Nador", "Al Hoceïma", "Prison", "Meknès", "Électricité", "Fès", "Ifrane", "Gare de Marrakech", "El Jadida", "Caisse commune", "Safi", "Essaouira", "Parc gratuit", "Agadir", "Chance", "Marrakech", "Ouarzazate", "Gare de Tanger", "Tanger", "Kénitra", "Compagnie des eaux", "Larache", "Allez en prison", "Rabat", "Salé", "Caisse commune", "Témara", "Gare de Bouskoura", "Chance", "Casablanca", "Taxe de luxe", "Victoria"]

var api = GameApi.new()
var camera: Camera3D
var pawns := {}
var labels: Array[Label3D] = []
var tile_colors: Array[MeshInstance3D] = []
var ownership_markers: Array[Node3D] = []
var tile_visuals := {}
var tile_color_values := {}
var dice_nodes: Array[Node3D] = []
var dice_labels: Array[Label3D] = []
var dice_pips: Array[Array] = []
var pawn_tweens := {}
var last_event_seq := -1
var last_round := -1
var audio_player: AudioStreamPlayer
var turn_alert: AudioStreamPlayer
var last_turn_key := ""
var victory_key := ""
var victory_dialog: AcceptDialog
var sound_enabled := true
var tile_details: Label
var status: Label
var room_label: Label
var players_label: RichTextLabel
var player_name: LineEdit
var room_code: LineEdit
var server_field: LineEdit
var actions: VBoxContainer
var action_scroll: ScrollContainer
var session_view: Control
var resume_button: Button
var exit_button: Button
var last_error := ""
var error_until := 0
var timer: Timer
var waiting := false
var state: Dictionary = {}
var action_key := ""
var view_angle := 0.65
var view_elevation := 0.9
var view_distance := 14.7
var session_file := "user://quartiers-session.cfg"
var saved_session: Dictionary = {}
var saved_server := ""

func _ready() -> void:
	add_child(api)
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = load("res://assets/offer-refused.mp3")
	audio_player.volume_db = -8
	add_child(audio_player)
	turn_alert = AudioStreamPlayer.new()
	turn_alert.stream = make_turn_sound()
	turn_alert.volume_db = -10
	add_child(turn_alert)
	load_session()
	build_world()
	build_ui()
	timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(refresh)
	add_child(timer)

func material(color: Color, roughness: float = 0.82) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, top: float = -1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func tile_position(index: int) -> Vector3:
	if index == 0:
		return Vector3(5.12, 0, 5.12)
	if index < 10:
		return Vector3(5.0 - index, 0, 5.12)
	if index == 10:
		return Vector3(-5.12, 0, 5.12)
	if index < 20:
		return Vector3(-5.12, 0, 5.0 - (index - 10))
	if index == 20:
		return Vector3(-5.12, 0, -5.12)
	if index < 30:
		return Vector3(-5.0 + index - 20, 0, -5.12)
	if index == 30:
		return Vector3(5.12, 0, -5.12)
	return Vector3(5.12, 0, -5.0 + index - 30)

func tile_rotation(index: int) -> float:
	if index > 10 and index < 20:
		return -PI / 2
	if index >= 20 and index < 30:
		return PI
	if index >= 30:
		return PI / 2
	return 0.0

# Wrap long names onto the card; keep the full spelling and the price.
func set_tile_text(label: Label3D, tile_name: String, price: int) -> void:
	var lines: Array[String] = []
	var line := ""
	for word in tile_name.split(" ", false):
		if not line.is_empty() and (line.length() + word.length() + 1) > 11:
			lines.append(line)
			line = word
		else:
			line = word if line.is_empty() else line + " " + word
	if not line.is_empty():
		lines.append(line)
	if price > 0:
		lines.append(str(price) + " DH")
	label.text = "\n".join(lines)
	var widest := 0.0
	for item in lines:
		widest = maxf(widest, ThemeDB.fallback_font.get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size)
	label.scale.x = minf(1.0, 0.84 / maxf(widest, 0.01))

func label_on_tile(text: String, pos: Vector3, index: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos + Vector3(0, 0.075, 0.10).rotated(Vector3.UP, tile_rotation(index))
	label.rotation = Vector3(-PI / 2, 0, 0)
	label.rotate_y(tile_rotation(index))
	label.font_size = 50
	label.pixel_size = 0.0035
	label.modulate = Color("172521")
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(label)
	return label

func board_symbol(text: String, pos: Vector3, index: int, color: Color) -> void:
	var symbol := Label3D.new()
	symbol.text = text
	symbol.font_size = 80
	symbol.pixel_size = 0.0042
	symbol.modulate = color
	symbol.outline_size = 2
	symbol.outline_modulate = Color("fff7dc")
	symbol.position = pos + Vector3(0, 0.085, -0.27).rotated(Vector3.UP, tile_rotation(index))
	symbol.rotation = Vector3(-PI / 2, 0, 0)
	symbol.rotate_y(tile_rotation(index))
	add_child(symbol)

func build_world() -> void:
	var env := WorldEnvironment.new()
	var sky_env := Environment.new()
	sky_env.background_mode = Environment.BG_COLOR
	sky_env.background_color = Color("a8c8c6")
	sky_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky_env.ambient_light_color = Color("f9f3df")
	sky_env.ambient_light_energy = 0.48
	env.environment = sky_env
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58, -28, 0)
	light.light_color = Color("fff1d1")
	light.light_energy = 0.72
	light.shadow_enabled = true
	add_child(light)
	build_city()
	# The playing surface is a ring of rectangular cards and larger corner cards.
	box(self, Vector3(12.1, 0.5, 12.1), Vector3(0, -0.6, 0), Color("b69d70"))
	box(self, Vector3(11.7, 0.22, 11.7), Vector3(0, -0.22, 0), Color("426453"))
	box(self, Vector3(8.95, 0.10, 8.95), Vector3(0, -0.04, 0), Color("9dce37"))
	for i in range(40):
		var pos := tile_position(i)
		var corner := i % 10 == 0
		var side := (i > 10 and i < 20) or i > 30
		var dimensions := Vector3(1.20, 0.10, 1.20) if corner else (Vector3(1.20, 0.10, 0.96) if side else Vector3(0.96, 0.10, 1.20))
		box(self, dimensions, pos, Color("dcebd0"))
		var group_color := Color("9d977b")
		for group_index in range(PROPERTY_GROUPS.size()):
			if i in PROPERTY_GROUPS[group_index]:
				group_color = GROUP_COLORS[group_index]
				break
		var band_offset := Vector3(0, 0.09, -0.49).rotated(Vector3.UP, tile_rotation(i))
		var band := box(self, Vector3(0.88, 0.06, 0.16), pos + band_offset, group_color)
		band.rotation.y = tile_rotation(i)
		band.visible = i in CITY_TILES
		tile_colors.append(band)
		var markers := Node3D.new()
		markers.position = pos
		add_child(markers)
		ownership_markers.append(markers)
		var tile_text: String = DEFAULT_NAMES[i]
		if DEFAULT_PRICES.has(i):
			tile_text += "\n" + str(DEFAULT_PRICES[i]) + " DH"
		var card_label := label_on_tile(tile_text, pos, i)
		set_tile_text(card_label, DEFAULT_NAMES[i], int(DEFAULT_PRICES.get(i, 0)))
		labels.append(card_label)
		if i in [7, 22, 36]:
			board_symbol("?", pos, i, Color("dc2b87"))
		elif i in [2, 17, 33]:
			board_symbol("✦", pos, i, Color("32a9c6"))
		elif i in [5, 15, 25, 35]:
			board_symbol("♜", pos, i, Color("222b28"))
		elif i == 0:
			board_symbol("➜", pos, i, Color("dc4836"))
		elif i in [10, 20, 30]:
			board_symbol("★", pos, i, Color("de8c28"))
	# Coloured corners of the centre carry the two familiar card piles.
	cylinder(self, 1.55, 0.03, Vector3(-2.65, 0.035, -2.65), Color("e6a276"))
	cylinder(self, 1.55, 0.03, Vector3(2.65, 0.035, 2.65), Color("e6a276"))
	box(self, Vector3(1.28, 0.06, 0.96), Vector3(-2.65, 0.08, -2.65), Color("fff8e7"))
	box(self, Vector3(1.1, 0.34, 0.75), Vector3(-2.65, 0.28, -2.65), Color("85c9db"))
	box(self, Vector3(1.17, 0.09, 0.82), Vector3(-2.65, 0.49, -2.65), Color("eff9f4"))
	box(self, Vector3(0.9, 0.04, 0.50), Vector3(-2.65, 0.55, -2.65), Color("55adca"))
	box(self, Vector3(1.28, 0.07, 0.96), Vector3(2.65, 0.09, 2.65), Color("fff8e7"))
	box(self, Vector3(1.12, 0.07, 0.80), Vector3(2.65, 0.16, 2.65), Color("fa8c22"))
	var question := Label3D.new()
	question.text = "?"
	question.position = Vector3(2.65, 0.21, 2.65)
	question.rotation.x = -PI / 2
	question.font_size = 100
	question.pixel_size = 0.005
	question.outline_size = 0
	add_child(question)
	box(self, Vector3(5.9, 0.05, 1.45), Vector3(0, 0.04, 0), Color("e9bb79"))
	box(self, Vector3(5.55, 0.06, 1.17), Vector3(0, 0.10, 0), Color("fff9e7"))
	box(self, Vector3(5.28, 0.06, 0.94), Vector3(0, 0.14, 0), Color("e74d3e"))
	for i in range(2):
		var die := Node3D.new()
		die.position = Vector3((i - 0.5) * 0.8, 0.35, 1.8)
		add_child(die)
		box(die, Vector3(0.58, 0.58, 0.58), Vector3.ZERO, Color("fff7e7"))
		var face := Label3D.new()
		face.text = "–"
		face.position = Vector3(0, 0.30, 0)
		face.rotation.x = -PI / 2
		face.font_size = 58
		face.pixel_size = 0.007
		face.modulate = Color("183c33")
		face.outline_size = 0
		face.visible = false
		die.add_child(face)
		var dots: Array = []
		for row in range(3):
			for col in range(3):
				var dot := cylinder(die, 0.055, 0.012, Vector3((col - 1) * 0.16, 0.297, (row - 1) * 0.16), Color("202c2a"))
				dot.visible = (row * 3 + col) in ([0, 8] if i == 0 else [0, 2, 4, 6, 8])
				dots.append(dot)
		dice_pips.append(dots)
		dice_nodes.append(die)
		dice_labels.append(face)
	var title := Label3D.new()
	title.text = "QUARTIERS MAROC"
	title.position = Vector3(0, 0.19, 0)
	title.rotation.x = -PI / 2
	title.font_size = 100
	title.pixel_size = 0.0056
	title.modulate = Color("fffdf4")
	title.outline_size = 0
	add_child(title)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	add_child(camera)
	update_camera()

# A stylised city surrounds the shared board; these are not landmark replicas.
func build_city() -> void:
	box(self, Vector3(40, 0.3, 40), Vector3(0, -1.22, 0), Color("a1b0a9"))
	for side in [-1, 1]:
		box(self, Vector3(40, 0.07, 2.8), Vector3(0, -1.02, side * 9.0), Color("6f7774"))
		box(self, Vector3(2.8, 0.07, 40), Vector3(side * 9.0, -1.01, 0), Color("6f7774"))
		box(self, Vector3(40, 0.11, 0.65), Vector3(0, -0.98, side * 7.3), Color("d3d9d2"))
		box(self, Vector3(0.65, 0.11, 40), Vector3(side * 7.3, -0.97, 0), Color("d3d9d2"))
		for n in range(-18, 19, 2):
			box(self, Vector3(0.85, 0.015, 0.07), Vector3(n, -0.96, side * 9.0), Color("ede6c3"))
			box(self, Vector3(0.07, 0.015, 0.85), Vector3(side * 9.0, -0.95, n), Color("ede6c3"))
	for side in [-1, 1]:
		for stripe in range(-2, 3):
			box(self, Vector3(0.25, 0.025, 1.8), Vector3(stripe * 0.42, -0.94, side * 9.0), Color("f5f3df"))
			box(self, Vector3(1.8, 0.025, 0.25), Vector3(side * 9.0, -0.93, stripe * 0.42), Color("f5f3df"))
	for i in range(-2, 3):
		for side in [-1, 1]:
			make_building(Vector3(i * 4.4, -0.9, side * 13.0), i + side * 3, side < 0)
	for side in [-1, 1]:
		for i in range(-1, 2):
			if side == -1 and i == 0:
				make_tower(Vector3(-14.0, -0.9, 0))
			else:
				make_building(Vector3(side * 14.0, -0.9, i * 5.0), i + side * 7, side < 0)
	for side in [-1, 1]:
		for n in [-13, 13]:
			box(self, Vector3(3.1, 0.035, 1.9), Vector3(n, -1.035, side * 6.5), Color("82a95f"))
	for side in [-1, 1]:
		for n in [-15, -11, -5, 0, 5, 11, 15]:
			make_tree(Vector3(n, -0.9, side * 6.8), n + side)
			make_tree(Vector3(side * 6.8, -0.9, n), n - side)
	make_vehicle(Vector3(-4.5, -0.65, 8.65), 0.0, Color("e6a632"))
	make_vehicle(Vector3(5.0, -0.65, -8.65), PI, Color("c76155"))
	make_vehicle(Vector3(-8.65, -0.65, 3.0), PI / 2, Color("72aab4"))
	for n in [-5, -2, 2, 5]:
		make_pedestrian(Vector3(n, -0.88, 7.3), n)
		make_pedestrian(Vector3(7.3, -0.88, n), n + 2)
	for x in [-6.6, 6.6]:
		for z in [-6.6, 6.6]:
			cylinder(self, 0.05, 1.25, Vector3(x, -0.25, z), Color("2f4742"))
			var lamp := MeshInstance3D.new()
			var globe := SphereMesh.new()
			globe.radius = 0.17
			globe.height = 0.34
			lamp.mesh = globe
			lamp.material_override = material(Color("fff2b3"))
			lamp.position = Vector3(x, 0.46, z)
			add_child(lamp)

func make_tower(pos: Vector3) -> void:
	var model := add_kenney_model("city-commercial/building-skyscraper-a.glb", pos, 2.1, 0.0)
	if model != null:
		tint_model(model, Color("f0dbb2"))
		cylinder(self, 0.74, 1.1, pos + Vector3(0, 6.50, 0), Color("d9b457"), 0.08)
		cylinder(self, 0.12, 0.32, pos + Vector3(0, 7.18, 0), Color("736044"), 0.02)

func make_building(pos: Vector3, variant: int, reverse: bool) -> void:
	var names := ["a", "b", "c", "d", "f", "g", "h", "i", "l"]
	var model_name: String = names[absi(variant) % names.size()]
	var model := add_kenney_model("city-commercial/building-" + model_name + ".glb", pos, 2.25, PI if reverse else 0.0)
	var pastel := [Color("e9c1a6"), Color("e5b0a1"), Color("f4dfbf"), Color("a5cfc5"), Color("eacba7")]
	if model != null:
		tint_model(model, pastel[absi(variant) % pastel.size()])

func tint_model(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(surface)
			if source is BaseMaterial3D:
				var variant := source.duplicate() as BaseMaterial3D
				variant.albedo_color *= tint
				node.set_surface_override_material(surface, variant)
	for child in node.get_children():
		tint_model(child, tint)

func add_kenney_model(path: String, pos: Vector3, scale_value: float, angle: float) -> Node3D:
	var prefab: PackedScene = load("res://assets/kenney/" + path)
	if prefab == null:
		return null
	var instance := prefab.instantiate() as Node3D
	instance.position = pos
	instance.scale = Vector3.ONE * scale_value
	instance.rotation.y = angle
	add_child(instance)
	return instance

func make_vehicle(pos: Vector3, angle: float, paint: Color) -> void:
	var model := "taxi" if paint == Color("e6a632") else ("sedan" if paint == Color("c76155") else "hatchback-sports")
	var car := add_kenney_model("car/" + model + ".glb", pos, 0.35, angle + PI / 2)
	if car != null:
		var travel := Vector3(2.2, 0, 0) if absf(sin(angle)) < 0.5 else Vector3(0, 0, 2.2)
		var route := create_tween().set_loops()
		route.tween_property(car, "position", pos + travel, 5.0)
		route.tween_property(car, "position", pos, 5.0)

func make_pedestrian(pos: Vector3, variant: int) -> void:
	var characters := ["male-a", "male-b", "female-a", "female-b"]
	var model_name: String = characters[absi(variant) % characters.size()]
	var person := add_kenney_model("mini-characters/character-" + model_name + ".glb", pos, 1.2, 0.0)
	if person != null:
		var travel := Vector3(0.7, 0, 0) if absf(pos.z) > 7.0 else Vector3(0, 0, 0.7)
		var stroll := create_tween().set_loops()
		stroll.tween_property(person, "position", pos + travel, 3.5)
		stroll.tween_property(person, "position", pos, 3.5)

func make_tree(pos: Vector3, variant: int) -> void:
	cylinder(self, 0.12, 0.72, pos + Vector3(0, 0.36, 0), Color("865b42"))
	var foliage := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = 0.48
	shape.height = 0.96
	shape.radial_segments = 10
	shape.rings = 5
	foliage.mesh = shape
	var greens := [Color("719b48"), Color("a2ad43"), Color("d5a841")]
	foliage.material_override = material(greens[absi(variant) % greens.size()])
	foliage.position = pos + Vector3(0, 1.04, 0)
	add_child(foliage)

func update_camera() -> void:
	camera.size = view_distance * 1.16
	var target := Vector3(cos(view_angle), 0, -sin(view_angle)) * 1.5
	camera.position = target + Vector3(sin(view_angle) * view_distance, max(6.0, view_distance * view_elevation), cos(view_angle) * view_distance)
	camera.look_at(target, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			view_angle -= 0.12
		elif event.keycode == KEY_RIGHT:
			view_angle += 0.12
		elif event.keycode == KEY_UP:
			view_elevation = min(1.6, view_elevation + 0.1)
		elif event.keycode == KEY_DOWN:
			view_elevation = max(0.55, view_elevation - 0.1)
		else:
			return
		update_camera()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		view_angle -= event.relative.x * 0.006
		view_elevation = clamp(view_elevation + event.relative.y * 0.004, 0.55, 1.6)
		update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			inspect_tile(event.position)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			view_distance = max(10.0, view_distance - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view_distance = min(25.0, view_distance + 1.0)
		else:
			return
		update_camera()

func inspect_tile(screen_pos: Vector2) -> void:
	var ray_start := camera.project_ray_origin(screen_pos)
	var ray_direction := camera.project_ray_normal(screen_pos)
	var point = Plane(Vector3.UP, 0.05).intersects_ray(ray_start, ray_direction)
	if point == null:
		return
	var closest := -1
	var distance := 0.82
	for i in range(40):
		var tile := tile_position(i)
		var d := Vector2(point.x - tile.x, point.z - tile.z).length()
		if d < distance:
			distance = d
			closest = i
	if closest >= 0:
		tile_details.text = labels[closest].text.replace("\n", " ")

func add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 38)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-370, 18)
	panel.size = Vector2(350, 0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "QUARTIERS MAROC · PC 3D"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)
	var note := Label.new()
	note.text = "Prototype : monuments et commandes incomplets.\nCaméra : flèches ou clic droit, molette."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	tile_details = Label.new()
	tile_details.text = "Clique sur une case pour la lire"
	tile_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile_details.add_theme_font_size_override("font_size", 20)
	content.add_child(tile_details)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Connexion requise pour jouer."
	content.add_child(status)
	var sound := CheckButton.new()
	sound.text = "Son"
	sound.button_pressed = true
	sound.toggled.connect(func(enabled: bool):
		sound_enabled = enabled
		if not enabled:
			audio_player.stop()
			turn_alert.stop())
	content.add_child(sound)
	session_view = VBoxContainer.new()
	content.add_child(session_view)
	player_name = LineEdit.new()
	player_name.placeholder_text = "Ton prénom"
	player_name.max_length = 20
	session_view.add_child(player_name)
	room_code = LineEdit.new()
	room_code.placeholder_text = "Code du salon"
	session_view.add_child(room_code)
	server_field = LineEdit.new()
	server_field.text = saved_server if not saved_server.is_empty() else api.server
	server_field.tooltip_text = "Adresse du serveur commun"
	session_view.add_child(server_field)
	resume_button = add_button(session_view, "Reprendre ma partie", resume_session)
	resume_button.visible = not saved_session.is_empty()
	add_button(session_view, "Créer un salon", func(): enter(false, false))
	add_button(session_view, "Rejoindre un salon", func(): enter(true, false))
	add_button(session_view, "Jouer contre un robot", func(): enter(false, true))
	room_label = Label.new()
	content.add_child(room_label)
	players_label = RichTextLabel.new()
	players_label.fit_content = true
	players_label.scroll_active = false
	players_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(players_label)
	action_scroll = ScrollContainer.new()
	action_scroll.visible = false
	action_scroll.custom_minimum_size = Vector2(310, 350)
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(action_scroll)
	actions = VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.add_child(actions)
	exit_button = add_button(content, "Retour à l’accueil", confirm_leave)
	exit_button.visible = false

func enter(join: bool, solo: bool) -> void:
	if waiting:
		return
	if player_name.text.strip_edges().is_empty():
		status.text = "Indique ton prénom."
		return
	var address := server_field.text.strip_edges().trim_suffix("/")
	if not address.begins_with("https://") and not address.begins_with("http://127.0.0.1:"):
		status.text = "Utilise une adresse HTTPS."
		return
	waiting = true
	api.server = address
	status.text = "Connexion au serveur… Cela peut prendre une minute."
	var result: Dictionary
	if join:
		result = await api.join_room(player_name.text.strip_edges(), room_code.text)
	else:
		result = await api.create_room(player_name.text.strip_edges(), solo)
	waiting = false
	request_idle.emit()
	if not result.ok:
		show_error(str(result.error))
		return
	save_session()
	session_view.visible = false
	action_scroll.visible = true
	exit_button.visible = true
	room_label.text = "Salon : " + str(api.session.code)
	timer.start()
	refresh()

func refresh() -> void:
	if waiting or api.session.is_empty():
		return
	waiting = true
	var result: Dictionary = await api.state()
	waiting = false
	request_idle.emit()
	if not result.ok:
		show_error(str(result.error))
		return
	state = result.data
	update_state()

func send_action(kind: String, fields: Dictionary = {}) -> void:
	if waiting:
		await request_idle
	if waiting or api.session.is_empty():
		return
	waiting = true
	var result: Dictionary = await api.action(kind, fields)
	waiting = false
	request_idle.emit()
	if not result.ok:
		show_error(str(result.error))
		return
	refresh()

func update_state() -> void:
	var players: Array = state.get("players", [])
	var tiles: Array = state.get("tiles", [])
	var me: String = str(state.get("me", ""))
	var phase: String = str(state.get("phase", ""))
	var current_index := int(state.get("turn", 0))
	var current: Dictionary = players[current_index] if current_index < players.size() else {}
	var mine: Dictionary = {}
	players_label.clear()
	var round_number := int(state.get("gameRound", 0))
	if last_round >= 0 and round_number != last_round:
		for old_tween in pawn_tweens.values():
			if old_tween is Tween and old_tween.is_running():
				old_tween.kill()
		pawn_tweens.clear()
	last_round = round_number
	var new_events: Array = []
	if last_event_seq >= 0:
		for event in state.get("events", []):
			if int(event.get("id", 0)) > last_event_seq:
				new_events.append(event)
	last_event_seq = int(state.get("eventSeq", 0))
	for event in new_events:
		if event.get("type", "") == "offer-rejected" and sound_enabled and audio_player.stream != null:
			audio_player.play()
		elif event.get("type", "") == "payment":
			show_payment(event)
	var dice: Array = state.get("dice", [])
	var patterns := [[4], [0, 8], [0, 4, 8], [0, 2, 6, 8], [0, 2, 4, 6, 8], [0, 2, 3, 5, 6, 8]]
	for i in range(min(dice.size(), dice_labels.size())):
		var value := clampi(int(dice[i]), 1, 6)
		dice_labels[i].text = str(value)
		for pip in range(dice_pips[i].size()):
			dice_pips[i][pip].visible = pip in patterns[value - 1]
	if new_events.any(func(event): return event.get("type", "") == "dice"):
		for die in dice_nodes:
			die.rotation.y = 0.0
			var spin := create_tween()
			spin.tween_property(die, "rotation:y", TAU, 0.5).set_trans(Tween.TRANS_SINE)
	for i in range(players.size()):
		var player: Dictionary = players[i]
		if player.id == me:
			mine = player
		players_label.push_color(COLORS[i % COLORS.size()])
		players_label.add_text("● ")
		players_label.pop()
		players_label.add_text(str(player.name) + " · " + str(int(player.money)) + " DH" + (" · vous" if player.id == me else "") + "\n")
		var pawn: MeshInstance3D
		var is_new: bool = not pawns.has(player.id)
		if is_new:
			pawn = cylinder(self, 0.19, 0.12, Vector3.ZERO, COLORS[i % COLORS.size()])
			var characters := ["male-a", "female-a", "male-b", "female-b"]
			var prefab: PackedScene = load("res://assets/kenney/mini-characters/character-" + characters[i % characters.size()] + ".glb")
			if prefab != null:
				var figure := prefab.instantiate() as Node3D
				figure.position.y = 0.06
				figure.scale = Vector3.ONE * 0.9
				pawn.add_child(figure)
			pawns[player.id] = pawn
		else:
			pawn = pawns[player.id]
		var offset := Vector3((i % 3 - 1) * 0.22, 0.12, int(i / 3) * 0.22)
		var path: Array = []
		if not is_new:
			for event in new_events:
				if event.get("type", "") == "move" and event.get("playerId", "") == player.id:
					path.append_array(event.get("path", []))
		if not path.is_empty():
			if pawn_tweens.has(player.id) and pawn_tweens[player.id].is_running():
				pawn_tweens[player.id].kill()
			var movement := create_tween()
			pawn_tweens[player.id] = movement
			for square in path:
				movement.tween_property(pawn, "position", tile_position(int(square)) + offset, 0.18).set_trans(Tween.TRANS_SINE)
		elif is_new or not pawn_tweens.has(player.id) or not pawn_tweens[player.id].is_running():
			pawn.position = tile_position(int(player.pos)) + offset
	show_victory(phase, current, players, tiles, me, round_number)
	var turn_key := phase + ":" + str(current.get("id", "")) + ":" + str(round_number)
	if not last_turn_key.is_empty() and turn_key != last_turn_key and phase == "playing" and str(current.get("id", "")) == me and not mine.get("autoPlay", false) and sound_enabled:
		turn_alert.play()
	last_turn_key = turn_key
	for i in range(min(tiles.size(), labels.size())):
		set_tile_text(labels[i], str(tiles[i].name), int(tiles[i].get("price", 0)))
		var c := str(tiles[i].get("color", ""))
		if c.begins_with("#") and tile_color_values.get(i, "") != c:
			tile_colors[i].material_override = material(Color(c))
			tile_color_values[i] = c
		update_ownership(i, tiles[i], players)
	if Time.get_ticks_msec() < error_until:
		status.text = last_error
	else:
		var phase_names := {"lobby": "Salon", "opening": "Tirage de l’ordre", "playing": "Partie", "finished": "Partie terminée"}
		var turn_name := str(current.get("name", ""))
		var dice_text := str(int(dice[0])) + " + " + str(int(dice[1])) if dice.size() >= 2 else "–"
		status.text = str(phase_names.get(phase, phase)) + " · " + ("À toi de jouer" if str(current.get("id", "")) == me and phase == "playing" else turn_name) + " · Dés : " + dice_text
	var signature := JSON.stringify({"phase": phase, "turn": current.get("id", ""), "rolled": state.get("rolled"), "auction": state.get("auction"), "offer": state.get("offer"), "debts": state.get("debts"), "mine": mine, "tiles": tiles, "host": state.get("host"), "player_count": players.size()})
	# Presence clocks change every second; do not erase a player's typed price.
	if mine.has("timeoutSeconds"):
		var stable_mine := mine.duplicate(true)
		stable_mine.erase("timeoutSeconds")
		signature = JSON.stringify({"phase": phase, "turn": current.get("id", ""), "rolled": state.get("rolled"), "auction": state.get("auction"), "offer": state.get("offer"), "debts": state.get("debts"), "mine": stable_mine, "tiles": tiles, "host": state.get("host"), "player_count": players.size()})
	if signature == action_key:
		return
	action_key = signature
	call_deferred("resize_action_scroll")
	for child in actions.get_children():
		child.queue_free()
	if phase in ["opening", "playing"] and not mine.get("out", false):
		var auto := CheckButton.new()
		auto.text = "Mode auto"
		auto.button_pressed = bool(mine.get("autoPlay", false))
		auto.toggled.connect(func(enabled: bool): send_action("autoplay", {"enabled": enabled}))
		actions.add_child(auto)
	if mine.get("autoPlay", false) and phase == "lobby":
		# The existing server restores a temporary robot on the next state request.
		# This makes a replay lobby usable even if the player finished in auto mode.
		add_button(actions, "Reprendre le contrôle", func(): send_action("leave"))
		return
	if mine.get("autoPlay", false) and phase in ["opening", "playing"]:
		return
	var sale: Variant = state.get("auction")
	if sale != null:
		var auction_label := Label.new()
		auction_label.text = "Enchère : " + str(tiles[int(sale.index)].name) + " · " + str(sale.amount) + " DH"
		actions.add_child(auction_label)
		if str(sale.respondent) == me:
			var bid := SpinBox.new()
			bid.min_value = int(sale.amount) + 1
			bid.max_value = max(float(bid.min_value), float(mine.get("money", 0)))
			bid.value = bid.min_value
			actions.add_child(bid)
			add_button(actions, "Enchérir", func(): send_action("bid", {"amount": int(bid.value)}))
			add_button(actions, "Passer", func(): send_action("auctionpass"))
		return
	var trade: Variant = state.get("offer")
	if trade != null:
		var offer_label := Label.new()
		var offered_names: Array[String] = []
		for index in trade.get("offered", []):
			if int(index) >= 0 and int(index) < tiles.size():
				offered_names.append(str(tiles[int(index)].name))
		offer_label.text = "Offre pour " + str(tiles[int(trade.index)].name) + " : " + str(trade.amount) + " DH"
		if not offered_names.is_empty():
			offer_label.text += " + " + ", ".join(offered_names)
		offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actions.add_child(offer_label)
		if str(trade.respondent) == me:
			add_button(actions, "Accepter", func(): send_action("acceptoffer"))
			add_button(actions, "Refuser", func(): send_action("rejectoffer"))
			var counter := SpinBox.new()
			counter.min_value = 1
			counter.max_value = 100000
			counter.value = max(1, int(trade.amount))
			actions.add_child(counter)
			add_button(actions, "Contre-offre", func(): send_action("counteroffer", {"amount": int(counter.value)}))
		elif str(trade.buyer) == me or str(trade.seller) == me:
			add_button(actions, "Annuler l’offre", func(): send_action("canceloffer"))
		return
	var debts: Array = state.get("debts", [])
	if not debts.is_empty():
		var debt_label := Label.new()
		debt_label.text = "Dette à régler : " + str(debts[0].amount) + " DH"
		actions.add_child(debt_label)
		if str(debts[0].player) == me:
			add_property_management(tiles, me)
			add_button(actions, "Déclarer faillite", confirm_bankruptcy)
		return
	if phase == "lobby" and me == str(state.get("host", "")):
		add_button(actions, "Ajouter un robot", func(): send_action("addbot"))
		if players.size() >= 2:
			add_button(actions, "Commencer", func(): send_action("start"))
	elif phase == "opening" and str(current.get("id", "")) == me:
		add_button(actions, "Lancer pour l’ordre", func(): send_action("orderroll"))
	elif phase == "playing" and str(current.get("id", "")) == me and not mine.get("out", false):
		if not state.get("rolled", false):
			add_button(actions, "Lancer les dés", func(): send_action("roll"))
			if mine.get("jail", false):
				add_button(actions, "Payer pour sortir", func(): send_action("payjail"))
				if not mine.get("jailCards", []).is_empty():
					add_button(actions, "Utiliser une carte de sortie", func(): send_action("usejail"))
		else:
			var tile: Dictionary = tiles[int(mine.get("pos", 0))]
			if int(tile.get("price", 0)) > 0 and str(tile.get("owner", "")).is_empty() and not state.get("auctioned", false):
				var buy := add_button(actions, "Acheter · " + str(tile.price) + " DH", func(): send_action("buy"))
				buy.disabled = int(mine.get("money", 0)) < int(tile.price)
				add_button(actions, "Mettre aux enchères", func(): send_action("auction"))
			add_button(actions, "Terminer le tour", func(): send_action("end"))
	elif phase == "finished" and me == str(state.get("host", "")):
		add_button(actions, "Rejouer", func(): send_action("rematch"))
	if phase == "playing" and not mine.get("out", false):
		add_property_management(tiles, me)
		add_offer_controls(tiles, me, int(mine.get("money", 0)))

func add_property_management(tiles: Array, me: String) -> void:
	var own := OptionButton.new()
	for i in range(tiles.size()):
		if str(tiles[i].get("owner", "")) == me and int(tiles[i].get("price", 0)) > 0:
			own.add_item(str(tiles[i].name), i)
	if own.item_count == 0:
		own.free()
		return
	actions.add_child(own)
	add_button(actions, "Hypothéquer", func(): send_action("mortgage", {"index": own.get_selected_id()}))
	add_button(actions, "Lever l’hypothèque", func(): send_action("unmortgage", {"index": own.get_selected_id()}))
	add_button(actions, "Construire", func(): send_action("build", {"index": own.get_selected_id()}))
	add_button(actions, "Vendre une maison", func(): send_action("sellhouse", {"index": own.get_selected_id()}))

func add_offer_controls(tiles: Array, me: String, money: int) -> void:
	var target := OptionButton.new()
	for i in range(tiles.size()):
		var owner := str(tiles[i].get("owner", ""))
		if not owner.is_empty() and owner != me:
			target.add_item(str(tiles[i].name), i)
	if target.item_count == 0:
		target.free()
		return
	actions.add_child(target)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = max(1, money)
	amount.value = min(100, max(1, money))
	actions.add_child(amount)
	var own_tiles := ItemList.new()
	own_tiles.select_mode = ItemList.SELECT_MULTI
	own_tiles.custom_minimum_size = Vector2(0, 76)
	for i in range(tiles.size()):
		if str(tiles[i].get("owner", "")) == me and not tiles[i].get("mortgaged", false):
			own_tiles.add_item(str(tiles[i].name))
			own_tiles.set_item_metadata(own_tiles.item_count - 1, i)
	if own_tiles.item_count > 0:
		var help := Label.new()
		help.text = "Biens proposés en plus (facultatif)"
		actions.add_child(help)
		actions.add_child(own_tiles)
	else:
		own_tiles.free()
		own_tiles = null
	add_button(actions, "Envoyer une offre", func():
		var offered: Array[int] = []
		if own_tiles != null:
			for selected in own_tiles.get_selected_items():
				offered.append(int(own_tiles.get_item_metadata(selected)))
		send_action("offer", {"index": target.get_selected_id(), "amount": int(amount.value), "offered": offered}))

func confirm_bankruptcy() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Déclarer faillite ?"
	dialog.dialog_text = "Confirmer la faillite et abandonner vos biens ?"
	dialog.confirmed.connect(func(): send_action("bankrupt"))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 160))

func load_session() -> void:
	var config := ConfigFile.new()
	if config.load(session_file) != OK:
		return
	var previous: Variant = config.get_value("game", "session", {})
	var address: String = str(config.get_value("game", "server", ""))
	if typeof(previous) == TYPE_DICTIONARY and previous.has("code") and previous.has("token") and (address.begins_with("https://") or address.begins_with("http://127.0.0.1:")):
		saved_session = previous
		saved_server = address

func save_session() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "session", api.session)
	config.set_value("game", "server", api.server)
	config.save(session_file)
	saved_session = api.session.duplicate(true)
	saved_server = api.server
	if resume_button != null:
		resume_button.visible = true

func resume_session() -> void:
	if waiting or saved_session.is_empty():
		return
	api.server = saved_server
	api.session = saved_session.duplicate(true)
	waiting = true
	status.text = "Reprise de la partie… Cela peut prendre une minute."
	var health_result: Dictionary = await api.health()
	var result: Dictionary = await api.state() if health_result.ok else health_result
	waiting = false
	request_idle.emit()
	if not result.ok:
		show_error(str(result.error))
		return
	session_view.visible = false
	action_scroll.visible = true
	exit_button.visible = true
	room_label.text = "Salon : " + str(api.session.code)
	state = result.data
	update_state()
	timer.start()

func show_error(message: String) -> void:
	last_error = message
	error_until = Time.get_ticks_msec() + 5000
	status.text = message

func leave_session() -> void:
	if waiting:
		await request_idle
	if waiting or api.session.is_empty():
		return
	waiting = true
	timer.stop()
	var result: Dictionary = await api.action("leave")
	waiting = false
	request_idle.emit()
	if not result.ok:
		show_error(str(result.error))
		timer.start()
		return
	save_session()
	api.session = {}
	state = {}
	action_key = ""
	session_view.visible = true
	action_scroll.visible = false
	exit_button.visible = false
	room_label.text = ""
	players_label.clear()
	for pawn in pawns.values():
		pawn.queue_free()
	pawns.clear()
	pawn_tweens.clear()
	last_event_seq = -1
	last_round = -1
	last_turn_key = ""
	victory_key = ""
	if is_instance_valid(victory_dialog):
		victory_dialog.queue_free()
		victory_dialog = null
	for child in actions.get_children():
		child.queue_free()
	status.text = "Le robot prend le relais. Tu peux reprendre ta partie."

func confirm_leave() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Revenir à l’accueil ?"
	dialog.dialog_text = "Un robot prendra le relais. Tu pourras reprendre ta partie."
	dialog.confirmed.connect(leave_session)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 160))

func resize_action_scroll() -> void:
	await get_tree().process_frame
	if is_instance_valid(action_scroll) and is_instance_valid(actions):
		action_scroll.custom_minimum_size.y = clamp(actions.get_combined_minimum_size().y, 80.0, 350.0)

func update_ownership(index: int, tile: Dictionary, players: Array) -> void:
	var owner := str(tile.get("owner", ""))
	var level := int(tile.get("level", 0))
	var mortgaged := bool(tile.get("mortgaged", false))
	var key := owner + ":" + str(level) + ":" + str(mortgaged)
	if tile_visuals.get(index, "") == key:
		return
	tile_visuals[index] = key
	var marker: Node3D = ownership_markers[index]
	for child in marker.get_children():
		child.queue_free()
	for i in range(players.size()):
		if str(players[i].get("id", "")) == owner:
			box(marker, Vector3(0.14, 0.12, 0.14), Vector3(0.33, 0.12, 0.30), COLORS[i % COLORS.size()])
			break
	if level > 0:
		var count := 1 if level == 5 else level
		for n in range(count):
			var color := Color("c83838") if level == 5 else Color("16884e")
			box(marker, Vector3(0.11, 0.12, 0.12), Vector3(-0.31 + n * 0.15, 0.13, 0.32), color)
	if mortgaged:
		box(marker, Vector3(0.13, 0.11, 0.13), Vector3(-0.33, 0.12, -0.28), Color("bc302e"))

func show_payment(event: Dictionary) -> void:
	var index := int(event.get("tileIndex", -1))
	var amount := int(event.get("amount", 0))
	if index < 0 or index >= 40 or amount <= 0:
		return
	var label := Label3D.new()
	label.text = "−" + str(amount) + " DH"
	label.font_size = 64
	label.pixel_size = clamp(0.002 + log(float(amount) + 1.0) * 0.00055, 0.003, 0.007)
	label.modulate = Color("df2626")
	label.outline_size = 6
	label.outline_modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = tile_position(index) + Vector3(0, 0.7, 0)
	add_child(label)
	var animation := create_tween()
	animation.tween_property(label, "position:y", 1.7, 2.0)
	animation.parallel().tween_property(label, "modulate:a", 0.0, 2.0)
	animation.tween_callback(label.queue_free)

func make_turn_sound() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	sound.stereo = false
	var samples := PackedByteArray()
	var count := 5500
	samples.resize(count * 2)
	for i in range(count):
		var time := float(i) / float(sound.mix_rate)
		var envelope: float = minf(1.0, time * 35.0) * (1.0 - float(i) / float(count))
		var sample := int(sin(TAU * 660.0 * time) * envelope * 11000.0)
		samples.encode_s16(i * 2, sample)
	sound.data = samples
	return sound

func show_victory(phase: String, winner: Dictionary, players: Array, tiles: Array, me: String, round_number: int) -> void:
	if phase != "finished":
		if is_instance_valid(victory_dialog):
			victory_dialog.hide()
			victory_dialog.queue_free()
			victory_dialog = null
		return
	var key := str(round_number) + ":" + str(winner.get("id", ""))
	if key == victory_key:
		return
	victory_key = key
	if is_instance_valid(victory_dialog):
		victory_dialog.queue_free()
	victory_dialog = AcceptDialog.new()
	victory_dialog.title = "🏆 Champion du Maroc"
	var message := str(winner.get("name", "")) + " remporte la partie !\n\nClassement :\n"
	for player in players:
		var owned := 0
		for tile in tiles:
			if str(tile.get("owner", "")) == str(player.get("id", "")):
				owned += 1
		message += str(player.get("name", "")) + " · " + str(int(player.get("money", 0))) + " DH · " + str(owned) + " biens\n"
	victory_dialog.dialog_text = message
	victory_dialog.close_requested.connect(victory_dialog.queue_free)
	victory_dialog.confirmed.connect(victory_dialog.queue_free)
	if me == str(state.get("host", "")):
		victory_dialog.add_button("Rejouer", true, "rematch")
		victory_dialog.custom_action.connect(func(action: StringName):
			if action == "rematch":
				send_action("rematch")
				victory_dialog.hide())
	add_child(victory_dialog)
	victory_dialog.popup_centered(Vector2i(460, 270))
