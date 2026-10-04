class_name NetTransport
extends Node
## Sends and receives raw byte packets over the active MultiplayerPeer. When a
## NetConditioner is set, traffic in both directions passes through it so latency,
## jitter and packet loss can be simulated.

signal packet_received(peer_id: int, bytes: PackedByteArray)

var conditioner: NetConditioner
## Payload bytes sent and received, for stats.
var bytes_sent := 0
var bytes_received := 0


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
	# A peer that vanished without disconnecting lingers until ENet times it out; sending
	# to it in the meantime only produces errors.
	if peer is ENetMultiplayerPeer and peer_id > 0:
		var enet_peer := (peer as ENetMultiplayerPeer).get_peer(peer_id)
		if enet_peer == null or enet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	(multiplayer as SceneMultiplayer).send_bytes(bytes, peer_id, mode)
	bytes_sent += bytes.size()


func _on_peer_packet(peer_id: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	bytes_received += bytes.size()
	if conditioner:
		var reliable := Protocol.is_reliable(bytes[0])
		conditioner.schedule(NetConditioner.INCOMING, reliable, packet_received.emit.bind(peer_id, bytes))
	else:
		packet_received.emit(peer_id, bytes)
