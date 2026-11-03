package dev.bookfin.bookfin

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import dev.bookfin.bookfin.ocr.OcrWorker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.File
import java.security.MessageDigest

class OcrPlugin : FlutterPlugin {
    private var channel: OcrChannel? = null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = OcrChannel(binding.applicationContext, binding.binaryMessenger)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.detach()
        channel = null
    }
}

class OcrChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bookfin/ocr")
    private val main = Handler(Looper.getMainLooper())
    private var attached = true
    private var worker: OcrWorker? = null
    private var draining = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> {
                    val bytes = call.argument<ByteArray>("bgra")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    if (bytes == null || width == null || height == null || draining) {
                        result.error("recognition", "Recognition is draining or has no valid page.", null)
                    } else {
                        val owner = worker ?: OcrWorker { TesseractEngine(context) }.also { worker = it }
                        owner.recognize(bytes, width, height).whenComplete { text, error ->
                            main.post {
                                if (attached) {
                                    if (error == null) result.success(text)
                                    else result.error("recognition", "English recognition failed. The original page is available.", null)
                                }
                            }
                        }
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

    fun detach() {
        attached = false
        channel.setMethodCallHandler(null)
        worker?.close()
    }
}

private class TesseractEngine(context: Context) : OcrWorker.Engine {
    private val engine = TessBaseAPI()

    init {
        try {
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
            if (!engine.init(directory.absolutePath, "eng", TessBaseAPI.OEM_LSTM_ONLY)) {
                throw java.io.IOException("Bundled English model initialization failed.")
            }
            engine.setPageSegMode(3)
        } catch (error: Exception) {
            engine.recycle()
            throw error
        }
    }

    override fun recognize(bgra: ByteArray, width: Int, height: Int): String {
        val gray = ByteArray(width * height)
        for (pixel in gray.indices) {
            val offset = pixel * 4
            val alpha = bgra[offset + 3].toInt() and 255
            val luminance = ((bgra[offset + 2].toInt() and 255) * 77 +
                (bgra[offset + 1].toInt() and 255) * 150 +
                (bgra[offset].toInt() and 255) * 29) shr 8
            gray[pixel] = ((luminance * alpha + 255 * (255 - alpha)) / 255).toByte()
        }
        try {
            engine.setImage(gray, width, height, 1, width)
            return engine.getHOCRText(0) ?: ""
        } finally {
            engine.clear()
        }
    }

    override fun close() { engine.recycle() }
}
