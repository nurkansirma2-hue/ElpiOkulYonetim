import 'package:google_sign_in/google_sign_in.dart';

/// Form ekranlarının aynı Google hesabını yeniden kullanmasını sağlar.
/// Kalıcı parola/token tutmaz; GoogleSignIn sessiz oturumu yönetir.
class OrtakGoogleOturumService {
  OrtakGoogleOturumService._();

  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '809052042804-k51q6va9bvevktpf8hoqcs87s752n5cg.apps.googleusercontent.com',
  );
  static const silmeScope =
      'https://www.googleapis.com/auth/forms';

  static final GoogleSignIn hesap = GoogleSignIn(
    serverClientId: webClientId,
    scopes: const [
      'https://www.googleapis.com/auth/forms.body',
      'https://www.googleapis.com/auth/forms.responses.readonly',
      'https://www.googleapis.com/auth/forms',
    ],
  );

  static Future<GoogleSignInAccount> hesapGetir() async {
    final secili = hesap.currentUser ??
        await hesap.signInSilently() ??
        await hesap.signIn();
    if (secili == null) {
      throw StateError('Google hesap seçimi iptal edildi.');
    }
    return secili;
  }

  static Future<String> token({String? ekIzin}) async {
    final kullanici = await hesapGetir();
    if (ekIzin != null && !(await hesap.requestScopes([ekIzin]))) {
      throw StateError('Google için gerekli izin verilmedi.');
    }
    final accessToken = (await kullanici.authentication).accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Google oturumu yenilenmeli.');
    }
    return accessToken;
  }

  static Future<void> hesapDegistir() async {
    await hesap.signOut();
  }
}
