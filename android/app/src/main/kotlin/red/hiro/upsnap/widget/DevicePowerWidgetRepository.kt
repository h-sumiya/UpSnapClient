package red.hiro.upsnap.widget

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64

internal class AuthRequiredException : IllegalStateException()

internal class ShutdownUnavailableException : IllegalStateException()

internal class DevicePowerWidgetRepository(context: Context) {
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences =
        appContext.getSharedPreferences(sharedPrefsName, Context.MODE_PRIVATE)

    suspend fun fetchSnapshots(deviceIds: Set<String>): Map<String, WidgetSnapshot> =
        withContext(Dispatchers.IO) {
            Log.d("DevicePowerWidget", "fetchSnapshots ids=${deviceIds.size}")
            if (deviceIds.isEmpty()) {
                return@withContext emptyMap()
            }

            val session = ensureSession()
            val filter = deviceIds.joinToString(" || ") { "id = '$it'" }
            val uri = Uri.parse(session.serverUrl).buildUpon()
                .appendPath("api")
                .appendPath("collections")
                .appendPath("devices")
                .appendPath("records")
                .appendQueryParameter("perPage", deviceIds.size.coerceAtLeast(1).toString())
                .appendQueryParameter("skipTotal", "1")
                .appendQueryParameter("sort", "name")
                .appendQueryParameter("fields", "id,name,status,shutdown_cmd")
                .appendQueryParameter("filter", filter)
                .build()

            val response = requestJsonObject(
                method = "GET",
                url = uri.toString(),
                authToken = session.token,
                retryOnUnauthorized = true,
            )
            val items = response.optJSONArray("items") ?: JSONArray()
            buildMap(items.length()) {
                repeat(items.length()) { index ->
                    val item = items.optJSONObject(index) ?: return@repeat
                    val id = item.optString("id")
                    if (id.isBlank()) {
                        return@repeat
                    }

                    put(
                        id,
                        WidgetSnapshot(
                            id = id,
                            name = item.optString("name").ifBlank { id },
                            status = DevicePowerStatus.fromRaw(item.optString("status")),
                            shutdownSupported = item.optString("shutdown_cmd").isNotBlank(),
                        ),
                    )
                }
            }
        }

    suspend fun fetchWidgetCandidates(): List<WidgetSnapshot> =
        withContext(Dispatchers.IO) {
            Log.d("DevicePowerWidget", "fetchWidgetCandidates")
            val session = ensureSession()
            val uri = Uri.parse(session.serverUrl).buildUpon()
                .appendPath("api")
                .appendPath("collections")
                .appendPath("devices")
                .appendPath("records")
                .appendQueryParameter("perPage", "500")
                .appendQueryParameter("skipTotal", "1")
                .appendQueryParameter("sort", "name")
                .appendQueryParameter("fields", "id,name,status,shutdown_cmd")
                .build()

            val response = requestJsonObject(
                method = "GET",
                url = uri.toString(),
                authToken = session.token,
                retryOnUnauthorized = true,
            )
            val items = response.optJSONArray("items") ?: JSONArray()
            buildList(items.length()) {
                repeat(items.length()) { index ->
                    val item = items.optJSONObject(index) ?: return@repeat
                    val id = item.optString("id")
                    if (id.isBlank()) {
                        return@repeat
                    }

                    add(
                        WidgetSnapshot(
                            id = id,
                            name = item.optString("name").ifBlank { id },
                            status = DevicePowerStatus.fromRaw(item.optString("status")),
                            shutdownSupported = item.optString("shutdown_cmd").isNotBlank(),
                        ),
                    )
                }
            }
        }

    suspend fun togglePower(
        deviceId: String,
        currentStatus: DevicePowerStatus,
        shutdownSupported: Boolean,
    ) = withContext(Dispatchers.IO) {
        Log.d(
            "DevicePowerWidget",
            "togglePower deviceId=$deviceId status=$currentStatus shutdownSupported=$shutdownSupported",
        )
        val session = ensureSession()
        val actionPath = when (currentStatus) {
            DevicePowerStatus.OFFLINE -> "wake"
            DevicePowerStatus.ONLINE -> {
                if (!shutdownSupported) {
                    throw ShutdownUnavailableException()
                }
                "shutdown"
            }
            DevicePowerStatus.PENDING,
            DevicePowerStatus.UNKNOWN,
            -> return@withContext
        }

        val uri = Uri.parse(session.serverUrl).buildUpon()
            .appendPath("api")
            .appendPath("upsnap")
            .appendPath(actionPath)
            .appendPath(deviceId)
            .build()

        request(
            method = "GET",
            url = uri.toString(),
            authToken = session.token,
            retryOnUnauthorized = true,
        )
    }

    private fun ensureSession(): AuthSession {
        val serverUrl = prefs.getString(serverUrlKey, null)?.trim().orEmpty()
        val rawAuth = prefs.getString(pbAuthKey, null)?.trim().orEmpty()
        if (serverUrl.isBlank() || rawAuth.isBlank()) {
            Log.w("DevicePowerWidget", "ensureSession missing auth or server url")
            throw AuthRequiredException()
        }

        val authEnvelope = runCatching { JSONObject(rawAuth) }.getOrNull()
            ?: throw AuthRequiredException()
        val token = authEnvelope.optString("token")
        val model = authEnvelope.optJSONObject("model")
        val collection = model?.optString("collectionName")
            ?.takeIf(String::isNotBlank)
            ?: model?.optString("collectionId")?.takeIf(String::isNotBlank)
            ?: "users"

        val currentSession = AuthSession(
            serverUrl = serverUrl,
            token = token,
            collection = collection,
            model = model ?: JSONObject(),
        )
        Log.d("DevicePowerWidget", "ensureSession collection=$collection tokenValid=${!isExpired(token)}")
        if (!isExpired(token)) {
            return currentSession
        }

        return refreshSession(currentSession)
    }

    private fun refreshSession(session: AuthSession): AuthSession {
        Log.d("DevicePowerWidget", "refreshSession collection=${session.collection}")
        val uri = Uri.parse(session.serverUrl).buildUpon()
            .appendPath("api")
            .appendPath("collections")
            .appendPath(session.collection)
            .appendPath("auth-refresh")
            .build()

        val response = requestJsonObject(
            method = "POST",
            url = uri.toString(),
            authToken = session.token,
            retryOnUnauthorized = false,
        )

        val token = response.optString("token")
        val record = response.optJSONObject("record") ?: JSONObject()
        if (token.isBlank()) {
            Log.e("DevicePowerWidget", "refreshSession returned blank token")
            throw AuthRequiredException()
        }

        val envelope = JSONObject().apply {
            put("token", token)
            put("model", record)
        }
        prefs.edit().putString(pbAuthKey, envelope.toString()).apply()

        return AuthSession(
            serverUrl = session.serverUrl,
            token = token,
            collection = record.optString("collectionName").takeIf(String::isNotBlank)
                ?: record.optString("collectionId").takeIf(String::isNotBlank)
                ?: session.collection,
            model = record,
        )
    }

    private fun requestJsonObject(
        method: String,
        url: String,
        authToken: String,
        retryOnUnauthorized: Boolean,
    ): JSONObject {
        val response = request(method, url, authToken, retryOnUnauthorized)
        return if (response.isBlank()) JSONObject() else JSONObject(response)
    }

    private fun request(
        method: String,
        url: String,
        authToken: String,
        retryOnUnauthorized: Boolean,
    ): String {
        Log.d("DevicePowerWidget", "request method=$method url=$url retryOnUnauthorized=$retryOnUnauthorized")
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 5_000
            readTimeout = 8_000
            doInput = true
            useCaches = false
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", authToken)
            if (method != "GET") {
                setRequestProperty("Content-Type", "application/json")
            }
        }

        return try {
            val responseCode = connection.responseCode
            Log.d("DevicePowerWidget", "response code=$responseCode url=$url")
            if (responseCode == HttpURLConnection.HTTP_UNAUTHORIZED) {
                if (retryOnUnauthorized) {
                    val current = ensureSession()
                    return request(
                        method = method,
                        url = url,
                        authToken = current.token,
                        retryOnUnauthorized = false,
                    )
                }
                prefs.edit().remove(pbAuthKey).apply()
                throw AuthRequiredException()
            }

            if (responseCode >= HttpURLConnection.HTTP_BAD_REQUEST) {
                throw IllegalStateException("HTTP $responseCode")
            }

            readBody(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun readBody(connection: HttpURLConnection): String =
        BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
            buildString {
                var line = reader.readLine()
                while (line != null) {
                    append(line)
                    line = reader.readLine()
                }
            }
        }

    private fun isExpired(token: String): Boolean {
        val parts = token.split(".")
        if (parts.size < 2) {
            return true
        }

        return runCatching {
            val payload = String(
                Base64.getUrlDecoder().decode(parts[1].padBase64()),
                Charsets.UTF_8,
            )
            val exp = JSONObject(payload).optLong("exp", 0L)
            exp <= (System.currentTimeMillis() / 1000L) + 60L
        }.getOrDefault(true)
    }

    private fun String.padBase64(): String {
        val remainder = length % 4
        if (remainder == 0) {
            return this
        }
        return this + "=".repeat(4 - remainder)
    }

    private data class AuthSession(
        val serverUrl: String,
        val token: String,
        val collection: String,
        val model: JSONObject,
    )

    private companion object {
        const val sharedPrefsName = "FlutterSharedPreferences"
        const val serverUrlKey = "flutter.server_url"
        const val pbAuthKey = "flutter.pb_auth"
    }
}
