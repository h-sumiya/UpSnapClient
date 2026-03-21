package red.hiro.upsnap.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

object DevicePowerWidgetPinner {
    private const val extraDeviceId = "extra_device_id"
    private const val extraDeviceName = "extra_device_name"

    fun requestPin(
        context: Context,
        deviceId: String,
        deviceName: String,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }

        val appWidgetManager = AppWidgetManager.getInstance(context)
        if (!appWidgetManager.isRequestPinAppWidgetSupported) {
            Log.w("DevicePowerWidget", "requestPin not supported by launcher")
            return false
        }

        val callbackIntent = Intent(context, DevicePowerWidgetPinReceiver::class.java).apply {
            putExtra(extraDeviceId, deviceId)
            putExtra(extraDeviceName, deviceName)
        }
        val requestCode = (31 * deviceId.hashCode()) + deviceName.hashCode()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag()
        val successCallback = PendingIntent.getBroadcast(
            context,
            requestCode,
            callbackIntent,
            flags,
        )

        val accepted = appWidgetManager.requestPinAppWidget(
            ComponentName(context, DevicePowerWidgetReceiver::class.java),
            null,
            successCallback,
        )
        Log.d("DevicePowerWidget", "requestPin accepted=$accepted deviceId=$deviceId deviceName=$deviceName")
        return accepted
    }

    internal fun readDeviceId(intent: Intent): String? = intent.getStringExtra(extraDeviceId)

    internal fun readDeviceName(intent: Intent): String? = intent.getStringExtra(extraDeviceName)

    private fun mutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
}
