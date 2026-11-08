import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elpi_okul_yonetim/services/ogretmen_gorus_google_service.dart';

Map<String, dynamic> sonuc({bool yayin = false}) => {
  'protocol': 'okul-ogretmen-gorus/v1',
  'requestId': 'a' * 32,
  'formId': 'form_1',
  'ready': true,
  'published': yayin,
  'acceptingResponses': yayin,
  'editUrl': 'https://docs.google.com/forms/d/form_1/edit',
  'responderUrl': 'https://docs.google.com/forms/d/e/form_1/viewform',
};
http.Response cevap(Map<String, dynamic> r) => http.Response(
  jsonEncode({
    'done': true,
    'response': {'result': r},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('özel API endpoint, OAuth, fotoğraflı payload ve protokol', () async {
    final s = OgretmenGorusGoogleService(
      dagitim: 'dagitim',
      client: MockClient((r) async {
        expect(
          r.url.toString(),
          'https://script.googleapis.com/v1/scripts/dagitim:run',
        );
        expect(r.headers['Authorization'], 'Bearer test-token');
        final body = jsonDecode(r.body) as Map;
        expect(body['function'], 'okulOgretmenGorusFormOlustur');
        expect(body['devMode'], false);
        expect((body['parameters'] as List).single['requestId'], 'a' * 32);
        return cevap(sonuc());
      }),
    );
    expect(
      (await s.olustur('test-token', {'requestId': 'a' * 32}))['formId'],
      'form_1',
    );
  });
  test('kurulum eski ise form açılmaz', () async {
    final s = OgretmenGorusGoogleService(
      client: MockClient(
        (r) async => cevap({'protocol': 'eski', 'ready': true}),
      ),
    );
    await expectLater(s.kontrol('token'), throwsStateError);
  });
  test(
    'yanlış request/form kimliği ve tehlikeli bağlantı reddedilir',
    () async {
      for (final bozuk in [
        {...sonuc(), 'requestId': 'b' * 32},
        {...sonuc(), 'formId': 'yanlis'},
        {
          ...sonuc(),
          'responderUrl':
              'https://docs.google.com.evil.com/forms/d/e/a/viewform',
        },
        {...sonuc(), 'editUrl': 'http://docs.google.com/forms/d/a/edit'},
      ]) {
        final s = OgretmenGorusGoogleService(
          client: MockClient((r) async => cevap(bozuk)),
        );
        await expectLater(
          s.yayinla('token', 'a' * 32, 'form_1'),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
      }
    },
  );
  test('yayımlama doğrulanmadan gönderime geçilmez', () async {
    final s = OgretmenGorusGoogleService(
      client: MockClient((r) async => cevap(sonuc())),
    );
    await expectLater(s.yayinla('token', 'a' * 32, 'form_1'), throwsStateError);
  });
  test('HTTP veya script hatası kişisel yanıtı hata mesajına dökmez', () async {
    for (final response in [
      http.Response('GIZLI_TOKEN_OGR_ENCI', 403),
      http.Response(
        jsonEncode({
          'done': true,
          'error': {'message': 'GIZLI_TOKEN_OGR_ENCI'},
        }),
        200,
      ),
    ]) {
      final s = OgretmenGorusGoogleService(
        client: MockClient((r) async => response),
      );
      try {
        await s.kontrol('token');
        fail('Hata bekleniyor');
      } catch (e) {
        expect(e, isA<StateError>());
        expect('$e', isNot(contains('GIZLI')));
      }
    }
  });
  test('görüşler sayfalanır ve responseId ile birleştirilir', () async {
    var call = 0;
    final s = OgretmenGorusGoogleService(
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map;
        expect((body['parameters'] as List).last, call == 0 ? 0 : 50);
        call++;
        return cevap({
          'protocol': 'okul-ogretmen-gorus/v1',
          'requestId': 'a' * 32,
          'formId': 'form_1',
          'yanitlar': [
            {
              'responseId': 'y1',
              'ogrenciler': {'1': call == 1 ? 'İlk' : 'Güncel'},
            },
          ],
          'nextOffset': call == 1 ? 50 : null,
        });
      }),
    );
    final r = await s.yanitlar('token', 'a' * 32, 'form_1');
    expect(r, hasLength(1));
    expect((r.single['ogrenciler'] as Map)['1'], 'Güncel');
  });
  test('bozuk sayfalama sonsuz döngüye girmez', () async {
    final s = OgretmenGorusGoogleService(
      client: MockClient(
        (r) async => cevap({
          'protocol': 'okul-ogretmen-gorus/v1',
          'requestId': 'a' * 32,
          'formId': 'form_1',
          'yanitlar': [],
          'nextOffset': 0,
        }),
      ),
    );
    await expectLater(
      s.yanitlar('token', 'a' * 32, 'form_1'),
      throwsFormatException,
    );
  });
}
