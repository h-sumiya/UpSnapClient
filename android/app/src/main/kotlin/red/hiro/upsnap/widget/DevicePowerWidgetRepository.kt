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

    private fun ensureSession(forceRenew: Boolean = false): AuthSession {
        val serverUrl = prefs.getString(serverUrlKey, null)?.trim().orEmpty()
        val rawAuth = prefs.getString(pbAuthKey, null)?.trim().orEmpty()
        if (serverUrl.isBlank()) {
            Log.w("DevicePowerWidget", "ensureSession missing auth or server url")
            throw AuthRequiredException()
        }

        if (rawAuth.isBlank()) {
            return loginWithSavedCredentials(serverUrl)
        }

        val authEnvelope = runCatching { JSONObject(rawAuth) }.getOrNull()
            ?: return loginWithSavedCredentials(serverUrl)
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
        if (!forceRenew && !isExpired(token)) {
            return currentSession
        }

        return runCatching { refreshSession(currentSession) }.getOrElse {
            loginWithSavedCredentials(serverUrl, collection)
        }
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

    private fun loginWithSavedCredentials(
        serverUrl: String,
        preferredCollection: String? = null,
    ): AuthSession {
        if (!prefs.getBoolean(rememberLoginKey, false)) {
            throw AuthRequiredException()
        }

        val identity = prefs.getString(loginIdentityKey, null)?.trim().orEmpty()
        val password = prefs.getString(loginPasswordKey, null).orEmpty()
        if (identity.isBlank() || password.isEmpty()) {
            throw AuthRequiredException()
        }

        val collections = listOfNotNull(preferredCollection?.takeIf(String::isNotBlank))
            .plus(listOf("_superusers", "users"))
            .distinct()
        for (collection in collections) {
            val session = runCatching {
                authWithPassword(serverUrl, collection, identity, password)
            }.getOrNull()
            if (session != null) {
                return session
            }
        }

        prefs.edit().remove(pbAuthKey).apply()
        throw AuthRequiredException()
    }

    private fun authWithPassword(
        serverUrl: String,
        collection: String,
        identity: String,
        password: String,
    ): AuthSession {
        val uri = Uri.parse(serverUrl).buildUpon()
            .appendPath("api")
            .appendPath("collections")
            .appendPath(collection)
            .appendPath("auth-with-password")
            .build()

        val body = JSONObject().apply {
            put("identity", identity)
            put("password", password)
        }.toString()
        val response = requestJsonObject(
            method = "POST",
            url = uri.toString(),
            authToken = "",
            retryOnUnauthorized = false,
            body = body,
        )

        val token = response.optString("token")
        val record = response.optJSONObject("record")
            ?: response.optJSONObject("model")
            ?: JSONObject()
        if (token.isBlank()) {
            throw AuthRequiredException()
        }

        val envelope = JSONObject().apply {
            put("token", token)
            put("model", record)
        }
        prefs.edit().putString(pbAuthKey, envelope.toString()).apply()

        return AuthSession(
            serverUrl = serverUrl,
            token = token,
            collection = record.optString("collectionName").takeIf(String::isNotBlank)
                ?: record.optString("collectionId").takeIf(String::isNotBlank)
                ?: collection,
            model = record,
        )
    }

    private fun requestJsonObject(
        method: String,
        url: String,
        authToken: String,
        retryOnUnauthorized: Boolean,
        body: String? = null,
    ): JSONObject {
        val response = request(method, url, authToken, retryOnUnauthorized, body)
        return if (response.isBlank()) JSONObject() else JSONObject(response)
    }

    private fun request(
        method: String,
        url: String,
        authToken: String,
        retryOnUnauthorized: Boolean,
        body: String? = null,
    ): String {
        Log.d("DevicePowerWidget", "request method=$method url=$url retryOnUnauthorized=$retryOnUnauthorized")
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 5_000
            readTimeout = 8_000
            doInput = true
            doOutput = body != null
            useCaches = false
            setRequestProperty("Accept", "application/json")
            if (authToken.isNotBlank()) {
                setRequestProperty("Authorization", authToken)
            }
            if (method != "GET") {
                setRequestProperty("Content-Type", "application/json")
            }
        }

        return try {
            if (body != null) {
                connection.outputStream.use { output ->
                    output.write(body.toByteArray(Charsets.UTF_8))
                }
            }

            val responseCode = connection.responseCode
            Log.d("DevicePowerWidget", "response code=$responseCode url=$url")
            if (responseCode == HttpURLConnection.HTTP_UNAUTHORIZED) {
                if (retryOnUnauthorized) {
                    val current = ensureSession(forceRenew = true)
                    return request(
                        method = method,
                        url = url,
                        authToken = current.token,
                        retryOnUnauthorized = false,
                        body = body,
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
        const val rememberLoginKey = "flutter.remember_login"
        const val loginIdentityKey = "flutter.login_identity"
        const val loginPasswordKey = "flutter.login_password"
    }
}
