package dev.bookfin.bookfin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Gives one Flutter engine its host channels. Dart talks to the host for
// the life of the engine, and it listens to each event channel once. Under
// audio_service the engine outlives an Activity. So the channels and their
// listeners live from the attach of the engine to its detach, and no
// Activity owns any of them. MainActivity adds this plugin once to each
// engine.
class HostPlugin : FlutterPlugin {
    private var channels: HostChannels? = null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channels = HostChannels(binding.applicationContext, binding.binaryMessenger)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channels?.detach()
        channels = null
    }
}

// The host side of every Bookfin channel except recognition (OcrChannel.kt):
// - `bookfin/media` and `bookfin/media-network`, the media host contract of
//   lib/downloads/platform_io.dart.
// - `bookfin/speech`, where the speech model lies (lib/speech/speech.dart).
// - `bookfin/device`, the device name and the installed build
//   (lib/sync/device.dart).
// - `bookfin/power`, whether the fill of heard windows is allowed
//   (lib/speech/platform_io.dart).
// `context` is the application's context. An Activity's context ends with
// the Activity, before the engine does.
class HostChannels(private val context: Context, messenger: BinaryMessenger) {
    private val media = MethodChannel(messenger, "bookfin/media")
    private val speech = MethodChannel(messenger, "bookfin/speech")
    private val device = MethodChannel(messenger, "bookfin/device")
    private val power = EventChannel(messenger, "bookfin/power")
    private val network = EventChannel(messenger, "bookfin/media-network")
    private val powerEvents = PowerEvents(context)
    private val networkEvents = NetworkEvents(context)

    init {
        media.setMethodCallHandler { call, result ->
            when (call.method) {
                "storage" -> result.success(mapOf("path" to File(context.filesDir, "bookfin-media").absolutePath))
                "freeBytes" -> result.success(StatFs(context.filesDir.absolutePath).availableBytes)
                "network" -> result.success(networkEvents.current())
                else -> result.notImplemented()
            }
        }
        // Where the speech model lies: the APK stores it uncompressed
        // (tool/reader/speech_package.py), so the speech library reads its
        // bytes in place, at their offset in the APK.
        speech.setMethodCallHandler { call, result ->
            when (call.method) {
                "model" -> try {
                    context.assets.openFd("bookfin-speech/tiny.en-q5_1.ggml").use { model ->
                        result.success(mapOf(
                            "path" to context.applicationInfo.sourceDir,
                            "offset" to model.startOffset,
                            "length" to model.length,
                        ))
                    }
                } catch (_: java.io.IOException) {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        device.setMethodCallHandler { call, result ->
            when (call.method) {
                "name" -> result.success(deviceName())
                "build" -> result.success(installedBuild())
                else -> result.notImplemented()
            }
        }
        power.setStreamHandler(powerEvents)
        network.setStreamHandler(networkEvents)
    }

    // Removes every handler and listener. The engine calls this once, when
    // it ends.
    fun detach() {
        media.setMethodCallHandler(null)
        speech.setMethodCallHandler(null)
        device.setMethodCallHandler(null)
        power.setStreamHandler(null)
        network.setStreamHandler(null)
        powerEvents.onCancel(null)
        networkEvents.onCancel(null)
    }

    // The name that the owner gave this device in the system settings, or
    // else its model name. Reading either needs no permission.
    private fun deviceName(): String {
        val named = try {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        } catch (_: SecurityException) {
            null
        }
        return named?.takeIf { it.isNotBlank() } ?: Build.MODEL
    }

    // The facts that decide how Flutter's text engine lays out a book: when
    // this package was installed or updated, which changes with every APK
    // install, and the system's build, which holds the fallback fonts.
    private fun installedBuild(): Map<String, Any> {
        val packages = context.packageManager
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packages.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packages.getPackageInfo(context.packageName, 0)
        }
        return mapOf("installTime" to info.lastUpdateTime, "system" to Build.FINGERPRINT)
    }
}

// The stream of `bookfin/power`: whether the phone is on power and whether
// battery saver is on. It sends the state when Dart starts to listen and at
// each change. The battery's sticky broadcast holds the power source, so
// reading it needs no permission.
private class PowerEvents(private val context: Context) : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null

    private fun power(): Map<String, Boolean> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val saver = (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode
        return mapOf("charging" to (plugged != 0), "saver" to saver)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        val made = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) = events.success(power())
        }
        receiver = made
        context.registerReceiver(made, IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        })
        events.success(power())
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
    }
}

// The stream of `bookfin/media-network`: the kind of the active network, by
// the name of a value of Dart's MediaNetwork. It sends the kind when Dart
// starts to listen and at each change of the default network.
private class NetworkEvents(context: Context) : EventChannel.StreamHandler {
    private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    // Android reports network changes on its own thread. An event sink
    // accepts events on the main thread only.
    private val main = Handler(Looper.getMainLooper())
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var events: EventChannel.EventSink? = null

    // The kind of the active network now. A network that Android did not
    // validate, a VPN and any other transport are "unknown", because the
    // host cannot tell whether their data is metered mobile data.
    fun current(): String {
        val network = connectivity.activeNetwork ?: return "disconnected"
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return "unknown"
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
            !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) return "unknown"
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return "unknown"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "unknown"
        }
    }

    private fun publish() {
        main.post { events?.success(current()) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        this.events = events
        val made = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = publish()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
            // A lost network first sends "unknown", so that Dart does not
            // keep the lost kind while Android chooses the next network.
            override fun onLost(network: Network) {
                main.post {
                    this@NetworkEvents.events?.success("unknown")
                    publish()
                }
            }
        }
        callback = made
        connectivity.registerDefaultNetworkCallback(made)
        publish()
    }

    override fun onCancel(arguments: Any?) {
        callback?.let { connectivity.unregisterNetworkCallback(it) }
        callback = null
        events = null
    }
}
