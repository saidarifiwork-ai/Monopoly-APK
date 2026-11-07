extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var api = load("res://scripts/game_api.gd").new()
	root.add_child(api)
	api.server = "http://127.0.0.1:8799"
	var room := OS.get_environment("QUARTIERS_TEST_ROOM")
	var result: Dictionary = await api.join_room("PC 3D", room)
	if not result.ok:
		printerr("Impossible de rejoindre le salon web")
		quit(1)
		return
	for attempt in range(50):
		var state: Dictionary = await api.state()
		if state.ok and state.data.phase == "opening" and state.data.players.size() == 2:
			print("OK : le client Godot voit le démarrage du salon web")
			quit(0)
			return
		await create_timer(0.2).timeout
	printerr("Le démarrage du salon web n'a pas été reçu")
	quit(1)
