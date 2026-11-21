import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_google_service.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_google_form_service.dart';

http.Response json(Object value, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), status);

class GoogleTaklidi {
  final mevcut = <String>{'cinar-ilk', 'cinar-son', 'diger'};
  final silinen = <String>[];
  int betikCagrisi = 0;
  int formDurumu = 200;
  int? yanitDurumu;
  bool kimlikUyusmaz = false, yanitKaybolsun = false;
  bool bozukSonuc = false, listeCakissin = false;
  late final client = MockClient((r) async {
    expect(r.headers['Authorization'], 'Bearer test-token');
    if (r.url.host == 'script.googleapis.com') {
      betikCagrisi++;
      final body = jsonDecode(r.body) as Map;
      expect(body['devMode'], false);
      final function = body['function'];
      if (function == 'okulYanitSilKurulumKontrol') {
        return json({
          'done': true,
          'response': {
            'result': {
              'protocol': 'okul-yanit-sil/v1',
              'ready': true,
              'implementation': 'exact-response-2026-11-19',
            },
          },
        });
      }
      if (function == 'okulYanitKimlikTani') {
        // Öğrenci içeriği salt okunur tanı için de gönderilmez.
        expect((body['parameters'] as List).skip(2), [null, null]);
        return json({
          'done': true,
          'response': {
            'result': {
              'protocol': 'okul-yanit-kimlik-tani/v1',
              'formId': 'f1',
              'scriptCount': 3,
              'exactMatches': 0,
            },
          },
        });
      }
      expect(function, 'okulYanitSil');
      final id = body['parameters'][1] as String;
      if (kimlikUyusmaz) {
        return json({
          'done': true,
          'error': {'code': 3},
        });
      }
      mevcut.remove(id);
      silinen.add(id);
      if (yanitKaybolsun) throw http.ClientException('test connection lost');
      return json({
        'done': true,
        'response': {
          'result': {
            'protocol': 'okul-yanit-sil/v1',
            'formId': 'f1',
            'responseId': bozukSonuc ? 'yanlis' : id,
            'deleted': true,
            'absent': true,
          },
        },
      });
    }
    expect(r.method, 'GET');
    if (r.url.path.endsWith('/responses')) {
      return json({
        'responses': [
          for (final id in mevcut) {'responseId': id},
          if (listeCakissin) {'responseId': 'cinar-ilk'},
        ],
      });
    }
    if (r.url.path.contains('/responses/')) {
      final id = r.url.pathSegments.last;
      return json({
        'formId': 'f1',
        'responseId': id,
      }, yanitDurumu ?? (mevcut.contains(id) ? 200 : 404));
    }
    return json({'formId': 'f1'}, formDurumu);
  });
  Future<void> sil(String id, {String deployment = 'deployment-id'}) =>
      BilgiToplamaGoogleService(
        client: client,
      ).googleYanitSil(deployment, 'test-token', 'f1', id);
}

void main() {
  test(
    'Çınar 15 Kasım yanıtı silinir; 18 Kasım yanıtı ve diğer öğrenci korunur',
    () async {
      final g = GoogleTaklidi();
      addTearDown(g.client.close);
      await g.sil('cinar-ilk');
      expect(g.silinen, ['cinar-ilk']);
      expect(g.mevcut, {'cinar-son', 'diger'});
      await g.sil('cinar-ilk', deployment: '');
      expect(g.silinen, ['cinar-ilk']);
    },
  );

  test('Google’da zaten yoksa bozuk dağıtımda da betik çağrılmaz', () async {
    final g = GoogleTaklidi()..mevcut.remove('cinar-ilk');
    addTearDown(g.client.close);
    await g.sil('cinar-ilk', deployment: '');
    expect(g.betikCagrisi, 0);
    expect(g.silinen, isEmpty);
  });

  test('kimlik uyuşmazlığında farklı yanıt seçilmez', () async {
    final g = GoogleTaklidi()..kimlikUyusmaz = true;
    addTearDown(g.client.close);
    await expectLater(g.sil('cinar-ilk'), throwsStateError);
    expect(g.silinen, isEmpty);
    expect(g.mevcut, hasLength(3));
  });

  test(
    'POST cevabı kaybolsa da tam yokluk doğrulanır; silme tekrarlanmaz',
    () async {
      final g = GoogleTaklidi()..yanitKaybolsun = true;
      addTearDown(g.client.close);
      await g.sil('cinar-ilk');
      expect(g.silinen, ['cinar-ilk']);
      expect(g.betikCagrisi, 2);
    },
  );

  test('betik yanlış hedef döndürürse başarı bildirilmez', () async {
    final g = GoogleTaklidi()..bozukSonuc = true;
    addTearDown(g.client.close);
    await expectLater(g.sil('cinar-ilk'), throwsStateError);
  });

  for (final status in [401, 403, 404]) {
    test('form HTTP $status ise betik çağrılmaz', () async {
      final g = GoogleTaklidi()..formDurumu = status;
      addTearDown(g.client.close);
      await expectLater(g.sil('cinar-ilk'), throwsStateError);
      expect(g.betikCagrisi, 0);
      expect(g.silinen, isEmpty);
    });
  }
  for (final status in [401, 403, 500]) {
    test('tekli yanıt HTTP $status ise betik çağrılmaz', () async {
      final g = GoogleTaklidi()..yanitDurumu = status;
      addTearDown(g.client.close);
      await expectLater(g.sil('cinar-ilk'), throwsStateError);
      expect(g.betikCagrisi, 0);
    });
  }
  test('404 ile liste çelişiyorsa yokluk kabul edilmez', () async {
    final g = GoogleTaklidi()..yanitDurumu = 404;
    addTearDown(g.client.close);
    await expectLater(
      BilgiToplamaGoogleService(
        client: g.client,
      ).googleSilinmesiniDogrula('test-token', 'f1', 'cinar-ilk'),
      throwsStateError,
    );
    expect(g.silinen, isEmpty);
  });

  for (final scenario in [
    'tekrar-sayfa',
    'tekrar-kimlik',
    'bozuk-token',
    'bozuk-liste',
    'eksik-kimlik',
    'yanlis-form',
    'ikinci-sayfa-hatasi',
    'ag-hatasi',
  ]) {
    test('eksiksiz liste oluşmadan yokluk onaylanmaz: $scenario', () async {
      var sayfa = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/responses/eksik')) return json({}, 404);
        if (!r.url.path.endsWith('/responses')) return json({'formId': 'f1'});
        sayfa++;
        switch (scenario) {
          case 'tekrar-sayfa':
            return json({'nextPageToken': 'ayni'});
          case 'tekrar-kimlik':
            return json({
              'responses': [
                {'responseId': 'r'},
                {'responseId': 'r'},
              ],
            });
          case 'bozuk-token':
            return json({'nextPageToken': 2});
          case 'bozuk-liste':
            return json({'responses': null});
          case 'eksik-kimlik':
            return json({
              'responses': [{}],
            });
          case 'yanlis-form':
            return json({
              'responses': [
                {'responseId': 'r', 'formId': 'f2'},
              ],
            });
          case 'ikinci-sayfa-hatasi':
            if (sayfa == 1) return json({'nextPageToken': 'sonraki'});
            return json({}, 403);
          default:
            throw http.ClientException('test offline');
        }
      });
      addTearDown(client.close);
      await expectLater(
        RehberlikGoogleFormService(client: client).yanitGoogledaYokMu(
          erisimBelirteci: 'test',
          googleFormId: 'f1',
          responseId: 'eksik',
        ),
        throwsA(anything),
      );
      expect(sayfa, lessThanOrEqualTo(2));
    });
  }

  test('404 sonrasında ikinci sayfada hedef bulunursa kayıt korunur', () async {
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/responses/eksik')) return json({}, 404);
      if (!r.url.path.endsWith('/responses')) return json({'formId': 'f1'});
      return r.url.queryParameters['pageToken'] == null
          ? json({'responses': [], 'nextPageToken': 'ikinci'})
          : json({
              'responses': [
                {'responseId': 'eksik'},
              ],
            });
    });
    addTearDown(client.close);
    await expectLater(
      RehberlikGoogleFormService(client: client).yanitGoogledaYokMu(
        erisimBelirteci: 'test',
        googleFormId: 'f1',
        responseId: 'eksik',
      ),
      throwsStateError,
    );
  });
  for (final body in [
    '{"responseId":"canonical-other"}',
    '{}',
    '{"formId":"other","responseId":"r1"}',
    'invalid-json',
  ]) {
    test(
      'HTTP 200 belirsiz gövde yenilemeyi engellemez, yokluk sayılmaz: $body',
      () async {
        final client = MockClient((r) async {
          if (r.url.path.contains('/responses/')) {
            return http.Response(body, 200);
          }
          return json({'formId': 'f1'});
        });
        addTearDown(client.close);
        expect(
          await RehberlikGoogleFormService(client: client).yanitGoogledaYokMu(
            erisimBelirteci: 'test',
            googleFormId: 'f1',
            responseId: 'r1',
          ),
          false,
        );
      },
    );
    test('aynı belirsiz HTTP 200 gövde silmeye izin vermez: $body', () async {
      var scriptCalls = 0;
      final client = MockClient((r) async {
        if (r.url.host == 'script.googleapis.com') {
          scriptCalls++;
          return json({});
        }
        if (r.url.path.contains('/responses/')) return http.Response(body, 200);
        return json({'formId': 'f1'});
      });
      addTearDown(client.close);
      await expectLater(
        BilgiToplamaGoogleService(
          client: client,
        ).googleYanitSil('deployment-id', 'test', 'f1', 'r1'),
        throwsA(anything),
      );
      expect(scriptCalls, 0);
    });
  }
}
