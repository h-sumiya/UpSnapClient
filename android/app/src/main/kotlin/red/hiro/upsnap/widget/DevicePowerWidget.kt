package red.hiro.upsnap.widget

import android.content.Context
import android.text.format.DateUtils
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.ColorFilter
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale
import red.hiro.upsnap.R

internal enum class DevicePowerStatus(val rawValue: String) {
    ONLINE("online"),
    OFFLINE("offline"),
    PENDING("pending"),
    UNKNOWN("unknown"),
    ;

    companion object {
        fun fromRaw(value: String?): DevicePowerStatus =
            entries.firstOrNull { it.rawValue == value } ?: UNKNOWN
    }
}

enum class WidgetDisplayType(val rawValue: String) {
    LABELED("labeled"),
    POWER_ICON("power_icon"),
    ;

    companion object {
        fun fromRaw(value: String?): WidgetDisplayType =
            entries.firstOrNull { it.rawValue == value } ?: LABELED
    }
}

internal data class WidgetSnapshot(
    val id: String,
    val name: String,
    val status: DevicePowerStatus,
    val shutdownSupported: Boolean,
)

internal data class StoredWidgetDevice(
    val deviceId: String?,
    val deviceName: String,
    val widgetType: WidgetDisplayType,
    val status: DevicePowerStatus,
    val shutdownSupported: Boolean,
    val isBusy: Boolean,
    val error: String?,
    val lastSyncedAt: Long,
    val actionPollingSourceStatusRaw: String? = null,
    val actionPollingTargetStatusRaw: String? = null,
    val actionPollingStartedAt: Long = 0L,
    val actionPollingDeadlineAt: Long = 0L,
) {
    val actionPollingSourceStatus: DevicePowerStatus?
        get() = actionPollingSourceStatusRaw?.let(DevicePowerStatus::fromRaw)

    val actionPollingTargetStatus: DevicePowerStatus?
        get() = actionPollingTargetStatusRaw?.let(DevicePowerStatus::fromRaw)

    fun shouldContinueActionPolling(
        now: Long,
        observedStatus: DevicePowerStatus,
    ): Boolean {
        val targetStatus = actionPollingTargetStatus ?: return false
        if (actionPollingDeadlineAt <= now) {
            return false
        }

        val minimumPollingEndsAt = actionPollingStartedAt +
            DevicePowerWidgetSyncScheduler.actionPollingMinimumDurationMillis
        return now < minimumPollingEndsAt || observedStatus != targetStatus
    }

    fun fallbackStatusOnError(): DevicePowerStatus = actionPollingSourceStatus ?: status
}

internal object DevicePowerWidgetState {
    private val deviceIdKey = stringPreferencesKey("device_id")
    private val deviceNameKey = stringPreferencesKey("device_name")
    private val widgetTypeKey = stringPreferencesKey("widget_type")
    private val statusKey = stringPreferencesKey("status")
    private val shutdownSupportedKey = booleanPreferencesKey("shutdown_supported")
    private val busyKey = booleanPreferencesKey("busy")
    private val errorKey = stringPreferencesKey("error")
    private val lastSyncedAtKey = longPreferencesKey("last_synced_at")
    private val actionPollingSourceStatusKey = stringPreferencesKey("action_polling_source_status")
    private val actionPollingTargetStatusKey = stringPreferencesKey("action_polling_target_status")
    private val actionPollingStartedAtKey = longPreferencesKey("action_polling_started_at")
    private val actionPollingDeadlineAtKey = longPreferencesKey("action_polling_deadline_at")

    suspend fun read(context: Context, glanceId: GlanceId): StoredWidgetDevice =
        withContext(Dispatchers.IO) {
            val prefs: Preferences = getAppWidgetState(
                context,
                PreferencesGlanceStateDefinition,
                glanceId,
            )
            prefs.toStoredState()
        }

    suspend fun bindDevice(
        context: Context,
        glanceId: GlanceId,
        deviceId: String,
        deviceName: String,
        widgetType: WidgetDisplayType,
    ) {
        updateAppWidgetState(context, glanceId) { prefs: MutablePreferences ->
            prefs[deviceIdKey] = deviceId
            prefs[deviceNameKey] = deviceName
            prefs[widgetTypeKey] = widgetType.rawValue
            prefs[statusKey] = DevicePowerStatus.UNKNOWN.rawValue
            prefs[shutdownSupportedKey] = false
            prefs[busyKey] = false
            prefs.remove(errorKey)
            prefs[lastSyncedAtKey] = 0L
            clearActionPolling(prefs)
        }
    }

    suspend fun writeSnapshot(
        context: Context,
        glanceId: GlanceId,
        snapshot: WidgetSnapshot,
    ) {
        updateAppWidgetState(context, glanceId) { prefs: MutablePreferences ->
            prefs[deviceIdKey] = snapshot.id
            prefs[deviceNameKey] = snapshot.name
            prefs[statusKey] = snapshot.status.rawValue
            prefs[shutdownSupportedKey] = snapshot.shutdownSupported
            prefs[busyKey] = false
            prefs.remove(errorKey)
            prefs[lastSyncedAtKey] = System.currentTimeMillis()
            clearActionPolling(prefs)
        }
    }

    suspend fun refreshPendingSnapshot(
        context: Context,
        glanceId: GlanceId,
        snapshot: WidgetSnapshot,
    ) {
        updateAppWidgetState(context, glanceId) { prefs: MutablePreferences ->
            prefs[deviceIdKey] = snapshot.id
            prefs[deviceNameKey] = snapshot.name
            prefs[statusKey] = DevicePowerStatus.PENDING.rawValue
            prefs[shutdownSupportedKey] = snapshot.shutdownSupported
            prefs[busyKey] = true
            prefs.remove(errorKey)
            prefs[lastSyncedAtKey] = System.currentTimeMillis()
        }
    }

    suspend fun markBusy(context: Context, glanceId: GlanceId, busy: Boolean) {
        updateAppWidgetState(context, glanceId) { prefs: MutablePreferences ->
            prefs[busyKey] = busy
            prefs.remove(errorKey)
            if (!busy) {
                clearActionPolling(prefs)
            }
        }
    }

    suspend fun markError(
        context: Context,
        glanceId: GlanceId,
        message: String,
        fallbackStatus: DevicePowerStatus? = null,
    ) {
        updateAppWidgetState(context, glanceId) { prefs: MutablePreferences ->
            prefs[busyKey] = false
            prefs[errorKey] = message
            fallbackStatus?.let { prefs[statusKey] = it.rawValue }
            clearActionPolling(prefs)
        }
    }

    suspend fun setPending(
        context: Context,
        glanceId: GlanceId,
        sourceStatus: DevicePowerStatus,
        targetStatus: DevicePowerStatus,
        actionPollingStartedAt: Long,
        actionPollingDeadlineAt: Long,
    ) {
        updateAppWidgetState(context, glanceId) { prefs: MutablePreferences ->
            prefs[statusKey] = DevicePowerStatus.PENDING.rawValue
            prefs[busyKey] = true
            prefs.remove(errorKey)
            prefs[actionPollingSourceStatusKey] = sourceStatus.rawValue
            prefs[actionPollingTargetStatusKey] = targetStatus.rawValue
            prefs[actionPollingStartedAtKey] = actionPollingStartedAt
            prefs[actionPollingDeadlineAtKey] = actionPollingDeadlineAt
        }
    }

    suspend fun clearAll(context: Context, glanceId: GlanceId) {
        updateAppWidgetState(context, glanceId) { prefs: MutablePreferences ->
            prefs.clear()
        }
    }

    private fun Preferences.toStoredState(): StoredWidgetDevice {
        val name = this[deviceNameKey].orEmpty()
        return StoredWidgetDevice(
            deviceId = this[deviceIdKey],
            deviceName = name,
            widgetType = WidgetDisplayType.fromRaw(this[widgetTypeKey]),
            status = DevicePowerStatus.fromRaw(this[statusKey]),
            shutdownSupported = this[shutdownSupportedKey] == true,
            isBusy = this[busyKey] == true,
            error = this[errorKey]?.takeIf(String::isNotBlank),
            lastSyncedAt = this[lastSyncedAtKey] ?: 0L,
            actionPollingSourceStatusRaw =
                this[actionPollingSourceStatusKey]?.takeIf(String::isNotBlank),
            actionPollingTargetStatusRaw =
                this[actionPollingTargetStatusKey]?.takeIf(String::isNotBlank),
            actionPollingStartedAt = this[actionPollingStartedAtKey] ?: 0L,
            actionPollingDeadlineAt = this[actionPollingDeadlineAtKey] ?: 0L,
        )
    }

    fun currentState(state: Preferences): StoredWidgetDevice = state.toStoredState()

    private fun clearActionPolling(prefs: MutablePreferences) {
        prefs.remove(actionPollingSourceStatusKey)
        prefs.remove(actionPollingTargetStatusKey)
        prefs.remove(actionPollingStartedAtKey)
        prefs.remove(actionPollingDeadlineAtKey)
    }
}

internal object DevicePowerWidgetInstances {
    suspend fun glanceIdsForDevice(context: Context, deviceId: String): List<GlanceId> {
        val manager = GlanceAppWidgetManager(context)
        return manager.getGlanceIds(DevicePowerWidget::class.java).filter { glanceId ->
            DevicePowerWidgetState.read(context, glanceId).deviceId == deviceId
        }
    }
}

class DevicePowerWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(72.dp, 72.dp), DpSize(132.dp, 132.dp), DpSize(192.dp, 110.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val state = DevicePowerWidgetState.currentState(currentState<Preferences>())
            val widgetSize = LocalSize.current
            val compact = widgetSize.width < 160.dp || widgetSize.height < 120.dp
            val palette = paletteFor(state.status)
            val action = when {
                state.deviceId.isNullOrBlank() -> null
                state.isBusy -> null
                else -> actionRunCallback<ToggleDevicePowerAction>()
            }
            val contextLocal = LocalContext.current
            val deviceName = state.deviceName.ifBlank {
                contextLocal.getString(R.string.device_power_widget_name)
            }
            val supportingText = supportingText(contextLocal, state)
            val rootModifier = if (state.widgetType == WidgetDisplayType.POWER_ICON) {
                GlanceModifier.fillMaxSize()
            } else {
                GlanceModifier
                    .fillMaxSize()
                    .background(ColorProvider(Color(0xFFF5F7F9)))
                    .cornerRadius(24.dp)
            }

            Box(
                modifier = rootModifier,
                contentAlignment = Alignment.Center,
            ) {
                if (state.widgetType == WidgetDisplayType.POWER_ICON) {
                    PowerIconOnlyWidget(
                        compact = compact,
                        palette = palette,
                        action = action,
                        actionLabel = actionLabel(contextLocal, state),
                    )
                } else {
                    LabeledPowerWidget(
                        compact = compact,
                        deviceName = deviceName,
                        supportingText = supportingText,
                        palette = palette,
                        action = action,
                        actionLabel = actionLabel(contextLocal, state),
                    )
                }
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun LabeledPowerWidget(
        compact: Boolean,
        deviceName: String,
        supportingText: String,
        palette: WidgetPalette,
        action: androidx.glance.action.Action?,
        actionLabel: String,
    ) {
        Column(
            modifier = GlanceModifier.padding(16.dp),
            verticalAlignment = Alignment.Vertical.Top,
            horizontalAlignment = Alignment.Horizontal.Start,
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                Text(
                    text = deviceName,
                    maxLines = 2,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF0F172A)),
                        fontWeight = FontWeight.Medium,
                        fontSize = if (compact) 15.sp else 16.sp,
                    ),
                )
                Spacer(modifier = GlanceModifier.width(12.dp))
                Box(
                    modifier = GlanceModifier
                        .size(12.dp)
                        .background(ColorProvider(palette.accent))
                        .cornerRadius(99.dp),
                ) {}
            }
            Spacer(modifier = GlanceModifier.height(if (compact) 10.dp else 14.dp))
            var powerModifier = GlanceModifier
                .fillMaxWidth()
                .height(if (compact) 92.dp else 108.dp)
                .background(ColorProvider(palette.panel))
                .cornerRadius(22.dp)
                .padding(14.dp)
            if (action != null) {
                powerModifier = powerModifier.clickable(action)
            }
            Box(
                modifier = powerModifier,
                contentAlignment = Alignment.Center,
            ) {
                val iconSize = if (compact) 30.dp else 36.dp
                Column(
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                    horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                ) {
                    Image(
                        provider = ImageProvider(android.R.drawable.ic_lock_power_off),
                        contentDescription = actionLabel,
                        modifier = GlanceModifier.size(iconSize),
                        colorFilter = ColorFilter.tint(ColorProvider(palette.icon)),
                        contentScale = ContentScale.Fit,
                    )
                    Spacer(modifier = GlanceModifier.height(8.dp))
                    Text(
                        text = actionLabel.uppercase(Locale.getDefault()),
                        style = TextStyle(
                            color = ColorProvider(palette.icon),
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp,
                        ),
                    )
                }
            }
            Spacer(modifier = GlanceModifier.height(10.dp))
            Text(
                text = supportingText,
                maxLines = 2,
                style = TextStyle(
                    color = ColorProvider(Color(0xFF475569)),
                    fontSize = 12.sp,
                ),
            )
        }
    }

    @androidx.compose.runtime.Composable
    private fun PowerIconOnlyWidget(
        compact: Boolean,
        palette: WidgetPalette,
        action: androidx.glance.action.Action?,
        actionLabel: String,
    ) {
        val iconSize = if (compact) 36.dp else 44.dp
        var iconModifier = GlanceModifier.size(iconSize)
        if (action != null) {
            iconModifier = iconModifier.clickable(action)
        }
        Box(
            modifier = iconModifier,
            contentAlignment = Alignment.Center,
        ) {
            Image(
                provider = ImageProvider(android.R.drawable.ic_lock_power_off),
                contentDescription = actionLabel,
                modifier = GlanceModifier.size(iconSize),
                colorFilter = ColorFilter.tint(ColorProvider(palette.icon)),
                contentScale = ContentScale.Fit,
            )
        }
    }

    private data class WidgetPalette(
        val accent: Color,
        val panel: Color,
        val icon: Color,
    )

    private fun paletteFor(status: DevicePowerStatus): WidgetPalette =
        when (status) {
            DevicePowerStatus.ONLINE -> WidgetPalette(
                accent = Color(0xFF16A34A),
                panel = Color(0xFFE8F7EE),
                icon = Color(0xFF166534),
            )
            DevicePowerStatus.OFFLINE -> WidgetPalette(
                accent = Color(0xFFDC2626),
                panel = Color(0xFFFDECEC),
                icon = Color(0xFF991B1B),
            )
            DevicePowerStatus.PENDING -> WidgetPalette(
                accent = Color(0xFFF59E0B),
                panel = Color(0xFFFEF3C7),
                icon = Color(0xFF92400E),
            )
            DevicePowerStatus.UNKNOWN -> WidgetPalette(
                accent = Color(0xFF64748B),
                panel = Color(0xFFE2E8F0),
                icon = Color(0xFF334155),
            )
        }

    private fun actionLabel(context: Context, state: StoredWidgetDevice): String =
        when {
            state.deviceId.isNullOrBlank() -> context.getString(R.string.widget_action_refresh)
            state.status == DevicePowerStatus.ONLINE -> context.getString(R.string.widget_action_turn_off)
            state.status == DevicePowerStatus.OFFLINE -> context.getString(R.string.widget_action_turn_on)
            else -> context.getString(R.string.widget_action_refresh)
        }

    private fun supportingText(context: Context, state: StoredWidgetDevice): String {
        state.error?.let { return it }
        if (state.deviceId.isNullOrBlank()) {
            return context.getString(R.string.widget_not_configured)
        }

        val statusLabel = when (state.status) {
            DevicePowerStatus.ONLINE -> context.getString(R.string.widget_status_online)
            DevicePowerStatus.OFFLINE -> context.getString(R.string.widget_status_offline)
            DevicePowerStatus.PENDING -> context.getString(R.string.widget_status_pending)
            DevicePowerStatus.UNKNOWN -> context.getString(R.string.widget_status_unknown)
        }

        if (state.lastSyncedAt <= 0L) {
            return statusLabel
        }

        val relativeTime = DateUtils.getRelativeTimeSpanString(
            state.lastSyncedAt,
            System.currentTimeMillis(),
            DateUtils.MINUTE_IN_MILLIS,
        )
        return "$statusLabel · $relativeTime"
    }
}

class ToggleDevicePowerAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: androidx.glance.action.ActionParameters,
    ) {
        val state = DevicePowerWidgetState.read(context, glanceId)
        val deviceId = state.deviceId ?: return
        val repository = DevicePowerWidgetRepository(context)

        if (state.status == DevicePowerStatus.PENDING) {
            DevicePowerWidgetSyncScheduler.enqueueImmediate(context)
            return
        }

        if (state.status == DevicePowerStatus.UNKNOWN) {
            DevicePowerWidgetSyncScheduler.enqueueImmediate(context)
            return
        }

        val targetStatus = when (state.status) {
            DevicePowerStatus.ONLINE -> DevicePowerStatus.OFFLINE
            DevicePowerStatus.OFFLINE -> DevicePowerStatus.ONLINE
            DevicePowerStatus.PENDING,
            DevicePowerStatus.UNKNOWN,
            -> null
        } ?: return

        val now = System.currentTimeMillis()
        val targetGlanceIds = DevicePowerWidgetInstances.glanceIdsForDevice(context, deviceId)
            .ifEmpty { listOf(glanceId) }

        targetGlanceIds.forEach { targetGlanceId ->
            DevicePowerWidgetState.setPending(
                context = context,
                glanceId = targetGlanceId,
                sourceStatus = state.status,
                targetStatus = targetStatus,
                actionPollingStartedAt = now,
                actionPollingDeadlineAt = now +
                DevicePowerWidgetSyncScheduler.actionPollingWindowMillis,
            )
        }
        DevicePowerWidget().updateAll(context)

        runCatching {
            repository.togglePower(
                deviceId = deviceId,
                currentStatus = state.status,
                shutdownSupported = state.shutdownSupported,
            )
        }.onSuccess {
            DevicePowerWidgetSyncScheduler.enqueueImmediate(context)
        }.onFailure { error ->
            val message = when (error) {
                is ShutdownUnavailableException ->
                    context.getString(R.string.widget_missing_shutdown)
                is AuthRequiredException ->
                    context.getString(R.string.widget_sign_in_required)
                else -> context.getString(R.string.widget_sync_error)
            }
            targetGlanceIds.forEach { targetGlanceId ->
                DevicePowerWidgetState.markError(
                    context = context,
                    glanceId = targetGlanceId,
                    message = message,
                    fallbackStatus = state.status,
                )
            }
            DevicePowerWidget().updateAll(context)
        }
    }
}
