package id.zishof.ebisnis

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity: FlutterActivity() {
    private val backupChannel = "id.zishof.ebisnis/persistent_transaction_backup"
    private val biometricChannel = "ais_mobile/biometric_capture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupChannel)
            .setMethodCallHandler { call, result ->
                val requestedName = call.argument<String>("fileName") ?: "transaksi-pos-backup.jsonl"
                // Setiap product flavor mempunyai applicationId berbeda. Prefix
                // mencegah arsip Al-Bahjah bercampur dengan Apotik/eMedik.
                val fileName = "${applicationContext.packageName}-$requestedName"
                try {
                    when (call.method) {
                        "append" -> {
                            val line = call.argument<String>("line") ?: ""
                            appendPersistentBackup(fileName, line)
                            result.success(null)
                        }
                        "read" -> result.success(readPersistentBackup(fileName))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("BACKUP_IO", e.message, null)
                }
            }

        // Sensor biometrik bawaan Android (BiometricPrompt) hanya boleh
        // mengautentikasi pemilik perangkat. Sensor tersebut tidak dapat
        // mengekspor template sidik jari member lain untuk dicocokkan di AIS.
        // Channel ini sengaja fail-closed sampai integrator memasang SDK
        // scanner USB/OTG dan/atau face embedding + liveness yang disetujui.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, biometricChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> result.success(mapOf(
                        "fingerprint" to false,
                        "face" to false,
                        "fingerprint_provider" to null,
                        "face_provider" to null,
                        "reason" to "Scanner biometrik eksternal USB/OTG dan SDK vendor belum dipasang pada build Android ini. BiometricPrompt bawaan tidak digunakan untuk membaca biometrik member lain."
                    ))
                    "captureProbe" -> result.error(
                        "BIOMETRIC_VENDOR_SDK_REQUIRED",
                        "Pasang scanner eksternal USB/OTG beserta SDK vendor, atau provider kamera face-liveness, lalu integrasikan hasil template ke channel ais_mobile/biometric_capture.",
                        mapOf("modality" to call.argument<String>("modality"))
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun backupCollection(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Files.getContentUri("external")
        }

    private fun findBackup(fileName: String): Uri? {
        val collection = backupCollection()
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?"
        } else {
            "${MediaStore.MediaColumns.DISPLAY_NAME}=?"
        }
        val arguments = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            arrayOf(fileName, "Download/eBisnis/")
        } else {
            arrayOf(fileName)
        }
        contentResolver.query(collection, projection, selection, arguments, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                return Uri.withAppendedPath(collection, cursor.getLong(0).toString())
            }
        }
        return null
    }

    private fun createBackup(fileName: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/x-ndjson")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/eBisnis/")
            }
        }
        return contentResolver.insert(backupCollection(), values)
            ?: throw IllegalStateException("Lokasi backup transaksi tidak tersedia")
    }

    private fun appendPersistentBackup(fileName: String, line: String) {
        val uri = findBackup(fileName) ?: createBackup(fileName)
        contentResolver.openOutputStream(uri, "wa")?.bufferedWriter().use { writer ->
            if (writer == null) throw IllegalStateException("File backup tidak dapat dibuka")
            writer.append(line)
            writer.newLine()
            writer.flush()
        }
    }

    private fun readPersistentBackup(fileName: String): String? {
        val uri = findBackup(fileName) ?: return null
        contentResolver.openInputStream(uri)?.use { input ->
            return BufferedReader(InputStreamReader(input)).readText()
        }
        return null
    }
}
