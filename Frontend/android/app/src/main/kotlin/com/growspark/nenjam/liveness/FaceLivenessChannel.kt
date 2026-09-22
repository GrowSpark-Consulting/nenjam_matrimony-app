package com.growspark.nenjam.liveness

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Registers `com.growspark.nenjam/face_liveness` / `startLiveness` — see
 * docs/development/selfie-verification-frontend-handoff.md §5 and the Dart
 * side, `lib/core/services/face_liveness/face_liveness_launcher.dart`, whose
 * channel name/method/args/result shape this must match exactly.
 *
 * Holds at most one pending [MethodChannel.Result]: a second concurrent
 * `startLiveness` call while one is already running gets an immediate
 * ERROR/ALREADY_RUNNING result rather than being queued, matching the Dart
 * flow controller's own double-tap guard (belt-and-braces, since a bug on
 * either side must not leave two AWS liveness sessions running from one
 * device).
 */
object FaceLivenessChannel {
    enum class Outcome { COMPLETED, CANCELLED, ERROR }

    private const val CHANNEL_NAME = "com.growspark.nenjam/face_liveness"
    private const val METHOD_START = "startLiveness"

    @Volatile
    private var pendingResult: MethodChannel.Result? = null

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            if (call.method != METHOD_START) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            startLiveness(activity, call.arguments as? Map<*, *>, result)
        }
    }

    private fun startLiveness(
        activity: Activity,
        args: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        if (pendingResult != null) {
            // Never throw for an expected outcome (handoff doc §5) — this is
            // a caller bug, not a liveness failure, so it gets its own
            // distinct code rather than a generic ERROR.
            result.success(
                mapOf(
                    "outcome" to Outcome.ERROR.name,
                    "errorCode" to "ALREADY_RUNNING",
                ),
            )
            return
        }

        val sessionId = args?.get("sessionId") as? String
        val region = args?.get("region") as? String
        val accessKeyId = args?.get("accessKeyId") as? String
        val secretAccessKey = args?.get("secretAccessKey") as? String
        val sessionToken = args?.get("sessionToken") as? String
        val expirationEpochSeconds = (args?.get("expirationEpochSeconds") as? Number)?.toLong()

        if (sessionId.isNullOrEmpty() ||
            region.isNullOrEmpty() ||
            accessKeyId.isNullOrEmpty() ||
            secretAccessKey.isNullOrEmpty() ||
            sessionToken.isNullOrEmpty() ||
            expirationEpochSeconds == null
        ) {
            result.success(
                mapOf(
                    "outcome" to Outcome.ERROR.name,
                    "errorCode" to "INVALID_ARGUMENTS",
                ),
            )
            return
        }

        // Credentials go straight into the in-memory holder — never into the
        // Intent below, which carries only sessionId/region (handoff doc §5).
        LivenessCredentialsHolder.set(
            buildLivenessCredentials(
                accessKeyId,
                secretAccessKey,
                sessionToken,
                expirationEpochSeconds,
            ),
        )

        pendingResult = result
        val intent = Intent(activity, LivenessActivity::class.java).apply {
            putExtra(LivenessActivity.EXTRA_SESSION_ID, sessionId)
            putExtra(LivenessActivity.EXTRA_REGION, region)
        }
        activity.startActivity(intent)
    }

    /** Called by [LivenessActivity] once it has a final outcome. */
    fun deliverResult(outcome: Outcome, errorCode: String?, errorMessage: String?) {
        val result = pendingResult ?: return
        pendingResult = null
        LivenessCredentialsHolder.clear()
        result.success(
            mapOf(
                "outcome" to outcome.name,
                "errorCode" to errorCode,
                "errorMessage" to errorMessage,
            ),
        )
    }
}
