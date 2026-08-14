// Copyright 2026 Lóránd Somogyi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.lorands.cirrhy

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The Android half of the file-access port (DESIGN.md §4.1).
 *
 * Storage Access Framework, not a path. The app asks for a *tree* rather than
 * a document (§4.2) and persists the grant, which is the only reason the
 * folder is still reachable after a restart. Everything here is deliberately
 * mechanical: pick, check, list, read bytes, write bytes. Nothing about what
 * the bytes mean lives on this side.
 */
class DocumentFolders(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.lorands.cirrhy/documents"

        /** Matches ChannelDocumentDirectory.unavailableCode on the Dart side. */
        private const val UNAVAILABLE = "unavailable"
        private const val FAILED = "failed"
        private const val PICK_REQUEST = 0x0C17

        private const val MIME = "application/json"
        private const val EXTERNAL_STORAGE = "com.android.externalstorage.documents"
    }

    /**
     * Content-provider I/O never runs on the main thread.
     *
     * §4.4: a provider may hand back a placeholder that has not been
     * downloaded yet, and ContentResolver can block or throw for cloud-backed
     * documents. On the main thread that is an ANR rather than a slow save.
     */
    private val io = Executors.newSingleThreadExecutor()

    private var pendingPick: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> pickDirectory(result)
            "isAvailable" -> onIoThread(result) { isAvailable(call.handle()) }
            "listDocuments" -> onIoThread(result) {
                listDocuments(call.handle(), call.argument<List<String>>("names").orEmpty())
            }
            "readDocument" -> onIoThread(result) {
                readDocument(call.handle(), call.name())
            }
            "writeDocument" -> onIoThread(result) {
                writeDocument(
                    call.handle(),
                    call.name(),
                    call.argument<ByteArray>("bytes") ?: ByteArray(0),
                )
            }
            else -> result.notImplemented()
        }
    }

    // ---- picking ----

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error(FAILED, "a folder picker is already open", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        activity.startActivityForResult(intent, PICK_REQUEST)
    }

    /** Returns true when this consumed the result. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null

        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null) // Cancelled.
            return true
        }

        // The whole point of the flow. Without this the grant dies with the
        // process and the folder is unreachable on the next launch.
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            result.error(UNAVAILABLE, "could not keep access to that folder", e.message)
            return true
        }

        result.success(mapOf("handle" to uri.toString(), "label" to labelFor(uri)))
        return true
    }

    /**
     * Something worth showing a human. The tree URI itself is not.
     *
     * On local storage the last segment carries a real path — `primary:Sync/Cirrhy`
     * — which says more than the folder's bare name when someone keeps several
     * sync folders. Other providers put an opaque id there, so those fall back
     * to the display name.
     */
    private fun labelFor(uri: Uri): String {
        if (uri.authority == EXTERNAL_STORAGE) {
            val path = uri.lastPathSegment?.substringAfter(':').orEmpty()
            if (path.isNotBlank()) return path
        }
        val name = DocumentFile.fromTreeUri(activity, uri)?.name
        return if (!name.isNullOrBlank()) name else uri.toString()
    }

    // ---- the folder ----

    private fun isAvailable(handle: String): Boolean {
        val uri = runCatching { Uri.parse(handle) }.getOrNull() ?: return false
        // A persisted grant can be revoked, and the folder itself can be
        // deleted. Both must read as "gone" rather than throwing (§4.4).
        val held = activity.contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }
        if (!held) return false
        val tree = DocumentFile.fromTreeUri(activity, uri)
        return tree != null && tree.isDirectory && tree.canWrite()
    }

    private fun tree(handle: String): DocumentFile {
        val uri = runCatching { Uri.parse(handle) }.getOrNull()
            ?: throw Unavailable("the stored folder handle is not a URI")
        val tree = DocumentFile.fromTreeUri(activity, uri)
            ?: throw Unavailable("the folder could not be opened")
        if (!tree.isDirectory) throw Unavailable("the folder is gone")
        return tree
    }

    private fun listDocuments(handle: String, names: List<String>): List<String> {
        val tree = tree(handle)
        // Listed by name rather than by scanning everything: the adopt rule
        // (§4.6) asks a yes/no question about known names, and a SAF directory
        // listing is expensive enough not to do for fun.
        return names.filter { tree.findFile(it)?.isFile == true }
    }

    private fun readDocument(handle: String, name: String): ByteArray? {
        val file = tree(handle).findFile(name)
        // Null means "no document yet", which is the ordinary first run. A
        // missing *folder* threw above, because treating that as an empty
        // document would write the user's history away on the next save.
        if (file == null || !file.isFile) return null
        return try {
            activity.contentResolver.openInputStream(file.uri).use {
                it?.readBytes() ?: throw Unavailable("the document could not be opened")
            }
        } catch (e: SecurityException) {
            throw Unavailable(e.message ?: "access to the document was withdrawn")
        }
    }

    /**
     * In place, and that is not laziness — SAF has no atomic replace.
     *
     * `DocumentsContract.renameDocument` fails when the target name is taken,
     * so the alternatives are delete-then-rename, which widens the window to
     * include a moment where nothing exists, or this. DESIGN.md §4.3 chooses
     * this and leans on the app-private pre-write backup, which the Dart side
     * has already taken by the time this runs.
     */
    private fun writeDocument(handle: String, name: String, bytes: ByteArray) {
        val tree = tree(handle)
        val file = tree.findFile(name) ?: create(tree, name)
        try {
            // "wt" truncates. Without the t a shorter document leaves the tail
            // of the longer one it replaced, which parses as nothing at all.
            activity.contentResolver.openOutputStream(file.uri, "wt").use {
                it ?: throw Unavailable("the document could not be opened for writing")
                it.write(bytes)
                it.flush()
            }
        } catch (e: SecurityException) {
            throw Unavailable(e.message ?: "access to the folder was withdrawn")
        }
    }

    /**
     * Creates the document, insisting on the name we asked for.
     *
     * Providers are entitled to rename on create — appending a second
     * extension, or dodging a collision with a suffix. A file quietly called
     * `cirrhy.json.json` would be written to happily and then never found by
     * the next device, so a name we cannot get is an error rather than a
     * surprise.
     */
    private fun create(tree: DocumentFile, name: String): DocumentFile {
        val created = tree.createFile(MIME, name)
            ?: throw Unavailable("the document could not be created")
        if (created.name == name) return created

        val renamed = runCatching {
            DocumentsContract.renameDocument(activity.contentResolver, created.uri, name)
        }.getOrNull()
        if (renamed != null) {
            val file = DocumentFile.fromSingleUri(activity, renamed)
            if (file != null && file.name == name) return file
        }
        created.delete()
        throw Unavailable("the folder would not accept a file named $name")
    }

    // ---- plumbing ----

    private class Unavailable(message: String) : Exception(message)

    private fun MethodCall.handle(): String =
        argument<String>("handle") ?: throw Unavailable("no folder handle")

    private fun MethodCall.name(): String =
        argument<String>("name") ?: throw Unavailable("no document name")

    /**
     * Runs [work] off the main thread and answers on it, because a
     * MethodChannel result may only be delivered from the main thread.
     */
    private fun onIoThread(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            val outcome = runCatching(work)
            activity.runOnUiThread {
                outcome
                    // Unit marks a void method (writeDocument); the standard
                    // codec cannot encode kotlin.Unit, so answer null.
                    .onSuccess { result.success(if (it === Unit) null else it) }
                    .onFailure { error ->
                        when (error) {
                            is Unavailable ->
                                result.error(UNAVAILABLE, error.message, null)
                            else ->
                                result.error(FAILED, error.message, error.toString())
                        }
                    }
            }
        }
    }

    fun dispose() {
        io.shutdown()
    }
}
