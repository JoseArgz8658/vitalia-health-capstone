package cl.vitalia.vitalia_health

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// VITALIA_ANDROID_DOWNLOAD_V1
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private val createDocumentRequest = 6419

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.vitalia/documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDocument") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("BUSY", "Hay una descarga en curso.", null)
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime")
                if (bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024 ||
                    name.isNullOrBlank() || name.length > 255 ||
                    name.contains('/') || name.contains('\\') ||
                    mime !in listOf("application/pdf", "image/jpeg", "image/png")) {
                    result.error("INVALID_FILE", "Archivo inválido.", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                pendingBytes = bytes
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_TITLE, name)
                }
                try {
                    startActivityForResult(intent, createDocumentRequest)
                } catch (_: Exception) {
                    finishSave(result, false, "No se pudo abrir el selector de destino.")
                }
            }
    }

    @Deprecated("Used to receive the system document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != createDocumentRequest) return
        val result = pendingResult ?: return
        val bytes = pendingBytes ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            finishSave(result, false, null)
            return
        }
        Thread {
            try {
                val output = contentResolver.openOutputStream(uri, "w")
                    ?: throw IllegalStateException("No output stream")
                output.use { it.write(bytes) }
                runOnUiThread { finishSave(result, true, null) }
            } catch (_: Exception) {
                try { contentResolver.delete(uri, null, null) } catch (_: Exception) { }
                runOnUiThread { finishSave(result, false, "No se pudo guardar el archivo.") }
            }
        }.start()
    }

    private fun finishSave(result: MethodChannel.Result, saved: Boolean, error: String?) {
        if (pendingResult !== result) return
        pendingResult = null
        pendingBytes = null
        if (error == null) result.success(saved)
        else result.error("SAVE_FAILED", error, null)
    }

    override fun onDestroy() {
        pendingResult?.let { finishSave(it, false, "La actividad se cerró.") }
        super.onDestroy()
    }
}
