import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bireysel_bilgi_toplama_service.dart';
import 'bilgi_toplama_google_service.dart';

/// Fotoğrafları URL olarak yayımlamadan mevcut özel Apps Script'e aktarır.
class OgretmenGorusGoogleService {
  OgretmenGorusGoogleService({http.Client? client, String? dagitim})
    : _client = client ?? http.Client(),
      _sahip = client == null,
      _dagitim = dagitim ?? BireyselBilgiToplamaService.varsayilanSilmeDagitimi;
  final http.Client _client;
  final bool _sahip;
  String _dagitim;
  void baglantiyiKullan(String dagitim) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(dagitim)) {
      throw const FormatException(
        'Kayıtlı Apps Script dağıtım kimliği geçersiz.',
      );
    }
    _dagitim = dagitim;
  }

  void dispose() {
    if (_sahip) _client.close();
  }

  Future<Map<String, dynamic>> _cagir(
    String token,
    String islev,
    List<Object?> parametreler,
  ) async {
    if (token.isEmpty || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(_dagitim)) {
      throw StateError(
        'Google bağlantısı veya Apps Script dağıtımı yapılandırılmamış.',
      );
    }
    final r = await _client
        .post(
          Uri.https('script.googleapis.com', '/v1/scripts/$_dagitim:run'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'function': islev,
            'parameters': parametreler,
            'devMode': false,
          }),
        )
        .timeout(
          Duration(seconds: islev == 'okulOgretmenGorusFormOlustur' ? 120 : 30),
          onTimeout: () {
            throw TimeoutException(
              'Google yanıtı zamanında alınamadı. Aynı form isteği korundu; tekrar deneyebilirsiniz. Google tarafında oluşturma devam ediyor olabilir.',
            );
          },
        );
    if (r.statusCode != 200) {
      throw StateError(
        'Google bağlantısı başarısız (${r.statusCode}). Hesap iznini ve Apps Script dağıtımını kontrol edin.',
      );
    }
    final v = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    if (v['error'] != null) {
      final error = v['error'];
      final details = error is Map ? error['details'] : null;
      final mesaj = details is List
          ? details
                .whereType<Map>()
                .map((d) => '${d['errorMessage'] ?? ''}')
                .join(' ')
          : '';
      if (mesaj.contains('Script function not found') ||
          islev == 'okulOgretmenGorusKurulumKontrol') {
        throw StateError(
          'Kayıtlı Apps Script dağıtımında öğretmen görüşü işlevi çalıştırılamadı. OgretmenGorus.gs dosyasını aynı projeye ekleyip mevcut API dağıtımını yeni sürümle güncelleyin.',
        );
      }
      if (mesaj.contains('ders seçeneklerini')) {
        throw StateError(
          'Öğretmen veya ders seçenekleri eksik. Öğretmen ders programını aktarın.',
        );
      }
      if (mesaj.contains('başka içerikle')) {
        throw StateError(
          'Kayıtlı form isteği Google’daki içerikle uyuşmuyor. Mevcut form korundu.',
        );
      }
      // Bilinmeyen ham yanıt kişisel bilgi içerebilir; ekrana dökülmez.
      throw StateError(
        'Google görüş formu işlemi tamamlanamadı. Apps Script kurulumunu, form erişimini ve fotoğrafları kontrol edin.',
      );
    }
    final response = v['response'];
    final result = response is Map ? response['result'] : null;
    if (v['done'] != true ||
        result is! Map ||
        result['protocol'] != 'okul-ogretmen-gorus/v1') {
      throw StateError(
        'Görüş formu kurulumu güncel değil. OgretmenGorus.gs dosyasını ekleyip API dağıtımını yeni sürümle güncelleyin.',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<void> kontrol(String token) async {
    final r = await _cagir(token, 'okulOgretmenGorusKurulumKontrol', []);
    if (r['ready'] != true || r['version'] != 1) {
      throw StateError('Fotoğraflı form kurulumu güncel değil.');
    }
  }

  Future<Map<String, dynamic>> olustur(
    String token,
    Map<String, dynamic> istek,
  ) async {
    final r = await _cagir(token, 'okulOgretmenGorusFormOlustur', [istek]);
    _sonucKontrol(r, '${istek['requestId']}');
    return r;
  }

  Future<Map<String, dynamic>> yayinla(
    String token,
    String requestId,
    String formId,
  ) async {
    final r = await _cagir(token, 'okulOgretmenGorusYayinla', [
      requestId,
      formId,
    ]);
    _sonucKontrol(r, requestId, formId: formId);
    if (r['published'] != true || r['acceptingResponses'] != true) {
      throw StateError(
        'Formun yayımlandığı doğrulanamadı; mesajlaşma açılmadı.',
      );
    }
    return r;
  }

  void _sonucKontrol(
    Map<String, dynamic> r,
    String requestId, {
    String? formId,
  }) {
    if (r['requestId'] != requestId ||
        r['ready'] != true ||
        r['formId'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,300}$').hasMatch(r['formId'] as String) ||
        (formId != null && r['formId'] != formId)) {
      throw StateError('Google yanıtı beklenen form ile eşleşmiyor.');
    }
    baglanti('${r['responderUrl']}');
    baglanti('${r['editUrl']}', duzenle: true);
  }

  static Uri baglanti(String url, {bool duzenle = false}) {
    final u = Uri.tryParse(url);
    if (u == null ||
        u.scheme != 'https' ||
        u.host != 'docs.google.com' ||
        u.userInfo.isNotEmpty ||
        u.hasPort ||
        !u.path.startsWith('/forms/') ||
        !u.path.endsWith(duzenle ? '/edit' : '/viewform')) {
      throw const FormatException('Google Form bağlantısı geçersiz.');
    }
    return u;
  }

  Future<void> yanitSil(String token, String formId, String responseId) =>
      BilgiToplamaGoogleService(
        client: _client,
      ).googleYanitSil(_dagitim, token, formId, responseId);

  Future<void> yanitAliminiAyarla(String token, String formId, bool acik) =>
      BilgiToplamaGoogleService(
        client: _client,
      ).googleYayinAyarla(token, formId, acik);

  Future<List<Map<String, dynamic>>> yanitlar(
    String token,
    String requestId,
    String formId,
  ) async {
    final tum = <String, Map<String, dynamic>>{};
    int? offset = 0;
    do {
      final r = await _cagir(token, 'okulOgretmenGorusYanitlari', [
        requestId,
        formId,
        offset,
      ]);
      if (r['requestId'] != requestId ||
          r['formId'] != formId ||
          r['yanitlar'] is! List) {
        throw StateError('Görüş yanıtları beklenen form ile eşleşmiyor.');
      }
      for (final y in r['yanitlar'] as List) {
        if (y is! Map ||
            y['responseId'] is! String ||
            y['ogrenciler'] is! Map) {
          throw const FormatException('Google görüş yanıtı geçersiz.');
        }
        tum[y['responseId'] as String] = Map<String, dynamic>.from(y);
      }
      final next = r['nextOffset'];
      if (next != null && (next is! int || next <= offset! || next > 10000)) {
        throw const FormatException('Google yanıt sayfalaması geçersiz.');
      }
      offset = next as int?;
    } while (offset != null);
    return tum.values.toList();
  }
}
