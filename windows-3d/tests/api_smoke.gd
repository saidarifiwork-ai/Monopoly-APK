extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	if not value:
		printerr("ÉCHEC : " + description)
		quit(1)

func run() -> void:
	var host = load("res://scripts/game_api.gd").new()
	var friend = load("res://scripts/game_api.gd").new()
	root.add_child(host)
	root.add_child(friend)
	host.server = "http://127.0.0.1:8799"
	friend.server = host.server
	var health: Dictionary = await host.health()
	check(health.ok and health.data.app == "quartiers", "serveur commun")
	var created: Dictionary = await host.create_room("PC 3D test")
	check(created.ok, "création salon")
	var joined: Dictionary = await friend.join_room("Web APK test", created.data.code)
	check(joined.ok, "ami rejoint le même salon")
	var host_state: Dictionary = await host.state()
	var friend_state: Dictionary = await friend.state()
	check(host_state.ok and friend_state.ok, "états accessibles")
	check(host_state.data.players.size() == 2 and friend_state.data.players.size() == 2, "deux joueurs ensemble")
	check(host_state.data.me != friend_state.data.me, "identités distinctes")
	for player in host_state.data.players:
		check(not player.has("token"), "jetons des autres joueurs confidentiels")
	var unauthorized: Dictionary = await friend.action("start")
	check(not unauthorized.ok, "seul l’hôte peut démarrer")
	var started: Dictionary = await host.action("start", {"token": "forged", "code": "wrong"})
	check(started.ok, "hôte peut démarrer avec la session protégée")
	var updated: Dictionary = await friend.state()
	check(updated.ok and updated.data.phase == "opening", "autre joueur voit le démarrage")
	print("OK : serveur partagé, salon, identités, démarrage synchronisé")
	quit(0)
