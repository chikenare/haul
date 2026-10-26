package dev.chikenare.haul

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * What haul needs from Android that no other plugin gives it: checking,
 * deleting and finding the path of finished files kept behind a
 * `content://` URI (MediaStore rows of the public Downloads, or documents
 * of a folder an older version wrote through), and the free space where
 * pieces are fetched. Picking folders and the battery saver are the app's.
 */
class HaulPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    /** Nothing of disk or providers on the main thread. */
    private var queries: ExecutorService? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        queries = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "haul/android").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        queries?.shutdown()
        queries = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = context ?: return result.error("detached", "No engine", null)
        when (call.method) {
            "exists" -> background(queries, result) { exists(context, Uri.parse(call.arg("uri"))) }
            "delete" -> background(queries, result) { delete(context, Uri.parse(call.arg("uri"))) }
            "pathOf" -> background(queries, result) { pathOf(context, Uri.parse(call.arg("uri"))) }
            // Where pieces are fetched and merged: internal storage.
            "freeBytes" -> background(queries, result) { StatFs(context.filesDir.path).availableBytes }
            else -> result.notImplemented()
        }
    }

    /** The same for a SAF document as for a MediaStore row. */
    private fun exists(context: Context, uri: Uri): Boolean = runCatching {
        // A column both documents and MediaStore have.
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { it.moveToFirst() } ?: false
    }.getOrDefault(false)

    private fun delete(context: Context, uri: Uri) {
        val resolver = context.contentResolver
        val deleted = if (DocumentsContract.isDocumentUri(context, uri)) {
            DocumentsContract.deleteDocument(resolver, uri)
        } else {
            resolver.delete(uri, null, null) > 0
        }
        // Already gone: for whoever deletes, the outcome is the same.
        if (!deleted && exists(context, uri)) throw IllegalStateException("Could not delete $uri")
    }

    /**
     * A finished file's path, for what only takes paths (a cast server): a
     * document on internal storage or an SD card, or a MediaStore row. Null
     * when it cannot be known (another provider, such as a cloud).
     */
    private fun pathOf(context: Context, uri: Uri): String? {
        if (DocumentsContract.isDocumentUri(context, uri) &&
            uri.authority == EXTERNAL_STORAGE_DOCUMENTS
        ) {
            val id = DocumentsContract.getDocumentId(uri)
            val volume = id.substringBefore(':')
            val path = id.substringAfter(':', "")
            val root = if (volume == "primary") {
                @Suppress("DEPRECATION")
                Environment.getExternalStorageDirectory().path
            } else {
                "/storage/$volume"
            }
            return "$root/$path"
        }
        return runCatching {
            @Suppress("DEPRECATION")
            context.contentResolver
                .query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
        }.getOrNull()
    }

    /** Nothing of disk or providers on the main thread. */
    private fun background(
        executor: ExecutorService?,
        result: MethodChannel.Result,
        work: () -> Any?,
    ) {
        if (executor == null) return result.error("detached", "No engine", null)
        executor.execute {
            try {
                val value = work()
                main.post { result.success(if (value is Unit) null else value) }
            } catch (e: Throwable) {
                // An Error too: without an answer, Dart would wait forever.
                main.post { result.error("io", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun <T> MethodCall.arg(name: String): T =
        argument<T>(name) ?: throw IllegalArgumentException("$name is required")

    companion object {
        private const val EXTERNAL_STORAGE_DOCUMENTS = "com.android.externalstorage.documents"
    }
}
