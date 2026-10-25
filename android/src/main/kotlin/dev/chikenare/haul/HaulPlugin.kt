package dev.chikenare.haul

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * What haul needs from Android that no other plugin gives it:
 *
 * - A folder the user picks with the system's explorer (Storage Access
 *   Framework). There are no paths there: the tree's URI is kept with a
 *   persistent grant and files are copied in through it.
 * - Checking and deleting finished files, which may be URIs of that folder
 *   or MediaStore rows (the public Downloads).
 * - Whether the battery saver may hold the app back, and asking to be let
 *   off it.
 */
class HaulPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    /** Only to open the explorer; let go when detached, so a copy of
     * minutes still running does not hold the Activity. */
    private var activity: ActivityPluginBinding? = null

    /** Copies, which can take minutes, on their own thread. */
    private var copies: ExecutorService? = null

    /** The quick ones (exists, delete) do not wait for a copy to end. */
    private var queries: ExecutorService? = null
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        copies = Executors.newSingleThreadExecutor()
        queries = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "haul/android").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        copies?.shutdown()
        queries?.shutdown()
        copies = null
        queries = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        detachActivity()
        // The explorer was still open: whoever asked would wait forever.
        pending?.error("cancelled", "The folder picker was closed", null)
        pending = null
    }

    private fun detachActivity() {
        activity?.removeActivityResultListener(this)
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = context ?: return result.error("detached", "No engine", null)
        when (call.method) {
            "pickFolder" -> pick(call.argument<String>("initial"), result)
            "describeFolder" -> background(queries, result) {
                describe(context, Uri.parse(call.arg("uri")))
            }
            "saveToFolder" -> background(copies, result) {
                save(
                    context,
                    Uri.parse(call.arg("uri")),
                    File(call.arg<String>("path")),
                    call.arg("name"),
                    call.arg("mimeType"),
                )
            }
            "exists" -> background(queries, result) { exists(context, Uri.parse(call.arg("uri"))) }
            "delete" -> background(queries, result) { delete(context, Uri.parse(call.arg("uri"))) }
            "pathOf" -> background(queries, result) { pathOf(context, Uri.parse(call.arg("uri"))) }
            // Where pieces are fetched and merged: internal storage.
            "freeBytes" -> background(queries, result) { StatFs(context.filesDir.path).availableBytes }
            "isIgnoringBatteryOptimizations" -> {
                val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(power.isIgnoringBatteryOptimizations(context.packageName))
            }
            "requestIgnoreBatteryOptimizations" -> {
                requestBattery(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * The system's own yes/no dialog when the app declares
     * REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (restricted on Google Play);
     * otherwise the list of apps in the battery settings, which needs nothing.
     */
    private fun requestBattery(context: Context) {
        val declared = context.packageManager.checkPermission(
            android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            context.packageName,
        ) == PackageManager.PERMISSION_GRANTED
        val intent = if (declared) {
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"),
            )
        } else {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }
        val from = activity?.activity
        if (from != null) {
            from.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    private fun pick(initial: String?, result: MethodChannel.Result) {
        val activity: Activity = activity?.activity ?: run {
            result.error("detached", "No activity to open the folder picker", null)
            return
        }
        if (pending != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            if (initial != null) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initial))
            }
        }
        activity.startActivityForResult(intent, REQUEST_PICK)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pending ?: return true
        pending = null
        val context = context ?: run {
            result.error("detached", "No engine", null)
            return true
        }

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        val flags =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            // Without it the grant is gone after a reboot.
            context.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (e: SecurityException) {
            // Some providers give no persistent grants.
            result.error("not_persistable", e.message, null)
            return true
        }
        // The grant of the previous folder is kept: what was saved there is
        // played and deleted through its URI, which stops working without it.
        result.success(describe(context, uri))
        return true
    }

    /** `{uri, name}` while the app can still write there; null once revoked. */
    private fun describe(context: Context, uri: Uri): Map<String, String>? {
        val granted = context.contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isWritePermission
        }
        if (!granted) return null
        return mapOf("uri" to uri.toString(), "name" to displayName(uri))
    }

    /** `Movies/App` on internal storage, `1A2B-3C4D/Videos` on an SD card. */
    private fun displayName(tree: Uri): String {
        val id = DocumentsContract.getTreeDocumentId(tree)
        val volume = id.substringBefore(':')
        val path = id.substringAfter(':', "")
        if (volume == "primary") return path.ifEmpty { "/" }
        return if (path.isEmpty()) volume else "$volume/$path"
    }

    /**
     * Copies [source] into the folder, under [folders] (created when
     * missing), and answers the new file's URI. Written as `.partial` and
     * renamed at the end: a kill in the middle of a copy of gigabytes leaves
     * no cut video under the real name.
     */
    private fun save(context: Context, tree: Uri, source: File, name: String, mimeType: String): String {
        val resolver = context.contentResolver
        var parent = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        // `Show/Season 01/Show S01E01.mkv`: folders first.
        val parts = name.split('/')
        for (folder in parts.dropLast(1).filter { it.isNotBlank() }) {
            parent = childFolder(context, parent, folder)
        }
        val fileName = parts.last()
        // No video type, so the provider adds no extension of its own.
        val partial = DocumentsContract.createDocument(
            resolver,
            parent,
            PARTIAL_MIME,
            "$fileName$PARTIAL",
        ) ?: throw IllegalStateException("Could not create $fileName")
        try {
            val output = resolver.openOutputStream(partial, "w")
                ?: throw IllegalStateException("Could not open $partial")
            output.use { out -> source.inputStream().use { it.copyTo(out, BUFFER) } }
        } catch (e: Throwable) {
            runCatching { DocumentsContract.deleteDocument(resolver, partial) }
            throw e
        }
        // With a file of that name already there, the system adds " (1)". A
        // provider that cannot rename leaves the temporary name: it is copied
        // whole again under the right one.
        val uri = runCatching { DocumentsContract.renameDocument(resolver, partial, fileName) }
            .getOrNull()?.toString()
            ?: copyAgain(context, parent, partial, fileName, mimeType)
        // Copied: the staged file goes, as a move would leave it.
        source.delete()
        return uri
    }

    /** The folder [name] inside [parent], made when it is not there. */
    private fun childFolder(context: Context, parent: Uri, name: String): Uri {
        val resolver = context.contentResolver
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent,
            DocumentsContract.getDocumentId(parent),
        )
        resolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name &&
                    cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR
                ) {
                    return DocumentsContract.buildDocumentUriUsingTree(parent, cursor.getString(0))
                }
            }
        }
        return DocumentsContract.createDocument(
            resolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        ) ?: throw IllegalStateException("Could not create the folder $name")
    }

    private fun copyAgain(context: Context, parent: Uri, partial: Uri, name: String, mimeType: String): String {
        val resolver = context.contentResolver
        val target = DocumentsContract.createDocument(resolver, parent, mimeType, name)
            ?: throw IllegalStateException("Could not create $name")
        try {
            val output = resolver.openOutputStream(target, "w")
                ?: throw IllegalStateException("Could not open $target")
            val input = resolver.openInputStream(partial)
                ?: throw IllegalStateException("Could not read $partial")
            output.use { out -> input.use { it.copyTo(out, BUFFER) } }
        } catch (e: Throwable) {
            runCatching { DocumentsContract.deleteDocument(resolver, target) }
            throw e
        } finally {
            runCatching { DocumentsContract.deleteDocument(resolver, partial) }
        }
        return target.toString()
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
        private const val REQUEST_PICK = 0x4A01
        private const val BUFFER = 1 shl 20
        private const val PARTIAL = ".partial"
        private const val PARTIAL_MIME = "application/octet-stream"
        private const val EXTERNAL_STORAGE_DOCUMENTS = "com.android.externalstorage.documents"
    }
}
