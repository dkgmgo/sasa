package fr.dkgmgo.saf_folder

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.io.FileNotFoundException

/** [Documents] for one SAF tree URI, through the [ContentResolver]. */
class ResolverDocuments(
    private val resolver: ContentResolver,
    private val tree: Uri,
) : Documents {

    private fun docUri(id: String): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    /** True while this app holds a persisted read+write grant for the tree. */
    fun hasGrant(): Boolean = resolver.persistedUriPermissions.any {
        it.uri == tree && it.isReadPermission && it.isWritePermission
    }

    override fun root(): Doc {
        if (!hasGrant()) throw AccessLost("No persisted access to $tree")
        val id = DocumentsContract.getTreeDocumentId(tree)
        val rows = try {
            query(docUri(id))
        } catch (e: SecurityException) {
            throw AccessLost("Access to $tree was revoked")
        } catch (e: FileNotFoundException) {
            throw AccessLost("$tree no longer exists")
        } catch (e: IllegalArgumentException) {
            throw AccessLost("$tree no longer exists")
        }
        return rows.firstOrNull()?.copy(id = id) ?: throw AccessLost("$tree no longer exists")
    }

    /** Display name of the picked folder, for the settings screen. */
    fun rootName(): String = root().name

    override fun children(dirId: String): List<Doc> =
        query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, dirId))

    override fun create(dirId: String, name: String, isDir: Boolean): String {
        // octet-stream: providers keep the name as given instead of adding an
        // extension that matches the MIME type.
        val mime = if (isDir) Document.MIME_TYPE_DIR else "application/octet-stream"
        val uri = DocumentsContract.createDocument(resolver, docUri(dirId), mime, name)
            ?: throw IllegalStateException("Provider refused to create $name")
        return DocumentsContract.getDocumentId(uri)
    }

    override fun read(id: String): ByteArray =
        resolver.openInputStream(docUri(id))?.use { it.readBytes() }
            ?: throw FileNotFoundException("Cannot open $id")

    override fun append(id: String, bytes: ByteArray) = output(id, "wa", bytes)

    override fun write(id: String, bytes: ByteArray) = output(id, "wt", bytes)

    override fun delete(id: String) {
        DocumentsContract.deleteDocument(resolver, docUri(id))
    }

    private fun output(id: String, mode: String, bytes: ByteArray) {
        val stream = resolver.openOutputStream(docUri(id), mode)
            ?: throw FileNotFoundException("Cannot open $id for writing")
        stream.use {
            it.write(bytes)
            it.flush()
        }
    }

    private fun query(uri: Uri): List<Doc> =
        resolver.query(uri, COLUMNS, null, null, null)?.use { c ->
            val out = ArrayList<Doc>(c.count)
            while (c.moveToNext()) {
                out += Doc(
                    id = c.getString(0),
                    name = c.getString(1) ?: "",
                    isDir = c.getString(2) == Document.MIME_TYPE_DIR,
                )
            }
            out
        } ?: throw FileNotFoundException("Provider returned no cursor for $uri")

    companion object {
        private val COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
        )

        const val GRANT_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    }
}
