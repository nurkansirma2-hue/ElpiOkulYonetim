import 'package:elpi_okul_yonetim/models/ogrenci_bilgi_formu.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_toplu_form_import.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_rehberlik_dosyasi_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_rehberlik_ogrencileri_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselRehberlikBaglami contextData;
  final service = BireyselRehberlikService.instance;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifKodu': '9/A',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OkulNo': '123',
      'Ad': 'Örnek',
      'Soyad': 'Öğrenci',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('RehberlikAtama', {
      'OkulId': 'okul',
      'OgretmenProfilId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026/2027',
      'BaslangicTarihi': '2000-01-01',
      'OlusturmaTarihi': 'test',
    });
    contextData = await service.hazirla();
  });
  tearDown(() => LocalDatabase.instance.close());
  late RehberlikTopluFormImport batch;
  setUp(() async {
    await db.insert('Ogrenci', {
      'OkulNo': '124',
      'Ad': 'İkinci',
      'Soyad': 'Öğrenci',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 2,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    batch = RehberlikTopluFormImport(
      service: service,
      baglam: contextData,
      atamaId: 1,
    );
  });
  Map<String, String> values(int student) => {
    'Adınız Soyadınız': student == 1 ? 'Örnek Öğrenci' : 'İkinci Öğrenci',
    'Okul numaranız': student == 1 ? '00123' : '124',
    'Sınıfınız': '9A',
    'Anne mesleği': 'Öğretmen',
  };
  ImportKaynakSatiri source(String id, int student) =>
      batch.kaynak(id, '$id.jpg', values(student));
  test(
    'Toplu eşleştirme farklı öğrencileri ayırır; seçim yapmadan kayıt olmaz',
    () async {
      final preview = await batch.hazirla([source('a', 1), source('b', 2)]);
      expect(
        preview.kayitlar.every((r) => r.durum == ImportDurumu.uyarili),
        true,
      );
      expect(ImportOturumu(preview).secimler, isEmpty);
      expect(await db.query('RehberlikForm'), isEmpty);
      await batch.kaydet(preview, {'b'});
      final rows = await db.query('RehberlikForm');
      expect(rows, hasLength(1));
      expect(rows.single['OgrenciId'], 2);
      expect(
        (jsonDecode(rows.single['Cevaplar'] as String) as Map)['Anne mesleği'],
        'Öğretmen',
      );
    },
  );
  test(
    'Tekrar resimleri ayrılır, Atla düzeltmesi tek formu serbest bırakır',
    () async {
      final preview = await batch.hazirla([source('a', 1), source('b', 1)]);
      expect(
        preview.kayitlar.every((r) => r.durum == ImportDurumu.hatali),
        true,
      );
      final fixed = await batch.tanim.duzenlemeHazirla!(preview, [
        source('a', 1),
        ImportKaynakSatiri('b', 'b.jpg', {
          ...source('b', 1).degerler,
          'islem': 'Atla',
        }),
      ]);
      expect(fixed.kayitlar.first.aktarilabilir, true);
      expect(fixed.kayitlar.last.durum, ImportDurumu.atlanan);
      final result = await batch.kaydet(fixed, {'a'});
      expect(result.eklenen, 1);
      expect(result.atlanan, 1);
      expect(await db.query('RehberlikForm'), hasLength(1));
    },
  );
  test(
    'Yanlış ad, sınıf, eksik numara ve inaktif öğrenci kaydedilemez',
    () async {
      final bad = [
        batch.kaynak('ad', 'ad.jpg', {
          ...values(1),
          'Adınız Soyadınız': 'Başka Öğrenci',
        }),
        batch.kaynak('sinif', 'sinif.jpg', {...values(2), 'Sınıfınız': '10/A'}),
        batch.kaynak('no', 'no.jpg', {...values(1), 'Okul numaranız': ''}),
      ];
      final p = await batch.hazirla(bad);
      expect(p.kayitlar.every((r) => !r.aktarilabilir), true);
      await expectLater(batch.kaydet(p, {'ad'}), throwsStateError);
      await db.update('Ogrenci', {'Aktif': 0}, where: 'OgrenciId=1');
      expect(
        (await batch.hazirla([source('a', 1)])).kayitlar.single.aktarilabilir,
        false,
      );
      expect(await db.query('RehberlikForm'), isEmpty);
    },
  );
  test(
    'Boş cevaplar, eski özel sorular ve öğrenci ana kaydı toplu kayıtta korunur',
    () async {
      await service.formKaydet(
        contextData,
        1,
        1,
        ['Eski soru', 'Baba mesleği'],
        {'Eski soru': 'Korunacak', 'Baba mesleği': 'Esnaf'},
        hassasOnay: true,
      );
      final old = (await db.query('RehberlikForm')).single;
      final students = await db.query('Ogrenci');
      final p = await batch.hazirla([source('a', 1), source('b', 2)]);
      final result = await batch.kaydet(p, {'a', 'b'});
      expect(result.eklenen, 1);
      expect(result.guncellenen, 1);
      final rows = await db.query('RehberlikForm', orderBy: 'Id');
      expect(rows.first, old);
      final last = rows.where((r) => r['OgrenciId'] == 1).last;
      final answers = jsonDecode(last['Cevaplar'] as String) as Map;
      expect(answers['Eski soru'], 'Korunacak');
      expect(answers['Baba mesleği'], 'Esnaf');
      expect(answers['Anne mesleği'], 'Öğretmen');
      expect(await db.query('Ogrenci'), students);
      final same = await batch.hazirla([source('a', 1), source('b', 2)]);
      final again = await batch.kaydet(same, {'a', 'b'});
      expect(again.atlanan, 2);
      expect(await db.query('RehberlikForm'), hasLength(3));
    },
  );
  test(
    'İkinci form hatalıysa ilk form da transaction ile geri alınır',
    () async {
      await expectLater(
        service.formlariTopluKaydet(contextData, 1, [
          RehberlikFormAktarimi(
            ogrenciId: 1,
            beklenenSonFormId: null,
            cevaplar: values(1),
          ),
          RehberlikFormAktarimi(
            ogrenciId: 2,
            beklenenSonFormId: 999,
            cevaplar: values(2),
          ),
        ], hassasOnay: true),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), isEmpty);
    },
  );
  test('Ön izlemeden sonraki değişiklik eski OCR ile ezilmez', () async {
    final p = await batch.hazirla([source('a', 1), source('b', 2)]);
    await service.formKaydet(
      contextData,
      1,
      2,
      ['Elle girilen'],
      {'Elle girilen': 'Yeni bilgi'},
      hassasOnay: true,
    );
    final before = await db.query('RehberlikForm');
    await expectLater(batch.kaydet(p, {'a', 'b'}), throwsStateError);
    expect(await db.query('RehberlikForm'), before);
  });
  test(
    'Hatalı resim seçilmeden diğer form kaydolur ve sonuç sayıları doğrudur',
    () async {
      final p = await batch.hazirla([
        source('a', 1),
        batch.kaynak('bozuk', 'bozuk.jpg', {}, hata: 'Okuma hatası'),
      ]);
      final result = await batch.kaydet(p, {'a'});
      expect(result.eklenen, 1);
      expect(result.hatali, 1);
      expect(result.atlanan, 0);
    },
  );
  test(
    'Hassas onay, mod, atama ve okul kapsamı toplu kayıtta zorunludur',
    () async {
      final request = RehberlikFormAktarimi(
        ogrenciId: 1,
        beklenenSonFormId: null,
        cevaplar: values(1),
      );
      await expectLater(
        service.formlariTopluKaydet(contextData, 1, [
          request,
        ], hassasOnay: false),
        throwsStateError,
      );
      await db.update('RehberlikAtama', {'BitisTarihi': '2000-01-02'});
      await expectLater(batch.hazirla([source('a', 1)]), throwsStateError);
      await expectLater(
        service.formlariTopluKaydet(contextData, 1, [
          request,
        ], hassasOnay: true),
        throwsStateError,
      );
      await db.update('RehberlikAtama', {'BitisTarihi': null});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('calisma_modu', 'kurumsal');
      await expectLater(batch.hazirla([source('a', 1)]), throwsStateError);
      await prefs.setString('calisma_modu', 'bireysel');
      await db.update('OkulProfil', {'OkulAdi': 'Başka Okul'});
      await db.update('OgretmenProfil', {'OkulAdi': 'Başka Okul'});
      await expectLater(
        service.formlariTopluKaydet(contextData, 1, [
          request,
        ], hassasOnay: true),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), isEmpty);
    },
  );
  test('Çift öğrenci ve sahte seçim kimliği reddedilir', () async {
    final r = RehberlikFormAktarimi(
      ogrenciId: 1,
      beklenenSonFormId: null,
      cevaplar: values(1),
    );
    await expectLater(
      service.formlariTopluKaydet(contextData, 1, [r, r], hassasOnay: true),
      throwsFormatException,
    );
    final p = await batch.hazirla([source('a', 1)]);
    await expectLater(batch.kaydet(p, {'olmayan'}), throwsFormatException);
    expect(await db.query('RehberlikForm'), isEmpty);
  });
  testWidgets('Öğrencilerim bölümünden ortak toplu resim importu açılır', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final atama = (await service.atamalariGetir(contextData)).single;
    await tester.pumpWidget(
      MaterialApp(
        home: BireyselRehberlikDosyasiScreen(
          service: service,
          baglam: contextData,
          atama: atama,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Öğrencilerim'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rehberlik-toplu-form-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erişimi aç'));
    await tester.pumpAndSettle();
    expect(find.text('Cihazdan Birden Fazla Resim Seç'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(await db.query('RehberlikForm'), isEmpty);
  });
  testWidgets(
    'Fotoğraflı Öğrencilerim ekranından da toplu resim importu açılır',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BireyselRehberlikOgrencileriScreen(
            service: service,
            baglam: contextData,
            atamaId: 1,
            sinifKodu: '9/A',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('rehberlik-toplu-form-import')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Devam Et'));
      await tester.pumpAndSettle();
      expect(find.text('Cihazdan Birden Fazla Resim Seç'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
