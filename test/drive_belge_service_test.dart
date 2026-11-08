import 'dart:convert';

import 'package:elpi_okul_yonetim/services/drive_belge_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Listeleme en fazla üç sayfa metadata okur; içerik indirmez', () async {
    var sayi = 0;
    final client = MockClient((r) async {
      sayi++;
      expect(r.url.path, '/drive/v3/files');
      expect(r.url.queryParameters['pageSize'], '100');
      expect(r.url.queryParameters['fields'], isNot(contains('accessToken')));
      return http.Response(
        jsonEncode({'files': [], 'nextPageToken': '$sayi'}),
        200,
      );
    });
    expect(
      await DriveBelgeService(client: client).adaylariListele('test'),
      isEmpty,
    );
    expect(sayi, 3);
    client.close();
  });
  Map<String, dynamic> meta({String version = '1', String? mime, String? ad}) =>
      {
        'id': 'dosya-1',
        'name': ad ?? 'plan.csv',
        'version': version,
        'mimeType': mime ?? 'text/csv',
        'size': '3',
        'trashed': false,
        'capabilities': {'canDownload': true},
      };
  Future<void> hata(Map<String, dynamic> metadata) async {
    var cagrilar = 0;
    final client = MockClient((request) async {
      cagrilar++;
      return http.Response(jsonEncode(metadata), 200);
    });
    await expectLater(
      DriveBelgeService(
        client: client,
      ).indir(token: 'test-token', dosyaId: 'dosya-1', uzantilar: {'csv'}),
      throwsA(anything),
    );
    expect(cagrilar, 1);
    client.close();
  }

  test(
    'Yalnız seçili dosyayı okur; indirmeden önce ve sonra sürümü doğrular',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.url.host, 'www.googleapis.com');
        return request.url.queryParameters['alt'] == 'media'
            ? http.Response('abc', 200)
            : http.Response(jsonEncode(meta()), 200);
      });
      final dosya = await DriveBelgeService(
        client: client,
      ).indir(token: 'test-token', dosyaId: 'dosya-1', uzantilar: {'csv'});
      expect(dosya.ad, 'plan.csv');
      expect(dosya.bytes, utf8.encode('abc'));
      expect(requests, hasLength(3));
      expect(requests.every((r) => r.url.path.endsWith('/dosya-1')), isTrue);
      client.close();
    },
  );

  test(
    'İzin verilmeyen, silinen, büyük ve yanlış tür dosya indirilmez',
    () async {
      await hata({
        ...meta(),
        'capabilities': {'canDownload': false},
      });
      await hata({...meta(), 'trashed': true});
      await hata({...meta(), 'size': '${DriveBelgeService.azamiBoyut + 1}'});
      await hata(meta(mime: 'application/pdf', ad: 'plan.csv'));
    },
  );

  test('İndirme sırasında değişen sürüm ön izlemeye gönderilmez', () async {
    var metaSayisi = 0;
    final client = MockClient(
      (request) async => request.url.queryParameters['alt'] == 'media'
          ? http.Response('abc', 200)
          : http.Response(jsonEncode(meta(version: '${++metaSayisi}')), 200),
    );
    await expectLater(
      DriveBelgeService(
        client: client,
      ).indir(token: 'test-token', dosyaId: 'dosya-1', uzantilar: {'csv'}),
      throwsStateError,
    );
    client.close();
  });

  test(
    'Google belgesi uygun Office biçimine dışa aktarılır; kaynak değiştirilmez',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/export')) {
          expect(
            request.url.queryParameters['mimeType'],
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          );
          return http.Response('abc', 200);
        }
        return http.Response(
          jsonEncode(
            meta(mime: 'application/vnd.google-apps.document', ad: 'Plan'),
          ),
          200,
        );
      });
      final dosya = await DriveBelgeService(
        client: client,
      ).indir(token: 'test-token', dosyaId: 'dosya-1', uzantilar: {'docx'});
      expect(dosya.ad, 'Plan.docx');
      client.close();
    },
  );

  test(
    'HTTP hatası tokenı veya Google yanıtındaki özel bilgileri göstermez',
    () async {
      final client = MockClient(
        (_) async => http.Response('test-token secret', 403),
      );
      try {
        await DriveBelgeService(
          client: client,
        ).indir(token: 'test-token', dosyaId: 'dosya-1', uzantilar: {'csv'});
        fail('İstek reddedilmeliydi');
      } catch (e) {
        expect('$e', contains('403'));
        expect('$e', isNot(contains('test-token')));
        expect('$e', isNot(contains('secret')));
      } finally {
        client.close();
      }
    },
  );

  test('Picker iptali ağ isteği veya kayıt başlatmaz', () async {
    const channel = MethodChannel('elpi_okul_yonetim/drive_belge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'sec');
          expect(
            (call.arguments as Map)['mimeTurleri'],
            contains('application/pdf'),
          );
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final client = MockClient((_) async {
      fail('İptalde ağ çağrısı olmamalı');
    });
    expect(await DriveBelgeService(client: client).sec({'pdf'}), isNull);
    client.close();
  });
}
