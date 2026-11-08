import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yillik_plan_import_screen.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Yıllık plan yükleme ders seçimi', () {
    late Database db;
    final factory = WindowsMemoryFactory();
    const hamYil = '2026/2027';
    const planYili = '2026-2027';
    final toggle = find.byKey(
      const ValueKey('yillik-plan-yuklenenleri-goster'),
    );
    final dropdown = find.byWidgetPredicate((w) => w is DropdownButton);

    // Yıllık planın özel okuyucusu CSV değil, Office dosyalarını destekler.
    ImportDosya planSatirlari(List<List<String>> satirlar) {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow(['Hafta', 'Tarih', 'Konu']);
      for (final satir in satirlar) {
        sheet.appendRow(satir);
      }
      return ImportDosya('plan.xlsx', Uint8List.fromList(excel.encode()!));
    }

    ImportDosya planDosyasi([String konu = 'Yeni Sayılar']) =>
        planSatirlari([['1', '7-11 Eylül', konu]]);

    ImportDosya baslikliPlanDosyasi(int seviye, String dersAdi) {
      final xml = utf8.encode('''
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:t>$seviye. SINIF $dersAdi YILLIK PLANI</w:t></w:r></w:p>
        <w:tbl>
        <w:tr><w:tc><w:p><w:r><w:t>Hafta</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Tarih</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Konu</w:t></w:r></w:p></w:tc></w:tr>
        <w:tr><w:tc><w:p><w:r><w:t>1. Hafta</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>7-11 Eylül</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Yeni Sayılar</w:t></w:r></w:p></w:tc></w:tr>
        </w:tbl></w:body></w:document>
      ''');
      final archive = Archive()
        ..addFile(ArchiveFile('word/document.xml', xml.length, xml));
      return ImportDosya('plan.docx',
        Uint8List.fromList(ZipEncoder().encode(archive)!));
    }

    Future<void> dersEkle(int id, String ad, List<int> seviyeler) async {
      await db.insert('Ders', {
        'DersId': id, 'DersAdi': ad, 'OlusturmaTarihi': 'test',
      });
      for (final seviye in seviyeler) {
        final siniflar = await db.query('SinifSube',
          where: 'SinifSeviyesi = ?', whereArgs: [seviye]);
        final sinifId = siniflar.isNotEmpty
            ? siniflar.single['SinifSubeId'] as int
            : await db.insert('SinifSube', {
                'SinifKodu': '$seviye-A', 'SinifSeviyesi': seviye,
                'EgitimOgretimYili': hamYil, 'OlusturmaTarihi': 'test',
              });
        await db.insert('DersProgrami', {
          'DersId': id, 'SinifSubeId': sinifId, 'DersSaatiId': 1,
          'Gun': 'Pazartesi', 'Baslangic': '08:00', 'Bitis': '08:40',
          'OgretmenProfilId': 1, 'EgitimOgretimYili': hamYil,
          'OlusturmaTarihi': 'test',
        });
      }
    }

    Future<int> planEkle(int dersId, {
      int seviye = 9, int profilId = 1, String yil = planYili,
      bool aktif = true, bool detay = true, bool detayAktif = true,
    }) async {
      final id = await db.insert('YillikPlan', {
        'DersId': dersId, 'SinifSeviyesi': seviye,
        'OgretmenProfilId': profilId, 'EgitimOgretimYili': yil,
        'Aktif': aktif ? 1 : 0, 'OlusturmaTarihi': 'test',
      });
      if (detay) {
        await db.insert('YillikPlanDetay', {
          'YillikPlanId': id, 'HaftaNo': 1,
          'TarihAraligi': '7-11 Eylül', 'Konu': 'Eski Sayılar',
          'Aktif': detayAktif ? 1 : 0, 'OlusturmaTarihi': 'test',
        });
      }
      return id;
    }

    List<String> secenekler(WidgetTester tester) {
      if (dropdown.evaluate().isEmpty) return const [];
      String metin(Widget widget) {
        if (widget is Text) return widget.data ?? widget.textSpan!.toPlainText();
        if (widget is Flex) return widget.children.map(metin).join(' ');
        if (widget is Flexible) return metin(widget.child);
        if (widget is SingleChildRenderObjectWidget && widget.child != null) {
          return metin(widget.child!);
        }
        return '';
      }
      return tester.widget<DropdownButton>(dropdown).items!
          .map((item) => metin(item.child)).toList();
    }

    Future<void> ekraniAc(WidgetTester tester, {
      ImportDosya? dosya, int? dersId, int? seviye, bool buyukYazi = false,
    }) async {
      await tester.pumpWidget(MaterialApp(
        builder: buyukYazi ? (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ) : null,
        home: BireyselYillikPlanImportScreen(
          key: UniqueKey(), baslangicDosyasi: dosya,
          baslangicDersId: dersId, baslangicSinifSeviyesi: seviye,
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tikla(WidgetTester tester, Finder finder, {
      bool durulmasiniBekle = true,
    }) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder, 200, scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(finder);
      if (durulmasiniBekle) await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(finder);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        // Diyalog kapanışı, kayıt Future'ları ve sonuç route'u ayrı karelerde ilerler.
        for (var kare = 0; kare < 4; kare++) {
          await tester.pump(const Duration(milliseconds: 350));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      if (durulmasiniBekle) {
        await tester.pumpAndSettle();
      } else {
        // Kayıt sonrası soru açıkken alttaki mevcut busy animasyonu sürer.
        await tester.pump(const Duration(milliseconds: 350));
      }
    }

    Future<void> dersSec(WidgetTester tester, String etiket) async {
      await tikla(tester, dropdown);
      await tikla(tester, find.text(etiket).last);
    }

    Future<void> onIzlemeAl(WidgetTester tester) async {
      await tikla(tester, find.text('Seçilen Derse Ait Yıllık Planı Seç'));
      await tikla(tester, find.text('Ön İzleme Hazırla'));
      expect(find.byType(OrtakImportScreen), findsOneWidget);
      expect(find.text('Seçilenleri Onayla ve Kaydet'), findsOneWidget);
      expect(find.text('Ön İzlemeyi Onayla'), findsNothing);
    }

    Future<void> kaydet(WidgetTester tester) async {
      await tikla(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      expect(find.text('Yıllık Planı Onayla ve Kaydet'), findsOneWidget);
      await tikla(tester, find.text('Onayla ve Kaydet'), durulmasiniBekle: false);
      expect(find.text('Başka Yıllık Plan Yükle'), findsOneWidget);
    }

    setUpAll(() async {
      databaseFactory = factory;
      db = await LocalDatabase.instance.database;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      for (final tablo in [
        'YillikPlanDetay', 'YillikPlan',
        'CalismaTakvimiDetay', 'CalismaTakvimi',
        'DersProgrami', 'SinifSube', 'Ders', 'DersSaati', 'OgretmenProfil',
      ]) {
        await db.delete(tablo);
      }
      for (var id = 1; id <= 2; id++) {
        await db.insert('OgretmenProfil', {
          'OgretmenProfilId': id, 'AdSoyad': 'Öğretmen $id',
          'EgitimOgretimYili': hamYil, 'Aktif': id == 1 ? 1 : 0,
          'OlusturmaTarihi': 'test',
        });
      }
      await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    });

    tearDownAll(() async {
      await factory.db?.close();
    });

    testWidgets('Eksikler varsayılan; yüklü ders ayrıca gösterilir ve seçilir',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 840));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const uzunDersAdi = 'Matematik ve Matematiksel Düşünme Uygulamaları';
      await dersEkle(1, uzunDersAdi, [9, 10]);
      await dersEkle(2, 'Fizik', [9]);
      await planEkle(1);
      await ekraniAc(tester, buyukYazi: true);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(secenekler(tester), hasLength(2));
      expect(secenekler(tester).any((s) => s.contains('9. Sınıf - $uzunDersAdi')), isFalse);
      expect(secenekler(tester).any((s) => s.contains('10. Sınıf - $uzunDersAdi')), isTrue);
      await tikla(tester, toggle);
      expect(secenekler(tester), hasLength(3));
      await dersSec(tester, '9. Sınıf - $uzunDersAdi');
      expect(find.text('✓ Yüklendi'), findsOneWidget);
      expect(tester.getRect(find.text('✓ Yüklendi')).right,
        lessThanOrEqualTo(tester.getRect(dropdown).right));
      expect(find.text('Seçilen ders: 9. Sınıf - $uzunDersAdi'), findsOneWidget);
      final dugme = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Seçilen Derse Ait Yıllık Planı Seç'),
        matching: find.byType(FilledButton),
      ));
      expect(dugme.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Son aktif planın aktif detayı ve doğru kapsam yüklü sayılır',
        (tester) async {
      const adlar = ['Matematik', 'Fizik', 'Kimya', 'Tarih',
        'Biyoloji', 'İngilizce', 'Coğrafya'];
      for (var i = 0; i < adlar.length; i++) {
        await dersEkle(i + 1, adlar[i], [9]);
      }
      await planEkle(1, yil: hamYil);
      await planEkle(1, aktif: false, detay: false);
      await planEkle(2, profilId: 2);
      await planEkle(3, yil: '2025-2026');
      await planEkle(4, seviye: 10);
      await planEkle(5);
      await planEkle(5, detay: false);
      await planEkle(6, detayAktif: false);
      await planEkle(7, aktif: false);
      await ekraniAc(tester);
      expect(secenekler(tester), hasLength(6));
      expect(secenekler(tester).any((s) => s.contains('Matematik')), isFalse);
      for (final ad in adlar.skip(1)) {
        expect(secenekler(tester).any((s) => s.contains(ad)), isTrue, reason: ad);
      }
      await tikla(tester, toggle);
      expect(secenekler(tester), hasLength(7));
      expect(secenekler(tester).where((s) => s.contains('✓ Yüklendi')), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tümü yüklü ve programsız boş durumlar ayrılır', (tester) async {
      await dersEkle(1, 'Matematik', [9]);
      await planEkle(1);
      await ekraniAc(tester);
      expect(find.textContaining('tüm dersler için yıllık plan yüklendi'), findsOneWidget);
      expect(secenekler(tester), isEmpty);
      await tikla(tester, toggle);
      await dersSec(tester, '9. Sınıf - Matematik');
      expect(find.text('✓ Yüklendi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.update('DersProgrami', {'Aktif': 0});
      await ekraniAc(tester);
      expect(find.textContaining('Önce ders programınızı yükleyin.'), findsOneWidget);
      expect(secenekler(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Vazgeçilen önizlemeden sonra yüklü ders gizlenebilir',
        (tester) async {
      await dersEkle(1, 'Matematik', [9]);
      await dersEkle(2, 'Fizik', [9]);
      await planEkle(1);
      await ekraniAc(tester, dosya: planDosyasi());
      await tikla(tester, toggle);
      await dersSec(tester, '9. Sınıf - Matematik');
      await onIzlemeAl(tester);
      await tikla(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      await tikla(tester, find.text('Vazgeç'));
      expect(find.byType(OrtakImportScreen), findsOneWidget);
      expect(await db.query('YillikPlanDetay'), hasLength(1));
      await tester.runAsync(() async {
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 350));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      await tikla(tester, toggle);
      expect(tester.widget<DropdownButton>(dropdown).value, isNull);
      expect(secenekler(tester), hasLength(1));
      expect(find.text('Ön İzlemeyi Onayla'), findsNothing);
      expect(find.text('Yıllık Planı Kaydet'), findsNothing);
      expect(find.text('Seçilenleri Onayla ve Kaydet'), findsNothing);
      expect(find.textContaining('Seçilen dosya:'), findsNothing);
      expect(find.text('Önce 1. adımda dersi seçin.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Farklı sınıf yıllık planı tek onay ekranında kaydedilemez',
        (tester) async {
      await dersEkle(1, 'Matematik', [9]);
      await ekraniAc(tester,
        dosya: baslikliPlanDosyasi(10, 'MATEMATİK'), dersId: 1, seviye: 9);
      await onIzlemeAl(tester);
      await tikla(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      expect(find.text('Yıllık Planı Onayla ve Kaydet'), findsOneWidget);
      expect(find.textContaining('ancak dosyada 10. sınıf tespit edildi.'), findsOneWidget);
      final onay = tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text('Onayla ve Kaydet'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ));
      expect(onay.onPressed, isNull);
      expect(await db.query('YillikPlan'), isEmpty);
      expect(await db.query('YillikPlanDetay'), isEmpty);
      await tikla(tester, find.text('Vazgeç'));
      expect(find.byType(OrtakImportScreen), findsOneWidget);
      expect(find.text('Seçilenleri Onayla ve Kaydet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Farklı ders adı kabulü her onayda yeniden istenir',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 840));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await dersEkle(1, 'Matematik', [9]);
      await ekraniAc(tester,
        dosya: baslikliPlanDosyasi(9, 'FİZİK'), dersId: 1, seviye: 9,
        buyukYazi: true);
      await onIzlemeAl(tester);
      final kabul = find.widgetWithText(CheckboxListTile,
        'Ders adını kabul et; seçtiğim derse aktar.');
      Finder onayDugmesi() => find.ancestor(
        of: find.text('Onayla ve Kaydet'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      await tikla(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      expect(tester.widget<CheckboxListTile>(kabul).value, isFalse);
      expect(tester.widget<ButtonStyleButton>(onayDugmesi()).onPressed, isNull);
      await tikla(tester, kabul);
      expect(tester.widget<ButtonStyleButton>(onayDugmesi()).onPressed, isNotNull);
      await tikla(tester, find.text('Vazgeç'));
      expect(await db.query('YillikPlan'), isEmpty);
      await tikla(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      expect(tester.widget<CheckboxListTile>(kabul).value, isFalse);
      expect(tester.widget<ButtonStyleButton>(onayDugmesi()).onPressed, isNull);
      await tikla(tester, kabul);
      await tikla(tester, find.text('Onayla ve Kaydet'), durulmasiniBekle: false);
      expect(find.text('Başka Yıllık Plan Yükle'), findsOneWidget);
      final plan = (await db.query('YillikPlan')).single;
      expect(plan['DersId'], 1);
      expect(plan['SinifSeviyesi'], 9);
      expect((await db.query('Ders')).single['DersAdi'], 'Matematik');
      await tikla(tester, find.text('Başka Yıllık Plan Yükle'), durulmasiniBekle: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('SQLite kayıt hatası seçim ve önizlemeyi korur; tekrar tamamlar',
        (tester) async {
      await dersEkle(1, 'Matematik', [9]);
      final dosya = planSatirlari([
        ['1', '7-11 Eylül', 'Sayılar'],
        ['2', '14-18 Eylül', 'Kesirler'],
      ]);
      await ekraniAc(tester, dosya: dosya, dersId: 1, seviye: 9);
      await onIzlemeAl(tester);
      await db.execute("CREATE TRIGGER test_plan_failure BEFORE INSERT ON YillikPlanDetay WHEN NEW.HaftaNo = 2 BEGIN SELECT RAISE(ABORT, 'plan test failure'); END");
      try {
        await tikla(tester, find.text('Seçilenleri Onayla ve Kaydet'));
        expect(find.textContaining('Plan kaydı: 2'), findsOneWidget);
        await tikla(tester, find.text('Onayla ve Kaydet'));
        expect(find.byType(OrtakImportScreen), findsOneWidget);
        expect(find.textContaining('plan test failure'), findsWidgets);
        expect(find.text('Seçilenleri Onayla ve Kaydet'), findsOneWidget);
        expect(await db.query('YillikPlan'), isEmpty);
        expect(await db.query('YillikPlanDetay'), isEmpty);
        expect(await db.query('CalismaTakvimi'), isEmpty);
      } finally {
        await db.execute('DROP TRIGGER test_plan_failure');
      }
      await kaydet(tester);
      expect(await db.query('YillikPlan'), hasLength(1));
      expect(await db.query('YillikPlanDetay'), hasLength(2));
      expect(await db.query('CalismaTakvimiDetay'), hasLength(2));
      await tikla(tester, find.text('Başka Yıllık Plan Yükle'), durulmasiniBekle: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Kayıt sonrası başka plan seçimi güncel eksik listesini yükler',
        (tester) async {
      await dersEkle(1, 'Matematik', [9]);
      await dersEkle(2, 'Fizik', [9]);
      await ekraniAc(tester, dosya: planDosyasi());
      await dersSec(tester, '9. Sınıf - Matematik');
      await onIzlemeAl(tester);
      await kaydet(tester);
      expect(find.descendant(of: find.byType(AlertDialog),
        matching: find.textContaining('1 yeni, 0 güncellenen')), findsOneWidget);
      expect((await db.query('YillikPlan')).single['EgitimOgretimYili'], planYili);
      await tikla(tester, find.text('Başka Yıllık Plan Yükle'), durulmasiniBekle: false);
      await tester.pumpAndSettle();
      expect(secenekler(tester), hasLength(1));
      expect(secenekler(tester).single, contains('Fizik'));
      expect(tester.widget<DropdownButton>(dropdown).value, isNull);
      await tikla(tester, toggle);
      expect(secenekler(tester), hasLength(2));
      expect(secenekler(tester).where((s) => s.contains('✓ Yüklendi')), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dışarıdan seçili yüklü ders aynı haftayı güncelleyebilir',
        (tester) async {
      await dersEkle(1, 'Matematik', [9]);
      final planId = await planEkle(1);
      await db.insert('YillikPlanDetay', {
        'YillikPlanId': planId, 'HaftaNo': 2,
        'TarihAraligi': '14-18 Eylül', 'Konu': 'Korunacak Kesirler',
        'OlusturmaTarihi': 'test',
      });
      await ekraniAc(tester, dosya: planDosyasi(), dersId: 1, seviye: 9);
      expect(toggle, findsNothing);
      expect(dropdown, findsNothing);
      expect(find.text('Seçili Ders'), findsOneWidget);
      expect(find.text('9. Sınıf - Matematik'), findsOneWidget);
      await onIzlemeAl(tester);
      await kaydet(tester);
      expect(find.descendant(of: find.byType(AlertDialog),
        matching: find.textContaining('0 yeni, 1 güncellenen')), findsOneWidget);
      expect(await db.query('YillikPlan'), hasLength(1));
      final detaylar = await db.query('YillikPlanDetay', orderBy: 'HaftaNo');
      expect(detaylar, hasLength(2));
      expect(detaylar.first['Konu'], 'Yeni Sayılar');
      expect(detaylar.last['Konu'], 'Korunacak Kesirler');
      await tikla(tester, find.text('Başka Yıllık Plan Yükle'), durulmasiniBekle: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isWindows);
}
