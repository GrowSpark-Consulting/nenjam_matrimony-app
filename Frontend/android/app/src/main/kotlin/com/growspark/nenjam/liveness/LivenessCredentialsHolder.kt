package com.growspark.nenjam.liveness

import com.amplifyframework.auth.AWSCredentials

/**
 * In-memory, single-use holder for the backend-issued AWS credentials for
 * one liveness attempt.
 *
 * See docs/development/selfie-verification-frontend-handoff.md §5/§7:
 * credentials must never cross an Intent, never be logged, and must be
 * cleared as soon as the attempt is done (success, error, or cancel) — this
 * object is the one place they live between [FaceLivenessChannel] setting
 * them and [LivenessActivity] reading them via
 * [BackendIssuedCredentialsProvider].
 */
object LivenessCredentialsHolder {
    @Volatile
    private var credentials: AWSCredentials? = null

    fun set(credentials: AWSCredentials) {
        this.credentials = credentials
    }

    /** The held credentials, or null once [clear] has run. Never logged. */
    fun get(): AWSCredentials? = credentials

    fun clear() {
        credentials = null
    }
}

/**
 * Builds the credentials object from the channel call's raw arguments, using
 * the real `com.amplifyframework.auth.AWSCredentials.Factory` (there is no
 * separate "temporary credentials" type in the Amplify Android SDK — a
 * session token is just one of this factory's four arguments).
 */
fun buildLivenessCredentials(
    accessKeyId: String,
    secretAccessKey: String,
    sessionToken: String,
    expirationEpochSeconds: Long,
): AWSCredentials {
    return requireNotNull(
        AWSCredentials.Factory.createAWSCredentials(
            accessKeyId,
            secretAccessKey,
            sessionToken,
            expirationEpochSeconds,
        ),
    ) { "AWSCredentials.Factory.createAWSCredentials returned null for non-null inputs" }
}
