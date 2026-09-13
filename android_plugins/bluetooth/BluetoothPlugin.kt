// RBlox Bluetooth Plugin — SKELETON (Alpha).
//
// KERANGKA SAJA: file ini BELUM dikompilasi di CI dan belum menjadi AAR
// yang dipasang ke build Godot Android. Ia mendefinisikan kontrak API
// yang dipakai scripts/multiplayer/transport_bt.gd setelah plugin siap.
//
// Rencana build: modul gradle terpisah dengan dependency
// `org.godotengine:godot:4.4.0` (provided), dikompilasi menjadi AAR,
// lalu didaftarkan sebagai Android plugin v2 pada preset export.
// Lihat android_plugins/bluetooth/README.md untuk roadmap lengkap.

package com.rblox.plugins.bluetooth

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.util.UUID
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class BluetoothPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        // UUID layanan SPP tetap RBlox (harus sama host & client).
        private val SPP_UUID: UUID = UUID.fromString("fa87c0d0-afac-11de-8a39-0800200c9a66")
        const val SIGNAL_ON_MESSAGE = "on_message"
        const val SIGNAL_ON_STATE = "on_state"
    }

    private var adapter: BluetoothAdapter? = null
    private var serverSocket: BluetoothServerSocket? = null
    private val clientSockets = mutableListOf<BluetoothSocket>()
    private var acceptThread: Thread? = null

    override fun getPluginName(): String = "RBloxBluetooth"

    override fun getPluginSignals(): MutableSet<SignalInfo> {
        return mutableSetOf(
            SignalInfo(SIGNAL_ON_MESSAGE, String::class.java),
            SignalInfo(SIGNAL_ON_STATE, String::class.java)
        )
    }

    // ------------------------------------------------------------- host

    /**
     * Mulai menerima koneksi RFCOMM. Mengembalikan true bila socket server
     * berhasil dibuat (permission BLUETOOTH_CONNECT harus sudah disetujui).
     * TODO(Alpha): thread accept loop per client + runtime permission flow.
     */
    @UsedByGodot
    fun startServer(): Boolean {
        val a = adapter ?: return false
        // TODO(Alpha): listenUsingRfcommWithServiceRecord + accept loop thread.
        return false
    }

    @UsedByGodot
    fun stopServer() {
        // TODO(Alpha): tutup server socket & semua socket client, hentikan thread.
        serverSocket?.close()
        serverSocket = null
    }

    // ----------------------------------------------------------- client

    /**
     * Konek ke perangkat terpairing berdasarkan MAC address.
     * TODO(Alpha): createRfcommSocketToServiceRecord + retry 3x, baca baris
     * JSON di thread reader lalu emit SIGNAL_ON_MESSAGE per baris.
     */
    @UsedByGodot
    fun connectTo(address: String): Boolean {
        // TODO(Alpha): implementasi klien RFCOMM.
        return false
    }

    // ------------------------------------------------------------- data

    /**
     * Kirim satu baris (JSON + "\n") ke semua socket yang tersambung
     * (host: broadcast; client: ke host).
     * TODO(Alpha): writer per socket, antrian + flush, penanganan IO error.
     */
    @UsedByGodot
    fun sendLine(line: String): Boolean {
        // TODO(Alpha): implementasi pengiriman.
        return false
    }

    /**
     * Dipanggil thread reader saat satu baris JSON utuh diterima.
     * Meneruskan ke Godot lewat signal on_message(String).
     */
    fun emitMessage(line: String) {
        emitSignal(SIGNAL_ON_MESSAGE, line)
    }

    /** Notifikasi status koneksi (mis. "connected", "disconnected:<mac>"). */
    fun emitState(state: String) {
        emitSignal(SIGNAL_ON_STATE, state)
    }

    // ------------------------------------------------------------ utils

    private fun obtainAdapter(): BluetoothAdapter? {
        if (adapter != null) return adapter
        val ctx: Context = godot.getActivity()?.applicationContext ?: return null
        val mgr = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        adapter = mgr?.adapter
        return adapter
    }

    private fun readerLoop(socket: BluetoothSocket) {
        // TODO(Alpha): BufferedReader per socket, split newline, emitMessage().
        try {
            val reader = BufferedReader(InputStreamReader(socket.inputStream))
            while (true) {
                val line = reader.readLine() ?: break
                emitMessage(line)
            }
        } catch (e: Exception) {
            emitState("disconnected")
        }
    }
}
