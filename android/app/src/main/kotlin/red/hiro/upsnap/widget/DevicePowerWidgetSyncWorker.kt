package red.hiro.upsnap.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import red.hiro.upsnap.R
import java.util.concurrent.TimeUnit

class DevicePowerWidgetSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result = coroutineScope {
        val glanceManager = GlanceAppWidgetManager(applicationContext)
        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
        val widgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(applicationContext, DevicePowerWidgetReceiver::class.java),
        )
        if (widgetIds.isEmpty()) {
            DevicePowerWidgetSyncScheduler.cancelAll(applicationContext)
            return@coroutineScope Result.success()
        }

        val pairs = widgetIds.map { appWidgetId ->
            async {
                val glanceId = glanceManager.getGlanceIdBy(appWidgetId)
                val state = DevicePowerWidgetState.read(applicationContext, glanceId)
                glanceId to state
            }
        }.awaitAll()

        val ids = pairs.mapNotNull { (_, state) -> state.deviceId }.toSet()
        if (ids.isEmpty()) {
            DevicePowerWidget().updateAll(applicationContext)
            return@coroutineScope Result.success()
        }

        val repository = DevicePowerWidgetRepository(applicationContext)
        val result = runCatching { repository.fetchSnapshots(ids) }
        result.onSuccess { snapshots ->
            pairs.forEach { (glanceId, state) ->
                val deviceId = state.deviceId
                if (deviceId == null) {
                    return@forEach
                }

                val snapshot = snapshots[deviceId]
                if (snapshot == null) {
                    DevicePowerWidgetState.markError(
                        context = applicationContext,
                        glanceId = glanceId,
                        message = applicationContext.getString(R.string.widget_sync_error),
                        fallbackStatus = DevicePowerStatus.UNKNOWN,
                    )
                } else {
                    DevicePowerWidgetState.writeSnapshot(applicationContext, glanceId, snapshot)
                }
            }
            DevicePowerWidget().updateAll(applicationContext)
        }.onFailure { error ->
            val message = when (error) {
                is AuthRequiredException ->
                    applicationContext.getString(R.string.widget_sign_in_required)
                else -> applicationContext.getString(R.string.widget_sync_error)
            }
            pairs.forEach { (glanceId, _) ->
                DevicePowerWidgetState.markError(
                    context = applicationContext,
                    glanceId = glanceId,
                    message = message,
                    fallbackStatus = DevicePowerStatus.UNKNOWN,
                )
            }
            DevicePowerWidget().updateAll(applicationContext)
        }

        Result.success()
    }
}

object DevicePowerWidgetSyncScheduler {
    private const val periodicWorkName = "device_power_widget_periodic_sync"
    private const val immediateWorkName = "device_power_widget_immediate_sync"

    fun ensurePeriodic(context: Context) {
        if (!hasWidgets(context)) {
            return
        }

        val request = PeriodicWorkRequestBuilder<DevicePowerWidgetSyncWorker>(
            30,
            TimeUnit.MINUTES,
        ).setConstraints(defaultConstraints()).build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            periodicWorkName,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun enqueueImmediate(context: Context) {
        enqueue(context, delaySeconds = 0)
    }

    fun enqueueDelayed(context: Context, delaySeconds: Long) {
        enqueue(context, delaySeconds = delaySeconds)
    }

    fun cancelAll(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(immediateWorkName)
        WorkManager.getInstance(context).cancelUniqueWork(periodicWorkName)
    }

    fun hasWidgets(context: Context): Boolean {
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(
            ComponentName(context, DevicePowerWidgetReceiver::class.java),
        )
        return ids.isNotEmpty()
    }

    private fun enqueue(context: Context, delaySeconds: Long) {
        if (!hasWidgets(context)) {
            return
        }

        val request = OneTimeWorkRequestBuilder<DevicePowerWidgetSyncWorker>()
            .setConstraints(defaultConstraints())
            .setInitialDelay(delaySeconds, TimeUnit.SECONDS)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            immediateWorkName,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    private fun defaultConstraints(): Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
}
