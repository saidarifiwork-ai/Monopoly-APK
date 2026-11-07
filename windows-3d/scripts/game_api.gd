class_name QuartiersGameApi
extends Node

# The server remains authoritative for all rules and room state.
var server: String = "https://monopoly-bw6e.onrender.com"
var session: Dictionary = {}

func _request(method: int, path: String, data: Dictionary = {}) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = 75.0 if path in ["/api/health", "/api/create", "/api/join"] else 12.0
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify(data) if method == HTTPClient.METHOD_POST else ""
	var err := request.request(server.trim_suffix("/") + path, headers, method, body)
	if err != OK:
		request.queue_free()
		return {"ok": false, "error": "Connexion impossible"}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Connexion interrompue"}
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Réponse serveur invalide"}
	if response[1] < 200 or response[1] >= 300:
		return {"ok": false, "error": parsed.get("error", "Erreur serveur")}
	return {"ok": true, "data": parsed}

func health() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/api/health")

func create_room(player_name: String, solo: bool = false) -> Dictionary:
	var payload := {"name": player_name}
	if solo:
		payload["mode"] = "solo"
	var result := await _request(HTTPClient.METHOD_POST, "/api/create", payload)
	if result.ok:
		session = result.data.duplicate(true)
	return result

func join_room(player_name: String, room: String) -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, "/api/join", {"name": player_name, "code": room.strip_edges().to_upper()})
	if result.ok:
		session = result.data.duplicate(true)
	return result

func state() -> Dictionary:
	if not session.has("code") or not session.has("token"):
		return {"ok": false, "error": "Aucune partie en cours"}
	var path: String = "/api/state?code=" + str(session.code).uri_encode() + "&token=" + str(session.token).uri_encode()
	return await _request(HTTPClient.METHOD_GET, path)

func action(kind: String, fields: Dictionary = {}) -> Dictionary:
	if not session.has("code") or not session.has("token"):
		return {"ok": false, "error": "Aucune partie en cours"}
	var payload := fields.duplicate(true)
	# Identity comes from the session, never from caller-supplied fields.
	payload["code"] = session.code
	payload["token"] = session.token
	payload["type"] = kind
	return await _request(HTTPClient.METHOD_POST, "/api/action", payload)
