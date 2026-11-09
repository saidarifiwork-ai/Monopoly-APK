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
	for asset in ["voiture", "bateau", "monsieur", "de", "plateau-original"]:
		if load("res://assets/user_models/" + asset + ".glb") == null:
			fail("modèle fourni manquant : " + asset)
			return
	if scene.labels.size() != 40:
		fail("les 40 cases")
		return
	if not scene.labels[1].text.contains("60 DH") or not scene.tile_colors[1].visible or scene.tile_colors[2].visible:
		fail("prix et couleurs des cases")
		return
	if scene.get_node_or_null("Plateau3DImporte") == null:
		fail("plateau 3D fourni non affiché")
		return
	for i in range(40):
		scene.inspect_tile(scene.camera.unproject_position(scene.tile_position(i) + Vector3(0, 0.05, 0)))
		if scene.tile_details.text != scene.labels[i].text.replace("\n", " "):
			fail("case mal alignée : " + str(i))
			return
	# Clicking a card exposes its full name and price in large UI text.
	scene.inspect_tile(scene.camera.unproject_position(scene.tile_position(1) + Vector3(0, 0.05, 0)))
	if not scene.tile_details.text.contains("Chefchaouen") or not scene.tile_details.text.contains("60 DH"):
		fail("lecture agrandie de la case et de son prix")
		return
	var hop_pawn := Node3D.new()
	scene.add_child(hop_pawn)
	scene.animate_pawn_hop(0.5, hop_pawn, Vector3.ZERO, Vector3(1, 0, 0))
	if absf(hop_pawn.position.x - 0.5) > 0.01 or hop_pawn.position.y < 0.2:
		fail("saut du pion entre deux cases")
		return
	hop_pawn.queue_free()
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
	if scene.focused_board or scene.focus_overlay.visible or scene.view_distance != 18.5:
		fail("vue générale pendant le salon")
		return
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
	if not scene.focused_board or scene.focus_overlay.visible or scene.view_distance != 7.8:
		fail("plateau agrandi en mode performance")
		return
	await process_frame
	if not is_equal_approx(root.scaling_3d_scale, 1.0) or not scene.labels[20].visible:
		fail("optimisations du plateau rapproché")
		return
	scene.quality_control.button_pressed = true
	if not scene.focus_overlay.visible or not is_equal_approx(root.scaling_3d_scale, 1.0):
		fail("activation du flou facultatif")
		return
	scene.quality_control.button_pressed = false
	var pawn_screen: Vector2 = scene.camera.unproject_position(scene.pawns[scene.state.me].position)
	var centre_screen: Vector2 = scene.camera.unproject_position(Vector3.ZERO)
	var viewport_size: Vector2 = root.get_visible_rect().size
	if absf(pawn_screen.x / viewport_size.x - 0.5) > 0.08 or pawn_screen.y < viewport_size.y * 0.52 or centre_screen.y >= pawn_screen.y:
		fail("cadrage : pion centré en bas, plateau devant")
		return
	if not scene.map_button.visible or scene.map_button.text != "Voir tout le plateau" or not scene.follow_anchor_valid:
		fail("caméra qui suit le pion")
		return
	scene.map_button.pressed.emit()
	if not scene.map_overview or scene.view_distance != 14.7 or scene.map_button.text != "Suivre mon pion" or not scene.labels[20].visible:
		fail("bouton pour voir tout le plateau")
		return
	scene.map_button.pressed.emit()
	await process_frame
	await process_frame
	if scene.map_overview or scene.view_distance != 7.8 or not scene.follow_anchor_valid:
		fail("retour au suivi du pion")
		return
	scene.view_distance = 13.0
	scene.update_state()
	if scene.view_distance != 13.0:
		fail("zoom du joueur conservé pendant les actualisations")
		return
	for control in [scene.context_button, scene.map_button, scene.menu_button]:
		var rect: Rect2 = control.get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > root.get_visible_rect().size.x or rect.end.y > root.get_visible_rect().size.y:
			fail("commande hors de l’écran : " + str(control.text) + " " + str(rect) + " viewport " + str(root.get_visible_rect()))
			return
	if scene.main_panel.visible:
		fail("grand panneau encore visible")
		return
	if not scene.roll_button.visible:
		fail("bouton de lancer affiché quand c’est son tour")
		return
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
	if scene.focused_board or scene.focus_overlay.visible or scene.view_distance != 18.5:
		fail("retour à la vue générale du salon")
		return
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
	for die in scene.dice_nodes:
		if absf(die.position.x) > 2.0 or absf(die.position.z) > 2.0:
			fail("le lancer doit démarrer dans la zone centrale")
			return
	if not scene.roll_button.disabled or scene.main_panel.visible:
		fail("bouton de lancer désactivé et panneau fermé après le lancer")
		return
	await create_timer(0.6).timeout
	var expected: Vector3 = scene.tile_position(2) + Vector3(-0.22, 0.12, 0)
	if scene.follow_anchor.distance_to(expected) > 0.6:
		fail("la caméra suit le pion en déplacement")
		return
	if scene.pawns[sample.players[0].id].position.distance_to(expected) > 0.02 or scene.dice_labels[0].text != "6" or scene.dice_labels[1].text != "2":
		fail("dés et chemin animé du pion")
		return
	if not scene.context_button.disabled:
		fail("achat sur case spéciale")
		return
	var purchase: Dictionary = sample.duplicate(true)
	purchase.players[0].pos = 1
	purchase.events = []
	scene.state = purchase
	scene.update_state()
	if scene.context_button.disabled or scene.context_kind != "buy":
		fail("achat disponible après arrivée sur une propriété libre")
		return
	scene.state = sample
	scene.update_state()
	var building: Dictionary = sample.duplicate(true)
	for square in [1, 3]:
		building.tiles[square].owner = building.me
		building.tiles[square].level = 0
	scene.state = building
	scene.selected_tile = 1
	scene.update_state()
	if scene.context_kind != "build" or scene.context_button.disabled:
		fail("construction depuis la case sélectionnée")
		return
	scene.state = sample
	scene.selected_tile = 2
	scene.update_state()
	for die_index in range(2):
		if scene.dice_nodes[die_index].position.distance_to(scene.dice_center_position(die_index)) > 0.01:
			fail("les dés doivent s’arrêter au centre du plateau")
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
