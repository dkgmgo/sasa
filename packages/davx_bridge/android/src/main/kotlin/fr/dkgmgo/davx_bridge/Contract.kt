package fr.dkgmgo.davx_bridge

/**
 * Names used on the method channel and from the providers' contracts.
 *
 * Task column names come from the OpenTasks `TaskContract`, which Tasks.org
 * re-exports under `org.tasks.opentasks`. They are spelled out here instead of
 * depending on the contract artifact.
 */
internal object Contract {
    const val CHANNEL = "fr.dkgmgo.davx_bridge"

    /** Error codes sent to Dart. */
    const val ERR_PERMISSION = "permission_denied"
    const val ERR_UNAVAILABLE = "provider_unavailable"
    const val ERR_ARGS = "bad_arguments"
    const val ERR_FAILED = "query_failed"
    const val ERR_BUSY = "request_in_progress"

    /** A task provider: authority and the permission that guards reads. */
    data class TaskProvider(val authority: String, val readPermission: String)

    /** Tried in order: Tasks.org first, then the plain OpenTasks app. */
    val TASK_PROVIDERS = listOf(
        TaskProvider("org.tasks.opentasks", "org.tasks.permission.READ_TASKS"),
        TaskProvider("org.dmfs.tasks", "org.dmfs.permission.READ_TASKS"),
    )

    const val READ_CALENDAR = "android.permission.READ_CALENDAR"

    // OpenTasks TaskContract.Tasks (the `tasks` view, joined with its list).
    val TASK_COLUMNS = arrayOf(
        "_id", "_uid", "title", "list_id", "list_name", "account_type", "account_name",
        "due", "is_allday", "tz", "priority", "status", "completed",
        "original_instance_sync_id", "original_instance_id",
    )

    // OpenTasks TaskContract.Properties with the Category mimetype.
    const val CATEGORY_MIMETYPE = "vnd.android.cursor.item/category"
    val CATEGORY_COLUMNS = arrayOf("task_id", "data1")

    /** Widening applied to instance queries, see [widen]. */
    const val DAY_MS = 24L * 60 * 60 * 1000

    /**
     * All-day instances are stored at UTC midnight, so a range given in the
     * user's zone can miss them by up to a day; Dart filters exactly.
     */
    fun widen(start: Long, end: Long): Pair<Long, Long> = (start - DAY_MS) to (end + DAY_MS)

    /** First provider for which [resolves] is true, or null. */
    fun pickTaskProvider(resolves: (String) -> Boolean): TaskProvider? =
        TASK_PROVIDERS.firstOrNull { resolves(it.authority) }

    /** Maps a failure while querying a provider to a channel error code. */
    fun errorCode(t: Throwable): String = when (t) {
        is SecurityException -> ERR_PERMISSION
        // Unknown authority/URI: the provider is gone or too old.
        is IllegalArgumentException -> ERR_UNAVAILABLE
        else -> ERR_FAILED
    }
}
