package com.mimo.mimo_companion

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mimo/tailscale").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isInstalled" -> result.success(packageManager.getLaunchIntentForPackage("com.tailscale.ipn") != null)
                    "openTailscale" -> {
                        val intent = packageManager.getLaunchIntentForPackage("com.tailscale.ipn")
                        if (intent == null) result.error("NOT_INSTALLED", "กรุณาติดตั้ง Tailscale ก่อน", null)
                        else { startActivity(intent); result.success(null) }
                    }
                    "installPage" -> { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=com.tailscale.ipn"))); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("TAILSCALE_OPEN_FAILED", "เปิด Tailscale ไม่ได้ กรุณาเปิดจากหน้าจอโทรศัพท์", null) }
        }
    }
}
