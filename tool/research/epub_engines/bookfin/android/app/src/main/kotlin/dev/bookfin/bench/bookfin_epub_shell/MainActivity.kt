package dev.bookfin.bench.bookfin_epub_shell

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import dev.bookfin.bench.epub.ProbeEvidence
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var evidence: ProbeEvidence

    override fun configureFlutterEngine(engine: FlutterEngine) {
        evidence = ProbeEvidence(this)
        MethodChannel(engine.dartExecutor.binaryMessenger, "bookfin/device").setMethodCallHandler { call, result ->
            if (call.method == "build") {
                val info = packageManager.getPackageInfo(packageName, 0)
                result.success(mapOf("installTime" to info.lastUpdateTime, "system" to Build.FINGERPRINT))
            } else result.notImplemented()
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "epubbench/probe").setMethodCallHandler { call, result ->
            when (call.method) {
                "clock" -> result.success(SystemClock.elapsedRealtimeNanos())
                "configuration" -> worker.execute {
                    try {
                        val book = intent.data?.getQueryParameter("book") ?: "prose"
                        val manifest = assets.open("manifest.json").bufferedReader().use { it.readText() }
                        val specification = JSONObject(manifest).getJSONObject("books").getJSONObject(book)
                        val directory = File(filesDir, "fixture")
                        directory.mkdirs()
                        val original = File(directory, specification.getString("file"))
                        assets.open(specification.getString("file")).use { input ->
                            original.outputStream().use { output -> input.copyTo(output) }
                        }
                        runOnUiThread { result.success(mapOf("book" to book, "path" to original.absolutePath, "specification" to specification.toString())) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("FIXTURE", error.toString(), null) }
                    }
                }
                "capture" -> {
                    val metadata = JSONObject(call.arguments as String)
                    val left = metadata.getInt("left_px")
                    val top = metadata.getInt("top_px")
                    val rect = Rect(left, top, left + metadata.getInt("width_px"), top + metadata.getInt("height_px"))
                    evidence.capture(rect, metadata) { event -> result.success(event.toString()) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        worker.shutdown()
        if (::evidence.isInitialized) evidence.close()
        super.onDestroy()
    }
}
