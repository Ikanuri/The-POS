package com.thepos.the_pos

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.thepos/bt_print"
        private const val CRASH_CHANNEL = "com.thepos/crash_log"
        private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val TAG = "BtPrint"
    }

    private var btSocket: BluetoothSocket? = null

    // Jaring pengaman native — cakupan LEBIH LUAS dari `runZonedGuarded` di
    // sisi Dart (main.dart): menangkap exception Java/Kotlin tak tertangani
    // (mis. UnsatisfiedLinkError saat gagal memuat native library) SEBELUM
    // proses benar-benar dihentikan OS. Dipasang PALING AWAL (sebelum
    // super.onCreate) supaya jendela cakupannya semaksimal mungkin — tapi
    // `CrashCatchingApplication.attachBaseContext()` sudah pasang jaring
    // yang LEBIH awal lagi (sebelum Activity manapun ada), handler di sini
    // ikut RANTAI ke situ (lihat `previous?.uncaughtException`), bukan
    // menimpanya. TIDAK bisa menangkap crash native murni (segfault C/C++)
    // — itu di luar jangkauan handler Java/Kotlin mana pun, satu-satunya
    // cara lihat itu adalah adb logcat.
    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashLogHandler()
        super.onCreate(savedInstanceState)
    }

    private fun installCrashLogHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                CrashLogWriter.appendThrowable(
                    applicationContext, "AndroidUncaughtExceptionHandler", throwable)
            } catch (_: Exception) {
                // Jaring pengaman ini sendiri tidak boleh ikut melempar.
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect"    -> doConnect(call.argument("mac") ?: "", result)
                    "write"      -> doWrite(call.argument("bytes") ?: ByteArray(0), result)
                    "disconnect" -> doDisconnect(result)
                    "status"     -> result.success(btSocket?.isConnected == true)
                    else         -> result.notImplemented()
                }
            }

        // Item 24d susulan — jembatan Dart → native utk crash log: error yang
        // tertangkap Flutter (`runZonedGuarded`/`FlutterError.onError`, engine
        // MASIH hidup) ikut ditulis ke folder Downloads publik via
        // `CrashLogWriter` (sisi Dart sendiri, lewat `path_provider`, TIDAK
        // bisa akses MediaStore — cuma folder khusus app yang kena restriksi
        // Android 11+ File Manager, lihat komentar `CrashLogWriter`).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CRASH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "append" -> {
                        val json = call.argument<String>("json")
                        if (json != null) CrashLogWriter.appendLine(applicationContext, json)
                        result.success(true)
                    }
                    "readDownloads" ->
                        result.success(CrashLogWriter.readDownloads(applicationContext))
                    "clearDownloads" -> {
                        CrashLogWriter.clearDownloads(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Connect ──────────────────────────────────────────────────────────────
    private fun doConnect(mac: String, result: MethodChannel.Result) {
        Thread {
            val reply = mutableMapOf<String, Any?>()
            try {
                btSocket?.let { try { it.close() } catch (_: IOException) {} }
                btSocket = null

                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter == null) {
                    reply["ok"] = false
                    reply["err"] = "BluetoothAdapter null — perangkat tidak mendukung BT"
                    result.success(reply); return@Thread
                }

                // Hentikan scan/discovery agar tidak mengganggu koneksi
                adapter.cancelDiscovery()

                val device = adapter.getRemoteDevice(mac.uppercase())

                // Strategi 1: secure RFCOMM via SPP UUID (standar)
                val socket: BluetoothSocket = try {
                    Log.d(TAG, "Coba createRfcommSocketToServiceRecord (secure, UUID)")
                    device.createRfcommSocketToServiceRecord(SPP_UUID)
                } catch (e1: IOException) {
                    // Strategi 2: reflection langsung ke RFCOMM channel 1
                    Log.d(TAG, "Secure UUID gagal: ${e1.message}, coba reflection ch1")
                    try {
                        val m = device.javaClass.getMethod("createRfcommSocket", Int::class.java)
                        m.invoke(device, 1) as BluetoothSocket
                    } catch (e2: Exception) {
                        reply["ok"] = false
                        reply["err"] = "Tidak bisa buat socket. Secure: ${e1.message} | Refl: ${e2.message}"
                        result.success(reply); return@Thread
                    }
                }

                Log.d(TAG, "Menghubungkan ke $mac …")
                socket.connect()
                btSocket = socket
                Log.d(TAG, "Terhubung. isConnected=${socket.isConnected}")
                reply["ok"] = true
                reply["err"] = null

            } catch (e: IOException) {
                Log.e(TAG, "connect IOException: ${e.message}")
                btSocket = null
                reply["ok"] = false
                reply["err"] = "IOException: ${e.message}"
            } catch (e: Exception) {
                Log.e(TAG, "connect Exception: ${e.message}")
                btSocket = null
                reply["ok"] = false
                reply["err"] = "${e.javaClass.simpleName}: ${e.message}"
            }
            result.success(reply)
        }.start()
    }

    // ── Write ─────────────────────────────────────────────────────────────────
    private fun doWrite(bytes: ByteArray, result: MethodChannel.Result) {
        val reply = mutableMapOf<String, Any?>()
        val s = btSocket
        if (s == null || !s.isConnected) {
            reply["ok"] = false
            reply["err"] = "Socket null atau belum terhubung (isConnected=${s?.isConnected})"
            result.success(reply); return
        }
        Thread {
            try {
                Log.d(TAG, "Menulis ${bytes.size} bytes …")
                s.outputStream.write(bytes)
                s.outputStream.flush()
                Log.d(TAG, "Write berhasil")
                reply["ok"] = true
                reply["err"] = null
            } catch (e: IOException) {
                Log.e(TAG, "write IOException: ${e.message}")
                reply["ok"] = false
                reply["err"] = "IOException: ${e.message}"
            } catch (e: Exception) {
                Log.e(TAG, "write Exception: ${e.message}")
                reply["ok"] = false
                reply["err"] = "${e.javaClass.simpleName}: ${e.message}"
            }
            result.success(reply)
        }.start()
    }

    // ── Disconnect ────────────────────────────────────────────────────────────
    private fun doDisconnect(result: MethodChannel.Result) {
        try { btSocket?.close() } catch (_: IOException) {}
        btSocket = null
        result.success(true)
    }
}
