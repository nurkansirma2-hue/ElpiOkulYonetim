import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_sifirlama_screen.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselBakimService service;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    mod = CalismaModu.bireyselOgretmen;
    service = BireyselBakimService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
    );
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
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
    await db.insert('Ogrenci', {
      'OgrenciId': 1,
      'OkulNo': '001',
      'Ad': 'Öğrenci',
      'Soyad': 'Test',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciFotograf', {
      'OgrenciId': 1,
      'DosyaYolu': 'kaynak.jpg',
      'FotoVerisi': Uint8List.fromList([1, 2]),
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9/A',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('YillikPlan', {
      'DersId': 1,
      'SinifSubeId': 1,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
  });
  tearDown(LocalDatabase.instance.close);
  Future<SifirlamaPlani> plan(Set<String> ids) async =>
      (await service.sifirlamaEnvanteri()).planla(ids);

  test(
    'güncel şemanın bütün modülleri kapsanır ve ön izleme veri silmez',
    () async {
      final e = await service.sifirlamaEnvanteri();
      expect(e.planla({}).kapsam, isEmpty);
      expect(e.planla({'fotograflar'}).kapsam, {'fotograflar'});
      expect(await db.query('OgrenciFotograf'), hasLength(1));
      expect(() => e.planla({'yok'}), throwsStateError);
    },
  );
  test(
    'yalnız fotoğraf sıfırlanır; öğrenci, program tanımları ve profil korunur',
    () async {
      await service.seciliModulleriSifirla(
        await plan({'fotograflar'}),
        onayMetni: 'SIFIRLA',
      );
      expect(await db.query('OgrenciFotograf'), isEmpty);
      expect(await db.query('Ogrenci'), hasLength(1));
      expect(await db.query('YillikPlan'), hasLength(1));
      expect(await db.query('OgretmenProfil'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'öğrenci seçimi bağlı modülleri dahil eder; yıllık plan ve profil silinmez',
    () async {
      final p = await plan({'ogrenciler'});
      expect(
        p.kapsam,
        containsAll([
          'ogrenciler',
          'fotograflar',
          'odev',
          'rehberlik',
          'formlar',
        ]),
      );
      expect(p.kapsam, isNot(contains('planlar')));
      expect(p.nedenler['fotograflar'], 'Öğrenciler ve veli bilgileri');
      await service.seciliModulleriSifirla(p, onayMetni: 'SIFIRLA');
      expect(await db.query('Ogrenci'), isEmpty);
      expect(await db.query('OgrenciSinifKayit'), isEmpty);
      expect(await db.query('YillikPlan'), hasLength(1));
      expect(await db.query('OgretmenProfil'), hasLength(1));
    },
  );
  test('ders seçimi sınıf ve öğretmen ders bağlantılarını da kapsar', () async {
    final p = await plan({'dersler'});
    expect(
      p.kapsam,
      containsAll([
        'planlar',
        'program',
        'ogretmenler',
        'gunluk',
        'odev',
      ]),
    );
    expect(p.kapsam, isNot(contains('profil')));
    await service.seciliModulleriSifirla(p, onayMetni: 'SIFIRLA');
    expect(await db.query('Ders'), isEmpty);
    expect(await db.query('YillikPlan'), isEmpty);
    expect(await db.query('Ogrenci'), hasLength(1));
  });
  test(
    'tümünü seç bütün modül tablolarını boşaltır; belge arşivi korunur',
    () async {
      const arsiv = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await db.insert('BelgeArsivi', {
        'ArsivId': arsiv,
        'OkulId': 'okul',
        'OgretmenProfilId': 1,
        'OkulAdi': 'Okul',
        'OgretmenAdi': 'Öğretmen',
        'OlusturmaTarihi': 'test',
      });
      final ids = BireyselSifirlama.moduller.map((m) => m.id).toSet();
      final p = await plan(ids);
      await service.seciliModulleriSifirla(p, onayMetni: 'SIFIRLA');
      for (final t in p.tablolar) {
        expect(await db.query(t), isEmpty, reason: t);
      }
      expect(await db.query('BelgeArsivi'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test('son onay eksik, seçim boş veya mod farklıysa silme başlamaz', () async {
    final p = await plan({'fotograflar'});
    await expectLater(
      service.seciliModulleriSifirla(p, onayMetni: ''),
      throwsStateError,
    );
    await expectLater(
      service.seciliModulleriSifirla(await plan({}), onayMetni: 'SIFIRLA'),
      throwsStateError,
    );
    mod = null;
    await expectLater(
      service.seciliModulleriSifirla(p, onayMetni: 'SIFIRLA'),
      throwsStateError,
    );
    await expectLater(service.sifirlamaEnvanteri(), throwsStateError);
    expect(await db.query('OgrenciFotograf'), hasLength(1));
  });
  test(
    'ön izleme sonrasında yeni kayıt gelirse yeniden onay gerekir',
    () async {
      final p = await plan({'ogrenciler'});
      await db.insert('Ogrenci', {
        'OkulNo': '002',
        'Ad': 'Yeni',
        'Soyad': 'Öğrenci',
        'OlusturmaTarihi': 'test',
      });
      await expectLater(
        service.seciliModulleriSifirla(p, onayMetni: 'SIFIRLA'),
        throwsStateError,
      );
      expect(await db.query('Ogrenci'), hasLength(2));
      expect(await db.query('OgrenciFotograf'), hasLength(1));
    },
  );
  test('silme hatasında önce silinen bağlı kayıtlar da geri alınır', () async {
    final p = await plan({'ogrenciler'});
    await db.execute(
      "CREATE TRIGGER reset_deneme BEFORE DELETE ON Ogrenci BEGIN SELECT RAISE(ABORT,'Deneme'); END",
    );
    await expectLater(
      service.seciliModulleriSifirla(p, onayMetni: 'SIFIRLA'),
      throwsStateError,
    );
    expect(await db.query('Ogrenci'), hasLength(1));
    expect(await db.query('OgrenciFotograf'), hasLength(1));
    expect(await db.query('OgrenciSinifKayit'), hasLength(1));
  });
  test('tanınmayan yeni tablo varsa güvenli biçimde durur', () async {
    await db.execute('CREATE TABLE GelecekModul (Id INTEGER PRIMARY KEY)');
    await expectLater(service.sifirlamaEnvanteri(), throwsStateError);
    expect(await db.query('Ogrenci'), hasLength(1));
  });

  Future<void> dokun(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      final position = t
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      position.jumpTo(position.minScrollExtent);
      await t.pump();
      await t.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
    await t.tap(f.last);
    await t.pump(const Duration(milliseconds: 350));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpAndSettle();
  }

  testWidgets('boş seçim, tümünü seç ve temizle; dar ekranda son onay iptali', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: BireyselSifirlamaScreen(service: service, yedekle: () async {}),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpAndSettle();
    final buton = find.byKey(const ValueKey('secili-modulleri-sifirla'));
    await dokun(t, find.text('Tümünü seç'));
    final tik = t.widget<CheckboxListTile>(
      find.byKey(const ValueKey('sifirla-modul-profil')),
    );
    expect(tik.value, true);
    await dokun(t, find.text('Seçimi temizle'));
    await dokun(t, find.byKey(const ValueKey('sifirla-modul-fotograflar')));
    await dokun(t, buton);
    expect(find.text('Sıfırlamadan önce yedekle'), findsOneWidget);
    await dokun(t, find.text('Yedek almadan devam et'));
    expect(find.text('Seçilen modüller silinsin mi?'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Onayla ve Sıfırla'),
          )
          .onPressed,
      isNull,
    );
    await dokun(t, find.text('İptal'));
    expect(await db.query('OgrenciFotograf'), hasLength(1));
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'yedek dönüşü silmez; yazılı onay yalnız seçilen modülü sıfırlar',
    (t) async {
      bool? sonuc;
      var yedek = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  sonuc = await Navigator.of(c).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => BireyselSifirlamaScreen(
                        service: service,
                        yedekle: () async {
                          yedek++;
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await dokun(t, find.text('Aç'));
      await dokun(t, find.byKey(const ValueKey('sifirla-modul-fotograflar')));
      final uygula = find.byKey(const ValueKey('secili-modulleri-sifirla'));
      await dokun(t, uygula);
      await dokun(t, find.text('Önce Yedekle'));
      expect(yedek, 1);
      expect(await db.query('OgrenciFotograf'), hasLength(1));
      await dokun(t, uygula);
      await dokun(t, find.text('Yedek almadan devam et'));
      await t.enterText(
        find.byKey(const ValueKey('sifirlama-onay-metni')),
        'SIFIRLA',
      );
      await t.pumpAndSettle();
      await dokun(t, find.text('Onayla ve Sıfırla'));
      expect(find.text('Sıfırlama tamamlandı'), findsOneWidget);
      expect(await db.query('OgrenciFotograf'), isEmpty);
      expect(await db.query('Ogrenci'), hasLength(1));
      expect(await db.query('OgretmenProfil'), hasLength(1));
      await dokun(t, find.text('Tamam'));
      expect(sonuc, true);
      expect(t.takeException(), isNull);
    },
  );
}
