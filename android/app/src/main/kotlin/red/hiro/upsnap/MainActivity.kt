package red.hiro.upsnap

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import red.hiro.upsnap.widget.DevicePowerWidgetPinner
import red.hiro.upsnap.widget.DevicePowerWidgetSyncScheduler

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pinDeviceWidget" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val deviceName = call.argument<String>("deviceName")
                    if (deviceId.isNullOrBlank() || deviceName.isNullOrBlank()) {
                        result.error("invalid_args", "deviceId and deviceName are required", null)
                        return@setMethodCallHandler
                    }

                    Log.d("DevicePowerWidget", "pinDeviceWidget request deviceId=$deviceId deviceName=$deviceName")
                    result.success(
                        DevicePowerWidgetPinner.requestPin(
                            context = this,
                            deviceId = deviceId,
                            deviceName = deviceName,
                        ),
                    )
                }

                "refreshDeviceWidgets" -> {
                    DevicePowerWidgetSyncScheduler.enqueueImmediate(this)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val WIDGET_CHANNEL = "red.hiro.upsnap/device_widget"
    }
}
