import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_google_form_service.dart';

void main() {
  test('MEB ve ek sorular tekilleştirilir; öğrenci seçimi ilk sorudur', () {
    final sorular = RehberlikGoogleFormService.sorulariHazirla([
      'Özel soru',
      'Adınız Soyadınız',
      'Okul numaranız',
      'Sınıfınız',
      'Okulunuz',
      'Özel soru',
      '  ',
    ]);
    expect(sorular.where((s) => s == 'Özel soru'), hasLength(1));
    expect(sorular.first, RehberlikGoogleFormService.ogrenciSecimSorusu);
    expect(sorular, isNot(contains(RehberlikGoogleFormService.davetSorusu)));
    expect(sorular, isNot(contains('Adınız Soyadınız')));
    expect(sorular, isNot(contains('Okul numaranız')));
    expect(sorular, isNot(contains('Sınıfınız')));
    expect(sorular, isNot(contains('Okulunuz')));
    expect(sorular.toSet().length, sorular.length);
  });

  test('Form kimliği sorulardan önce kalıcı kayda bildirilir', () async {
    final sira = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/v1/forms') {
        sira.add('create');
        return http.Response('{"formId":"form123"}', 200);
      }
      if (request.url.path.endsWith(':batchUpdate')) {
        sira.add('batch');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final istekler = body['requests'] as List;
        final davet = istekler.singleWhere(
          (r) =>
              r['createItem']['item']['title'] ==
              RehberlikGoogleFormService.ogrenciSecimSorusu,
        );
        expect(
          davet['createItem']['item']['questionItem']['question']['required'],
          isTrue,
        );
        expect(davet['createItem']['location']['index'], 0);
        expect(
          davet['createItem']['item']['questionItem']['question']['choiceQuestion']['type'],
          'DROP_DOWN',
        );
        return http.Response(
          jsonEncode({
            'replies': [
              for (var i = 0; i < istekler.length; i++)
                {
                  'createItem': {
                    'itemId': 'item$i',
                    'questionId': ['question$i'],
                  },
                },
            ],
          }),
          200,
        );
      }
      throw StateError('Beklenmeyen istek: ${request.url}');
    });
    final service = RehberlikGoogleFormService(client: client);
    final sorular = RehberlikGoogleFormService.sorulariHazirla(['Özel soru']);
    final sonuc = await service.formOlustur(
      erisimBelirteci: 'test-token',
      baslik: '9-C',
      sorular: sorular,
      ogrenciSecenekleri: ['1 – Öğrenci Test'],
      onFormOlusturuldu: (id) async {
        expect(id, 'form123');
        sira.add('sqlite');
      },
    );
    expect(sira, ['create', 'sqlite', 'batch']);
    expect(sonuc.googleFormId, 'form123');
    expect(sonuc.soruEslemeleri.length, sorular.length);
    expect(sonuc.soruEslemeleri['Özel soru']?['questionId'], isNotEmpty);
    service.dispose();
  });

  test('Google yanıtları sayfalanır ve questionId ile eşleştirilir', () async {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.toString());
      final token = request.url.queryParameters['pageToken'];
      if (token == null) {
        return http.Response(
          jsonEncode({
            'responses': [
              {
                'responseId': 'response1',
                'answers': {
                  'question1': {
                    'textAnswers': {
                      'answers': [
                        {'value': 'Merhaba'},
                      ],
                    },
                  },
                },
              },
            ],
            'nextPageToken': 'next',
          }),
          200,
        );
      }
      expect(token, 'next');
      return http.Response(
        jsonEncode({
          'responses': [
            {
              'responseId': 'response2',
              'answers': {
                'question1': {
                  'textAnswers': {
                    'answers': [
                      {'value': 'İkinci'},
                    ],
                  },
                },
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = RehberlikGoogleFormService(client: client);
    final rows = await service.yanitlariGetir(
      erisimBelirteci: 'test',
      googleFormId: 'form123',
    );
    expect(rows, hasLength(2));
    expect(requested, hasLength(2));
    final sonuc = RehberlikGoogleFormService.yanitiEsle(rows.first, {
      'Özel soru': {'itemId': 'item1', 'questionId': 'question1'},
    });
    expect(sonuc['Özel soru'], 'Merhaba');
  });
  test(
    'Eski form dönüştürülür; soru kimlikleri korunur ve sadece seçim seçenekleri güncellenir',
    () async {
      final items = <Map<String, dynamic>>[
        {
          'itemId': 'old-code',
          'title': RehberlikGoogleFormService.davetSorusu,
          'questionItem': {
            'question': {
              'questionId': 'code-q',
              'required': true,
              'textQuestion': {'paragraph': true},
            },
          },
        },
        {
          'itemId': 'old-ad',
          'title': 'Adınız Soyadınız',
          'questionItem': {
            'question': {
              'questionId': 'ad-q',
              'required': true,
              'textQuestion': {'paragraph': true},
            },
          },
        },
        {
          'itemId': 'adres',
          'title': 'Adresiniz',
          'questionItem': {
            'question': {
              'questionId': 'adres-q',
              'required': false,
              'textQuestion': {'paragraph': true},
            },
          },
        },
      ];
      for (final title in ['Sınıfınız', 'Okulunuz', 'Okul numaranız']) {
        items.insert(1, {
          'itemId': 'old-$title',
          'title': title,
          'questionItem': {
            'question': {
              'questionId': 'q-$title',
              'required': false,
              'textQuestion': {'paragraph': true},
            },
          },
        });
      }
      final oldAnswers = {'code-q': 'old-code-value', 'adres-q': 'Eski yanıt'};
      final previous = jsonEncode(items.last);
      var creates = 0;
      final g = RehberlikGoogleFormService(
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return http.Response(
              jsonEncode({
                'formId': 'old-form',
                'revisionId': 'r1',
                'items': items,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(r.url.path, '/v1/forms/old-form:batchUpdate');
          final body = jsonDecode(r.body) as Map;
          expect(body['writeControl']['requiredRevisionId'], 'r1');
          for (final req in body['requests'] as List) {
            if (req.containsKey('deleteItem')) {
              final index = req['deleteItem']['location']['index'] as int;
              expect([
                'Adınız Soyadınız',
                'Sınıfınız',
                'Okulunuz',
                'Okul numaranız',
              ], contains(items[index]['title']));
              items.removeAt(index);
            } else if (req.containsKey('createItem')) {
              creates++;
              final item = Map<String, dynamic>.from(
                req['createItem']['item'] as Map,
              );
              item['itemId'] = 'select-item';
              item['questionItem']['question']['questionId'] = 'select-q';
              items.insert(req['createItem']['location']['index'] as int, item);
            } else if (req.containsKey('updateItem')) {
              final u = req['updateItem'];
              final index = u['location']['index'] as int;
              expect(u['updateMask'].toString(), isNot(contains('questionId')));
              final q = items[index]['questionItem']['question'] as Map;
              final next = u['item']['questionItem']['question'] as Map;
              expect(q['questionId'], next['questionId']);
              q['required'] = next['required'];
              if (next.containsKey('choiceQuestion')) {
                q['choiceQuestion']['options'] =
                    next['choiceQuestion']['options'];
              }
            } else if (req.containsKey('moveItem')) {
              final m = req['moveItem'];
              final item = items.removeAt(
                m['originalLocation']['index'] as int,
              );
              items.insert(m['newLocation']['index'] as int, item);
            }
          }
          return http.Response('{}', 200);
        }),
      );
      final first = await g.ogrenciListesiniGuncelle(
        erisimBelirteci: 'fake',
        googleFormId: 'old-form',
        secenekler: ['1 – Öğrenci1 Test'],
      );
      expect(
        items.first['title'],
        RehberlikGoogleFormService.ogrenciSecimSorusu,
      );
      expect(items.first['questionItem']['question']['required'], isTrue);
      expect(items[1]['questionItem']['question']['required'], isFalse);
      expect(
        first.soruEslemeleri[RehberlikGoogleFormService
            .davetSorusu]?['questionId'],
        'code-q',
      );
      final second = await g.ogrenciListesiniGuncelle(
        erisimBelirteci: 'fake',
        googleFormId: 'old-form',
        secenekler: ['3004 – YeniAd Test'],
      );
      expect(creates, 1);
      expect(
        second.soruEslemeleri[RehberlikGoogleFormService
            .ogrenciSecimSorusu]?['questionId'],
        'select-q',
      );
      expect(jsonEncode(items.last), previous);
      expect(oldAnswers, {'code-q': 'old-code-value', 'adres-q': 'Eski yanıt'});
      expect(items.map((i) => i['title']), isNot(contains('Okulunuz')));
      // Seçim sorusu ilk sırada değilken silmelerin ardından doğru indeksle taşınır.
      final select = items.removeAt(0);
      items.add(select);
      items.insert(0, {
        'itemId': 'school-again',
        'title': 'Okulunuz',
        'questionItem': {
          'question': {
            'questionId': 'school-q',
            'required': false,
            'textQuestion': {'paragraph': true},
          },
        },
      });
      await g.ogrenciListesiniGuncelle(
        erisimBelirteci: 'fake',
        googleFormId: 'old-form',
        secenekler: ['3004 – YeniAd Test'],
      );
      expect(items.first['itemId'], 'select-item');
      expect(items.last['itemId'], 'adres');
    },
  );
}
