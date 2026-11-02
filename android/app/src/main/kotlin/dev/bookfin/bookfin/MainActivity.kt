package dev.bookfin.bookfin

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import java.io.File

class MainActivity : FlutterActivity() {
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkEvents: EventChannel.EventSink? = null
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

    private fun publishNetwork() {
        mainHandler.post { networkEvents?.success(mediaNetwork()) }
    }

    private fun stopNetworkEvents() {
        networkCallback?.let { connectivity.unregisterNetworkCallback(it) }
        networkCallback = null
        networkEvents = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bookfin/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "storage" -> result.success(mapOf("path" to File(filesDir, "bookfin-media").absolutePath))
                    "freeBytes" -> result.success(StatFs(filesDir.absolutePath).availableBytes)
                    "network" -> result.success(mediaNetwork())
                    else -> result.notImplemented()
                }
            }
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
        super.onDestroy()
    }
}
