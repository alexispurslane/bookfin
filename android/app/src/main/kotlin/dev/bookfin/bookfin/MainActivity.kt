package dev.bookfin.bookfin

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// The Activity owns no channel and no listener. Under audio_service one
// cached Flutter engine outlives each Activity, and Dart listens to an event
// channel once for the life of that engine. A listener that an Activity
// owned ended with the Activity, and Dart then got no more events. So each
// channel belongs to a plugin of the engine (HostChannels.kt, OcrChannel.kt).
// Add a new channel to one of those plugins, never here.
class MainActivity : AudioServiceActivity() {
    // Runs for each new Activity, also with the cached engine of an earlier
    // Activity. So it adds each plugin only to an engine that lacks it.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(OcrPlugin::class.java)) {
            flutterEngine.plugins.add(OcrPlugin())
        }
        if (!flutterEngine.plugins.has(HostPlugin::class.java)) {
            flutterEngine.plugins.add(HostPlugin())
        }
    }
}
