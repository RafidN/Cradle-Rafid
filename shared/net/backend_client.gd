class_name BackendClient
extends Node
## JSON-over-HTTP calls to the backend service (backend/). The game client uses it for
## accounts, characters and joining; the game server uses it to redeem join tickets,
## save progress and send heartbeats.

const TIMEOUT_SECONDS := 10.0

var base_url := "http://127.0.0.1:8080"
## Player session token (game client), sent as a bearer token.
var token := ""
## Shared secret (game server), sent to /internal endpoints.
var server_secret := ""


## Returns {ok: bool, status: int, data: Dictionary, error: String}.
func request_json(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	if not server_secret.is_empty():
		headers.append("X-Server-Secret: %s" % server_secret)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url.trim_suffix("/") + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": {}, "error": "Couldn't send request: %s" % error_string(err)}
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "data": {}, "error": "Couldn't reach the server at %s" % base_url}
	var status: int = response[1]
	var parsed = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var ok := status >= 200 and status < 300
	return {"ok": ok, "status": status, "data": data, "error": "" if ok else String(data.get("error", "HTTP %d" % status))}
