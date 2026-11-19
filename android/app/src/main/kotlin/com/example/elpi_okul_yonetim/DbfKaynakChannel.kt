package com.example.elpi_okul_yonetim

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object DbfKaynakChannel {
    fun register(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger,
            "elpi_okul_yonetim/dbf").setMethodCallHandler { call, result ->
            if (call.method != "kaynakAc") {
                result.notImplemented()
            } else {
                try {
                    val text = call.argument<String>("adres") ?: ""
                    val uri = Uri.parse(text)
                    require(text.length <= 2048 && uri.scheme == "https" &&
                        !uri.host.isNullOrBlank() && uri.userInfo.isNullOrEmpty() &&
                        text.none { it.code <= 32 }) { "Geçerli bir HTTPS adresi gerekli." }
                    activity.startActivity(Intent(Intent.ACTION_VIEW, uri)
                        .addCategory(Intent.CATEGORY_BROWSABLE))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("DBF_KAYNAK_ACILAMADI", "Kaynak sayfası açılamadı.", e.toString())
                }
            }
        }
    }
}
