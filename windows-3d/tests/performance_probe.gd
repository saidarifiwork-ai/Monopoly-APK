extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.session_file = "user://quartiers-performance-test.cfg"
	root.add_child(scene)
	await process_frame
	scene.state = {"me": "probe"}
	var pawn = scene.cylinder(scene, 0.19, 0.12, scene.tile_position(0), Color("d9483b"))
	scene.pawns["probe"] = pawn
	scene.set_board_focus(true)
	await create_timer(2.0).timeout
	var started := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - started < 5000:
		await process_frame
		frames += 1
	print("RENDER_PROBE_FPS=", snappedf(frames * 1000.0 / (Time.get_ticks_msec() - started), 0.1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quartiers-performance-test.cfg"))
	quit()
