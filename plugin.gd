@tool
extends EditorPlugin

const AUTOLOAD_NAME = "SIN_WEBSOCKET"
const SCRIPT_PATH = "res://addons/delalex_websocket/SIN_WEBSOCKET.gd"

func _enter_tree() -> void:
	# Ничего не делаем здесь, только инициализация UI если нужна
	pass

func _exit_tree() -> void:
	# Очистка UI если была
	pass

func _enable_plugin() -> void:
	_add_singleton()

func _disable_plugin() -> void:
	_remove_singleton()

func _add_singleton() -> void:
	if not FileAccess.file_exists(SCRIPT_PATH):
		push_error("WEBSOCKET: Script not found at ", SCRIPT_PATH)
		return
	
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, SCRIPT_PATH)
		print("WEBSOCKET enabled: ", AUTOLOAD_NAME, " добавлен в автозагрузку")

func _remove_singleton() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
		print("WEBSOCKET disabled: ", AUTOLOAD_NAME, " убран из автозагрузки")
