extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.session_file = "user://quartiers-web-test.cfg"
	root.add_child(scene)
	await process_frame
	scene.api.server = "http://127.0.0.1:8799"
	var room := OS.get_environment("QUARTIERS_TEST_ROOM")
	var result: Dictionary = await scene.api.join_room("PC 3D", room)
	if not result.ok:
		printerr("Impossible de rejoindre le salon web")
		quit(1)
		return
	for attempt in range(200):
		var current: Dictionary = await scene.api.state()
		if current.ok and current.data.players.size() >= 3:
			var game: Dictionary = current.data
			scene.state = game
			scene.update_state()
			await process_frame
			var current_player: Dictionary = game.players[int(game.turn)]
			if current_player.id == game.me and game.phase == "opening":
				await scene.api.action("orderroll")
			elif current_player.id == game.me and game.phase == "playing" and not game.rolled:
				await scene.api.action("roll")
			for event in game.get("events", []):
				if event.type == "move":
					if scene.pawns.size() != game.players.size():
						printerr("Les pions de la partie ne sont pas affichés")
						quit(1)
						return
					print("OK : le client Godot voit le démarrage du salon web, tous les pions et un déplacement")
					quit(0)
					return
		await create_timer(0.2).timeout
	printerr("Le démarrage du salon web n'a pas été reçu")
	quit(1)
