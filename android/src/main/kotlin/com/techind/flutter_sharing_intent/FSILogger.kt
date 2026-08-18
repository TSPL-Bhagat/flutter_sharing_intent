package com.techind.flutter_sharing_intent

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Persistent, file-based debug logger so users can capture and share a log of
 * the sharing-intent hand-off (which intent arrived, what it decoded to)
 * without needing an attached debugger/Logcat session.
 */
object FSILogger {
    private const val FILE_NAME = "fsi_debug.log"
    private const val MAX_BYTES = 512 * 1024
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)

    private fun logFile(context: Context): File = File(context.filesDir, FILE_NAME)

    @Synchronized
    fun log(context: Context, message: String, tag: String = "") {
        val file = logFile(context)
        val prefix = if (tag.isEmpty()) "" else "[$tag] "
        val line = "${dateFormat.format(Date())} $prefix$message\n"
        file.appendText(line)
        if (file.length() > MAX_BYTES) {
            val trimmed = file.readText().takeLast(MAX_BYTES / 2)
            file.writeText(trimmed)
        }
    }

    @Synchronized
    fun readAll(context: Context): String {
        val file = logFile(context)
        return if (file.exists()) file.readText() else ""
    }

    @Synchronized
    fun clear(context: Context) {
        val file = logFile(context)
        if (file.exists()) file.delete()
    }

    fun fileForSharing(context: Context): File? {
        val file = logFile(context)
        return if (file.exists()) file else null
    }
}
