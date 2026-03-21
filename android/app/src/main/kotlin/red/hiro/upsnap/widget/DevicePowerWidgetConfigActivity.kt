package red.hiro.upsnap.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.glance.appwidget.GlanceAppWidgetManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import red.hiro.upsnap.R

class DevicePowerWidgetConfigActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var selectedWidgetType = WidgetDisplayType.LABELED
    private lateinit var progressView: ProgressBar
    private lateinit var messageView: TextView
    private lateinit var listView: ListView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            Log.w("DevicePowerWidget", "ConfigActivity missing appWidgetId")
            finish()
            return
        }

        Log.d(
            "DevicePowerWidget",
            "ConfigActivity onCreate appWidgetId=$appWidgetId deviceId=${DevicePowerWidgetPinner.readDeviceId(intent)}",
        )

        setResult(RESULT_CANCELED)
        title = getString(R.string.widget_config_title)
        setContentView(buildContentView())

        val pinnedDeviceId = DevicePowerWidgetPinner.readDeviceId(intent)
        val pinnedDeviceName = DevicePowerWidgetPinner.readDeviceName(intent)
        selectedWidgetType =
            if (DevicePowerWidgetPinner.hasWidgetType(intent)) {
                DevicePowerWidgetPinner.readWidgetType(intent)
            } else {
                DevicePowerWidgetPinner.inferWidgetType(this, appWidgetId)
                    ?: WidgetDisplayType.LABELED
            }
        loadDevices(
            preselectedDeviceId = pinnedDeviceId,
            preselectedDeviceName = pinnedDeviceName,
        )
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun loadDevices(
        preselectedDeviceId: String?,
        preselectedDeviceName: String?,
    ) {
        progressView.visibility = View.VISIBLE
        messageView.visibility = View.GONE
        listView.visibility = View.GONE

        scope.launch {
            val repository = DevicePowerWidgetRepository(this@DevicePowerWidgetConfigActivity)
            runCatching { repository.fetchWidgetCandidates() }
                .onSuccess { devices ->
                    Log.d("DevicePowerWidget", "ConfigActivity loaded devices=${devices.size}")
                    if (devices.isEmpty()) {
                        showMessage(getString(R.string.widget_config_empty))
                        return@onSuccess
                    }

                    val preselected = preselectedDeviceId?.let { targetId ->
                        devices.firstOrNull { it.id == targetId }
                    } ?: preselectedDeviceName?.let { targetName ->
                        devices.firstOrNull { it.name == targetName }
                    }
                    if (preselected != null) {
                        Log.d("DevicePowerWidget", "ConfigActivity preselected deviceId=${preselected.id}")
                        bindAndFinish(preselected)
                        return@onSuccess
                    }

                    showList(devices)
                }
                .onFailure { error ->
                    Log.e("DevicePowerWidget", "ConfigActivity load failed", error)
                    if (error is AuthRequiredException) {
                        showMessage(getString(R.string.widget_config_sign_in))
                    } else {
                        showMessage(getString(R.string.widget_sync_error))
                    }
                }
        }
    }

    private fun showList(devices: List<WidgetSnapshot>) {
        progressView.visibility = View.GONE
        messageView.visibility = View.GONE
        listView.visibility = View.VISIBLE

        val labels = devices.map { snapshot ->
            "${snapshot.name}  ·  ${statusLabel(snapshot.status)}"
        }
        listView.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_list_item_1,
            labels,
        )
        listView.onItemClickListener = AdapterView.OnItemClickListener { _, _, position, _ ->
            bindAndFinish(devices[position])
        }
    }

    private fun showMessage(text: String) {
        progressView.visibility = View.GONE
        listView.visibility = View.GONE
        messageView.visibility = View.VISIBLE
        messageView.text = text
    }

    private fun bindAndFinish(snapshot: WidgetSnapshot) {
        Log.d("DevicePowerWidget", "ConfigActivity bindAndFinish widgetId=$appWidgetId deviceId=${snapshot.id}")
        progressView.visibility = View.VISIBLE
        listView.visibility = View.GONE
        messageView.visibility = View.GONE

        scope.launch {
            val glanceId = withContext(Dispatchers.IO) {
                GlanceAppWidgetManager(this@DevicePowerWidgetConfigActivity)
                    .getGlanceIdBy(appWidgetId)
            }
            DevicePowerWidgetState.bindDevice(
                context = this@DevicePowerWidgetConfigActivity,
                glanceId = glanceId,
                deviceId = snapshot.id,
                deviceName = snapshot.name,
                widgetType = selectedWidgetType,
            )
            DevicePowerWidgetState.writeSnapshot(
                context = this@DevicePowerWidgetConfigActivity,
                glanceId = glanceId,
                snapshot = snapshot,
            )
            DevicePowerWidget().update(this@DevicePowerWidgetConfigActivity, glanceId)
            DevicePowerWidgetSyncScheduler.ensurePeriodic(this@DevicePowerWidgetConfigActivity)
            DevicePowerWidgetSyncScheduler.enqueueImmediate(this@DevicePowerWidgetConfigActivity)

            val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            setResult(RESULT_OK, result)
            Log.d("DevicePowerWidget", "ConfigActivity finished widgetId=$appWidgetId")
            finish()
        }
    }

    private fun statusLabel(status: DevicePowerStatus): String =
        when (status) {
            DevicePowerStatus.ONLINE -> getString(R.string.widget_status_online)
            DevicePowerStatus.OFFLINE -> getString(R.string.widget_status_offline)
            DevicePowerStatus.PENDING -> getString(R.string.widget_status_pending)
            DevicePowerStatus.UNKNOWN -> getString(R.string.widget_status_unknown)
        }

    private fun buildContentView(): View {
        val padding = (20 * resources.displayMetrics.density).toInt()

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)

            progressView = ProgressBar(context).apply {
                isIndeterminate = true
            }
            addView(
                progressView,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                    bottomMargin = padding / 2
                },
            )

            messageView = TextView(context).apply {
                gravity = Gravity.CENTER
                visibility = View.GONE
                text = getString(R.string.widget_config_loading)
            }
            addView(
                messageView,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )

            listView = ListView(context).apply {
                visibility = View.GONE
            }
            addView(
                listView,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                ),
            )
        }
    }
}
