package com.growspark.nenjam.liveness

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Surface
import androidx.compose.ui.Modifier
import com.amplifyframework.ui.liveness.model.FaceLivenessDetectionException
import com.amplifyframework.ui.liveness.ui.FaceLivenessDetector

/**
 * Hosts Amplify's `FaceLivenessDetector` Compose composable — see
 * docs/development/selfie-verification-frontend-handoff.md §2/§5. A separate,
 * small `ComponentActivity` rather than anything inside `MainActivity`
 * (`FlutterActivity`), since the two UI toolkits (Compose here, Flutter's own
 * surface there) don't share a window.
 *
 * Started only by [FaceLivenessChannel], which puts the AWS credentials into
 * [LivenessCredentialsHolder] first and passes only `sessionId`/`region` as
 * Intent extras — credentials never cross an Intent (handoff doc §5).
 *
 * The native `onComplete`/`onError` callbacks here mean only "the capture
 * finished" or "the capture could not run" — never "verified". Whatever this
 * activity reports, [FaceLivenessChannel] forwards to Flutter as one of
 * COMPLETED / CANCELLED / ERROR, and the actual verification decision comes
 * only from the backend's `/complete` response (handoff doc §1 rule 1).
 */
class LivenessActivity : ComponentActivity() {
    private var resultDelivered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Back press during capture is a cancel, not a bypass (handoff doc
        // §5) — registered via the modern callback API rather than
        // overriding the deprecated onBackPressed(), consistent with the
        // app-level android:enableOnBackInvokedCallback="true".
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    finishWith(FaceLivenessChannel.Outcome.CANCELLED, "USER_CANCELLED", null)
                }
            },
        )

        val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)
        val region = intent.getStringExtra(EXTRA_REGION)
        if (sessionId.isNullOrEmpty() || region.isNullOrEmpty()) {
            finishWith(FaceLivenessChannel.Outcome.ERROR, "MISSING_SESSION_ARGS", null)
            return
        }

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    FaceLivenessDetector(
                        sessionId = sessionId,
                        region = region,
                        credentialsProvider = BackendIssuedCredentialsProvider(),
                        // false: show Amplify's own "get ready" instructions
                        // screen before the check starts, per the component's
                        // default, documented UX.
                        disableStartView = false,
                        onComplete = {
                            // The capture finished; AWS still has to be asked
                            // for the result — see the backend's
                            // GetFaceLivenessSessionResults call, triggered by
                            // /complete. This is not a pass/fail signal.
                            finishWith(FaceLivenessChannel.Outcome.COMPLETED, null, null)
                        },
                        onError = { exception -> handleError(exception) },
                    )
                }
            }
        }
    }

    private fun handleError(exception: FaceLivenessDetectionException) {
        val (outcome, code) = when (exception) {
            is FaceLivenessDetectionException.UserCancelledException ->
                FaceLivenessChannel.Outcome.CANCELLED to "USER_CANCELLED"
            is FaceLivenessDetectionException.CameraPermissionDeniedException ->
                FaceLivenessChannel.Outcome.ERROR to "CAMERA_PERMISSION_DENIED"
            is FaceLivenessDetectionException.AccessDeniedException ->
                FaceLivenessChannel.Outcome.ERROR to "ACCESS_DENIED"
            is FaceLivenessDetectionException.SessionNotFoundException ->
                FaceLivenessChannel.Outcome.ERROR to "SESSION_NOT_FOUND"
            is FaceLivenessDetectionException.SessionTimedOutException ->
                FaceLivenessChannel.Outcome.ERROR to "SESSION_TIMED_OUT"
            // FaceInOvalMatchExceededTimeLimitException is `internal` to the
            // Amplify liveness module and not visible here — it falls into
            // the `else` branch below as a generic LIVENESS_ERROR.
            is FaceLivenessDetectionException.UnsupportedChallengeTypeException ->
                FaceLivenessChannel.Outcome.ERROR to "UNSUPPORTED_CHALLENGE_TYPE"
            is FaceLivenessDetectionException.VideoEncodingException ->
                FaceLivenessChannel.Outcome.ERROR to "VIDEO_ENCODING_ERROR"
            is FaceLivenessDetectionException.VideoMuxingException ->
                FaceLivenessChannel.Outcome.ERROR to "VIDEO_MUXING_ERROR"
            else -> FaceLivenessChannel.Outcome.ERROR to "LIVENESS_ERROR"
        }
        // The exception's own message can describe request/network details —
        // never a credential — so it is safe to forward, but never logged
        // here (handoff doc §5: "Never log any credential field").
        finishWith(outcome, code, exception.message)
    }

    private fun finishWith(
        outcome: FaceLivenessChannel.Outcome,
        errorCode: String?,
        errorMessage: String?,
    ) {
        if (resultDelivered) return
        resultDelivered = true
        FaceLivenessChannel.deliverResult(outcome, errorCode, errorMessage)
        finish()
    }

    override fun onDestroy() {
        // If the process dies or this activity is destroyed without a result
        // ever being delivered (e.g. the OS reclaims it mid-capture), the
        // pending Flutter call is left unresolved rather than guessed at —
        // FaceLivenessChannel times it out, and the backend independently
        // expires the attempt (handoff doc §5).
        if (!resultDelivered) {
            FaceLivenessChannel.deliverResult(
                FaceLivenessChannel.Outcome.ERROR,
                "ACTIVITY_DESTROYED",
                null,
            )
        }
        LivenessCredentialsHolder.clear()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_REGION = "region"
    }
}
