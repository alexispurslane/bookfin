package dev.bookfin.bookfin

import io.flutter.embedding.engine.plugins.FlutterPlugin

// Gives one Flutter engine every Bookfin host channel: the media, speech,
// device and power channels (HostChannels.kt) and recognition
// (OcrChannel.kt). Flutter's generated plugin registrant adds this plugin to
// each engine that it makes, whoever makes it: an Activity, or the audio
// service that a media button or the system's resume player starts before
// any Activity (t0-wedg). Dart talks to the host for the life of the
// engine, so the channels live from the attach of the engine to its detach,
// and no Activity owns any of them.
class BookfinHostPlugin : FlutterPlugin {
    private var host: HostChannels? = null
    private var ocr: OcrChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        host = HostChannels(binding.applicationContext, binding.binaryMessenger)
        ocr = OcrChannel(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        host?.detach()
        ocr?.detach()
        host = null
        ocr = null
    }
}
