import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';
import 'package:elpi_okul_yonetim/screens/rehberlik_tanima_form_screen.dart';
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
  Future<void> open(WidgetTester tester, {bool readonly = false}) async {
    final student = (await service.sinifOgrencileri(contextData, 1)).single;
    await tester.pumpWidget(
      MaterialApp(
        home: RehberlikTanimaFormScreen(
          service: service,
          baglam: contextData,
          atamaId: 1,
          ogrenci: student,
          saltOkunur: readonly,
        ),
      ),
    );
    await tester.tap(find.text('Hassas formu görüntüle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Görüntüle'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Dar formda yeni alanlar kayıt olur, eski sürüm ve öğrenci ana kaydı korunur',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await service.formKaydet(
        contextData,
        1,
        1,
        ['Eski özel soru'],
        {'Eski özel soru': 'Korunacak cevap'},
        hassasOnay: true,
      );
      final old = (await db.query('RehberlikForm')).single;
      final student = await db.query('Ogrenci');
      await open(tester);
      expect(find.text('Resimden içe aktar'), findsOneWidget);
      final scroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final field in [
        'Anne mesleği',
        'Baba mesleği',
        'Kaç kardeşsiniz?',
        'Eski özel soru',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(field)),
          400,
          scrollable: scroll,
          maxScrolls: 70,
        );
        expect(tester.takeException(), isNull);
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('Eski özel soru')))
            .controller!
            .text,
        'Korunacak cevap',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Eski özel soru')),
        'Güncel cevap',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Yeni sürüm olarak kaydet'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final rows = await db.query('RehberlikForm', orderBy: 'Id');
      expect(
        rows,
        hasLength(2),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((t) => t.contains('hata') || t.contains('kaydedilemedi'))
            .join('\n'),
      );
      expect(rows.first, old);
      final answers = jsonDecode(rows.last['Cevaplar'] as String) as Map;
      expect(answers['Eski özel soru'], 'Güncel cevap');
      expect(answers.containsKey('Anne mesleği'), true);
      expect(await db.query('Ogrenci'), student);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  testWidgets('Salt okunur formda resim aktarımı ve kayıt sunulmaz', (
    tester,
  ) async {
    await open(tester, readonly: true);
    expect(find.text('Resimden içe aktar'), findsNothing);
    expect(find.byTooltip('Yeni sürüm olarak kaydet'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).readOnly,
      true,
    );
    expect(await db.query('RehberlikForm'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  Future<void> alanaGit(WidgetTester t, Finder finder) async {
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await t.pump();
    await t.scrollUntilVisible(
      finder,
      400,
      maxScrolls: 70,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
  }

  Future<void> sec(WidgetTester t, String ad) async {
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await alanaGit(t, dropdown);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text(ad).last);
    await t.pumpAndSettle();
  }

  Future<String> cevap(WidgetTester t, String alan) async {
    final finder = find.byKey(ValueKey(alan));
    await alanaGit(t, finder);
    return t.widget<TextField>(finder).controller!.text;
  }

  testWidgets(
    'veli seçimi kayıtlı kişiyi doldurur; taslak ve öğrenci korunur',
    (t) async {
      await db.update('Ogrenci', {
        'VeliTuru': 'Baba',
        'AnneAdi': 'Ayşe',
        'AnneTelefon': '05320000001',
        'BabaAdi': 'Ali',
        'BabaTelefon': '05320000002',
        'VeliAdi': 'Teyze',
        'VeliTelefonu': '05320000003',
      });
      final onceki = await db.query('Ogrenci');
      await open(t);
      expect(await cevap(t, 'Veli adı soyadı'), 'Ali');
      expect(await cevap(t, 'Veli telefon numarası'), '05320000002');
      expect(await cevap(t, 'Anne adı soyadı'), 'Ayşe');
      await sec(t, 'Anne');
      expect(await cevap(t, 'Veli adı soyadı'), 'Ayşe');
      expect(await cevap(t, 'Veli telefon numarası'), '05320000001');
      final ad = find.byKey(const ValueKey('Veli adı soyadı'));
      await alanaGit(t, ad);
      await t.enterText(ad, 'Formdaki anne adı');
      await sec(t, 'Diğer veli');
      expect(await cevap(t, 'Veli adı soyadı'), 'Teyze');
      expect(await cevap(t, 'Veli telefon numarası'), '05320000003');
      await sec(t, 'Anne');
      expect(await cevap(t, 'Veli adı soyadı'), 'Formdaki anne adı');
      await t.runAsync(() async {
        await t.tap(find.byTooltip('Yeni sürüm olarak kaydet'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await t.pumpAndSettle();
      final kayit = (await db.query('RehberlikForm')).single;
      final answers = jsonDecode(kayit['Cevaplar'] as String) as Map;
      expect(answers['Veli yakınlığı'], 'Anne');
      expect(answers['Veli adı soyadı'], 'Formdaki anne adı');
      expect(await db.query('Ogrenci'), onceki);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'eski veli cevabı korunur; seçilen ebeveynin eğitim ve mesleği alınır',
    (t) async {
      await db.update('Ogrenci', {'AnneAdi': 'Ayşe', 'AnneTelefon': ''});
      final a = {
        'Veli yakınlığı': 'Dedesi',
        'Veli adı soyadı': 'Eski veli',
        'Veli telefon numarası': '05320000009',
        'Anne eğitim durumu': 'Lise',
        'Anne mesleği': 'Terzi',
      };
      await t.runAsync(() async {
        await service.formKaydet(
          contextData,
          1,
          1,
          a.keys.toList(),
          a,
          hassasOnay: true,
        );
      });
      final eski = (await db.query('RehberlikForm')).single;
      await open(t);
      expect(await cevap(t, 'Veli adı soyadı'), 'Eski veli');
      await sec(t, 'Anne');
      expect(await cevap(t, 'Veli eğitim durumu'), 'Lise');
      expect(await cevap(t, 'Veli mesleği'), 'Terzi');
      expect(await cevap(t, 'Veli telefon numarası'), '');
      expect((await db.query('RehberlikForm')).single, eski);
      expect(t.takeException(), isNull);
    },
  );

  test('veli okuma hassas onay ve öğrenci sınıf kapsamı gerektirir', () async {
    await expectLater(
      service.formVeliBilgileri(contextData, 1, 1, hassasOnay: false),
      throwsStateError,
    );
    await expectLater(
      service.formVeliBilgileri(contextData, 1, 999, hassasOnay: true),
      throwsStateError,
    );
  });
}
