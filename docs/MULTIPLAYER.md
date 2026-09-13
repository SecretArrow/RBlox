# Multiplayer RBlox — Arsitektur & Protokol

Status: MVP LAN (Alpha). Transport lain (Bluetooth, WiFi Direct) menyusul
via plugin Android.

## Ringkasan

- Model: **host-authoritative client-server**. Host = peer ID `1`.
  Client tidak saling mengubah dunia; semua perubahan dunia disiarkan host.
- Implementasi: `scripts/multiplayer/lan_backend.gd` (backend), dipanggil
  hanya lewat facade autoload `Net` (`scripts/autoload/net_manager.gd`).
  UI: `scenes/lobby.tscn` (lobby), `scenes/chat_overlay.tscn` (chat).
- Transport: ENet (`ENetMultiplayerPeer`) port **24565** untuk data.
  `SceneMultiplayer.server_relay` tetap ON sehingga broadcast RPC dari
  client (chat, player state) diteruskan server ke client lain.
- Identity: client mengirim profile (nama + avatar JSON) saat tersambung;
  host menyusun roster dan menyiarkannya ke semua client.
- Watchdog: host memantau `last_seen` tiap peer (refresh oleh player state,
  chat, register, keepalive tiap 2 detik). Peer tanpa kabar > 8 detik
  dianggap hilang dan diputus.
- Reconnect: bila host menghilang, client menerima `Net.connection_lost`
  lalu mencoba join ulang ke alamat sama 3 kali (interval 2 detik) dengan
  nama/avatar dari `GameState`. Rejoin dibatalkan bila user keluar manual
  atau membuat/menyambung room lain.

## Port & Discovery

| Kanal | Port | Protokol | Isi |
|---|---|---|---|
| Data (ENet) | 24565 | TCP-like reliable/unreliable channel | RPC & sync |
| Discovery | 24566 | UDP broadcast | `"RBLOX_DISCOVER"` -> reply JSON |

Discovery:

- Host: `PacketPeerUDP.bind(24566)`; menerima `RBLOX_DISCOVER`, membalas
  JSON `{name: GameState.player_name, players: n, max: 16, ip: <ip>}` ke
  pengirim.
- Client: `Net.list_lan_rooms(timeout)` bersifat **sinkron** (tanpa await):
  bind socket acak, `set_broadcast_enabled(true)`, kirim discover ke
  `255.255.255.255:24566` tiap 300 ms, kumpulkan reply unik (IP sendiri
  diabaikan) sampai timeout habis, lalu socket ditutup.
- Catatan Android: beberapa perangkat/ROM butuh multicast/broadcast lock
  agar reply broadcast diterima; fallback selalu tersedia lewat input IP
  manual di lobby.

## Tabel RPC (SceneMultiplayer, channel 0)

| Nama fungsi | Mode @rpc | Transfer | Payload | Arah |
|---|---|---|---|---|
| `_rpc_register_player(info)` | any_peer, call_remote | reliable | `{name, avatar}` | client -> host |
| `_rpc_player_list(list)` | authority, call_remote | reliable | Array `{id,name,avatar,ping}` | host -> semua client |
| `_rpc_player_state(pos, yaw, anim)` | any_peer, call_remote | unreliable_ordered | posisi/orientasi/anim pemain | semua -> semua (relay server) |
| `_rpc_keepalive()` | any_peer, call_remote | unreliable | (kosong) | client -> host |
| `_rpc_chat(text, is_emote)` | any_peer, call_local | reliable | teks chat / emote | pengirim -> semua (termasuk diri) |
| `_rpc_kick_notify(reason)` | authority, call_remote | reliable | alasan (string) | host -> satu client |
| `_rpc_world_chunk(idx, total, part)` | authority, call_remote | reliable | potongan `PackedByteArray` 32000 byte | host -> satu client |
| `_rpc_block_update_net(data, removed)` | authority, call_local | reliable | `{...}` deskripsi blok + flag hapus | host -> semua + lokal |

Catatan protokol:

- `start_game`: host menyimpan world (`current_world`) lalu mengirim JSON
  world sebagai rangkaian chunk 32000 byte (`_rpc_world_chunk`). Client
  menyusun ulang, `JSON.parse_string`, menyimpan, dan memancarkan
  `Net.game_started(world)`. Host sendiri langsung pindah scene dari lobby.
- `rpc_block_update(data, removed)`: hanya host yang boleh memanggil
  (authority). Handler memancarkan `Net.world_block_changed` di semua
  pihak (host juga, lewat `call_local`).
- Chat: dibatasi 200 karakter, di-trim, kosong ditolak. Parental lock
  diperiksa dua sisi: overlay menyembunyikan input teks bila
  `Settings.chat_enabled()` false, dan backend menolak teks (emote tetap
  boleh) sebelum dikirim.
- Kick: host mengirim `_rpc_kick_notify` (reliable) lalu menunggu 0.3 detik
  sebelum `disconnect_peer` agar notifikasi sempat sampai. Client yang
  dikick memancarkan `Net.kicked(reason)` dan membersihkan sesi tanpa
  auto-rejoin.

## Alur Lobby

1. Host: isi nama -> "Buat Room" -> `Net.host_room(16)` -> panel room
   (IP lokal dari `IP.get_local_addresses()` yang berawalan `192.168.` /
   `10.` / `172.`, daftar pemain + ping + tombol Keluarkan, pilihan dunia).
2. Pilihan dunia: file `.myworld` dari `Saves.list_worlds()`, plus katalog
   template bila `res://scripts/world/templates.gd` ada (`Templates.catalog()`,
   dibangun via `Templates.build_world_json(id)`), plus dunia kosong bawaan.
3. "Mulai Game": `Net.start_game(json)` -> host set `GameState.current_world`
   -> pindah ke `res://scenes/game.tscn`. Client menerima `game_started`
   lalu melakukan hal sama.
4. Client: "Cari Room" (`Net.list_lan_rooms`) atau input IP manual ->
   `Net.join_room(ip)` -> roster & ping mengalir dari host.
5. Achievement: host sukses -> `GameState.unlock_achievement("host_mp")`;
   join sukses -> `GameState.unlock_achievement("join_mp")`.

## Akses data tambahan untuk modul game

Facade Net tidak punya signal posisi pemain; backend menyimpan posisi
terakhir pemain lain dan bisa dibaca via `Net._call("get_remote_states")`
yang mengembalikan `{peer_id: {pos: Vector3, yaw: float, anim: int, t: float}}`.

## Batasan MVP (rencana menyusul)

- Tidak ada migrasi host (host keluar = sesi berakhir).
- Sinkronisasi fisika dinamis penuh belum ada; yang disinkron: blok dunia,
  chat, state pemain (posisi/yaw/anim, unreliable).
- Late joiner setelah game mulai belum menerima world.
- Satu world transfer pada satu waktu (chunk tidak multiplex per sesi).

## Transport BT / WiFi Direct (Alpha)

`scripts/multiplayer/transport_bt.gd` dan `transport_wfd.gd` adalah stub
dengan interface identik (semua `ERR_UNAVAILABLE`). `Net.set_transport(0)`
(LAN/WiFi) selalu berhasil; `1` (BT) dan `2` (WFD) ditolak sampai plugin
Android siap. Kerangka plugin Bluetooth (RFCOMM/SPP, pairing, framing baris
JSON, integrasi Android plugin v2 via gradle) ada di
`android_plugins/bluetooth/` (README.md, plugin.cfg, BluetoothPlugin.kt).
