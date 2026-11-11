package dev.bookfin.bookfin

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import java.io.File

class MainActivity : AudioServiceActivity() {
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkEvents: EventChannel.EventSink? = null
    private var powerReceiver: BroadcastReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val connectivity: ConnectivityManager
        get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private fun mediaNetwork(): String {
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

    // The name that the owner gave this device in the system settings, or
    // else its model name. Reading either needs no permission.
    private fun deviceName(): String {
        val named = try {
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        } catch (_: SecurityException) {
            null
        }
        return named?.takeIf { it.isNotBlank() } ?: Build.MODEL
    }

    // The facts that decide how Flutter's text engine lays out a book: when
    // this package was installed or updated, which changes with every APK
    // install, and the system's build, which holds the fallback fonts.
    private fun installedBuild(): Map<String, Any> {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
        return mapOf("installTime" to info.lastUpdateTime, "system" to Build.FINGERPRINT)
    }

    private fun publishNetwork() {
        mainHandler.post { networkEvents?.success(mediaNetwork()) }
    }

    // Whether the phone is on power and whether battery saver is on, for the
    // fill of heard windows (lib/speech/platform_io.dart). The battery's
    // sticky broadcast holds the power source, so reading it needs no
    // permission.
    private fun power(): Map<String, Boolean> {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val plugged = battery?.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val saver = (getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode
        return mapOf("charging" to (plugged != 0), "saver" to saver)
    }

    private fun stopPowerEvents() {
        powerReceiver?.let { unregisterReceiver(it) }
        powerReceiver = null
    }

    private fun stopNetworkEvents() {
        networkCallback?.let { connectivity.unregisterNetworkCallback(it) }
        networkCallback = null
        networkEvents = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(OcrPlugin::class.java)) {
            flutterEngine.plugins.add(OcrPlugin())
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bookfin/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "storage" -> result.success(mapOf("path" to File(filesDir, "bookfin-media").absolutePath))
                    "freeBytes" -> result.success(StatFs(filesDir.absolutePath).availableBytes)
                    "network" -> result.success(mediaNetwork())
                    else -> result.notImplemented()
                }
            }
        // Where the speech model lies: the APK stores it uncompressed
        // (tool/reader/speech_package.py), so the speech library reads its
        // bytes in place, at their offset in the APK.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bookfin/speech")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "model" -> try {
                        assets.openFd("bookfin-speech/tiny.en-q5_1.ggml").use { model ->
                            result.success(mapOf(
                                "path" to applicationInfo.sourceDir,
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bookfin/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "name" -> result.success(deviceName())
                    "build" -> result.success(installedBuild())
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "bookfin/power")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopPowerEvents()
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent) = events.success(power())
                    }
                    powerReceiver = receiver
                    registerReceiver(receiver, IntentFilter().apply {
                        addAction(Intent.ACTION_POWER_CONNECTED)
                        addAction(Intent.ACTION_POWER_DISCONNECTED)
                        addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
                    })
                    events.success(power())
                }
                override fun onCancel(arguments: Any?) = stopPowerEvents()
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "bookfin/media-network")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopNetworkEvents()
                    networkEvents = events
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) = publishNetwork()
                        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publishNetwork()
                        override fun onLost(network: Network) {
                            mainHandler.post {
                                networkEvents?.success("unknown")
                                publishNetwork()
                            }
                        }
                    }
                    networkCallback = callback
                    connectivity.registerDefaultNetworkCallback(callback)
                    publishNetwork()
                }
                override fun onCancel(arguments: Any?) = stopNetworkEvents()
            })
    }

    override fun onDestroy() {
        stopNetworkEvents()
        stopPowerEvents()
        super.onDestroy()
    }
}
