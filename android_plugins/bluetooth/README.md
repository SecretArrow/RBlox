# RBlox Bluetooth Plugin (ALPHA — kerangka)

Plugin Android (Godot Android plugin v2) untuk transport multiplayer
Bluetooth RFCOMM pada RBlox. Status saat ini: **kerangka / skeleton**.
File `BluetoothPlugin.kt` belum dikompilasi di CI dan belum dipasang ke
build Godot; ia mendefinisikan kontrak API yang akan diimplementasikan.

## Mengapa butuh plugin

GDScript tidak punya akses ke `BluetoothAdapter` / `BluetoothSocket`.
Android mengharuskan runtime permission `BLUETOOTH_CONNECT` (API 31+)
dan `BLUETOOTH_SCAN`, plus alur pairing yang hanya bisa diakses dari
sisi Java/Kotlin. Maka transport BT berdiri di atas plugin Android,
bukan ENet.

## Desain teknis (rencana Alpha)

- Protokol: RFCOMM (SPP) dengan UUID layanan tetap:
  `fa87c0d0-afac-11de-8a39-0800200c9a66`.
- Host: `listenUsingRfcommWithServiceRecord` pada thread worker,
  menerima beberapa client (max 16) dan menyimpan socket per client.
- Client: `createRfcommSocketToServiceRecord` ke device terpilih,
  retry 3x bila gagal (device busy).
- Framing: pesan = satu baris JSON diakhiri `\n` (menghindari
  fragmentasi paket; pembacaan per-buffer lalu split newline).
- Threading: semua I/O socket di thread terpisah; emit ke Godot lewat
  signal `on_message` (sudah dideklarasikan di skeleton).
- Payload baris JSON mengikuti protokol RPC backend LAN (register /
  player list / chat / player state / world chunk / block update) —
  lihat `docs/MULTIPLAYER.md`.

## Permission

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

`BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN` harus diminta runtime sebelum
memakai fitur apa pun (request dari plugin, hasil via signal).

## Integrasi Godot Android plugin v2 (gradle)

1. Buat modul gradle (mis. `android_plugins/bluetooth/`) berisi
   `build.gradle` dengan dependency `org.godotengine:godot:4.4.0`
   (provided) dan kompilasi `BluetoothPlugin.kt` menjadi AAR.
2. AAR hasil build diletakkan di folder plugin ini dan didaftarkan lewat
   file metadata plugin v2 (`*.gdap` / entry `Plugins` pada preset export
   dengan build gradle diaktifkan).
3. Di GDScript, plugin diakses via singleton engine:

```gdscript
if Engine.has_singleton("RBloxBluetooth"):
    var bt := Engine.get_singleton("RBloxBluetooth")
    bt.on_message.connect(_on_bt_line)
    bt.startServer()
```

4. Sisi GDScript (`scripts/multiplayer/transport_bt.gd`) memetakan baris
   JSON dari `on_message` ke event facade yang sama seperti
   `lan_backend.gd` (chat_received, player_list_changed, dst).

## Checklist status

- [x] Kerangka API Kotlin (`BluetoothPlugin.kt`)
- [x] Metadata plugin (`plugin.cfg`)
- [ ] build.gradle + AAR terkompilasi
- [ ] Runtime permission flow
- [ ] Framing + reconnect
- [ ] Uji lapangan 2 device
