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
    private const val extraWidgetType = "extra_widget_type"

    fun requestPin(
        context: Context,
        deviceId: String,
        deviceName: String,
        widgetType: WidgetDisplayType,
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
            putExtra(extraWidgetType, widgetType.rawValue)
        }
        val requestCode =
            (((31 * deviceId.hashCode()) + deviceName.hashCode()) * 31) + widgetType.rawValue.hashCode()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag()
        val successCallback = PendingIntent.getBroadcast(
            context,
            requestCode,
            callbackIntent,
            flags,
        )

        val accepted = appWidgetManager.requestPinAppWidget(
            componentNameFor(context, widgetType),
            null,
            successCallback,
        )
        Log.d(
            "DevicePowerWidget",
            "requestPin accepted=$accepted deviceId=$deviceId deviceName=$deviceName widgetType=${widgetType.rawValue}",
        )
        return accepted
    }

    internal fun readDeviceId(intent: Intent): String? = intent.getStringExtra(extraDeviceId)

    internal fun readDeviceName(intent: Intent): String? = intent.getStringExtra(extraDeviceName)

    internal fun hasWidgetType(intent: Intent): Boolean = intent.hasExtra(extraWidgetType)

    internal fun readWidgetType(intent: Intent): WidgetDisplayType =
        WidgetDisplayType.fromRaw(intent.getStringExtra(extraWidgetType))

    internal fun inferWidgetType(
        context: Context,
        appWidgetId: Int,
    ): WidgetDisplayType? {
        val providerClassName = AppWidgetManager.getInstance(context)
            .getAppWidgetInfo(appWidgetId)
            ?.provider
            ?.className
            ?: return null
        return when (providerClassName) {
            DevicePowerIconWidgetReceiver::class.java.name -> WidgetDisplayType.POWER_ICON
            DevicePowerWidgetReceiver::class.java.name -> WidgetDisplayType.LABELED
            else -> null
        }
    }

    private fun componentNameFor(
        context: Context,
        widgetType: WidgetDisplayType,
    ): ComponentName =
        when (widgetType) {
            WidgetDisplayType.LABELED ->
                ComponentName(context, DevicePowerWidgetReceiver::class.java)
            WidgetDisplayType.POWER_ICON ->
                ComponentName(context, DevicePowerIconWidgetReceiver::class.java)
        }

    private fun mutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
}
