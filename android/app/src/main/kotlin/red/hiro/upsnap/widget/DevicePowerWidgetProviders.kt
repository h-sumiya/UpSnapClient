package red.hiro.upsnap.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

internal object DevicePowerWidgetProviders {
    fun appWidgetIds(context: Context): IntArray {
        val manager = AppWidgetManager.getInstance(context)
        return buildList {
            addAll(
                manager.getAppWidgetIds(
                    ComponentName(context, DevicePowerWidgetReceiver::class.java),
                ).toList(),
            )
            addAll(
                manager.getAppWidgetIds(
                    ComponentName(context, DevicePowerIconWidgetReceiver::class.java),
                ).toList(),
            )
        }.toIntArray()
    }

    fun hasWidgets(context: Context): Boolean = appWidgetIds(context).isNotEmpty()

    fun handleEnabled(context: Context) {
        DevicePowerWidgetSyncScheduler.ensurePeriodic(context)
        DevicePowerWidgetSyncScheduler.enqueueImmediate(context)
    }

    fun handleDisabled(context: Context) {
        if (!hasWidgets(context)) {
            DevicePowerWidgetSyncScheduler.cancelAll(context)
        }
    }
}

class DevicePowerWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DevicePowerWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        DevicePowerWidgetProviders.handleEnabled(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        DevicePowerWidgetProviders.handleDisabled(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        DevicePowerWidgetProviders.handleDisabled(context)
    }
}

class DevicePowerIconWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DevicePowerWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        DevicePowerWidgetProviders.handleEnabled(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        DevicePowerWidgetProviders.handleDisabled(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        DevicePowerWidgetProviders.handleDisabled(context)
    }
}
