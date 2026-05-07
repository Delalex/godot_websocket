extends Node

# ============================================================================
#
#
#      ▒█░░▒█ ▒█▀▀▀ ▒█▀▀█ ▒█▀▀▀█ ▒█▀▀▀█ ▒█▀▀█ ▒█░▄▀ ▒█▀▀▀ ▀▀█▀▀ 
#      ▒█▒█▒█ ▒█▀▀▀ ▒█▀▀▄ ░▀▀▀▄▄ ▒█░░▒█ ▒█░░░ ▒█▀▄░ ▒█▀▀▀ ░▒█░░ 
#      ▒█▄▀▄█ ▒█▄▄▄ ▒█▄▄█ ▒█▄▄▄█ ▒█▄▄▄█ ▒█▄▄█ ▒█░▒█ ▒█▄▄▄ ░▒█░░
#
#                         MADE BY DELALEX
#                          СДЕЛАЛ DELALEX
# ============================================================================

# Порт для подключения
const PORT = 8080

# Сигналы
signal client_connected(client_id: String, ws: WebSocketPeer, meta: Dictionary)
signal client_disconnected(client_id: String, reason: String)
signal data_received(client_id: String, ws: WebSocketPeer, data, is_binary: bool)
signal channel_message(channel: String, client_id: String, data)
signal client_subscribed(client_id: String, channel: String)
signal client_unsubscribed(client_id: String, channel: String)

var tcp_server := TCPServer.new()
var is_running: bool = false

# =========================
# INFORMATION
# =========================

var clients := {}   # ws -> {id, meta, connected_at}
var channels := {}  # channel -> [ws]


#region MAIN LOOP
func _process(_delta):
	if not is_running or not tcp_server.is_listening():
		return

	# новые подключения
	while tcp_server.is_connection_available():
		var stream = tcp_server.take_connection()
		if stream:
			var ws = WebSocketPeer.new()
			var err = ws.accept_stream(stream)

			if err == OK:
				var client_id = str(Time.get_ticks_msec())

				clients[ws] = {
					"id": client_id,
					"connected_at": Time.get_ticks_msec(),
					"meta": {}
				}

				print("NEW CLIENT:", client_id)
				emit_signal("client_connected", client_id, ws, clients[ws]["meta"])

	# обработка клиентов
	for ws in clients.keys().duplicate():
		ws.poll()

		var state = ws.get_ready_state()

		if state == WebSocketPeer.STATE_OPEN:
			_process_packets(ws)

		elif state == WebSocketPeer.STATE_CLOSED:
			remove_client(ws, "closed")


func _process_packets(ws):
	if not clients.has(ws):
		return

	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		var is_string = ws.was_string_packet()
		var data = packet.get_string_from_utf8() if is_string else packet

		if not clients.has(ws):
			return

		var ctx = clients[ws]
		emit_signal("data_received", ctx["id"], ws, data, not is_string)
#endregion

#region CLIENT MANAGEMENT
func remove_client(ws: WebSocketPeer, reason: String = "unknown"):
	if not clients.has(ws):
		return

	var client_id = clients[ws]["id"]

	# очистка каналов (важно через централизованный метод)
	for ch in get_client_channels(ws).duplicate():
		_unsubscribe(ws, ch)

	clients.erase(ws)
	ws.close()
	ws.poll()

	print("CLIENT REMOVED:", client_id, "reason:", reason)
	emit_signal("client_disconnected", client_id, reason)


func get_all_clients() -> Array:
	var result := []
	for ws in clients:
		result.append(clients[ws]["id"])
	return result


func get_ws_by_id(client_id: String) -> WebSocketPeer:
	for ws in clients:
		if clients[ws]["id"] == client_id:
			return ws
	return null


func get_client_channels(ws: WebSocketPeer) -> Array:
	var result := []
	for ch in channels:
		if ws in channels[ch]:
			result.append(ch)
	return result
#endregion

#region CHANNEL CORE (SOURCE OF TRUTH)
func _subscribe(ws: WebSocketPeer, channel: String):
	if not clients.has(ws):
		return

	if not channels.has(channel):
		channels[channel] = []

	if ws not in channels[channel]:
		channels[channel].append(ws)

	var id = clients[ws]["id"]
	emit_signal("client_subscribed", id, channel)


func _unsubscribe(ws: WebSocketPeer, channel: String):
	if not clients.has(ws):
		return

	if channels.has(channel):
		channels[channel].erase(ws)

		if channels[channel].is_empty():
			channels.erase(channel)

	var id = clients[ws]["id"]
	emit_signal("client_unsubscribed", id, channel)


func channel_exists(channel: String) -> bool:
	return channels.has(channel)


func channel_has_client(client_id: String, channel: String) -> bool:
	var ws = get_ws_by_id(client_id)
	if ws == null:
		return false
	return ws in channels.get(channel, [])


func channels_of_client(client_id: String) -> Array:
	var ws = get_ws_by_id(client_id)
	if ws == null:
		return []
	return get_client_channels(ws)
#endregion

#region PUBLIC CHANNEL API
func channel_peer_subscribe(ws: WebSocketPeer, channel: String):
	_subscribe(ws, channel)


func channel_peer_unsubscribe(ws: WebSocketPeer, channel: String):
	_unsubscribe(ws, channel)


func channel_send_message(channel: String, ws_sender: WebSocketPeer, data):
	if channel == "" or not clients.has(ws_sender):
		return

	var sender_id = clients[ws_sender]["id"]
	var msg = data if data is String else JSON.stringify(data)

	if not channels.has(channel):
		return

	var has_receivers := false

	for ws in channels[channel]:
		has_receivers = true
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(msg)

	if has_receivers:
		emit_signal("channel_message", channel, sender_id, data)
#endregion

#region SERVER CONTROL
func start_server() -> bool:
	var err = tcp_server.listen(PORT, "0.0.0.0")

	if err == OK:
		is_running = true
		print("WEBSOCKET >>> SERVER STARTED:", get_local_ip(), PORT)
		return true

	push_error(err)
	return false


func stop_server():
	tcp_server.stop()
	is_running = false

	for ws in clients.keys().duplicate():
		ws.close()

	clients.clear()
	channels.clear()

	print("SERVER STOPPED")


func restart():
	stop_server()
	await get_tree().create_timer(1.0).timeout
	start_server()
#endregion

#region UTILITIES
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.0.") or ip.begins_with("172.16."):
			return ip
	return "127.0.0.1"


func get_client_count() -> int:
	return clients.size()


func has_clients() -> bool:
	return not clients.is_empty()
#endregion

#region BROADCAST
func send_text(message: String):
	for ws in clients:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(message)


func send_bytes(data: PackedByteArray):
	for ws in clients:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.put_packet(data)
#endregion

# SHORTCUT API

func send(channel, data):
	channel_send_message(channel, null, data)

func broadcast(data):
	send_text(data if data is String else JSON.stringify(data))
