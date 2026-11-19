package com.example.elpi_okul_yonetim

import android.app.Activity
import android.accounts.Account
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Token yalnız bu seçim için bellekte kalır; dosya veya ayarlara yazılmaz. */
class DriveBelgeChannel(private val activity: Activity, engine: FlutterEngine) {
    private val requestCode = 7105
    private val scope = "https://www.googleapis.com/auth/drive.file"
    private var bekleyen: MethodChannel.Result? = null
    private var bekleyenHesap: String? = null
    private val client = Identity.getAuthorizationClient(activity)
    private val handler = Handler(Looper.getMainLooper())
    private var yetkiZamanAsimi: Runnable? = null

    private fun zamanAsiminiKaldir() {
        yetkiZamanAsimi?.let { handler.removeCallbacks(it) }
        yetkiZamanAsimi = null
    }

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger,
            "elpi_okul_yonetim/drive_belge").setMethodCallHandler { call, result ->
            if (call.method != "sec" && call.method != "erisim") result.notImplemented()
            else if (bekleyen != null) result.error("DRIVE_BEKLIYOR", "Dosya seçimi sürüyor.", null)
            else {
                bekleyen = result
                try {
                    val sessiz = call.method == "erisim"
                    val mime = call.argument<List<String>>("mimeTurleri").orEmpty()
                    require(sessiz || (mime.isNotEmpty() && mime.size <= 20 &&
                        mime.all { Regex("^[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+$").matches(it) })
                    )
                    val builder = AuthorizationRequest.builder()
                        .setRequestedScopes(listOf(Scope(scope)))
                        .setOptOutIncludingGrantedScopes(true)
                    if (sessiz) {
                        val hesap = call.argument<String>("hesap").orEmpty()
                        require(hesap.contains('@') && hesap.length <= 320 && hesap.none { it.code < 32 })
                        bekleyenHesap = hesap
                        builder.setAccount(Account(hesap, "com.google"))
                    } else {
                        bekleyenHesap = null
                        builder
                        .setPrompt(AuthorizationRequest.Prompt.CONSENT or AuthorizationRequest.Prompt.SELECT_ACCOUNT)
                        .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_OAUTH_TRIGGER, "true")
                        .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_ALLOW_MULTIPLE, "false")
                        .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_MIMETYPES, mime.joinToString(","))
                    }
                    // Kullanıcının seçim ekranında geçirdiği süreyi sınırlama.
                    // Yalnız Google'ın authorize isteğinin cevapsız kalmasını kes.
                    val zamanAsimi = Runnable {
                        if (bekleyen === result) {
                            result.error("DRIVE_ZAMAN_ASIMI",
                                "Google Drive bağlantısı 60 saniyede yanıt vermedi. İnternet bağlantısını kontrol edip yeniden deneyin veya Cihazımdan/Belgelerimden seçin.", null)
                            bekleyen = null
                            bekleyenHesap = null
                            yetkiZamanAsimi = null
                        }
                    }
                    yetkiZamanAsimi = zamanAsimi
                    handler.postDelayed(zamanAsimi, 60_000L)
                    client.authorize(builder.build()).addOnSuccessListener { auth ->
                        if (bekleyen !== result) return@addOnSuccessListener
                        zamanAsiminiKaldir()
                        try {
                            if (auth.hasResolution()) {
                                if (sessiz) {
                                    bekleyen?.success(null)
                                    bekleyen = null
                                    bekleyenHesap = null
                                    return@addOnSuccessListener
                                }
                                val pending = auth.pendingIntent ?: error("Yetkilendirme ekranı bulunamadı.")
                                activity.startIntentSenderForResult(pending.intentSender,
                                    requestCode, null, 0, 0, 0)
                            } else tamamla(auth, sessiz)
                        } catch (_: Exception) { hata() }
                    }.addOnFailureListener { e ->
                        if (bekleyen !== result) return@addOnFailureListener
                        hata((e as? ApiException)?.statusCode)
                    }
                } catch (_: Exception) { hata() }
            }
        }
    }

    fun sonucuAl(kod: Int, sonuc: Int, data: Intent?): Boolean {
        if (kod != requestCode) return false
        if (sonuc != Activity.RESULT_OK || data == null) {
            bekleyen?.success(null)
            bekleyen = null
        } else try {
            tamamla(client.getAuthorizationResultFromIntent(data))
        } catch (e: Exception) { hata((e as? ApiException)?.statusCode) }
        return true
    }

    @Suppress("DEPRECATION")
    private fun tamamla(auth: AuthorizationResult, sessiz: Boolean = false) {
        val ids = auth.tokenResponseParams?.getString("picked_file_ids")
            ?.split(",")?.filter { it.isNotBlank() }.orEmpty()
        val token = auth.accessToken
        val hesap = auth.toGoogleSignInAccount()?.email
        if (sessiz) {
            if (token.isNullOrBlank() || !auth.grantedScopes.contains(scope) ||
                (hesap != null && hesap != bekleyenHesap)) {
                hata()
            } else {
                bekleyen?.success(mapOf("token" to token))
                bekleyen = null
                bekleyenHesap = null
            }
            return
        }
        if (ids.isEmpty()) {
            bekleyen?.success(null)
            bekleyen = null
            return
        }
        if (ids.size != 1 || token.isNullOrBlank() || !auth.grantedScopes.contains(scope)) {
            hata()
            return
        }
        bekleyen?.success(mapOf("dosyaId" to ids.single(), "token" to token, "hesap" to hesap))
        bekleyen = null
    }

    private fun hata(kod: Int? = null) {
        zamanAsiminiKaldir()
        // Google hata gövdesi veya yetki belirteci Flutter hata çıktısına taşınmaz.
        bekleyen?.error("DRIVE_YETKI_HATASI",
            "Google Drive bağlantısı kurulamadı. Cihazımdan veya Belgelerimden seçebilirsiniz.", kod)
        bekleyen = null
        bekleyenHesap = null
    }
}
