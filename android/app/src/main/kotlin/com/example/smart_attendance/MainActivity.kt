package com.example.smart_attendance

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterFragmentActivity() {
    private val emailChannel = "smart_attendance/report_email"
    private val exportChannel = "smart_attendance/report_export"
    private val exportRequestCode = 4172
    private var pendingExport: Pair<ByteArray, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportChannel).setMethodCallHandler { call, result ->
            if (call.method != "saveFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingExport != null) {
                result.error("busy", "An export is already open", null)
                return@setMethodCallHandler
            }
            val fileName = call.argument<String>("fileName")
            val bytes = call.argument<ByteArray>("bytes")
            val validName = fileName != null && fileName.matches(Regex("[A-Za-z0-9._-]+\\.(pdf|zip)"))
            val validPdf = fileName?.endsWith(".pdf") == true && bytes?.take(5) == "%PDF-".toByteArray().toList()
            val validZip = fileName?.endsWith(".zip") == true && bytes?.take(4) == listOf(0x50.toByte(), 0x4b.toByte(), 0x03.toByte(), 0x04.toByte())
            if (!validName || bytes == null || !(validPdf || validZip)) {
                result.error("invalid_arguments", "Invalid report file", null)
                return@setMethodCallHandler
            }
            try {
                pendingExport = bytes to result
                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (validPdf) "application/pdf" else "application/zip"
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }, exportRequestCode)
            } catch (error: Exception) {
                pendingExport = null
                result.error("file_error", "Cannot open save location", null)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, emailChannel).setMethodCallHandler { call, result ->
            if (call.method != "openDraft") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val recipient = call.argument<String>("recipient")
            val subject = call.argument<String>("subject")
            val body = call.argument<String>("body")
            val fileName = call.argument<String>("fileName")
            val pdfBytes = call.argument<ByteArray>("pdfBytes")
            if (recipient.isNullOrBlank() || subject.isNullOrBlank() || body.isNullOrBlank() ||
                fileName == null || !fileName.matches(Regex("[A-Za-z0-9._-]+\\.pdf")) ||
                pdfBytes == null || pdfBytes.size < 5 ||
                !pdfBytes.copyOfRange(0, 5).contentEquals("%PDF-".toByteArray())) {
                result.error("invalid_arguments", "Invalid email draft or PDF", null)
                return@setMethodCallHandler
            }

            Thread {
                val uri = try {
                    val directory = File(cacheDir, "report_email_attachments")
                    if (!directory.exists() && !directory.mkdirs()) throw IOException("Cannot create attachment directory")
                    val attachment = File(directory, fileName)
                    attachment.writeBytes(pdfBytes)
                    FileProvider.getUriForFile(this, "$packageName.report_files", attachment)
                } catch (error: Exception) {
                    runOnUiThread { result.error("file_error", "Cannot prepare PDF attachment", null) }
                    return@Thread
                }
                runOnUiThread {
                    try {
                        openEmailChooser(recipient, subject, body, fileName, uri)
                        result.success(null)
                    } catch (error: NoEmailAppException) {
                        result.error("no_email_app", "No email app available", null)
                    } catch (error: AttachmentUnsupportedException) {
                        result.error("attachment_unsupported", "Email apps cannot accept PDF attachment", null)
                    } catch (error: ActivityNotFoundException) {
                        result.error("no_email_app", "No email app available", null)
                    } catch (error: SecurityException) {
                        result.error("permission_denied", "Attachment access denied", null)
                    } catch (error: Exception) {
                        result.error("email_intent_error", "Cannot open email draft", null)
                    }
                }
            }.start()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportRequestCode) return
        val pending = pendingExport ?: return
        pendingExport = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pending.second.success(false)
            return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w")?.use { it.write(pending.first) }
                    ?: throw IOException("Cannot write report")
                runOnUiThread { pending.second.success(true) }
            } catch (error: Exception) {
                runOnUiThread { pending.second.error("file_error", "Cannot save report", null) }
            }
        }.start()
    }

    private fun openEmailChooser(recipient: String, subject: String, body: String, fileName: String, uri: Uri) {
        val emailQuery = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        val emailPackages = packageManager.queryIntentActivities(emailQuery, PackageManager.MATCH_DEFAULT_ONLY)
            .map { it.activityInfo.packageName }
            .toSet()
        if (emailPackages.isEmpty()) throw NoEmailAppException()

        val attachmentQuery = Intent(Intent.ACTION_SEND).apply { type = "application/pdf" }
        val targets = packageManager.queryIntentActivities(attachmentQuery, PackageManager.MATCH_DEFAULT_ONLY)
            .filter { emailPackages.contains(it.activityInfo.packageName) }
            .distinctBy { it.activityInfo.packageName to it.activityInfo.name }
            .map { handler ->
                Intent(Intent.ACTION_SEND).apply {
                    type = "application/pdf"
                    setClassName(handler.activityInfo.packageName, handler.activityInfo.name)
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(recipient))
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, body)
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newUri(contentResolver, fileName, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
        if (targets.isEmpty()) throw AttachmentUnsupportedException()

        val chooser = Intent.createChooser(targets.first(), "Chọn ứng dụng email").apply {
            if (targets.size > 1) putExtra(Intent.EXTRA_INITIAL_INTENTS, targets.drop(1).toTypedArray())
            clipData = ClipData.newUri(contentResolver, fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(chooser)
    }

    private class NoEmailAppException : Exception()
    private class AttachmentUnsupportedException : Exception()
}
