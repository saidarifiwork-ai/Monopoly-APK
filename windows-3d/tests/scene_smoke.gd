extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	printerr("ÉCHEC : " + message)
	quit(1)

func has_button(scene, value: String) -> bool:
	for child in scene.actions.get_children():
		if child is Button and child.text == value:
			return true
	return false

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.session_file = "user://quartiers-scene-test.cfg"
	root.add_child(scene)
	await process_frame
	var panel: Control
	for child in scene.get_children():
		if child is CanvasLayer:
			panel = child.get_child(0)
	if panel == null or panel.get_global_rect().position.x < 0:
		fail("panneau visible à l’écran : " + str(panel.get_global_rect() if panel != null else "absent"))
		return
	for asset in ["city-commercial/building-a.glb", "car/taxi.glb", "mini-characters/character-male-a.glb"]:
		if load("res://assets/kenney/" + asset) == null:
			fail("modèle 3D manquant : " + asset)
			return
	if scene.labels.size() != 40:
		fail("les 40 cases")
		return
	if not scene.labels[1].text.contains("60 DH") or not scene.tile_colors[1].visible or scene.tile_colors[2].visible:
		fail("prix et couleurs des cases")
		return
	var default_dots := 0
	for pip in scene.dice_pips[0]:
		if pip.visible:
			default_dots += 1
	if default_dots != 2:
		fail("points des dés")
		return
	scene.api.server = "http://127.0.0.1:8799"
	var made: Dictionary = await scene.api.create_room("Test PC")
	if not made.ok:
		fail("création de partie")
		return
	var friend = load("res://scripts/game_api.gd").new()
	root.add_child(friend)
	friend.server = scene.api.server
	var joined: Dictionary = await friend.join_room("Ami web", made.data.code)
	if not joined.ok:
		fail("ami rejoint")
		return
	var snapshot: Dictionary = await scene.api.state()
	scene.state = snapshot.data
	scene.update_state()
	await process_frame
	if scene.pawns.size() != 2 or not has_button(scene, "Commencer"):
		fail("pions et commandes du salon")
		return
	var started: Dictionary = await scene.api.action("start")
	if not started.ok:
		fail("démarrage")
		return
	snapshot = await scene.api.state()
	scene.state = snapshot.data
	scene.update_state()
	await process_frame
	if not has_button(scene, "Lancer pour l’ordre"):
		fail("commande de tirage")
		return
	# A player who finished the previous game in auto mode can resume in the lobby.
	var lobby_auto: Dictionary = snapshot.data.duplicate(true)
	lobby_auto.phase = "lobby"
	lobby_auto.players[0].autoPlay = true
	lobby_auto.players[0].bot = true
	scene.state = lobby_auto
	scene.update_state()
	await process_frame
	if not has_button(scene, "Reprendre le contrôle"):
		fail("reprise du mode auto dans le salon")
		return
	# Check dice and a multi-square path from server events.
	var sample: Dictionary = snapshot.data.duplicate(true)
	sample.phase = "playing"
	sample.rolled = true
	sample.dice = [6, 2]
	sample.players[0].pos = 2
	sample.eventSeq = int(sample.eventSeq) + 2
	sample.events = [
		{"id": int(sample.eventSeq) - 1, "type": "dice", "dice": [6, 2]},
		{"id": int(sample.eventSeq), "type": "move", "playerId": sample.players[0].id, "path": [1, 2]}
	]
	scene.state = sample
	scene.update_state()
	await create_timer(0.6).timeout
	var expected: Vector3 = scene.tile_position(2) + Vector3(-0.22, 0.12, 0)
	if scene.pawns[sample.players[0].id].position.distance_to(expected) > 0.02 or scene.dice_labels[0].text != "6" or scene.dice_labels[1].text != "2":
		fail("dés et chemin animé du pion")
		return
	# Check the interactive auction layout using the same authoritative state.
	sample.auction = {"index": 1, "amount": 4, "respondent": sample.me, "deadline": 123456}
	scene.state = sample
	scene.update_state()
	await process_frame
	if not has_button(scene, "Enchérir") or not has_button(scene, "Passer"):
		fail("commandes d’enchères")
		return
	var bid: SpinBox
	for child in scene.actions.get_children():
		if child is SpinBox:
			bid = child
	if bid == null or bid.min_value != 5:
		fail("prix minimum d’enchère")
		return
	bid.value = 17
	scene.update_state()
	if bid.value != 17 or bid.is_queued_for_deletion():
		fail("prix conservé pendant l’actualisation")
		return
	sample.auction = null
	sample.tiles[5].owner = sample.me
	sample.tiles[5].level = 2
	scene.state = sample
	scene.update_state()
	await process_frame
	if scene.ownership_markers[5].get_child_count() < 3:
		fail("propriétaire et maisons visibles sur la case")
		return
	scene.show_payment({"tileIndex": 5, "amount": 20})
	scene.show_payment({"tileIndex": 5, "amount": 200})
	var sizes: Array[float] = []
	for child in scene.get_children():
		if child is Label3D and child.text.begins_with("−"):
			sizes.append(child.pixel_size)
	if sizes.size() != 2 or sizes[1] <= sizes[0]:
		fail("taille du paiement sur la case")
		return
	sample.offer = {"index": 1, "amount": 4, "respondent": sample.me, "buyer": "other", "seller": sample.me, "offered": [5]}
	scene.state = sample
	scene.update_state()
	await process_frame
	var offer_shows_property := false
	for child in scene.actions.get_children():
		if child is Label and child.text.contains(str(sample.tiles[5].name)):
			offer_shows_property = true
	if not offer_shows_property or not has_button(scene, "Accepter") or not has_button(scene, "Refuser"):
		fail("détails et contrôles d’échange")
		return
	# Proposing an offer must work both with and without extra owned properties.
	sample.offer = null
	sample.tiles[1].owner = sample.players[1].id
	sample.tiles[5].owner = ""
	sample.tiles[5].level = 0
	scene.state = sample
	scene.update_state()
	await process_frame
	if not has_button(scene, "Envoyer une offre"):
		fail("proposer une offre en argent")
		return
	sample.tiles[5].owner = sample.me
	scene.state = sample
	scene.update_state()
	await process_frame
	var selection_found := false
	for child in scene.actions.get_children():
		if child is ItemList and child.item_count > 0:
			selection_found = true
	if not selection_found:
		fail("proposer aussi un bien dans l’échange")
		return
	if scene.audio_player.stream == null:
		fail("audio de refus embarqué")
		return
	scene.sound_enabled = false
	sample.eventSeq = int(sample.eventSeq) + 1
	sample.events = [{"id": sample.eventSeq, "type": "offer-rejected"}]
	scene.state = sample
	scene.update_state()
	if scene.audio_player.playing:
		fail("son coupé respecté")
		return
	scene.sound_enabled = true
	sample.eventSeq = int(sample.eventSeq) + 1
	sample.events = [{"id": sample.eventSeq, "type": "offer-rejected"}]
	scene.state = sample
	scene.update_state()
	if not scene.audio_player.playing:
		fail("lecture du son de refus")
		return
	sample.offer = null
	sample.phase = "finished"
	sample.turn = 0
	sample.gameRound = 1
	scene.state = sample
	scene.update_state()
	await process_frame
	if not is_instance_valid(scene.victory_dialog) or not scene.victory_dialog.visible or not scene.victory_dialog.dialog_text.contains("Test PC"):
		fail("célébration et classement")
		return
	var first_dialog = scene.victory_dialog
	scene.update_state()
	if scene.victory_dialog != first_dialog:
		fail("la victoire ne doit pas se rouvrir à chaque actualisation")
		return
	sample.phase = "lobby"
	sample.gameRound = 2
	scene.state = sample
	scene.update_state()
	await process_frame
	sample.phase = "finished"
	scene.state = sample
	scene.update_state()
	await process_frame
	if not is_instance_valid(scene.victory_dialog) or not scene.victory_dialog.visible:
		fail("nouvelle célébration après une revanche")
		return
	scene.save_session()
	var restored = load("res://scenes/main.tscn").instantiate()
	restored.session_file = "user://quartiers-scene-test.cfg"
	root.add_child(restored)
	await process_frame
	if restored.saved_session.get("code", "") != made.data.code or restored.saved_session.get("token", "") != made.data.token:
		fail("session conservée pour la reprise")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quartiers-scene-test.cfg"))
	scene.audio_player.stop()
	scene.turn_alert.stop()
	await create_timer(0.3).timeout
	scene.queue_free()
	restored.queue_free()
	friend.queue_free()
	await process_frame
	print("OK : scène 3D, dés, chemin des pions, salon, enchères, offres, son et reprise")
	quit(0)
