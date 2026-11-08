package fr.dkgmgo.davx_bridge

import android.database.Cursor

/** The parts of a [Cursor] that [readRows] needs, so it can be tested on the JVM. */
internal interface RowSource {
    val columnNames: Array<String>
    fun moveToNext(): Boolean
    fun type(index: Int): Int
    fun long(index: Int): Long
    fun double(index: Int): Double
    fun string(index: Int): String?

    companion object {
        // Same values as Cursor.FIELD_TYPE_*.
        const val NULL = 0
        const val INTEGER = 1
        const val FLOAT = 2
        const val STRING = 3
        const val BLOB = 4
    }
}

internal class CursorRows(private val c: Cursor) : RowSource {
    override val columnNames: Array<String> get() = c.columnNames
    override fun moveToNext() = c.moveToNext()
    override fun type(index: Int) = c.getType(index)
    override fun long(index: Int) = c.getLong(index)
    override fun double(index: Int) = c.getDouble(index)
    override fun string(index: Int): String? = c.getString(index)
}

/**
 * Reads every remaining row as a map of column name to Long, Double, String or
 * null (types the standard message codec carries). Blobs are dropped.
 */
internal fun readRows(rows: RowSource): List<Map<String, Any?>> {
    val names = rows.columnNames
    val out = ArrayList<Map<String, Any?>>()
    while (rows.moveToNext()) {
        val row = HashMap<String, Any?>(names.size)
        for (i in names.indices) {
            row[names[i]] = when (rows.type(i)) {
                RowSource.INTEGER -> rows.long(i)
                RowSource.FLOAT -> rows.double(i)
                RowSource.STRING -> rows.string(i)
                else -> null
            }
        }
        out.add(row)
    }
    return out
}
