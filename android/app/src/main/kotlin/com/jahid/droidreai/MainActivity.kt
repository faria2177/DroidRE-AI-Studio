package com.jahid.droidreai

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

/** Writes bounded recovered source to a user-selected Android document tree. */
class MainActivity : FlutterActivity() {
    private val channelName = "com.jahid.droidreai/recovery_folder"
    private val requestTree = 2164
    private val requestSource = 2165
    private var sourceId: String? = null
    private var pendingSource: MethodChannel.Result? = null
    private val prefsName = "droidre_source_recovery"
    private val treeKey = "tree_uri"
    private val displayKey = "tree_label"
    private val maxZipBytes = 24 * 1024 * 1024
    private val maxUnpackedBytes = 48L * 1024 * 1024
    private val maxFiles = 900
    private val maxPreview = 64 * 1024
    private val workers = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingSelection: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "chooseDirectory" -> chooseDirectory(result)
                    "copySourceFolder" -> chooseSourceFolder(call, result)
                    "selectedDirectory" -> result.success(
                        selectedTree()?.let { treeInfo(it) }
                    )
                    "clearDirectory" -> {
                        val previous = selectedTree()
                        if (previous != null) {
                            try {
                                contentResolver.releasePersistableUriPermission(
                                    previous, Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                                )
                            } catch (_: Exception) { }
                        }
                        getSharedPreferences(prefsName, MODE_PRIVATE).edit()
                            .clear().apply()
                        result.success(null)
                    }
                    "writeRecoveryZip", "listRecoveredFiles", "readRecoveredFile" -> {
                        workers.execute {
                            try {
                                val payload: Any? = when (call.method) {
                                    "writeRecoveryZip" -> writeRecoveryZip(call)
                                    "listRecoveredFiles" -> listRecoveredFiles(call)
                                    else -> readRecoveredFile(call)
                                }
                                main.post { result.success(payload) }
                            } catch (error: Exception) {
                                main.post {
                                    result.error("RECOVERY_STORAGE_ERROR",
                                        error.message ?: "Storage operation failed", null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun chooseSourceFolder(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id == null || !id.matches(Regex("[0-9]{1,24}")) ||
            pendingSource != null || pendingSelection != null) {
            result.error("SOURCE_PICKER", "Invalid request or another picker is open", null)
            return
        }
        sourceId = id
        pendingSource = result
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }, requestSource)
        } catch (e: Exception) {
            sourceId = null
            pendingSource = null
            result.error("SOURCE_PICKER", e.message, null)
        }
    }

    private fun copySourceTree(tree: Uri, id: String): String {
        val base = File(filesDir, "source-projects").apply { mkdirs() }
        val output = File(base, id)
        if (!output.mkdir()) throw IOException("Source copy already exists")
        val seen = HashSet<String>()
        val visited = HashSet<String>()
        var entries = 0
        var files = 0
        var total = 0L
        val ignored = setOf(".git", ".gradle", ".dart_tool", ".idea", "build",
            "node_modules", ".cxx", "local.properties", "key.properties")
        fun skip(name: String): Boolean {
            val n = name.lowercase(Locale.ROOT)
            return n in ignored || n == ".env" || n.startsWith(".env.") ||
                listOf(".jks", ".keystore", ".p12", ".pem", ".key").any { n.endsWith(it) }
        }
        fun visit(parent: Uri, prefix: String, depth: Int) {
            if (depth > 31 || !visited.add(DocumentsContract.getDocumentId(parent))) {
                throw IOException("Source tree depth or repeated directory exceeded")
            }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree, DocumentsContract.getDocumentId(parent))
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE)
            (contentResolver.query(children, columns, null, null, null)
                ?: throw IOException("Cannot read source directory")).use { cursor ->
                while (cursor.moveToNext()) {
                    if (++entries > 16000) throw IOException("Too many source entries")
                    val name = cursor.getString(1) ?: throw IOException("Missing source name")
                    if (name.isEmpty() || name == "." || name == ".." || name.length > 150 ||
                        name.endsWith(".") || name.endsWith(" ") ||
                        name.any { it.code < 32 || it in "/\\\\<>:\"|?*" } ||
                        Regex("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\\\\.|$)", RegexOption.IGNORE_CASE).containsMatchIn(name)) {
                        throw IOException("Unsafe source path")
                    }
                    if (skip(name)) continue
                    val relative = if (prefix.isEmpty()) name else "$prefix/$name"
                    if (relative.length > 512 || !seen.add(relative.lowercase(Locale.ROOT))) {
                        throw IOException("Long or conflicting source path")
                    }
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        visit(uri, relative, depth + 1)
                    } else {
                        if (++files > 8000) throw IOException("Too many source files")
                        val target = File(output, relative)
                        if (!target.canonicalPath.startsWith(output.canonicalPath + File.separator)) {
                            throw IOException("Source path escaped output")
                        }
                        target.parentFile?.mkdirs()
                        var copied = 0L
                        val buffer = ByteArray(32768)
                        (contentResolver.openInputStream(uri) ?: throw IOException("Cannot read $name")).use { input ->
                            target.outputStream().use { out ->
                                while (true) {
                                    val amount = input.read(buffer)
                                    if (amount < 0) break
                                    copied += amount
                                    total += amount
                                    if (copied > 24L * 1024 * 1024 || total > 128L * 1024 * 1024) {
                                        throw IOException("Source file/copy size limit exceeded")
                                    }
                                    out.write(buffer, 0, amount)
                                }
                            }
                        }
                    }
                }
            }
        }
        try {
            visit(rootDocument(tree), "", 0)
            return displayName(rootDocument(tree), tree)
        } catch (e: Exception) {
            output.deleteRecursively()
            throw e
        }
    }

    private fun chooseDirectory(result: MethodChannel.Result) {
        if (pendingSelection != null) {
            result.error("BUSY", "Folder selection is already in progress", null)
            return
        }
        pendingSelection = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
            startActivityForResult(intent, requestTree)
        } catch (error: Exception) {
            pendingSelection = null
            result.error("FOLDER_PICKER", error.message, null)
        }
    }

    @Deprecated("Platform activity result bridge for Android document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestSource) {
            val waiting = pendingSource ?: return
            val id = sourceId ?: return
            pendingSource = null
            sourceId = null
            val tree = data?.data
            if (resultCode != Activity.RESULT_OK || tree == null) {
                waiting.success(null)
                return
            }
            workers.execute {
                try {
                    val name = copySourceTree(tree, id)
                    main.post { waiting.success(name) }
                } catch (e: Exception) {
                    main.post { waiting.error("SOURCE_COPY", e.message, null) }
                }
            }
            return
        }
        if (requestCode != requestTree) return
        val waiting = pendingSelection ?: return
        pendingSelection = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            waiting.success(null)
            return
        }
        val chosen = data.data!!
        try {
            val documentPath = DocumentsContract.getTreeDocumentId(chosen)
                .replace(':', '/').replace('\\', '/')
            if (documentPath.split('/').any {
                    it.equals("Android", ignoreCase = true)
                }) {
                throw SecurityException(
                    "Choose a destination outside the Android system folder"
                )
            }
            if ((data.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION) == 0) {
                throw SecurityException("Selected folder is not writable")
            }
            val flags = data.flags and (
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(chosen, flags)
            val label = displayName(rootDocument(chosen), chosen)
            getSharedPreferences(prefsName, MODE_PRIVATE).edit()
                .putString(treeKey, chosen.toString())
                .putString(displayKey, label)
                .apply()
            waiting.success(mapOf("uri" to chosen.toString(), "label" to label))
        } catch (error: Exception) {
            waiting.error("FOLDER_PERMISSION", error.message, null)
        }
    }

    private fun selectedTree(): Uri? {
        val value = getSharedPreferences(prefsName, MODE_PRIVATE)
            .getString(treeKey, null) ?: return null
        val uri = Uri.parse(value)
        val writable = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isWritePermission
        }
        return if (writable) uri else null
    }

    private fun treeInfo(tree: Uri): Map<String, String> {
        val label = getSharedPreferences(prefsName, MODE_PRIVATE)
            .getString(displayKey, null) ?: "Selected folder"
        return mapOf("uri" to tree.toString(), "label" to label)
    }

    private fun rootDocument(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree))

    private fun displayName(document: Uri, tree: Uri): String {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        return contentResolver.query(document, projection, null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            ?: DocumentsContract.getTreeDocumentId(tree).substringAfterLast(':')
    }

    private fun safePart(value: String, maxLength: Int = 55): String =
        value.replace(Regex("[^A-Za-z0-9_-]"), "_")
            .take(maxLength).ifEmpty { "unknown" }

    private fun safePath(path: String): List<String> {
        if (path.startsWith('/') || path.contains('\\') ||
            path.contains('\u0000') || path.length > 1200) {
            throw IOException("Invalid source file path")
        }
        val segments = path.split('/')
        if (segments.size > 25 || segments.any {
                it.isEmpty() || it == "." || it == ".." ||
                    it.contains(':') || it.length > 75
            }) throw IOException("Unsafe source file path")
        return segments
    }

    private fun findChild(tree: Uri, parent: Uri, name: String): Pair<Uri, String>? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getDocumentId(parent))
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE)
        return contentResolver.query(children, projection, null, null, null)
            ?.use { c ->
                while (c.moveToNext()) {
                    if (c.getString(1) == name) {
                        return@use DocumentsContract.buildDocumentUriUsingTree(
                            tree, c.getString(0)) to c.getString(2)
                    }
                }
                null
            }
    }

    private fun ensureDirectory(tree: Uri, parent: Uri, name: String): Uri {
        val existing = findChild(tree, parent, name)
        if (existing != null) {
            if (existing.second != DocumentsContract.Document.MIME_TYPE_DIR) {
                throw IOException("Output name conflict: $name")
            }
            return existing.first
        }
        return DocumentsContract.createDocument(
            contentResolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, name)
            ?: throw IOException("Cannot create folder: $name")
    }

    private fun writeRecoveryZip(call: MethodCall): Map<String, Any> {
        val tree = selectedTree() ?: throw IOException("Choose a writable folder")
        val zipBytes = call.argument<ByteArray>("zipBytes")
            ?: throw IOException("Source preview ZIP is missing")
        if (zipBytes.isEmpty() || zipBytes.size > maxZipBytes) {
            throw IOException("Source ZIP exceeds 24 MiB")
        }
        val name = "DroidRE_" + safePart(
            call.argument<String>("packageName") ?: "") + "_" +
            safePart(call.argument<String>("projectId") ?: "")
        val root = rootDocument(tree)
        if (findChild(tree, root, name) != null) {
            throw IOException("Project folder already exists. No files overwritten.")
        }
        val project = DocumentsContract.createDocument(
            contentResolver, root, DocumentsContract.Document.MIME_TYPE_DIR, name)
            ?: throw IOException("Cannot create project folder")
        val directories = hashMapOf("" to project)
        val seen = HashSet<String>()
        val buffer = ByteArray(32768)
        var total = 0L
        var files = 0
        try {
            ZipInputStream(ByteArrayInputStream(zipBytes)).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    if (entry.isDirectory) {
                        zip.closeEntry()
                        continue
                    }
                    val parts = safePath(entry.name)
                    if (!seen.add(entry.name) || ++files > maxFiles) {
                        throw IOException("Duplicate or excessive source entries")
                    }
                    var parent = project
                    for (i in 0 until parts.lastIndex) {
                        val key = parts.take(i + 1).joinToString("/")
                        parent = directories.getOrPut(key) {
                            ensureDirectory(tree, parent, parts[i])
                        }
                    }
                    val fileName = parts.last()
                    if (findChild(tree, parent, fileName) != null) {
                        throw IOException("Duplicate output file")
                    }
                    val mimeType = when {
                        fileName.endsWith(".json") -> "application/json"
                        fileName.endsWith(".xml") -> "text/xml"
                        fileName.endsWith(".txt") || fileName.endsWith(".md") ->
                            "text/plain"
                        else -> "application/octet-stream"
                    }
                    val created = DocumentsContract.createDocument(
                        contentResolver, parent, mimeType, fileName)
                        ?: throw IOException("Cannot create $fileName")
                    (contentResolver.openOutputStream(created, "w")
                        ?: throw IOException("Cannot write $fileName")).use { output ->
                        while (true) {
                            val amount = zip.read(buffer)
                            if (amount < 0) break
                            total += amount
                            if (total > maxUnpackedBytes) {
                                throw IOException("Decoded ZIP exceeds 48 MiB")
                            }
                            output.write(buffer, 0, amount)
                        }
                    }
                    zip.closeEntry()
                }
            }
            return mapOf(
                "folderUri" to project.toString(),
                "folderLabel" to (
                    (treeInfo(tree)["label"] ?: "Selected folder") + "/" + name),
                "filesWritten" to files,
                "bytesWritten" to total)
        } catch (error: Exception) {
            try {
                DocumentsContract.deleteDocument(contentResolver, project)
            } catch (_: Exception) { }
            throw error
        }
    }

    private fun projectFrom(call: MethodCall): Pair<Uri, Uri> {
        val requested = call.argument<String>("folderUri")
            ?: throw IOException("Folder URI missing")
        val uri = Uri.parse(requested)
        if (!DocumentsContract.isDocumentUri(this, uri)) {
            throw SecurityException("Invalid recovered folder URI")
        }
        // A user may choose a new destination after generating an older
        // project. Each previously granted tree remains browsable until
        // Android or the user explicitly revokes its permission.
        val tree = contentResolver.persistedUriPermissions.firstOrNull {
            it.isReadPermission &&
                it.uri.authority == uri.authority &&
                DocumentsContract.getTreeDocumentId(it.uri) ==
                    DocumentsContract.getTreeDocumentId(uri)
        }?.uri ?: throw IOException("Access to this source folder was revoked")
        return tree to uri
    }

    private fun listRecoveredFiles(call: MethodCall): List<String> {
        val (tree, project) = projectFrom(call)
        val result = ArrayList<String>()
        fun visit(parent: Uri, prefix: String, depth: Int) {
            if (depth >= 25 || result.size >= maxFiles) return
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree, DocumentsContract.getDocumentId(parent))
            val columns = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE)
            contentResolver.query(children, columns, null, null, null)
                ?.use { c ->
                    while (c.moveToNext() && result.size < maxFiles) {
                        val label = c.getString(1) ?: continue
                        if (label == "." || label == ".." ||
                            label.contains('/') || label.contains('\\')) continue
                        val uri = DocumentsContract.buildDocumentUriUsingTree(
                            tree, c.getString(0))
                        val path = if (prefix.isEmpty()) label else "$prefix/$label"
                        if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                            visit(uri, path, depth + 1)
                        } else {
                            result.add(path)
                        }
                    }
                }
        }
        visit(project, "", 0)
        result.sort()
        return result
    }

    private fun readRecoveredFile(call: MethodCall): String {
        val (tree, project) = projectFrom(call)
        val path = call.argument<String>("path")
            ?: throw IOException("Missing preview file")
        val parts = safePath(path)
        var current = project
        for ((index, part) in parts.withIndex()) {
            val found = findChild(tree, current, part)
                ?: throw IOException("File not found")
            if (index != parts.lastIndex &&
                found.second != DocumentsContract.Document.MIME_TYPE_DIR) {
                throw IOException("Not a folder")
            }
            if (index == parts.lastIndex &&
                found.second == DocumentsContract.Document.MIME_TYPE_DIR) {
                throw IOException("Cannot preview a directory")
            }
            current = found.first
        }
        val bytes = ByteArrayOutputStream()
        (contentResolver.openInputStream(current)
            ?: throw IOException("Cannot read file")).use { stream ->
            val buffer = ByteArray(4096)
            while (true) {
                val size = stream.read(buffer)
                if (size < 0) break
                if (bytes.size() + size > maxPreview) {
                    return "Preview limited to 64 KiB. Open in File Manager."
                }
                bytes.write(buffer, 0, size)
            }
        }
        val data = bytes.toByteArray()
        return if (path.endsWith(".bin")) {
            "Binary: " + data.size + " bytes\n" +
                data.take(256).joinToString(" ") {
                    "%02x".format(it.toInt() and 255)
                }
        } else String(data, Charsets.UTF_8)
    }

    override fun onDestroy() {
        workers.shutdown()
        super.onDestroy()
    }
}
