extends Node
## Stub transport Bluetooth (RFCOMM) untuk facade Net — status ALPHA.
##
## Multiplayer via Bluetooth membutuhkan plugin Android native (Godot
## Android plugin v2 / gradle) karena GDScript tidak punya akses ke
## BluetoothAdapter/BluetoothSocket. Kerangka plugin ada di:
##   android_plugins/bluetooth/ (README.md, plugin.cfg, BluetoothPlugin.kt)
##
## Roadmap Alpha:
## 1. Selesaikan plugin Kotlin (startServer/stopServer/connectTo/sendLine,
##    signal onMessage) dengan framing baris JSON dan UUID SPP tetap.
## 2. Implementasi transport ini di atas plugin: ENet-diolah jadi line
##    protocol (register/chat/state/block) sama seperti lan_backend.gd.
## 3. Uji pairing + throughput di 2 perangkat Android fisik.
##
## Semua method mengikuti interface lan_backend.gd dan aman dipanggil
## kapan pun (tanpa efek samping, selalu return ERR_UNAVAILABLE / default).


func setup(_facade: Node) -> void:
	pass


func is_active() -> bool:
	return false


func is_host() -> bool:
	return false


func my_id() -> int:
	return 1


func players() -> Array:
	return []


func current_world() -> Dictionary:
	return {}


func host_room(_max_players: int = 16) -> Error:
	return ERR_UNAVAILABLE


func join_room(_address: String) -> Error:
	return ERR_UNAVAILABLE


func leave() -> void:
	pass


func send_chat(_text: String, _emote: bool = false) -> void:
	pass


func kick(_peer_id: int) -> void:
	pass


func start_game(_world_data: Dictionary) -> void:
	pass


func rpc_block_update(_data: Dictionary, _removed: bool) -> void:
	pass


func send_player_state(_pos: Vector3, _yaw: float, _anim: int) -> void:
	pass


func list_lan_rooms(_timeout: float = 1.5) -> Array:
	return []


func set_transport(_t: int) -> Error:
	return ERR_UNAVAILABLE
