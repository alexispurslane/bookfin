// Tool code for the boo-snng speech prototype, not part of Bookfin.
package dev.bookfin.speech_probe

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Debug
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        // Makes Android create the external files folder, owned by this app,
        // before the plan and the models are pushed into it.
        getExternalFilesDir(null)
        MethodChannel(engine.dartExecutor.binaryMessenger, "speech_probe").setMethodCallHandler { call, result ->
            if (call.method != "decode") return@setMethodCallHandler result.notImplemented()
            val source = call.argument<String>("source")!!
            val startMs = call.argument<Number>("startMs")!!.toLong()
            val lengthMs = call.argument<Number>("lengthMs")!!.toLong()
            worker.execute {
                try {
                    val out = decode(source, startMs, lengthMs)
                    runOnUiThread { result.success(out) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("decode", e.toString(), null) }
                }
            }
        }
    }

    /**
     * [lengthMs] of [source], a file path or an http URL, from [startMs], as
     * 16 kHz mono float samples in little-endian bytes, with the time of
     * each step. Android's own decoder (MediaCodec) decodes, as a player
     * would. For a URL, MediaExtractor reads only the byte ranges it needs.
     */
    private fun decode(source: String, startMs: Long, lengthMs: Long): Map<String, Any> {
        val wall0 = System.nanoTime()
        val cpu0 = Debug.threadCpuTimeNanos()
        val extractor = MediaExtractor()
        if (source.startsWith("http")) extractor.setDataSource(source, emptyMap()) else extractor.setDataSource(source)
        val opened = System.nanoTime()
        val track = (0 until extractor.trackCount).first {
            extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)!!.startsWith("audio/")
        }
        extractor.selectTrack(track)
        val format = extractor.getTrackFormat(track)
        extractor.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        val sought = System.nanoTime()
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val startUs = startMs * 1000
        val endUs = (startMs + lengthMs) * 1000
        var mono = FloatArray(((lengthMs + 1000) * rate / 1000).toInt())
        var count = 0
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        while (!outputDone) {
            if (!inputDone) {
                // Short waits: the decoder answers within microseconds, and
                // a long wait per frame would cost 10 ms for each of the
                // window's 38 frames per second.
                val i = codec.dequeueInputBuffer(500)
                if (i >= 0) {
                    val n = extractor.readSampleData(codec.getInputBuffer(i)!!, 0)
                    if (n < 0 || extractor.sampleTime > endUs) {
                        codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(i, 0, n, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val o = codec.dequeueOutputBuffer(info, if (inputDone) 5_000 else 500)
            if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                rate = codec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = codec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else if (o >= 0) {
                val buffer: ByteBuffer = codec.getOutputBuffer(o)!!
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                val shorts = buffer.order(ByteOrder.nativeOrder()).asShortBuffer()
                val frames = info.size / 2 / channels
                for (f in 0 until frames) {
                    val us = info.presentationTimeUs + f * 1_000_000L / rate
                    if (us < startUs) continue
                    if (us >= endUs) break
                    var sum = 0f
                    for (c in 0 until channels) sum += shorts.get(f * channels + c)
                    if (count == mono.size) mono = mono.copyOf(mono.size * 2)
                    mono[count++] = sum / channels / 32768f
                }
                codec.releaseOutputBuffer(o, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
            }
        }
        codec.stop()
        codec.release()
        extractor.release()
        // Linear resampling to 16 kHz.
        val outCount = (count.toLong() * 16000 / rate).toInt()
        val bytes = ByteBuffer.allocate(outCount * 4).order(ByteOrder.LITTLE_ENDIAN)
        for (k in 0 until outCount) {
            val x = k.toDouble() * rate / 16000
            val i = x.toInt()
            val a = mono[minOf(i, count - 1)]
            val b = mono[minOf(i + 1, count - 1)]
            bytes.putFloat((a + (b - a) * (x - i)).toFloat())
        }
        val done = System.nanoTime()
        return mapOf(
            "pcm" to bytes.array(),
            "openMs" to (opened - wall0) / 1_000_000.0,
            "seekMs" to (sought - opened) / 1_000_000.0,
            "decodeMs" to (done - sought) / 1_000_000.0,
            "wallMs" to (done - wall0) / 1_000_000.0,
            "cpuMs" to (Debug.threadCpuTimeNanos() - cpu0) / 1_000_000.0,
            "rate" to rate,
            "channels" to channels,
        )
    }
}
