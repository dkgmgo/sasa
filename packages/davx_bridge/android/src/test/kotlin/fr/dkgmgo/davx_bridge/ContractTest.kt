package fr.dkgmgo.davx_bridge

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class ContractTest {
    @Test
    fun prefersTasksOrgThenOpenTasks() {
        assertEquals(
            "org.tasks.opentasks",
            Contract.pickTaskProvider { true }?.authority,
        )
        assertEquals(
            "org.dmfs.permission.READ_TASKS",
            Contract.pickTaskProvider { it == "org.dmfs.tasks" }?.readPermission,
        )
        assertNull(Contract.pickTaskProvider { false })
    }

    @Test
    fun widensRangeByOneDayEachSide() {
        val (from, to) = Contract.widen(1_000_000_000_000, 1_000_000_360_000)
        assertEquals(1_000_000_000_000 - Contract.DAY_MS, from)
        assertEquals(1_000_000_360_000 + Contract.DAY_MS, to)
    }

    @Test
    fun mapsErrorsToChannelCodes() {
        assertEquals(Contract.ERR_PERMISSION, Contract.errorCode(SecurityException("no")))
        assertEquals(Contract.ERR_UNAVAILABLE, Contract.errorCode(IllegalArgumentException("uri")))
        assertEquals(Contract.ERR_FAILED, Contract.errorCode(IllegalStateException("db")))
    }

    @Test
    fun taskProjectionHasTheColumnsDartReads() {
        val cols = Contract.TASK_COLUMNS.toSet()
        for (c in listOf("_id", "_uid", "title", "list_name", "account_type", "due",
            "is_allday", "priority", "status", "completed", "original_instance_sync_id")) {
            assert(c in cols) { "missing $c" }
        }
    }
}
