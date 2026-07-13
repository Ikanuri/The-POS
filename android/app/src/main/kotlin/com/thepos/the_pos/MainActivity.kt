package com.thepos.the_pos

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileWriter
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.thepos/bt_print"
        private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val TAG = "BtPrint"
        // HARUS sama persis dgn CrashLogService.fileName di sisi Dart
        // (lib/core/services/crash_log_service.dart) & lokasi yang sama
        // (getExternalFilesDir == path_provider getExternalStorageDirectory)
        // supaya keduanya nulis ke satu file yang sama.
        private const val CRASH_LOG_FILE = "the_pos_crash_log.jsonl"
    }

    private var btSocket: BluetoothSocket? = null

    // Jaring pengaman native — cakupan LEBIH LUAS dari `runZonedGuarded` di
    // sisi Dart (main.dart): menangkap exception Java/Kotlin tak tertangani
    // (mis. UnsatisfiedLinkError saat gagal memuat native library) SEBELUM
    // proses benar-benar dihentikan OS, termasuk yang terjadi sebelum Dart
    // sempat jalan sama sekali. Dipasang PALING AWAL (sebelum super.onCreate)
    // supaya jendela cakupannya semaksimal mungkin. TIDAK bisa menangkap
    // crash native murni (segfault C/C++) — itu di luar jangkauan handler
    // Java/Kotlin mana pun, satu-satunya cara lihat itu adalah adb logcat.
    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashLogHandler()
        super.onCreate(savedInstanceState)
    }

    private fun installCrashLogHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                writeCrashLog(throwable)
            } catch (_: Exception) {
                // Jaring pengaman ini sendiri tidak boleh ikut melempar.
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    private fun writeCrashLog(throwable: Throwable) {
        val dir = getExternalFilesDir(null) ?: return
        val file = File(dir, CRASH_LOG_FILE)
        val json = JSONObject()
        json.put(
            "waktu",
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
        )
        json.put("context", "AndroidUncaughtExceptionHandler")
        json.put("jenis", throwable.javaClass.name)
        json.put("pesan", throwable.message ?: "")
        json.put("stackTrace", Log.getStackTraceString(throwable))
        json.put("platform", "android-native")
        FileWriter(file, true).use { it.write(json.toString() + "\n") }
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
