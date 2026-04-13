extends Node

# Сигналы для подключения
# Signals for connection
signal client_connected()
signal client_disconnected()
signal data_received_string(data: String)
signal data_received_bytes(data: PackedByteArray)

const PORT = 8080
var tcp_server := TCPServer.new()
var clients: Array = []
var is_running: bool = false

func _ready():
	pass

#region UNNECESSARY LOOP ROUTINE
func _process(_delta):
	if not is_running or not tcp_server.is_listening():
		return
	
	# Принимаем новые соединения
	while tcp_server.is_connection_available():
		var stream = tcp_server.take_connection()
		if stream:
			var ws = WebSocketPeer.new()
			var err = ws.accept_stream(stream)
			if err == OK:
				clients.append(ws)
				print("WEBSOCKET >>> NEW CONNECTION, TOTAL: ", clients.size())
				emit_signal("client_connected")
	
	# Обрабатываем существующие
	var active_clients: Array = []
	for ws in clients:
		ws.poll()
		var state = ws.get_ready_state()
		
		match state:
			WebSocketPeer.STATE_OPEN:
				active_clients.append(ws)
				_process_packets(ws)
			WebSocketPeer.STATE_CLOSED:
				print("WEBSOCKET >>> DISCONNECT")
				emit_signal("client_disconnected")
			_:
				active_clients.append(ws)
	
	clients = active_clients

func _process_packets(ws: WebSocketPeer):
	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		if ws.was_string_packet():
			var msg = packet.get_string_from_utf8()
			emit_signal("data_received_string", msg)
		else:
			emit_signal("data_received_bytes", packet)
#endregion

# Запуск Вебсокет сервера
# Start Websocket server
func start_server() -> bool:
	var err = tcp_server.listen(PORT, "0.0.0.0")
	if err == OK:
		is_running = true
		print("WEBSOCKET >>> ESTABLISHED ", get_local_ip(), ":", PORT)
		return true
	else:
		push_error("WEBSOCKET >>> ERROR: ", err)
		return false

# Остановка Вебсокет сервера
# Stop Websocket server
func stop_server():
	tcp_server.stop()
	is_running = false
	for ws in clients:
		ws.close()
	clients.clear()

# Функция получения локального IP для подключения
# Get Local IP address to connect clients
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.0.") or ip.begins_with("172.16."):
			return ip
	return "127.0.0.1"

# Функция отправки текстовых данных
# Send string function
func send_text(message: String):
	for ws in clients:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(message)

# Функция для отправки байтовых данных
# Send bytes function
func send_bytes(data: PackedByteArray):
	for ws in clients:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.put_packet(data)

# Получить кол-во подключенных клиентов
# Get count of connected clients
func get_client_count() -> int:
	return clients.size()

# Есть ли вообще клиенты у сервера?
# Do server has connected clients?
func has_clients() -> bool:
	return not clients.is_empty()
