package red.hiro.upsnap.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
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
        val widgetIds = DevicePowerWidgetProviders.appWidgetIds(applicationContext)
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
            val now = System.currentTimeMillis()
            var shouldContinueActionPolling = false
            pairs.forEach { (glanceId, stateAtSyncStart) ->
                val latestState = DevicePowerWidgetState.read(applicationContext, glanceId)
                val deviceId = latestState.deviceId
                if (deviceId == null) {
                    return@forEach
                }

                val snapshot = snapshots[deviceId]
                if (snapshot == null) {
                    if (deviceId != stateAtSyncStart.deviceId) {
                        Log.d(
                            "DevicePowerWidget",
                            "syncWorker skip stale device mapping previous=${stateAtSyncStart.deviceId} current=$deviceId",
                        )
                        return@forEach
                    }
                    DevicePowerWidgetState.markError(
                        context = applicationContext,
                        glanceId = glanceId,
                        message = applicationContext.getString(R.string.widget_sync_error),
                        fallbackStatus = latestState.fallbackStatusOnError(),
                    )
                } else if (latestState.shouldContinueActionPolling(now, snapshot.status)) {
                    shouldContinueActionPolling = true
                    val shouldShowObservedStatus =
                        snapshot.status != latestState.actionPollingSourceStatus ||
                            latestState.status != DevicePowerStatus.PENDING
                    Log.d(
                        "DevicePowerWidget",
                        "syncWorker continue polling deviceId=$deviceId observed=${snapshot.status} target=${latestState.actionPollingTargetStatus} showObserved=$shouldShowObservedStatus",
                    )
                    if (shouldShowObservedStatus) {
                        DevicePowerWidgetState.writeObservedSnapshotWhilePolling(
                            context = applicationContext,
                            glanceId = glanceId,
                            snapshot = snapshot,
                        )
                    } else {
                        DevicePowerWidgetState.refreshPendingSnapshot(
                            context = applicationContext,
                            glanceId = glanceId,
                            snapshot = snapshot,
                        )
                    }
                } else {
                    Log.d(
                        "DevicePowerWidget",
                        "syncWorker write snapshot deviceId=$deviceId status=${snapshot.status}",
                    )
                    DevicePowerWidgetState.writeSnapshot(applicationContext, glanceId, snapshot)
                }
            }
            DevicePowerWidget().updateAll(applicationContext)
            if (shouldContinueActionPolling) {
                DevicePowerWidgetSyncScheduler.enqueueActionPolling(
                    context = applicationContext,
                    delaySeconds = DevicePowerWidgetSyncScheduler.actionPollingIntervalSeconds,
                )
            }
        }.onFailure { error ->
            val message = when (error) {
                is AuthRequiredException ->
                    applicationContext.getString(R.string.widget_sign_in_required)
                else -> applicationContext.getString(R.string.widget_sync_error)
            }
            pairs.forEach { (glanceId, _) ->
                val latestState = DevicePowerWidgetState.read(applicationContext, glanceId)
                DevicePowerWidgetState.markError(
                    context = applicationContext,
                    glanceId = glanceId,
                    message = message,
                    fallbackStatus = latestState.fallbackStatusOnError(),
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
    private const val actionPollingWorkName = "device_power_widget_action_polling"
    const val actionPollingWindowMillis: Long = 10 * 60 * 1000
    const val actionPollingMinimumDurationMillis: Long = 30 * 1000
    private const val actionPollingInitialDelaySeconds = 5L
    const val actionPollingIntervalSeconds = 5L

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
        WorkManager.getInstance(context).cancelUniqueWork(actionPollingWorkName)
        enqueue(
            context = context,
            uniqueWorkName = immediateWorkName,
            policy = ExistingWorkPolicy.REPLACE,
            delaySeconds = 0,
        )
    }

    fun enqueueDelayed(context: Context, delaySeconds: Long) {
        enqueue(
            context = context,
            uniqueWorkName = immediateWorkName,
            policy = ExistingWorkPolicy.REPLACE,
            delaySeconds = delaySeconds,
        )
    }

    fun enqueueActionPolling(
        context: Context,
        delaySeconds: Long = actionPollingInitialDelaySeconds,
    ) {
        enqueue(
            context = context,
            uniqueWorkName = actionPollingWorkName,
            policy = ExistingWorkPolicy.APPEND_OR_REPLACE,
            delaySeconds = delaySeconds,
        )
    }

    fun cancelAll(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(immediateWorkName)
        WorkManager.getInstance(context).cancelUniqueWork(actionPollingWorkName)
        WorkManager.getInstance(context).cancelUniqueWork(periodicWorkName)
    }

    fun hasWidgets(context: Context): Boolean {
        return DevicePowerWidgetProviders.hasWidgets(context)
    }

    private fun enqueue(
        context: Context,
        uniqueWorkName: String,
        policy: ExistingWorkPolicy,
        delaySeconds: Long,
    ) {
        if (!hasWidgets(context)) {
            return
        }

        val requestBuilder = OneTimeWorkRequestBuilder<DevicePowerWidgetSyncWorker>()
            .setConstraints(defaultConstraints())
        if (delaySeconds > 0) {
            requestBuilder.setInitialDelay(delaySeconds, TimeUnit.SECONDS)
        } else {
            requestBuilder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        }
        val request = requestBuilder.build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            uniqueWorkName,
            policy,
            request,
        )
    }

    private fun defaultConstraints(): Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
}
