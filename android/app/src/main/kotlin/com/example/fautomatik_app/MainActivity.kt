package com.example.fautomatik_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var textureBridge: TextureBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        textureBridge = TextureBridge.bindTo(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        textureBridge?.dispose()
        textureBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
