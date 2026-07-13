package com.thepos.the_pos

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import java.io.BufferedReader
import java.io.File
import java.io.FileWriter
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONObject

/// Ditulis di 2 lokasi bersamaan:
/// 1. Folder eksternal khusus app (`getExternalFilesDir`) — cara lama,
///    TIDAK butuh izin apa pun, tapi Android 11+ MEMBLOKIR File Manager
///    pihak ketiga (termasuk "Files by Google") dari melihat ISI folder
///    `Android/data/<package>/` app lain — biasanya tampil "kosong" walau
///    filenya beneran ada (ini akar masalah nyata yang ditemukan user:
///    lapor filenya "tidak ada sama sekali" padahal mungkin cuma
///    tersembunyi oleh restriksi OS, bukan bukti jaring pengaman gagal).
/// 2. Folder Downloads PUBLIK via `MediaStore` (API 29+) — TIDAK kena
///    restriksi di atas, terlihat File Manager mana pun tanpa syarat.
///    Dipakai sbg lokasi UTAMA yang disarankan ke user (lebih pasti
///    terlihat), lokasi #1 dipertahankan sbg cadangan/kompatibilitas HP
///    lama (<Android 10).
///
/// Dipanggil dari 3 tempat: `CrashCatchingApplication` (hook paling awal,
/// attachBaseContext), `MainActivity.installCrashLogHandler` (hook
/// onCreate, jaring kedua), dan MethodChannel `com.thepos/crash_log` dari
/// sisi Dart (`CrashLogService`, utk error yang tertangkap Flutter tapi
/// engine masih hidup).
object CrashLogWriter {
    private const val FILE_NAME = "the_pos_crash_log.jsonl"

    fun appendThrowable(context: Context, source: String, throwable: Throwable) {
        val json = JSONObject()
        json.put(
            "waktu",
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
        )
        json.put("context", source)
        json.put("jenis", throwable.javaClass.name)
        json.put("pesan", throwable.message ?: "")
        json.put("stackTrace", Log.getStackTraceString(throwable))
        json.put("platform", "android-native")
        appendLine(context, json.toString())
    }

    fun appendLine(context: Context, jsonLine: String) {
        val line = "$jsonLine\n"
        try {
            val dir = context.getExternalFilesDir(null)
            if (dir != null) {
                FileWriter(File(dir, FILE_NAME), true).use { it.write(line) }
            }
        } catch (_: Exception) {
            // Best-effort — jaring pengaman ini sendiri tidak boleh melempar.
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                appendToDownloads(context, line)
            } catch (_: Exception) {
                // Best-effort juga — lokasi #1 di atas sudah dicoba duluan.
            }
        }
    }

    fun readDownloads(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val resolver = context.contentResolver
            val uri = findUri(resolver) ?: return null
            resolver.openInputStream(uri)?.use { input ->
                BufferedReader(InputStreamReader(input)).readText()
            }
        } catch (_: Exception) {
            null
        }
    }

    fun clearDownloads(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        try {
            val resolver = context.contentResolver
            val uri = findUri(resolver) ?: return
            resolver.delete(uri, null, null)
        } catch (_: Exception) {
            // Best-effort.
        }
    }

    private fun appendToDownloads(context: Context, line: String) {
        val resolver = context.contentResolver
        val uri = findUri(resolver) ?: run {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, FILE_NAME)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
            }
            resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        } ?: return
        resolver.openOutputStream(uri, "wa")?.use { it.write(line.toByteArray()) }
    }

    private fun findUri(resolver: ContentResolver): Uri? {
        val projection = arrayOf(MediaStore.Downloads._ID)
        val selection = "${MediaStore.Downloads.DISPLAY_NAME} = ?"
        resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            arrayOf(FILE_NAME),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID))
                return ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id)
            }
        }
        return null
    }
}
