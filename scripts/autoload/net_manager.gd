extends Node
## Autoload: Net — facade multiplayer. Implementasi LAN ada di
## scripts/multiplayer/lan_backend.gd (dibuat oleh modul multiplayer).
## Jika backend belum ada, semua method aman (tidak crash, return default).

signal room_state_changed
signal player_list_changed(players: Array)
signal chat_received(sender: String, text: String, is_emote: bool)
signal kicked(reason: String)
signal connection_failed(reason: String)
signal game_started(world_data: Dictionary)
signal world_block_changed(data: Dictionary, removed: bool)
signal connection_lost

const BACKEND_PATH := "res://scripts/multiplayer/lan_backend.gd"
const TRANSPORT_LAN := 0
const TRANSPORT_BT := 1
const TRANSPORT_WFD := 2

var _backend: Node = null


func _ready() -> void:
	if ResourceLoader.exists(BACKEND_PATH):
		var script: Variant = load(BACKEND_PATH)
		if script != null:
			_backend = script.new()
			_backend.name = "LanBackend"
			add_child(_backend)
			if _backend.has_method("setup"):
				_backend.setup(self)


func _call(method: String, args: Array = [], default: Variant = null) -> Variant:
	if _backend != null and _backend.has_method(method):
		return _backend.callv(method, args)
	return default


func is_active() -> bool:
	return bool(_call("is_active", [], false))


func is_host() -> bool:
	return bool(_call("is_host", [], false))


func my_id() -> int:
	return int(_call("my_id", [], 1))


func players() -> Array:
	var r: Variant = _call("players", [], [])
	return r if r is Array else []


func current_world() -> Dictionary:
	var r: Variant = _call("current_world", [], {})
	return r if r is Dictionary else {}


func host_room(max_players: int = 16) -> Error:
	return _call("host_room", [max_players], ERR_UNAVAILABLE) as Error


func join_room(address: String) -> Error:
	return _call("join_room", [address], ERR_UNAVAILABLE) as Error


func leave() -> void:
	_call("leave")


func send_chat(text: String, emote: bool = false) -> void:
	_call("send_chat", [text, emote])


func kick(peer_id: int) -> void:
	_call("kick", [peer_id])


func start_game(world_data: Dictionary) -> void:
	_call("start_game", [world_data])


func rpc_block_update(data: Dictionary, removed: bool) -> void:
	_call("rpc_block_update", [data, removed])


func send_player_state(pos: Vector3, yaw: float, anim: int) -> void:
	_call("send_player_state", [pos, yaw, anim])


func list_lan_rooms(timeout: float = 1.5) -> Array:
	var r: Variant = _call("list_lan_rooms", [timeout], [])
	return r if r is Array else []


func set_transport(transport: int) -> Error:
	return _call("set_transport", [transport], ERR_UNAVAILABLE) as Error
