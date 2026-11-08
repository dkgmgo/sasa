package fr.dkgmgo.saf_folder

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Files inside a folder picked with the Storage Access Framework.
 *
 * The picker needs an activity; every other call only needs the application
 * context and a persisted grant, so they also work in the engine a
 * WorkManager job starts. All document work runs on one thread shared by
 * every engine in the process, so the UI and a background job never
 * interleave a create or an append.
 */
class SafFolderPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pickTree") return pickTree(call, result)
        val treeArg = call.argument<String>("treeUri")
            ?: return result.error(ERR_ARGS, "treeUri is required", null)
        val tree = Uri.parse(treeArg)
        val path = call.argument<String>("path") ?: ""
        when (call.method) {
            "hasAccess" -> work(result) { runCatching { docs(tree).rootName() }.isSuccess }
            "describe" -> work(result) { mapOf("uri" to treeArg, "name" to docs(tree).rootName()) }
            "release" -> work(result) {
                trees.remove(treeArg)
                runCatching {
                    context.contentResolver.releasePersistableUriPermission(
                        tree,
                        ResolverDocuments.GRANT_FLAGS,
                    )
                }
                null
            }
            "list" -> work(result) {
                tree(tree).list(path).map { mapOf("name" to it.name, "isDirectory" to it.isDir) }
            }
            "read" -> work(result) { tree(tree).read(path)?.toString(Charsets.UTF_8) }
            "append" -> work(result) {
                tree(tree).append(path, text(call))
                null
            }
            "write" -> work(result) {
                tree(tree).write(path, text(call))
                null
            }
            "delete" -> work(result) {
                tree(tree).delete(path)
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun text(call: MethodCall): ByteArray =
        (call.argument<String>("text") ?: throw IllegalArgumentException("text is required"))
            .toByteArray(Charsets.UTF_8)

    private fun docs(tree: Uri) = ResolverDocuments(context.contentResolver, tree)

    /** Runs on [executor] only. */
    private fun tree(tree: Uri): SafTree =
        trees.getOrPut(tree.toString()) { SafTree(docs(tree)) }

    private fun work(result: MethodChannel.Result, op: () -> Any?) {
        executor.execute {
            val outcome = runCatching(op)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        result.error(errorCode(it), it.message ?: it.javaClass.simpleName, null)
                    },
                )
            }
        }
    }

    // ---- Picker ----

    private fun pickTree(call: MethodCall, result: MethodChannel.Result) {
        val activity: Activity = activityBinding?.activity
            ?: return result.error(ERR_NO_ACTIVITY, "The folder picker needs the app in front", null)
        if (pendingPick != null) {
            return result.error(ERR_BUSY, "The folder picker is already showing", null)
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                ResolverDocuments.GRANT_FLAGS or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
            val initial = call.argument<String>("initialUri")
            if (initial != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initial))
            }
        }
        pendingPick = result
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: Exception) {
            pendingPick = null
            result.error(ERR_FAILED, "No folder picker available: ${e.message}", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // Cancelled.
            return true
        }
        work(result) {
            context.contentResolver.takePersistableUriPermission(uri, ResolverDocuments.GRANT_FLAGS)
            trees.remove(uri.toString())
            mapOf("uri" to uri.toString(), "name" to docs(uri).rootName())
        }
        return true
    }

    // ---- ActivityAware ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
        pendingPick?.let {
            pendingPick = null
            it.success(null)
        }
    }

    companion object {
        const val CHANNEL = "fr.dkgmgo.saf_folder"
        const val ERR_ARGS = "invalid_arguments"
        const val ERR_PATH = "invalid_path"
        const val ERR_ACCESS = "access_lost"
        const val ERR_KIND = "wrong_kind"
        const val ERR_NO_ACTIVITY = "no_activity"
        const val ERR_BUSY = "busy"
        const val ERR_FAILED = "io_error"

        // Arbitrary, unlikely to clash with other plugins' request codes.
        private const val REQUEST_CODE = 0x5afe

        /** One thread for every engine in the process. Never shut down. */
        private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
            Thread(r, "saf_folder").apply { isDaemon = true }
        }

        /** Per tree URI; touched only on [executor]. */
        private val trees = HashMap<String, SafTree>()

        fun errorCode(e: Throwable): String = when (e) {
            is AccessLost, is SecurityException -> ERR_ACCESS
            is WrongKind -> ERR_KIND
            is BadPath -> ERR_PATH
            else -> ERR_FAILED
        }
    }
}
