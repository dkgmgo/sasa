package fr.dkgmgo.davx_bridge

import kotlin.test.Test
import kotlin.test.assertEquals

/** In-memory [RowSource]; values typed like a SQLite cursor. */
private class FakeRows(
    override val columnNames: Array<String>,
    private val rows: List<List<Any?>>,
) : RowSource {
    private var pos = -1
    private fun v(i: Int) = rows[pos][i]
    override fun moveToNext() = ++pos < rows.size
    override fun type(index: Int) = when (v(index)) {
        null -> RowSource.NULL
        is Long -> RowSource.INTEGER
        is Double -> RowSource.FLOAT
        is String -> RowSource.STRING
        else -> RowSource.BLOB
    }
    override fun long(index: Int) = v(index) as Long
    override fun double(index: Int) = v(index) as Double
    override fun string(index: Int) = v(index) as String?
}

internal class RowsTest {
    @Test
    fun readsTypedValuesAndDropsBlobs() {
        val rows = readRows(
            FakeRows(
                arrayOf("_id", "title", "due", "score", "blob"),
                listOf(
                    listOf(1L, "Read paper", 1_762_000_000_000L, 0.5, byteArrayOf(1)),
                    listOf(2L, null, null, null, null),
                ),
            ),
        )
        assertEquals(2, rows.size)
        assertEquals(
            mapOf("_id" to 1L, "title" to "Read paper", "due" to 1_762_000_000_000L, "score" to 0.5, "blob" to null),
            rows[0],
        )
        assertEquals(setOf(null), rows[1].filterKeys { it != "_id" }.values.toSet())
    }

    @Test
    fun emptyCursorGivesNoRows() {
        assertEquals(emptyList(), readRows(FakeRows(arrayOf("_id"), emptyList())))
    }
}
