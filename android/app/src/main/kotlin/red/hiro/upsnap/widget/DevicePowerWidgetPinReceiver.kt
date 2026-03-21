package red.hiro.upsnap.widget

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import kotlinx.coroutines.runBlocking

class DevicePowerWidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        Log.d(
            "DevicePowerWidget",
            "PinReceiver onReceive appWidgetId=$appWidgetId extras=${intent.extras?.keySet()?.joinToString()}",
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            Log.w("DevicePowerWidget", "PinReceiver missing appWidgetId")
            return
        }

        val deviceId = DevicePowerWidgetPinner.readDeviceId(intent) ?: return
        val deviceName = DevicePowerWidgetPinner.readDeviceName(intent) ?: return
        val widgetType = DevicePowerWidgetPinner.readWidgetType(intent)
        Log.d(
            "DevicePowerWidget",
            "PinReceiver binding deviceId=$deviceId deviceName=$deviceName widgetId=$appWidgetId widgetType=${widgetType.rawValue}",
        )

        runBlocking {
            val glanceId = GlanceAppWidgetManager(context).getGlanceIdBy(appWidgetId)
            DevicePowerWidgetState.bindDevice(
                context = context,
                glanceId = glanceId,
                deviceId = deviceId,
                deviceName = deviceName,
                widgetType = widgetType,
            )
            DevicePowerWidget().update(context, glanceId)
        }

        Log.d("DevicePowerWidget", "PinReceiver bound widgetId=$appWidgetId")
        DevicePowerWidgetSyncScheduler.ensurePeriodic(context)
        DevicePowerWidgetSyncScheduler.enqueueImmediate(context)
    }
}
