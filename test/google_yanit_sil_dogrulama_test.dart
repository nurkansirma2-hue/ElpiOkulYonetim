import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_google_service.dart';

void main() {
  for (final status in [200, 403, 404]) {
    test(
      'betik hatasında yalnız erişilebilir form ve yanıt 404 kurtarılır: $status',
      () async {
        var formChecks = 0;
        final client = MockClient((r) async {
          if (r.url.host == 'script.googleapis.com') {
            final body = jsonDecode(r.body);
            expect(body['devMode'], false);
            if (body['function'] == 'okulYanitSilKurulumKontrol') {
              expect(body['parameters'], isEmpty);
              return http.Response(
                jsonEncode({
                  'done': true,
                  'response': {
                    'result': {
                      'protocol': 'okul-yanit-sil/v1',
                      'ready': true,
                      'implementation': 'exact-response-2026-11-19',
                    },
                  },
                }),
                200,
              );
            }
            expect(body['function'], 'okulYanitSil');
            expect(body['parameters'], ['f1', 'r1']);
            return http.Response(
              jsonEncode({
                'done': true,
                'error': {'code': 3},
              }),
              200,
            );
          }
          expect(r.method, 'GET');
          if (r.url.path.endsWith('/responses/r1')) {
            return http.Response('{}', status);
          }
          formChecks++;
          return http.Response(jsonEncode({'formId': 'f1'}), 200);
        });
        final future = BilgiToplamaGoogleService(
          client: client,
        ).googleYanitSil('deployment', 'token', 'f1', 'r1');
        if (status == 404) {
          await future;
          expect(formChecks, 2);
        } else {
          await expectLater(future, throwsStateError);
        }
        client.close();
      },
    );
  }

  test('başarısız silmede REST ve Apps Script kimlik sayımı salt okunur karşılaştırılır', () async {
    var diagnoseCount = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'script.googleapis.com') {
        final body = jsonDecode(request.body);
        switch (body['function']) {
          case 'okulYanitSilKurulumKontrol':
            return http.Response(jsonEncode({
              'done': true,
              'response': {'result': {
                'protocol': 'okul-yanit-sil/v1',
                'ready': true,
                'implementation': 'exact-response-2026-11-19',
              }},
            }), 200);
          case 'okulYanitSil':
            return http.Response(jsonEncode({
              'done': true,
              'error': {'code': 3},
            }), 200);
          case 'okulYanitKimlikTani':
            diagnoseCount++;
            expect(body['parameters'], ['f1', 'r1']);
            return http.Response(jsonEncode({
              'done': true,
              'response': {'result': {
                'protocol': 'okul-yanit-kimlik-tani/v1',
                'formId': 'f1',
                'scriptCount': 23,
                'exactMatches': 0,
              }},
            }), 200);
        }
      }
      if (request.url.path.endsWith('/responses/r1')) {
        return http.Response('{}', 200);
      }
      return http.Response(jsonEncode({'formId': 'f1'}), 200);
    });
    await expectLater(
      BilgiToplamaGoogleService(client: client)
          .googleYanitSil('deployment', 'token', 'f1', 'r1'),
      throwsA(isA<StateError>().having(
        (error) => error.message.toString(), 'tanı',
        allOf(contains('yanıt sayısı: 23'), contains('kimlik eşleşmesi: 0')),
      )),
    );
    expect(diagnoseCount, 1);
    client.close();
  });

  test('erişilemeyen formun 404 sonucu yanıt yokluğu sayılmaz', () async {
    var responseChecks = 0;
    final client = MockClient((r) async {
      if (r.url.host == 'script.googleapis.com') {
        final body = jsonDecode(r.body);
        if (body['function'] == 'okulYanitSilKurulumKontrol') {
          return http.Response(
            jsonEncode({
              'done': true,
              'response': {
                'result': {
                  'protocol': 'okul-yanit-sil/v1',
                  'ready': true,
                  'implementation': 'exact-response-2026-11-19',
                },
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 3},
          }),
          200,
        );
      }
      if (r.url.path.contains('/responses/')) responseChecks++;
      return http.Response('{}', 404);
    });
    await expectLater(
      BilgiToplamaGoogleService(
        client: client,
      ).googleYanitSil('deployment', 'token', 'f1', 'r1'),
      throwsStateError,
    );
    expect(responseChecks, 0);
    client.close();
  });
  test('eski dağıtımda silme çağrısı yapılmaz ve yanıt korunur', () async {
    var deleteCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'script.googleapis.com') {
        final body = jsonDecode(request.body);
        if (body['function'] == 'okulYanitSil') deleteCalls++;
        return http.Response(
          jsonEncode({
            'done': true,
            'response': {
              'result': {
                'protocol': 'okul-yanit-sil/v1',
                'ready': true,
                'implementation': 'old-deployment',
              },
            },
          }),
          200,
        );
      }
      fail('Eski dağıtımda Forms API çağrısı beklenmiyor');
    });
    await expectLater(
      BilgiToplamaGoogleService(
        client: client,
      ).googleYanitSil('deployment', 'token', 'f1', 'r1'),
      throwsA(isA<StateError>().having(
        (e) => e.message.toString(),
        'mesaj',
        contains('yayımlanmış sürümü güncel değil'),
      )),
    );
    expect(deleteCalls, 0);
    client.close();
  });
}
