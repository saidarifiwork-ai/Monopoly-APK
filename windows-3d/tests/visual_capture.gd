extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.session_file = "user://quartiers-visual-test.cfg"
	root.add_child(scene)
	await process_frame
	if OS.get_environment("QUARTIERS_CAPTURE_GAME") == "1":
		scene.server_field.text = "http://127.0.0.1:8799"
		scene.player_name.text = "Saïd"
		await scene.enter(false, false)
		var friend = load("res://scripts/game_api.gd").new()
		root.add_child(friend)
		friend.server = scene.api.server
		await friend.join_room("Ami", scene.api.session.code)
		if OS.get_environment("QUARTIERS_CAPTURE_FOCUS") == "1":
			await scene.api.action("start")
		await scene.refresh()
	if OS.get_environment("QUARTIERS_CAPTURE_FOCUS") == "1":
		scene.set_board_focus(true)
	for frame in range(10):
		await process_frame
	await create_timer(1.0).timeout
	var image: Image = root.get_texture().get_image()
	var target := OS.get_environment("QUARTIERS_CAPTURE_PATH")
	if target.is_empty():
		target = "/tmp/quartiers-3d-preview.png"
	var result := image.save_png(target)
	if result != OK:
		printerr("Capture impossible : ", result)
		quit(1)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quartiers-visual-test.cfg"))
	print("Capture enregistrée : ", target)
	quit(0)
