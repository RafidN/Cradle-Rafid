class_name NetTransport
extends Node
## Sends and receives raw byte packets over the active MultiplayerPeer. When a
## NetConditioner is set, traffic in both directions passes through it so latency,
## jitter and packet loss can be simulated.

signal packet_received(peer_id: int, bytes: PackedByteArray)

var conditioner: NetConditioner


func _ready() -> void:
	(multiplayer as SceneMultiplayer).peer_packet.connect(_on_peer_packet)


func _process(_delta: float) -> void:
	if conditioner:
		conditioner.flush()


func send(peer_id: int, bytes: PackedByteArray, reliable: bool) -> void:
	if conditioner:
		conditioner.schedule(NetConditioner.OUTGOING, reliable, _send_now.bind(peer_id, bytes, reliable))
	else:
		_send_now(peer_id, bytes, reliable)


func _send_now(peer_id: int, bytes: PackedByteArray, reliable: bool) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	(multiplayer as SceneMultiplayer).send_bytes(bytes, peer_id, mode)


func _on_peer_packet(peer_id: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	if conditioner:
		var reliable := Protocol.is_reliable(bytes[0])
		conditioner.schedule(NetConditioner.INCOMING, reliable, packet_received.emit.bind(peer_id, bytes))
	else:
		packet_received.emit(peer_id, bytes)
