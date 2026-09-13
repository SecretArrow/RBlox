extends Node
## Backend multiplayer LAN (ENet) — di-instantiate & dipanggil facade
## scripts/autoload/net_manager.gd. Jangan panggil langsung; pakai Net.*.
##
## Port data      : 24565 (ENet, TCP-like reliable channel)
## Port discovery : 24566 (UDP broadcast "RBLOX_DISCOVER")
##
## Model: host-authoritative. Host = peer 1. Roster, kick, world start,
## dan block sync dikendalikan host. Server relay SceneMultiplayer dibiarkan
## ON sehingga broadcast RPC dari client (chat, player state) diteruskan
## server ke client lain.

const DATA_PORT := 24565
const DISCOVERY_PORT := 24566
const DISCOVER_REQ := "RBLOX_DISCOVER"
const CHAT_MAX_CHARS := 200
const NAME_MAX_CHARS := 24
const WORLD_CHUNK_SIZE := 32000
const WATCHDOG_TIMEOUT := 8.0
const KEEPALIVE_INTERVAL := 2.0
const PING_REFRESH_INTERVAL := 2.0
const REJOIN_ATTEMPTS := 3
const REJOIN_DELAY := 2.0
const TRANSPORT_LAN := 0

var _facade: Node = null
var _peer: ENetMultiplayerPeer = null
var _active: bool = false
var _connecting: bool = false
var _is_host: bool = false
var _transport: int = TRANSPORT_LAN
var _max_players: int = 16

var _players: Array = []
var _profile: Dictionary = {}
var _remote_states: Dictionary = {}
var _last_seen: Dictionary = {}
var _last_address: String = ""
var _current_world: Dictionary = {}

var _chunks: Dictionary = {}
var _chunks_total: int = 0

var _responder: PacketPeerUDP = null

var _keepalive_at: float = 0.0
var _ping_at: float = 0.0
var _rejoin_seq: int = 0
var _reconnecting: bool = false


func _ready() -> void:
	multiplayer.server_relay = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func setup(facade: Node) -> void:
	_facade = facade


func _process(_delta: float) -> void:
	if not _active:
		return
	var now := _now()
	if _is_host:
		_poll_discovery_host()
		_watchdog(now)
		if now - _ping_at >= PING_REFRESH_INTERVAL:
			_ping_at = now
			_refresh_pings_if_changed()
	elif now - _keepalive_at >= KEEPALIVE_INTERVAL:
		_keepalive_at = now
		if multiplayer.multiplayer_peer != null:
			_rpc_keepalive.rpc_id(1)


# ------------------------------------------------------------- API facade

func is_active() -> bool:
	return _active


func is_host() -> bool:
	return _is_host and _active


func my_id() -> int:
	if not _active:
		return 1
	return _my_peer_id()


func players() -> Array:
	return _players.duplicate(true)


func current_world() -> Dictionary:
	return _current_world


func host_room(max_players: int = 16) -> Error:
	_rejoin_seq += 1
	_reconnecting = false
	_leave_local(true)
	if _transport != TRANSPORT_LAN:
		return ERR_UNAVAILABLE
	var cap := clampi(max_players, 2, 16)
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(DATA_PORT, cap)
	if err != OK:
		_fail(Locale.t("error_generic"))
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_is_host = true
	_active = true
	_connecting = false
	_max_players = cap
	_profile = _make_profile()
	_players = [_self_entry()]
	_last_seen.clear()
	_remote_states.clear()
	_open_responder()
	_emit_players_changed()
	_emit_room_state()
	return OK


func join_room(address: String, from_rejoin: bool = false) -> Error:
	if not from_rejoin:
		_rejoin_seq += 1
		_reconnecting = false
	_leave_local(true)
	if _transport != TRANSPORT_LAN:
		return ERR_UNAVAILABLE
	var addr := address.strip_edges()
	if addr == "":
		_fail(Locale.t("error_generic"))
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(addr, DATA_PORT)
	if err != OK:
		_fail(Locale.t("error_generic"))
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_is_host = false
	_active = false
	_connecting = true
	_max_players = 16
	_profile = _make_profile()
	_players = []
	_remote_states.clear()
	_last_address = addr
	return OK


func leave() -> void:
	_rejoin_seq += 1
	_reconnecting = false
	_leave_local(true)
	_emit_room_state()


func send_chat(text: String, emote: bool = false) -> void:
	if not _active:
		return
	var msg := text.strip_edges()
	if msg == "":
		return
	if msg.length() > CHAT_MAX_CHARS:
		msg = msg.substr(0, CHAT_MAX_CHARS)
	# Parental lock: teks diblokir sisi pengirim juga; emote tetap boleh.
	if not emote and not Settings.chat_enabled():
		return
	_rpc_chat.rpc(msg, emote)


func kick(peer_id: int) -> void:
	if not (_active and _is_host):
		return
	if peer_id == _my_peer_id():
		return
	_do_kick(peer_id)


func start_game(world_data: Dictionary) -> void:
	if not (_active and _is_host):
		return
	if world_data.is_empty():
		return
	_current_world = world_data
	var text := JSON.stringify(world_data)
	var bytes := text.to_utf8_buffer()
	if bytes.is_empty():
		return
	var total := maxi(1, int(ceil(float(bytes.size()) / float(WORLD_CHUNK_SIZE))))
	for pid in multiplayer.get_peers():
		for i in range(total):
			var from := i * WORLD_CHUNK_SIZE
			var to := mini(from + WORLD_CHUNK_SIZE, bytes.size())
			_rpc_world_chunk.rpc_id(pid, i, total, bytes.slice(from, to))


func rpc_block_update(data: Dictionary, removed: bool) -> void:
	if not (_active and _is_host):
		return
	_rpc_block_update_net.rpc(data, removed)


func send_player_state(pos: Vector3, yaw: float, anim: int) -> void:
	if not _active:
		return
	_rpc_player_state.rpc(pos, yaw, anim)


func list_lan_rooms(timeout: float = 1.5) -> Array:
	var out: Array = []
	var udp := PacketPeerUDP.new()
	if udp.bind(0) != OK:
		udp.close()
		return out
	udp.set_broadcast_enabled(true)
	var start_ms := Time.get_ticks_msec()
	var timeout_ms := int(timeout * 1000.0)
	var last_send := -1000
	while Time.get_ticks_msec() - start_ms < timeout_ms:
		var now_ms := Time.get_ticks_msec()
		if now_ms - last_send >= 300:
			udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			udp.put_packet(DISCOVER_REQ.to_utf8_buffer())
			last_send = now_ms
		while udp.get_available_packet_count() > 0:
			var raw := udp.get_packet()
			var rip := udp.get_packet_ip()
			var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
			if typeof(parsed) != TYPE_DICTIONARY or rip == "" or _is_local_ip(rip):
				continue
			if _rooms_has(out, rip):
				continue
			var d: Dictionary = parsed
			out.append({
				"name": String(d.get("name", "Room")),
				"ip": rip,
				"players": int(d.get("players", 1)),
				"max": int(d.get("max", 16)),
			})
		OS.delay_msec(50)
	udp.close()
	return out


func set_transport(t: int) -> Error:
	if t == TRANSPORT_LAN:
		_transport = TRANSPORT_LAN
		return OK
	# BT / WiFi Direct menyusul via plugin Android (Alpha).
	return ERR_UNAVAILABLE


func get_remote_states() -> Dictionary:
	## Ekstra di luar kontrak facade: posisi terakhir pemain lain.
	## Dipakai modul game via Net._call("get_remote_states") bila perlu.
	var out: Dictionary = {}
	for k in _remote_states.keys():
		var v: Dictionary = _remote_states[k]
		out[k] = {
			"pos": v.get("pos", Vector3.ZERO),
			"yaw": float(v.get("yaw", 0.0)),
			"anim": int(v.get("anim", 0)),
			"t": float(v.get("t", 0.0)),
		}
	return out


# ------------------------------------------------------------------- RPC

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_player(info: Dictionary) -> void:
	if not _is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var pname := _sanitize_name(String(info.get("name", "")))
	var avatar: Dictionary = {}
	if typeof(info.get("avatar", {})) == TYPE_DICTIONARY:
		avatar = info["avatar"]
	_upsert_player(sender, pname, avatar)
	_last_seen[sender] = _now()
	_broadcast_roster()


@rpc("authority", "call_remote", "reliable")
func _rpc_player_list(list: Array) -> void:
	if _is_host:
		return
	_players = []
	for item in list:
		if typeof(item) == TYPE_DICTIONARY:
			_players.append(item)
	_emit_players_changed()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_player_state(pos: Vector3, yaw: float, anim: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or sender == _my_peer_id():
		return
	var now := _now()
	_remote_states[sender] = {"pos": pos, "yaw": yaw, "anim": anim, "t": now}
	if _is_host:
		_last_seen[sender] = now


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_keepalive() -> void:
	if not _is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender > 0:
		_last_seen[sender] = _now()


@rpc("any_peer", "call_local", "reliable")
func _rpc_chat(text: String, is_emote: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _is_host and sender > 0:
		_last_seen[sender] = _now()
	var sender_name := _resolve_name(sender)
	if _facade != null:
		_facade.chat_received.emit(sender_name, text, is_emote)


@rpc("authority", "call_local", "reliable")
func _rpc_block_update_net(data: Dictionary, removed: bool) -> void:
	if _facade != null:
		_facade.world_block_changed.emit(data, removed)


@rpc("authority", "call_remote", "reliable")
func _rpc_world_chunk(idx: int, total: int, part: PackedByteArray) -> void:
	if _is_host:
		return
	if idx == 0:
		_chunks.clear()
		_chunks_total = total
	if total != _chunks_total or total < 1:
		return
	_chunks[idx] = part
	if _chunks.size() < _chunks_total:
		return
	var bytes := PackedByteArray()
	for i in range(_chunks_total):
		if not _chunks.has(i):
			return
		bytes.append_array(_chunks[i])
	_chunks.clear()
	_chunks_total = 0
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_current_world = parsed
	if _facade != null:
		_facade.game_started.emit(_current_world)


@rpc("authority", "call_remote", "reliable")
func _rpc_kick_notify(reason: String) -> void:
	if _is_host:
		return
	if _facade != null:
		_facade.kicked.emit(reason)
	_leave_local(true)
	_emit_room_state()


# --------------------------------------------------- sinyal multiplayer

func _on_peer_connected(_id: int) -> void:
	# Host menunggu _rpc_register_player dari peer; roster diupdate saat itu.
	pass


func _on_peer_disconnected(id: int) -> void:
	_last_seen.erase(id)
	_remote_states.erase(id)
	if _is_host:
		if _remove_player(id):
			_broadcast_roster()
	elif id == 1:
		_server_lost()


func _on_connected_to_server() -> void:
	_active = true
	_connecting = false
	_rpc_register_player.rpc_id(1, _profile)
	_emit_room_state()


func _on_connection_failed() -> void:
	if _reconnecting:
		# Saat auto-rejoin: jangan toast / bersih-bersih, loop rejoin yang
		# mengatur percobaan berikutnya.
		_connecting = false
		return
	var was_connecting := _connecting
	_leave_local(false)
	_emit_room_state()
	if was_connecting and _facade != null:
		_facade.connection_failed.emit(Locale.t("error_generic"))


func _on_server_disconnected() -> void:
	if not _active:
		return
	_server_lost()


# ------------------------------------------------------------- internal

func _server_lost() -> void:
	var was_active := _active
	var addr := _last_address
	_leave_local(false)
	_emit_room_state()
	if not was_active or addr == "":
		return
	if _facade != null:
		_facade.connection_lost.emit()
	_start_rejoin()


func _start_rejoin() -> void:
	_reconnecting = true
	var seq := _rejoin_seq
	var addr := _last_address
	for _i in range(REJOIN_ATTEMPTS):
		await get_tree().create_timer(REJOIN_DELAY).timeout
		if seq != _rejoin_seq or _active or addr == "":
			_reconnecting = false
			return
		var err: Error = join_room(addr, true)
		if err != OK:
			continue
		# Tunggu hasil koneksi (connected_to_server / connection_failed).
		var waited := 0.0
		while _connecting and waited < 5.0 and seq == _rejoin_seq:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
		if _active:
			_reconnecting = false
			return
	_reconnecting = false
	_fail(Locale.t("error_generic"))


func _do_kick(peer_id: int) -> void:
	_rpc_kick_notify.rpc_id(peer_id, Locale.t("kicked_by_host"))
	await get_tree().create_timer(0.3).timeout
	if _is_host and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _leave_local(clear_address: bool) -> void:
	_active = false
	_connecting = false
	_is_host = false
	_chunks.clear()
	_chunks_total = 0
	_remote_states.clear()
	_last_seen.clear()
	_players = []
	_close_responder()
	var mp := multiplayer.multiplayer_peer
	if mp != null:
		multiplayer.multiplayer_peer = null
		mp.close()
	_peer = null
	if clear_address:
		_last_address = ""
		_profile = {}
		_current_world = {}


func _watchdog(now: float) -> void:
	for pid in _last_seen.keys():
		if now - float(_last_seen[pid]) > WATCHDOG_TIMEOUT:
			_last_seen.erase(pid)
			_remote_states.erase(pid)
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.disconnect_peer(int(pid))


func _poll_discovery_host() -> void:
	if _responder == null:
		return
	while _responder.get_available_packet_count() > 0:
		var raw := _responder.get_packet()
		var rip := _responder.get_packet_ip()
		var rport := _responder.get_packet_port()
		if raw.get_string_from_utf8().strip_edges() != DISCOVER_REQ:
			continue
		if rip == "" or rport <= 0:
			continue
		var reply := {
			"name": GameState.player_name,
			"players": _players.size(),
			"max": _max_players,
			"ip": rip,
		}
		_responder.set_send_address(rip, rport)
		_responder.put_packet(JSON.stringify(reply).to_utf8_buffer())


func _open_responder() -> void:
	_close_responder()
	var udp := PacketPeerUDP.new()
	if udp.bind(DISCOVERY_PORT) != OK:
		udp.close()
		return
	udp.set_broadcast_enabled(true)
	_responder = udp


func _close_responder() -> void:
	if _responder != null:
		_responder.close()
		_responder = null


func _refresh_pings_if_changed() -> void:
	var before := JSON.stringify(_players)
	_refresh_pings()
	if JSON.stringify(_players) != before:
		_rpc_player_list.rpc(_players)
		_emit_players_changed()


func _refresh_pings() -> void:
	if not _is_host or _peer == null:
		return
	var my := _my_peer_id()
	for p in _players:
		var pid := int(p.get("id", 0))
		if pid == my:
			p["ping"] = 0
			continue
		var enet_peer: ENetPacketPeer = _peer.get_peer(pid)
		if enet_peer != null:
			p["ping"] = int(enet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func _broadcast_roster() -> void:
	if not _is_host:
		return
	_refresh_pings()
	_rpc_player_list.rpc(_players)
	_emit_players_changed()


func _upsert_player(pid: int, pname: String, avatar: Dictionary) -> void:
	for p in _players:
		if int(p.get("id", 0)) == pid:
			p["name"] = pname
			p["avatar"] = avatar
			return
	_players.append({"id": pid, "name": pname, "avatar": avatar, "ping": 0})


func _remove_player(pid: int) -> bool:
	for i in range(_players.size()):
		if int(_players[i].get("id", 0)) == pid:
			_players.remove_at(i)
			return true
	return false


func _resolve_name(sender: int) -> String:
	if sender <= 0 or sender == _my_peer_id():
		return _my_name()
	for p in _players:
		if int(p.get("id", 0)) == sender:
			return String(p.get("name", "Player"))
	return "Player%d" % sender


func _my_name() -> String:
	var n := String(_profile.get("name", ""))
	if n == "":
		n = GameState.player_name
	if n == "":
		n = "Player"
	return n


func _make_profile() -> Dictionary:
	return {
		"name": _sanitize_name(GameState.player_name),
		"avatar": GameState.avatar_config.duplicate(true),
	}


func _self_entry() -> Dictionary:
	return {
		"id": _my_peer_id(),
		"name": String(_profile.get("name", "Player")),
		"avatar": _profile.get("avatar", {}),
		"ping": 0,
	}


func _my_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


func _sanitize_name(raw: String) -> String:
	var n := raw.strip_edges()
	if n.length() > NAME_MAX_CHARS:
		n = n.substr(0, NAME_MAX_CHARS)
	if n == "":
		n = "Player"
	return n


func _rooms_has(out: Array, ip: String) -> bool:
	for r in out:
		if String(r.get("ip", "")) == ip:
			return true
	return false


func _is_local_ip(ip: String) -> bool:
	if ip == "127.0.0.1" or ip == "255.255.255.255" or ip == "0.0.0.0":
		return true
	for a in IP.get_local_addresses():
		if String(a) == ip:
			return true
	return false


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _fail(reason: String) -> void:
	if _facade != null:
		_facade.connection_failed.emit(reason)


func _emit_players_changed() -> void:
	if _facade != null:
		_facade.player_list_changed.emit(players())


func _emit_room_state() -> void:
	if _facade != null:
		_facade.room_state_changed.emit()
