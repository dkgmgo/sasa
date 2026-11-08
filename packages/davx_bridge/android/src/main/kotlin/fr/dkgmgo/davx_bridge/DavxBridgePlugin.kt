package fr.dkgmgo.davx_bridge

import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Read-only bridge to CalendarContract and the OpenTasks-compatible task
 * provider (Tasks.org) that DAVx⁵ syncs into.
 *
 * Works in any Flutter engine, including the one WorkManager starts in the
 * background: reads only need the application context. An activity is only
 * used to show the permission prompt. Queries run off the main thread;
 * results are posted back on it.
 */
class DavxBridgePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var executor: ExecutorService? = null
    private val main = Handler(Looper.getMainLooper())

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        executor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, Contract.CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor?.shutdown()
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> background(result) { status() }
            "requestPermissions" -> requestPermissions(call, result)
            "calendars" -> background(result) { calendars() }
            "instances" -> {
                val start = call.argument<Number>("start")?.toLong()
                val end = call.argument<Number>("end")?.toLong()
                if (start == null || end == null || end < start) {
                    result.error(Contract.ERR_ARGS, "instances needs start <= end (epoch ms)", null)
                } else {
                    background(result) { instances(start, end) }
                }
            }
            "tasks" -> background(result) { tasks() }
            else -> result.notImplemented()
        }
    }

    // ---- Queries (run on the executor) ----

    private fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun taskProvider(): Contract.TaskProvider? =
        Contract.pickTaskProvider { context.packageManager.resolveContentProvider(it, 0) != null }

    private fun status(): Map<String, Any?> {
        val tasks = taskProvider()
        return mapOf(
            "calendarPermission" to granted(Contract.READ_CALENDAR),
            "taskAuthority" to tasks?.authority,
            "taskPermission" to (tasks != null && granted(tasks.readPermission)),
        )
    }

    private fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String? = null,
        args: Array<String>? = null,
    ): List<Map<String, Any?>> =
        context.contentResolver.query(uri, projection, selection, args, null)?.use {
            readRows(CursorRows(it))
        } ?: throw IllegalArgumentException("Provider for $uri returned no cursor")

    private fun calendars() = query(
        CalendarContract.Calendars.CONTENT_URI,
        arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.SYNC_EVENTS,
            CalendarContract.Calendars.CALENDAR_COLOR,
        ),
    )

    private fun instances(start: Long, end: Long): List<Map<String, Any?>> {
        val (from, to) = Contract.widen(start, end)
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
        }.build()
        return query(
            uri,
            arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.AVAILABILITY,
                CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.DESCRIPTION,
                CalendarContract.Instances.UID_2445,
                CalendarContract.Instances.STATUS,
                CalendarContract.Instances.CALENDAR_ID,
                CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
                // Instances joins Events, whose sync columns carry the account.
                CalendarContract.Events.ACCOUNT_TYPE,
                CalendarContract.Events.ACCOUNT_NAME,
                CalendarContract.Instances.VISIBLE,
            ),
        )
    }

    private fun tasks(): Map<String, Any?> {
        val provider = taskProvider()
            ?: throw ProviderMissing("No OpenTasks-compatible task provider installed")
        val base = Uri.parse("content://${provider.authority}")
        val tasks = query(Uri.withAppendedPath(base, "tasks"), Contract.TASK_COLUMNS)
        val categories = query(
            Uri.withAppendedPath(base, "properties"),
            Contract.CATEGORY_COLUMNS,
            "mimetype = ?",
            arrayOf(Contract.CATEGORY_MIMETYPE),
        )
        return mapOf(
            "authority" to provider.authority,
            "tasks" to tasks,
            "categories" to categories,
        )
    }

    private class ProviderMissing(message: String) : Exception(message)

    /** Runs [work] on the executor and replies on the main thread. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        val ex = executor ?: return result.error(Contract.ERR_FAILED, "Engine detached", null)
        ex.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        val code = if (it is ProviderMissing) Contract.ERR_UNAVAILABLE else Contract.errorCode(it)
                        result.error(code, it.message ?: it.javaClass.simpleName, null)
                    },
                )
            }
        }
    }

    // ---- Permissions ----

    /**
     * Prompts for the requested permissions when an activity is attached;
     * otherwise (background engine) replies with the current status.
     * Replies with the status map plus `prompted`.
     */
    private fun requestPermissions(call: MethodCall, result: MethodChannel.Result) {
        val wantCalendar = call.argument<Boolean>("calendar") ?: true
        val wantTasks = call.argument<Boolean>("tasks") ?: true
        val activity: Activity? = activityBinding?.activity
        val missing = buildList {
            if (wantCalendar && !granted(Contract.READ_CALENDAR)) add(Contract.READ_CALENDAR)
            if (wantTasks) taskProvider()?.let { if (!granted(it.readPermission)) add(it.readPermission) }
        }
        if (activity == null || missing.isEmpty()) {
            return background(result) { status() + ("prompted" to false) }
        }
        if (pendingPermissionResult != null) {
            return result.error(Contract.ERR_BUSY, "A permission request is already showing", null)
        }
        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        background(result) { status() + ("prompted" to true) }
        return true
    }

    // ---- ActivityAware ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    // A rotation while the prompt shows keeps the pending reply: the result is
    // delivered to the re-attached activity.
    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
        pendingPermissionResult?.let { r ->
            pendingPermissionResult = null
            background(r) { status() + ("prompted" to false) }
        }
    }

    private companion object {
        // Arbitrary, unlikely to clash with other plugins' request codes.
        const val REQUEST_CODE = 0x5a5a
    }
}
