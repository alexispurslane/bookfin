package dev.bookfin.bookfin

import android.content.Context
import android.os.Handler
import android.os.Looper
import dev.bookfin.bookfin.ocr.OcrWorker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CompletableFuture

class OcrChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bookfin/ocr")
    private val main = Handler(Looper.getMainLooper())
    private var attached = true
    private var worker: OcrWorker? = null
    private var draining = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Runs the layout pass on the page and gives its layout
                // record (see native/ocr/bookfin_ocr.c). The engine keeps
                // the page for a recognize without a page.
                "layout" -> {
                    val bytes = call.argument<ByteArray>("bgra")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    if (bytes == null || width == null || height == null) refuse(result)
                    else run(result) { it.layout(bytes, width, height) }
                }
                // Recognizes the page and gives its hOCR. Without a page, it
                // recognizes the page that the last layout pass kept.
                "recognize" -> {
                    if (call.arguments == null) run(result) { it.recognizeKept() }
                    else {
                        val bytes = call.argument<ByteArray>("bgra")
                        val width = call.argument<Int>("width")
                        val height = call.argument<Int>("height")
                        if (bytes == null || width == null || height == null) refuse(result)
                        else run(result) { it.recognize(bytes, width, height) }
                    }
                }
                "close" -> {
                    val owner = worker
                    if (owner == null) result.success(null)
                    else {
                        draining = true
                        owner.close().whenComplete { _, error ->
                            main.post {
                                if (worker === owner) worker = null
                                draining = false
                                if (attached) {
                                    if (error == null) result.success(null)
                                    else result.error("recognition", "Recognition did not close safely. Restart Bookfin.", null)
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun refuse(result: MethodChannel.Result) =
        result.error("recognition", "Recognition is draining or has no valid page.", null)

    private fun <T> run(result: MethodChannel.Result, operation: (OcrWorker) -> CompletableFuture<T>) {
        if (draining) return refuse(result)
        val owner = worker ?: OcrWorker { TesseractEngine(context) }.also { worker = it }
        operation(owner).whenComplete { value, error ->
            main.post {
                if (attached) {
                    if (error == null) result.success(value)
                    else if (error is Error || owner.requiresRestart()) result.error("recognition-fatal", "English recognition cannot continue safely. Restart Bookfin.", null)
                    else result.error("recognition", "English recognition failed. The original page is available.", null)
                }
            }
        }
    }

    fun detach() {
        attached = false
        channel.setMethodCallHandler(null)
        worker?.close()
    }
}

/** Tesseract's C API, through libbookfin_ocr.so (native/ocr/bookfin_ocr.c). */
private object TesseractC {
    init { System.loadLibrary("bookfin_ocr") }
    external fun create(tessdata: String): Long
    external fun setImage(handle: Long, gray: ByteArray, width: Int, height: Int)
    external fun layout(handle: Long, width: Int, height: Int): IntArray
    external fun recognize(handle: Long): String?
    external fun clear(handle: Long)
    external fun destroy(handle: Long)
}

/**
 * The one Tesseract handle of the worker, with the bundled English model.
 * After a failure the worker closes the engine, which frees its page.
 */
private class TesseractEngine(context: Context) : OcrWorker.Engine {
    private val handle: Long

    /** Whether the page of the last layout pass waits for [recognizeKept]. */
    private var kept = false

    init {
        val directory = File(context.filesDir, "bookfin-ocr-engine")
        val models = File(directory, "tessdata")
        if (!models.isDirectory && !models.mkdirs()) throw java.io.IOException("Cannot prepare bundled English model.")
        val model = File(models, "eng.traineddata")
        val expected = "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"
        fun hash(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
        if (!model.isFile || hash(model) != expected) {
            val pending = File(models, "eng.pending")
            try {
                context.assets.open("bookfin-ocr/eng.traineddata").use { input ->
                    pending.outputStream().use { output -> input.copyTo(output) }
                }
                if (pending.length() != 4113088L || hash(pending) != expected || !pending.renameTo(model)) {
                    throw java.io.IOException("Bundled English model failed verification.")
                }
            } finally {
                pending.delete()
            }
        }
        handle = TesseractC.create(models.absolutePath)
        if (handle == 0L) throw java.io.IOException("Bundled English model initialization failed.")
    }

    override fun layout(bgra: ByteArray, width: Int, height: Int): IntArray {
        kept = false
        TesseractC.setImage(handle, gray(bgra, width, height), width, height)
        val record = TesseractC.layout(handle, width, height)
        kept = true
        return record
    }

    override fun recognize(bgra: ByteArray, width: Int, height: Int): String {
        kept = false
        TesseractC.setImage(handle, gray(bgra, width, height), width, height)
        return recognizePage()
    }

    override fun recognizeKept(): String {
        if (!kept) throw IllegalStateException("No layout pass kept a page to recognize.")
        kept = false
        return recognizePage()
    }

    private fun recognizePage(): String {
        val hocr = TesseractC.recognize(handle) ?: ""
        TesseractC.clear(handle)
        return hocr
    }

    override fun close() = TesseractC.destroy(handle)
}

/** The 8-bit gray of the page [bgra], with transparent pixels on white. */
private fun gray(bgra: ByteArray, width: Int, height: Int): ByteArray {
    val gray = ByteArray(width * height)
    for (pixel in gray.indices) {
        val offset = pixel * 4
        val alpha = bgra[offset + 3].toInt() and 255
        val luminance = ((bgra[offset + 2].toInt() and 255) * 77 +
            (bgra[offset + 1].toInt() and 255) * 150 +
            (bgra[offset].toInt() and 255) * 29) shr 8
        gray[pixel] = ((luminance * alpha + 255 * (255 - alpha)) / 255).toByte()
    }
    return gray
}
