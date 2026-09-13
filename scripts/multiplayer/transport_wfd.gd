extends Node
## Stub transport WiFi Direct (Wi-Fi P2P) untuk facade Net — status ALPHA.
##
## WiFi Direct membutuhkan plugin Android native (Godot Android plugin v2 /
## gradle) karena butuh WifiP2pManager, penerimaan grup (group owner = host),
## dan socket stream antar perangkat. Setelah plugin siap, transport ini
## bisa memakai jalur TCP sederhana atau menjembatani ENet di atas socket
## lokal (LocalServerSocket) seperti pola plugin BT.
##
## Roadmap Alpha:
## 1. Plugin Kotlin: discover peers, request group, ambil group owner address.
## 2. Host = group owner; client konek via socket stream ke owner.
## 3. Gunakan kembali struktur RPC/protokol lan_backend.gd (lihat
##    docs/MULTIPLAYER.md).
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
