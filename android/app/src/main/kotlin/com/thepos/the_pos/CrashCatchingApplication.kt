package com.thepos.the_pos

import android.app.Application
import android.content.Context

/// Jaring pengaman crash PALING AWAL yang mungkin dipasang — di
/// `attachBaseContext()`, sebelum `Application.onCreate()`, jauh sebelum
/// `MainActivity` ada sama sekali. Cakupan LEBIH LUAS dari hook di
/// `MainActivity.onCreate()` (baru jalan setelah proses Activity mulai
/// dibuat) — kalau crash yang dilaporkan ternyata terjadi lebih dini dari
/// itu (mis. saat Flutter engine baru mau nyala), hook di sini yang jadi
/// kemungkinan terakhir menangkapnya sebelum genuinely butuh adb logcat.
///
/// Handler yang dipasang di sini otomatis ikut RANTAI dgn handler
/// `MainActivity` — `MainActivity.installCrashLogHandler()` menyimpan
/// handler SEBELUMNYA (yaitu punya class ini) & memanggilnya balik
/// setelah selesai, jadi keduanya jalan (bukan saling menimpa).
class CrashCatchingApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                CrashLogWriter.appendThrowable(
                    applicationContext, "ApplicationEarlyUncaughtExceptionHandler", throwable)
            } catch (_: Exception) {
                // Jaring pengaman ini sendiri tidak boleh ikut melempar.
            }
            previous?.uncaughtException(thread, throwable)
        }
    }
}
