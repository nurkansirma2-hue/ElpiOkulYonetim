import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bilgi_toplama_service.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_google_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselBilgiToplamaService local;
  late BilgiToplamaOturumu context;
  late int fid;
  late BilgiToplamaGoogleService google;
  late http.Client client;
  late Map<String, Map<String, dynamic>> native, rest;
  late List<String> deleted;
  late Set<String> failed;
  var complete = true,
      restDenied = false,
      delayedRest = false,
      lostPost = false;
  var continueWork = true, wrongResult = false;
  var scriptStatus = 200, oldProtocol = false, duplicate = false;
  Future<void> Function()? onRead;

  Map<String, dynamic> snapshot(String id, String name, String time) => {
    'source': 'apps-script/v2',
    'formId': 'google-form',
    'responseId': id,
    'submittedTime': time,
    'answers': [
      {
        'itemId': '1',
        'title': 'Öğrenci',
        'values': [name],
      },
    ],
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'school',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
      'EgitimYili': '2026-2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifKodu': '9/C',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'Gun': 'Pazartesi',
      'DersSaatiId': 1,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    for (var i = 1; i <= 2; i++) {
      await db.insert('Ogrenci', {
        'OkulNo': i == 1 ? '3004' : '4001',
        'Ad': i == 1 ? 'Çınar' : 'Diğer',
        'Soyad': i == 1 ? 'Kızmaz' : 'Öğrenci',
        'AnneAdi': 'Eski',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    local = BireyselBilgiToplamaService.instance;
    context = await local.hazirla();
    fid = await local.formOlustur(
      context,
      baslik: 'Doğrudan test',
      sorular: [
        BilgiToplamaSorusu(
          anahtar: 'anne',
          baslik: 'Anne',
          hedefAlan: 'AnneAdi',
        ),
      ],
    );
    final ids = {
      for (final q in await local.sorular(context, fid))
        q['AlanAnahtari'] as String: 'q${q['Id']}',
    };
    await local.googleBagla(context, fid, 'google-form', ids);
    await local.silmeBaglantisiniKaydet(context, 'test-deployment');
    Map<String, dynamic> restResponse(String id, {bool other = false}) => {
      'responseId': id,
      'lastSubmittedTime': '2026-11-18T10:00:00Z',
      'answers': {
        for (final e in {
          'okulNo': other ? '4001' : '3004',
          'adSoyad': other ? 'Diğer Öğrenci' : 'Çınar Kızmaz',
          'sinif': '9/C',
          'anne': 'Onaylı anne',
        }.entries)
          ids[e.key]: {
            'textAnswers': {
              'answers': [
                {'value': e.value},
              ],
            },
          },
      },
    };
    rest = {
      'rest-first': restResponse('rest-first'),
      'rest-last': restResponse('rest-last'),
      'rest-other': restResponse('rest-other', other: true),
    };
    final first = (await local.yanitlariKaydet(context, fid, [
      rest['rest-first']!,
    ])).single;
    await local.onayla(context, await local.onizle(context, first));
    await local.yanitlariKaydet(context, fid, [
      rest['rest-last']!,
      rest['rest-other']!,
    ]);
    native = {
      'native-first': snapshot(
        'native-first',
        '9/C • 3004 • Çınar Kızmaz',
        '2026-11-15T20:38:00.000Z',
      ),
      'native-last': snapshot(
        'native-last',
        '9/C • 3004 • Çınar Kızmaz',
        '2026-11-18T10:00:00.000Z',
      ),
      'native-other': snapshot(
        'native-other',
        '9/C • 4001 • Diğer Öğrenci',
        '2026-11-18T10:00:00.000Z',
      ),
    };
    deleted = [];
    failed = {};
    complete = true;
    restDenied = false;
    delayedRest = false;
    lostPost = false;
    continueWork = true;
    wrongResult = false;
    onRead = null;
    scriptStatus = 200; oldProtocol = false; duplicate = false;
    http.Response json(Object value, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(value)), status);
    client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.url.host == 'script.googleapis.com') {
        if (scriptStatus != 200) return json({}, scriptStatus);
        final body = jsonDecode(request.body) as Map;
        expect(body['devMode'], false);
        if (body['function'] == 'okulYanitlariOku') {
          if (onRead != null) await onRead!();
          return json({
            'done': true,
            'response': {
              'result': {
                'protocol': oldProtocol ? 'okul-yanitlar/v1' : 'okul-yanitlar/v2',
                'implementation': 'native-response-2026-11-20',
                'formId': 'google-form',
                'complete': complete,
                'count': native.length + (duplicate ? 1 : 0),
                'responses': [...native.values, if (duplicate) native.values.first],
              },
            },
          });
        }
        expect(body['function'], 'okulYanitSil');
        final parameters = body['parameters'] as List;
        expect(parameters, hasLength(3));
        final id = parameters[1] as String;
        expect(id, startsWith('native-'));
        expect(parameters[2], native[id]);
        if (failed.contains(id)) {
          return json({
            'done': true,
            'error': {'code': 3},
          });
        }
        native.remove(id);
        // Bu ilişki yalnız sahte Google sunucusunun gerçek depolama modelidir;
        // uygulamaya hiçbir REST/native eşleme verisi döndürülmez.
        if (!delayedRest) {
          rest.remove(
            {
              'native-first': 'rest-first',
              'native-last': 'rest-last',
              'native-other': 'rest-other',
            }[id],
          );
        }
        deleted.add(id);
        if (lostPost) throw http.ClientException('test connection lost');
        return json({
          'done': true,
          'response': {
            'result': {
              'protocol': 'okul-yanit-sil/v2',
              'implementation': 'native-response-2026-11-20',
              'formId': 'google-form',
              'responseId': wrongResult ? 'wrong-target' : id,
              'deleted': true,
              'absent': true,
            },
          },
        });
      }
      if (restDenied) return json({}, 403);
      if (request.url.path.endsWith('/responses')) {
        return json({'responses': rest.values.toList()});
      }
      if (request.url.path.contains('/responses/')) {
        final id = request.url.pathSegments.last;
        expect(
          id,
          startsWith('rest-'),
          reason: 'Native kimlikle REST 404 sorgusu yapılamaz',
        );
        return json(rest[id] ?? {}, rest.containsKey(id) ? 200 : 404);
      }
      return json({'formId': 'google-form'});
    });
    google = BilgiToplamaGoogleService(client: client);
  });
  tearDown(() async {
    client.close();
    await LocalDatabase.instance.close();
  });

  Future<BilgiToplamaTopluSilmeSonucu> remove(
    List<Map<String, dynamic>> snapshots,
  ) async {
    final plan = await local.topluSilmePlani(
      context,
      fid,
      sadeceKaydedilenler: false,
      seciliYanitIdleri: {},
    );
    return google.yanitlariTopluSil(
      local,
      context,
      plan,
      'test-token',
      dogrudanHedefler: snapshots,
      devamEt: () => continueWork,
    );
  }

  Future<List<Map<String, dynamic>>> read() =>
      google.dogrudanYanitlariAl(local, context, fid, 'test-token');

  test(
    'farklı REST kimliğine rağmen ilk seçilen gerçek yanıt silinir, son yanıt ve onaylı bilgiler korunur',
    () async {
      final before = await db.query('Ogrenci');
      final rows = await read();
      final result = await remove([
        rows.firstWhere((r) => r['responseId'] == 'native-first'),
      ]);
      expect(result.googleSilinen, 1);
      expect(result.kalan, 0);
      expect(result.yerelTemizlikTamam, true);
      expect(deleted, ['native-first']);
      expect(
        (await local.yanitlar(
          context,
          fid,
        )).map((r) => r['GoogleYanitId']).toSet(),
        {'rest-last', 'rest-other'},
      );
      expect(await db.query('Ogrenci'), before);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test('farklı öğrencilerden çoklu seçim yalnız seçilenleri siler', () async {
    final rows = await read();
    final result = await remove(
      rows.where((r) => r['responseId'] != 'native-last').toList(),
    );
    expect(result.googleSilinen, 2);
    expect(native.keys, ['native-last']);
    expect(
      (await local.yanitlar(context, fid)).single['GoogleYanitId'],
      'rest-last',
    );
  });
  test(
    'bir hedefin hatası diğer hedefin silme ve temizlik sonucunu kaybettirmez',
    () async {
      failed.add('native-first');
      final rows = await read();
      final result = await remove(
        rows.where((r) => r['responseId'] != 'native-last').toList(),
      );
      expect(result.googleSilinen, 1);
      expect(result.kalan, 1);
      expect(deleted, ['native-other']);
      expect(
        (await local.yanitlar(
          context,
          fid,
        )).map((r) => r['GoogleYanitId']).toSet(),
        {'rest-first', 'rest-last'},
      );
    },
  );
  test(
    'seçilen yanıt değişirse aynı öğrenciye ait diğer yanıt hedef yapılmaz',
    () async {
      final row = (await read()).first;
      native[row['responseId']]!['answers'] = [
        {
          'itemId': '1',
          'title': 'Öğrenci',
          'values': ['değişti'],
        },
      ];
      final result = await remove([row]);
      expect(result.basarili, 0);
      expect(deleted, isEmpty);
      expect(await local.yanitlar(context, fid), hasLength(3));
    },
  );
  test('eksik liste v2 sayılmaz ve silme çağrılmaz', () async {
    complete = false;
    await expectLater(read(), throwsStateError);
    expect(deleted, isEmpty);
  });
  test('okuma beklenirken iptal, POST gönderilmesini durdurur', () async {
    final row = (await read()).first;
    onRead = () async {
      continueWork = false;
    };
    final result = await remove([row]);
    expect(result.basarili, 0);
    expect(deleted, isEmpty);
  });
  test(
    'REST erişim hatasında uzak başarı bildirilir, ham kayıtlar korunur',
    () async {
      final row = (await read()).first;
      restDenied = true;
      final result = await remove([row]);
      expect(result.googleSilinen, 1);
      expect(result.yerelTemizlikTamam, false);
      expect(await local.yanitlar(context, fid), hasLength(3));
    },
  );
  test(
    'REST hâlâ gösteriyorsa native yokluk yerel ham kaydı temizlemez',
    () async {
      final row = (await read()).first;
      delayedRest = true;
      final result = await remove([row]);
      expect(result.googleSilinen, 1);
      expect(await local.yanitlar(context, fid), hasLength(3));
    },
  );
  test(
    'POST sonucu kaybolunca silme yinelenmez, bağımsız yokluk doğrulanır',
    () async {
      final row = (await read()).first;
      lostPost = true;
      final result = await remove([row]);
      expect(result.basarili, 1);
      expect(result.yokluguDogrulanan, 1);
      expect(result.googleSilinen, 0);
      expect(deleted, hasLength(1));
    },
  );
  test('yanlış hedefli betik cevabı başarı sayılmaz', () async {
    final row = (await read()).first;
    wrongResult = true;
    final result = await remove([row]);
    expect(result.basarili, 0);
    expect(await local.yanitlar(context, fid), hasLength(3));
  });

  for (final status in [401, 403, 404, 500]) {
    test('doğrudan okuma HTTP $status ise silme ve yerel temizlik yapılmaz', () async {
      scriptStatus = status;
      await expectLater(read(), throwsStateError);
      expect(deleted, isEmpty);
      expect(await local.yanitlar(context, fid), hasLength(3));
    });
  }
  test('eski dağıtım protokolü yeni kimlik kaynağı olarak kabul edilmez', () async {
    oldProtocol = true;
    await expectLater(read(), throwsStateError);
    expect(deleted, isEmpty);
  });
  test('tekrarlı native kimlik eksiksiz liste sayılmaz', () async {
    duplicate = true;
    await expectLater(read(), throwsFormatException);
    expect(deleted, isEmpty);
  });
  test('native liste boş diye eski REST kayıtları topluca temizlenmez', () async {
    native.clear();
    expect(await read(), isEmpty);
    expect(await local.yanitlar(context, fid), hasLength(3));
    expect(deleted, isEmpty);
  });
}
