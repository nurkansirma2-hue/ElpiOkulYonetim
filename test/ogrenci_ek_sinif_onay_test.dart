import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_import_tanimi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

ImportOnIzleme _preview({bool normal = true}) => ImportOnIzleme([
  if (normal) ...[
    ImportKaydi('101', 'Satır 2', {'okulNo': '101', 'sinif': '9-A'}),
    ImportKaydi('102', 'Satır 3', {'okulNo': '102', 'sinif': '9-A'}),
  ],
  ImportKaydi('201', 'Satır 4', {
    'okulNo': '201',
    'sinif': '10-B',
  }, durum: ImportDurumu.atlanan),
]);

ImportSecimi _secim(ImportOnIzleme preview) => ImportSecimi(
  ImportDosya(
    'liste.csv',
    Uint8List.fromList(utf8.encode('Okul No;Sınıf\n101;9-A')),
  ),
  preview,
  preview.kayitlar.where((r) => r.aktarilabilir).map((r) => r.id).toSet(),
);

ImportOzet _sonuc(int adet) => ImportOzet(
  eklenen: adet,
  guncellenen: 0,
  atlanan: 0,
  hatali: 0,
  mesaj: 'Kaydedildi',
);

Future<void> _dokun(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _ortakDokun(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

Future<void> _onayEkrani(
  WidgetTester tester,
  OgrenciImportKayitAkisi akis,
  ImportSecimi Function() secim,
  void Function(bool) sonuc, {
  String ozet =
      'Filtreyle gizlenen seçili: 1\nUyarılı seçili: 1\nBelge geçmişi korunur.',
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async =>
              sonuc(await akis.onayla(context, secim(), ozet)),
          child: const Text('Başlat'),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Sınıf sayıları ve ortak uyarılar görünür; iptal ek seçimi korur',
    (tester) async {
      final preview = _preview();
      final secim = _secim(preview);
      Set<String>? kaydedilenEkler;
      final akis = OgrenciImportKayitAkisi(
        ekSinifOzeti: (_) => {'10-B': 1, '11-C': 2},
        kaydet: (_, normal, {ekSiniflar = const {}}) async {
          kaydedilenEkler = ekSiniflar;
          return _sonuc(normal.length);
        },
      );
      bool? onay;
      await _onayEkrani(tester, akis, () => secim, (v) => onay = v);
      await _dokun(tester, find.text('Başlat'));
      expect(
        find.textContaining('Filtreyle gizlenen seçili: 1'),
        findsOneWidget,
      );
      expect(
        find.text('Seçili normal sınıflar: 1 • Öğrenci: 2'),
        findsOneWidget,
      );
      expect(find.text('9-A: 2 öğrenci'), findsOneWidget);
      expect(find.textContaining('2 sınıf • 3 öğrenci.'), findsOneWidget);
      final kutu = find.byKey(const ValueKey('ek-sinif:10-B'));
      expect(tester.widget<CheckboxListTile>(kutu).value, isFalse);
      await _dokun(tester, kutu);
      await _dokun(tester, find.text('Vazgeç'));
      expect(onay, isFalse);
      expect(kaydedilenEkler, isNull);
      await _dokun(tester, find.text('Başlat'));
      expect(tester.widget<CheckboxListTile>(kutu).value, isTrue);
      await _dokun(tester, find.text('Yalnız Normal Sınıfları Kaydet'));
      expect(onay, isTrue);
      final sonuc = await akis.kaydet(secim);
      expect(kaydedilenEkler, isEmpty);
      expect(sonuc.mesaj, contains('İşleme alınan: 1 sınıf • 2 öğrenci'));
      expect(sonuc.mesaj, isNot(contains('10-B:')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Yalnız ek sınıflar varsa açık seçim zorunlu ve tümünü seç çalışır',
    (tester) async {
      final secim = _secim(_preview(normal: false));
      Set<String>? ekler;
      final akis = OgrenciImportKayitAkisi(
        ekSinifOzeti: (_) => {'10-B': 1, '11-C': 2},
        kaydet: (_, normal, {ekSiniflar = const {}}) async {
          expect(normal, isEmpty);
          ekler = ekSiniflar;
          expect(() => ekSiniflar.add('12-D'), throwsUnsupportedError);
          return _sonuc(3);
        },
      );
      expect(akis.bosSecimleAktarilabilir(secim.onIzleme), isTrue);
      bool? onay;
      await _onayEkrani(tester, akis, () => secim, (v) => onay = v);
      await _dokun(tester, find.text('Başlat'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Seçilenlerle Kaydet'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Yalnız Normal Sınıfları Kaydet'),
            )
            .onPressed,
        isNull,
      );
      await _dokun(tester, find.text('Tüm Ek Sınıfları Seç'));
      expect(find.text('Seçilen ek sınıf: 2 • Öğrenci: 3'), findsOneWidget);
      await _dokun(tester, find.text('Seçilenlerle Kaydet'));
      expect(onay, isTrue);
      final sonuc = await akis.kaydet(secim);
      expect(ekler, {'10-B', '11-C'});
      expect(sonuc.mesaj, contains('İşleme alınan: 2 sınıf • 3 öğrenci'));
      expect(sonuc.mesaj, contains('11-C: 2 öğrenci'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Kayıt hatası seçimi korur; yeni ön izleme ek seçimleri temizler',
    (tester) async {
      var secim = _secim(_preview());
      final akis = OgrenciImportKayitAkisi(
        ekSinifOzeti: (_) => {'10-B': 1},
        kaydet: (_, __, {ekSiniflar = const {}}) async =>
            throw StateError('Örnek kayıt hatası'),
      );
      await _onayEkrani(tester, akis, () => secim, (_) {});
      await _dokun(tester, find.text('Başlat'));
      final kutu = find.byKey(const ValueKey('ek-sinif:10-B'));
      await _dokun(tester, kutu);
      await _dokun(tester, find.text('Seçilenlerle Kaydet'));
      await expectLater(akis.kaydet(secim), throwsStateError);
      await _dokun(tester, find.text('Başlat'));
      expect(tester.widget<CheckboxListTile>(kutu).value, isTrue);
      await _dokun(tester, find.text('Vazgeç'));
      secim = _secim(_preview());
      await _dokun(tester, find.text('Başlat'));
      expect(tester.widget<CheckboxListTile>(kutu).value, isFalse);
      await _dokun(tester, find.text('Vazgeç'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320 piksel büyük yazıda çok sınıf özeti kaydırılır ve son sınıf seçilir',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final secim = _secim(_preview());
      final akis = OgrenciImportKayitAkisi(
        ekSinifOzeti: (_) => {
          for (var i = 1; i <= 25; i++) '$i-ÖZEL EĞİTİM-A': i,
        },
        kaydet: (_, __, {ekSiniflar = const {}}) async => _sonuc(27),
      );
      await _onayEkrani(
        tester,
        akis,
        () => secim,
        (_) {},
        textScale: 1.5,
        ozet: List.filled(8, 'Belge ve kayıt kapsamı uyarısı.').join('\n'),
      );
      await _dokun(tester, find.text('Başlat'));
      expect(tester.takeException(), isNull);
      final son = find.byKey(const ValueKey('ek-sinif:25-ÖZEL EĞİTİM-A'));
      await _dokun(tester, son);
      expect(tester.widget<CheckboxListTile>(son).value, isTrue);
      await _dokun(tester, find.text('Seçilenlerle Kaydet'));
      expect(tester.takeException(), isNull);
    },
  );

  group('Ortak ekran ek sınıf onayı', () {
    final factory = WindowsMemoryFactory();
    setUpAll(() async {
      databaseFactory = factory;
      await LocalDatabase.instance.database;
    });
    setUp(
      () =>
          SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'}),
    );
    tearDownAll(() async => factory.db?.close());

    testWidgets(
      'Boş normal seçimle hata, yeniden deneme ve görünür başarı özeti',
      (tester) async {
        final preview = _preview(normal: false);
        var kayitSayisi = 0;
        final akis = OgrenciImportKayitAkisi(
          ekSinifOzeti: (_) => {'10-B': 1},
          kaydet: (_, normal, {ekSiniflar = const {}}) async {
            expect(normal, isEmpty);
            expect(ekSiniflar, {'10-B'});
            kayitSayisi++;
            if (kayitSayisi == 1) {
              throw StateError('Örnek kayıt hatası');
            }
            return _sonuc(1);
          },
        );
        final tanim = ImportTanimi(
          id: 'test_ek_sinif',
          ad: 'Öğrenci Test',
          aciklama: 'Öğrenci sınıf seçimi',
          alanlar: const [
            ImportAlan('okulNo', 'Okul No'),
            ImportAlan('sinif', 'Sınıf'),
          ],
          hazirla: (_) async => preview,
          aktar: (_, __) async =>
              throw StateError('Varsayılan kayıt çağrılmamalı'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: OrtakImportScreen(
              tanim: tanim,
              baslangicDosyasi: _secim(preview).dosya,
              secimOnayi: akis.onayla,
              secimiKaydet: akis.kaydet,
              bosSecimleAktarilabilir: akis.bosSecimleAktarilabilir,
              sonucIleDon: false,
            ),
          ),
        );
        // Biçim kontrolü ve tablo okuması ayrı isolate'larda tamamlanır.
        // Gerçek I/O bitmeden fake async pumpAndSettle'a geçilmez.
        await tester.runAsync(() async {
          final onIzlemeButonu = find.widgetWithText(
            FilledButton,
            'Ön İzleme Hazırla',
          );
          for (var deneme = 0; deneme < 100; deneme++) {
            await tester.pump();
            if (onIzlemeButonu.evaluate().isNotEmpty &&
                tester.widget<FilledButton>(onIzlemeButonu).onPressed != null) {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          throw StateError('Başlangıç dosyası okuması tamamlanmadı.');
        });
        await tester.pumpAndSettle();
        await _ortakDokun(tester, find.text('Ön İzleme Hazırla'));
        final buton = find.widgetWithText(
          FilledButton,
          'Sınıfları Seç ve Kaydet',
        );
        expect(tester.widget<FilledButton>(buton).onPressed, isNotNull);
        await _ortakDokun(tester, buton);
        final kutu = find.byKey(const ValueKey('ek-sinif:10-B'));
        await _dokun(tester, kutu);
        await _ortakDokun(tester, find.text('Seçilenlerle Kaydet'));
        expect(find.textContaining('Örnek kayıt hatası'), findsWidgets);
        expect(find.byType(OrtakImportScreen), findsOneWidget);
        await _ortakDokun(tester, buton);
        expect(tester.widget<CheckboxListTile>(kutu).value, isTrue);
        await _ortakDokun(tester, find.text('Seçilenlerle Kaydet'));
        expect(find.text('Kayıt Tamamlandı'), findsOneWidget);
        expect(
          find.textContaining('İşleme alınan: 1 sınıf • 1 öğrenci'),
          findsWidgets,
        );
        await _dokun(tester, find.text('Kapat'));
        expect(find.byType(OrtakImportScreen), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Aktarım Tamamlandı'),
              )
              .onPressed,
          isNull,
        );
        expect(kayitSayisi, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }, skip: !Platform.isWindows);
}
