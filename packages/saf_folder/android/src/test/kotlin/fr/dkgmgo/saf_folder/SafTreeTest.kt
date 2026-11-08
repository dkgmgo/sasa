package fr.dkgmgo.saf_folder

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** In-memory provider with opaque ids, counting queries. */
private class MemoryDocuments : Documents {
    private class Node(val id: String, var name: String, val isDir: Boolean) {
        val children = mutableListOf<Node>()
        var bytes = ByteArray(0)
    }

    private var next = 0
    private val root = Node("root", "Sync", true)
    private val byId = mutableMapOf(root.id to root)
    var childQueries = 0
    var revoked = false

    /** Makes the next N child queries fail, like a provider hiccup. */
    var failNext = 0

    private fun node(id: String) = byId[id] ?: throw java.io.FileNotFoundException(id)

    override fun root(): Doc {
        if (revoked) throw AccessLost("revoked")
        return Doc(root.id, root.name, true)
    }

    override fun children(dirId: String): List<Doc> {
        childQueries++
        if (failNext > 0) {
            failNext--
            throw IllegalStateException("provider hiccup")
        }
        return node(dirId).children.map { Doc(it.id, it.name, it.isDir) }
    }

    override fun create(dirId: String, name: String, isDir: Boolean): String {
        val n = Node("doc${next++}", name, isDir)
        node(dirId).children += n
        byId[n.id] = n
        return n.id
    }

    override fun read(id: String) = node(id).bytes

    override fun append(id: String, bytes: ByteArray) {
        val n = node(id)
        n.bytes += bytes
    }

    override fun write(id: String, bytes: ByteArray) {
        node(id).bytes = bytes
    }

    override fun delete(id: String) {
        val n = byId.remove(id) ?: throw java.io.FileNotFoundException(id)
        byId.values.forEach { it.children.remove(n) }
    }

    /**
     * Simulates the sync app deleting and re-creating a directory: the same
     * names and content under new ids.
     */
    fun recreateDir(path: List<String>) {
        var cur = root
        for (p in path.dropLast(1)) cur = cur.children.first { it.name == p }
        val old = cur.children.first { it.name == path.last() }
        cur.children.remove(old)
        forget(old)
        cur.children += copy(old)
    }

    private fun forget(n: Node) {
        byId.remove(n.id)
        n.children.forEach(::forget)
    }

    private fun copy(n: Node): Node {
        val fresh = Node("doc${next++}", n.name, n.isDir)
        fresh.bytes = n.bytes
        n.children.forEach { fresh.children += copy(it) }
        byId[fresh.id] = fresh
        return fresh
    }

    fun addFile(dirId: String, name: String) = create(dirId, name, isDir = false)
}

internal class SafTreeTest {
    private val docs = MemoryDocuments()
    private val tree = SafTree(docs)

    private fun text(path: String) = tree.read(path)?.toString(Charsets.UTF_8)

    @Test
    fun appendCreatesParentsAndAppends() {
        tree.append("Sasa/devices/d/log.jsonl", "one\n".toByteArray())
        tree.append("Sasa/devices/d/log.jsonl", "two\n".toByteArray())
        assertEquals("one\ntwo\n", text("Sasa/devices/d/log.jsonl"))
        assertEquals(listOf("devices"), tree.list("Sasa").map { it.name })
        assertTrue(tree.list("Sasa/devices").single().isDir)
    }

    @Test
    fun missingThingsAreNullOrEmpty() {
        assertNull(tree.read("nope.json"))
        assertNull(tree.read("a/b/c.json"))
        assertEquals(emptyList(), tree.list("nope"))
        assertEquals(emptyList(), tree.list(""))
        tree.delete("nope.json") // No error.
    }

    @Test
    fun writeReplacesContent() {
        tree.write("Sasa/config.json", "{\"a\":1}".toByteArray())
        tree.write("Sasa/config.json", "{}".toByteArray())
        assertEquals("{}", text("Sasa/config.json"))
        assertEquals(listOf("config.json"), tree.list("Sasa").map { it.name })
    }

    @Test
    fun listIsSortedByName() {
        tree.write("r/b", ByteArray(0))
        tree.write("r/a", ByteArray(0))
        tree.write("r/c/x", ByteArray(0))
        assertEquals(listOf("a", "b", "c"), tree.list("r").map { it.name })
    }

    @Test
    fun deleteRemovesTheFile() {
        tree.write("r/a.json", "{}".toByteArray())
        tree.delete("r/a.json")
        assertNull(tree.read("r/a.json"))
        tree.write("r/a.json", "new".toByteArray())
        assertEquals("new", text("r/a.json"))
    }

    @Test
    fun utf8RoundTrips() {
        tree.append("u.txt", "Réseaux ⏱\n".toByteArray())
        assertContentEquals("Réseaux ⏱\n".toByteArray(), tree.read("u.txt"))
    }

    @Test
    fun cachesResolvedIds() {
        tree.append("Sasa/devices/d/log.jsonl", "1\n".toByteArray())
        val before = docs.childQueries
        repeat(10) { tree.append("Sasa/devices/d/log.jsonl", "x\n".toByteArray()) }
        assertEquals(before, docs.childQueries)
    }

    @Test
    fun retriesOnceWithAnEmptyCacheAfterAFailure() {
        tree.append("Sasa/devices/d/log.jsonl", "1\n".toByteArray())
        docs.recreateDir(listOf("Sasa", "devices"))
        // The cached id of "Sasa/devices" is now stale: the first attempt
        // fails, the retry resolves the path again.
        tree.append("Sasa/devices/d/log.jsonl", "2\n".toByteArray())
        assertEquals("1\n2\n", text("Sasa/devices/d/log.jsonl"))
    }

    @Test
    fun aProviderHiccupIsRetried() {
        tree.write("a/b.json", "{}".toByteArray())
        val fresh = SafTree(docs)
        docs.failNext = 1
        assertEquals("{}", fresh.read("a/b.json")?.toString(Charsets.UTF_8))
    }

    @Test
    fun persistentFailuresSurface() {
        docs.failNext = 2
        assertFailsWith<IllegalStateException> { tree.list("a") }
    }

    @Test
    fun revokedAccessIsReportedAndNotRetried() {
        docs.revoked = true
        assertFailsWith<AccessLost> { tree.read("a") }
        assertEquals(0, docs.childQueries)
    }

    @Test
    fun wrongKindsAreErrors() {
        tree.write("a/file", ByteArray(0))
        assertFailsWith<WrongKind> { tree.append("a/file/x", ByteArray(0)) }
        assertFailsWith<WrongKind> { tree.write("a", ByteArray(0)) }
        assertFailsWith<WrongKind> { tree.read("a") }
        assertEquals(emptyList(), tree.list("a/file"))
    }

    @Test
    fun prefersADirectoryWhenAFileHasTheSameName() {
        tree.write("a/x/inner", "in".toByteArray())
        val a = tree.list("").single { it.name == "a" }
        docs.addFile(a.id, "x")
        assertEquals("in", text("a/x/inner"))
    }

    @Test
    fun rejectsUnsafePaths() {
        for (bad in listOf("", "../x", "a/../b", "/abs", "a//b", "a/./b", "a\\b")) {
            assertFailsWith<BadPath>(bad) { tree.read(bad) }
            assertFailsWith<BadPath>(bad) { tree.append(bad, ByteArray(0)) }
        }
        assertEquals(emptyList(), Paths.split("", allowRoot = true))
        assertEquals(listOf("a", "b"), Paths.split("a/b"))
    }

    @Test
    fun errorCodesForDart() {
        assertEquals("access_lost", SafFolderPlugin.errorCode(AccessLost("x")))
        assertEquals("access_lost", SafFolderPlugin.errorCode(SecurityException("x")))
        assertEquals("invalid_path", SafFolderPlugin.errorCode(BadPath("x")))
        assertEquals("wrong_kind", SafFolderPlugin.errorCode(WrongKind("x")))
        assertEquals("io_error", SafFolderPlugin.errorCode(java.io.IOException("x")))
    }
}
