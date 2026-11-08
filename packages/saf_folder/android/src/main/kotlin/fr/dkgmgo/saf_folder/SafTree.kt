package fr.dkgmgo.saf_folder

/** One document in a tree: a file or a directory. */
data class Doc(val id: String, val name: String, val isDir: Boolean)

/**
 * The few provider operations [SafTree] needs. Implemented on top of
 * `DocumentsContract` for a real tree URI, and in memory for JVM tests.
 */
interface Documents {
    /** The picked directory itself; throws [AccessLost] when it is gone. */
    fun root(): Doc
    fun children(dirId: String): List<Doc>

    /** Creates [name] in [dirId] and returns the new document's id. */
    fun create(dirId: String, name: String, isDir: Boolean): String
    fun read(id: String): ByteArray
    fun append(id: String, bytes: ByteArray)

    /** Replaces the whole content. */
    fun write(id: String, bytes: ByteArray)
    fun delete(id: String)
}

/** The persisted grant for the tree is gone, or the tree no longer exists. */
class AccessLost(message: String) : Exception(message)

/** A path names a file where a directory is needed, or the reverse. */
class WrongKind(message: String) : Exception(message)

/** A path that is empty or could leave the tree. */
class BadPath(message: String) : Exception(message)

/** Relative paths as used by the Dart side: `a/b/c`, no `.`/`..`/empty parts. */
object Paths {
    fun split(path: String, allowRoot: Boolean = false): List<String> {
        if (path.isEmpty()) {
            if (!allowRoot) throw BadPath("path must not be empty")
            return emptyList()
        }
        val parts = path.split('/')
        for (p in parts) {
            if (p.isEmpty() || p == "." || p == ".." || p.contains('\\')) {
                throw BadPath("not a plain relative path: $path")
            }
        }
        return parts
    }
}

/**
 * Path-based file operations inside one SAF tree.
 *
 * Not thread-safe: the plugin calls it from a single thread. Resolved
 * document ids are cached; an operation that fails is retried once with an
 * empty cache, in case the sync app replaced a folder underneath us. A
 * retried append may repeat a line; the event log de-duplicates by id.
 */
class SafTree(private val docs: Documents) {
    private val cache = HashMap<String, Doc>()

    fun list(path: String): List<Doc> = retrying {
        val dir = resolve(Paths.split(path, allowRoot = true)) ?: return@retrying emptyList()
        if (!dir.isDir) return@retrying emptyList()
        docs.children(dir.id).sortedBy { it.name }
    }

    /** Whole file, or null when it does not exist. */
    fun read(path: String): ByteArray? = retrying {
        val doc = resolve(Paths.split(path)) ?: return@retrying null
        if (doc.isDir) throw WrongKind("$path is a directory")
        docs.read(doc.id)
    }

    fun append(path: String, bytes: ByteArray) = retrying {
        docs.append(ensureFile(Paths.split(path)).id, bytes)
    }

    fun write(path: String, bytes: ByteArray) = retrying {
        docs.write(ensureFile(Paths.split(path)).id, bytes)
    }

    fun delete(path: String) = retrying {
        val parts = Paths.split(path)
        val doc = resolve(parts) ?: return@retrying
        if (doc.isDir) throw WrongKind("$path is a directory")
        docs.delete(doc.id)
        cache.remove(path)
    }

    private fun <T> retrying(op: () -> T): T = try {
        op()
    } catch (e: BadPath) {
        throw e
    } catch (e: AccessLost) {
        throw e
    } catch (e: WrongKind) {
        throw e
    } catch (e: Exception) {
        cache.clear()
        op()
    }

    /** The document at [parts], or null if some part is missing. */
    private fun resolve(parts: List<String>): Doc? {
        var current = docs.root()
        for (i in parts.indices) {
            val key = parts.subList(0, i + 1).joinToString("/")
            val cached = cache[key]
            if (cached != null) {
                current = cached
                continue
            }
            if (!current.isDir) return null
            val child = find(current, parts[i]) ?: return null
            cache[key] = child
            current = child
        }
        return current
    }

    private fun find(dir: Doc, name: String): Doc? {
        val matches = docs.children(dir.id).filter { it.name == name }
        // A directory and a file can share a name on some providers; prefer
        // the directory, as only the last part of a path can be a file.
        return matches.firstOrNull { it.isDir } ?: matches.firstOrNull()
    }

    /** Resolves [parts], creating missing directories and the file. */
    private fun ensureFile(parts: List<String>): Doc {
        var current = docs.root()
        for (i in parts.indices) {
            val key = parts.subList(0, i + 1).joinToString("/")
            val last = i == parts.size - 1
            val next = cache[key] ?: find(current, parts[i]) ?: Doc(
                docs.create(current.id, parts[i], isDir = !last),
                parts[i],
                isDir = !last,
            )
            if (next.isDir == last) {
                throw WrongKind(
                    if (last) "$key is a directory" else "$key is a file, not a directory",
                )
            }
            cache[key] = next
            current = next
        }
        return current
    }
}
