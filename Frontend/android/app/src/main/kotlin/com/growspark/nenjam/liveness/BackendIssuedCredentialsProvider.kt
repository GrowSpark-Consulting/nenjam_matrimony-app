package com.growspark.nenjam.liveness

import com.amplifyframework.auth.AWSCredentials
import com.amplifyframework.auth.AWSCredentialsProvider
import com.amplifyframework.auth.AuthException
import com.amplifyframework.core.Consumer

/**
 * Feeds Amplify's `FaceLivenessDetector` the backend-issued, single-use AWS
 * credentials instead of Amplify Auth/Cognito — see
 * docs/development/selfie-verification-frontend-handoff.md §2: "no Amplify
 * Auth, no Cognito, no amplifyconfiguration.json". The Amplify docs describe
 * `fetchAWSCredentials` as called once at start with no refresh, which is
 * exactly right here: the credentials last 15 minutes and a liveness session
 * lasts 3 (handoff doc §1 rule 3).
 *
 * Reads from [LivenessCredentialsHolder] rather than holding its own copy —
 * there is exactly one place these credentials live in the process.
 */
class BackendIssuedCredentialsProvider : AWSCredentialsProvider<AWSCredentials> {
    override fun fetchAWSCredentials(
        onResult: Consumer<AWSCredentials>,
        onError: Consumer<AuthException>,
    ) {
        val credentials = LivenessCredentialsHolder.get()
        if (credentials == null) {
            onError.accept(
                AuthException(
                    "No liveness credentials available",
                    "The attempt may have already completed or expired.",
                    IllegalStateException("LivenessCredentialsHolder was empty"),
                ),
            )
            return
        }
        onResult.accept(credentials)
    }
}
