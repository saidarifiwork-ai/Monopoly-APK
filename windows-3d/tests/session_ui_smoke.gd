extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quartiers-session-test.cfg"))
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.session_file = "user://quartiers-session-test.cfg"
	root.add_child(scene)
	await process_frame
	scene.server_field.text = "http://127.0.0.1:8799"
	scene.player_name.text = "Test Windows"
	await scene.enter(false, false)
	await create_timer(0.3).timeout
	if scene.api.session.is_empty() or scene.session_view.visible or not scene.action_scroll.visible:
		printerr("ÉCHEC : entrée dans le salon")
		quit(1)
		return
	var original: Dictionary = scene.api.session.duplicate(true)
	await scene.leave_session()
	if not scene.api.session.is_empty() or not scene.session_view.visible or not scene.resume_button.visible:
		printerr("ÉCHEC : retour à l’accueil")
		quit(1)
		return
	await scene.resume_session()
	if scene.api.session != original or scene.session_view.visible or not scene.action_scroll.visible:
		printerr("ÉCHEC : reprise avec la même session")
		quit(1)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quartiers-session-test.cfg"))
	print("OK : entrée, départ et reprise de session depuis l’interface 3D")
	quit(0)
