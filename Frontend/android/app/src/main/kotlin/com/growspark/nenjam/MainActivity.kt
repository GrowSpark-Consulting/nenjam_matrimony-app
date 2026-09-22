package com.growspark.nenjam

import com.growspark.nenjam.liveness.FaceLivenessChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FaceLivenessChannel.register(this, flutterEngine)
    }
}
