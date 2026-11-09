package dev.bookfin.ttsbench

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A run lasts up to 30 minutes. The screen stays on so that Android
        // does not put the process to sleep in the middle of it.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    // "phone" returns what an app can read about heat and battery without
    // system permissions, so that a run needs no computer attached.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ttsbench").setMethodCallHandler { call, result ->
            if (call.method != "phone") return@setMethodCallHandler result.notImplemented()
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val sticky = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            result.success(
                mapOf(
                    "thermalStatus" to power.currentThermalStatus,
                    "headroom10s" to power.getThermalHeadroom(10).toDouble(),
                    "batteryPct" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                    "currentUa" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW),
                    "plugged" to (sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0),
                    "batteryTempC" to (sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10.0,
                ),
            )
        }
    }
}
