import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/odev_kontrol.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_odev_kontrol_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselListeOturumu oturum;
  const tablolar = [
    'OdevTanim',
    'OdevOgrenci',
    'OdevKontrol',
    'OdevKontrolSonuc',
    'OdevDegerlendirmeOlcutu',
    'OdevDegerlendirmePuani',
  ];
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    await BireyselProfilService.kaydet(
      adSoyad: 'Öğretmen',
      brans: 'Ders',
      okulAdi: 'Okul',
      okulKisaAdi: 'O',
      egitimOgretimYili: '2026-2027',
      donem: 1,
      meslekPaketiAktif: false,
    );
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Ders',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    for (final id in [1, 2]) {
      await db.insert('SinifSube', {
        'SinifSubeId': id,
        'SinifKodu': '9-${id == 1 ? 'C' : 'D'}',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': id,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': id == 1 ? 'Pazartesi' : 'Salı',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '$id',
        'Ad': 'Öğrenci',
        'Soyad': '$id',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': id,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    oturum = await BireyselOdevKontrolService.hazirla();
  });
  tearDown(LocalDatabase.instance.close);
  Future<int> gorev(
    String baslik, {
    int sinif = 1,
    OdevGorevTuru tur = OdevGorevTuru.normalOdev,
  }) => BireyselOdevKontrolService.gorevOlustur(
    oturum,
    sinifSubeId: sinif,
    dersId: 1,
    gorevTuru: tur,
    baslik: baslik,
    baslangicTarihi: DateTime(2026, 9, 1),
    ogrenciIdleri: [sinif],
  );
  Future<void> puanliKontrol(int id) async {
    final k = await BireyselOdevKontrolService.kontrolOlustur(
      oturum,
      id,
      kontrolTarihi: DateTime(2026, 10, 1),
    );
    await BireyselOdevKontrolService.degerlendirmeOlcutleriniKaydet(oturum, k, [
      {'Baslik': 'Çalışma', 'AzamiPuan': 40},
    ]);
    final o = (await BireyselOdevKontrolService.degerlendirmeOlcutleri(
      oturum,
      k,
    )).single;
    await BireyselOdevKontrolService.degerlendirmePuaniKaydet(oturum, k, 1, {
      o['OlcutId'] as int: 30,
    });
    await BireyselOdevKontrolService.sonuclariKaydet(oturum, k, [
      const OdevSonucGirdisi(ogrenciId: 1, durum: OdevKontrolDurumu.yapti),
    ]);
  }

  Future<Map<String, List<Map<String, Object?>>>> durum() async => {
    for (final t in tablolar) t: await db.query(t),
  };
  test(
    'birleştirme aynı tarihli kontrolleri, sonuçları ve puanları korur',
    () async {
      final a = await gorev('Defter Kontrol', tur: OdevGorevTuru.proje);
      final b = await gorev('Nesne Defter', tur: OdevGorevTuru.proje);
      final diger = await gorev('Flash Kontrol');
      await puanliKontrol(a);
      await puanliKontrol(b);
      await db.update(
        'OdevOgrenci',
        {'Aktif': 0},
        where: 'OdevId = ?',
        whereArgs: [b],
      );
      final hedef = await BireyselOdevKontrolService.defterGorevleriniBirlestir(
        oturum,
        {a, b},
      );
      expect((await db.query('OdevTanim')).map((r) => r['OdevId']).toSet(), {
        hedef,
        diger,
      });
      expect(
        (await BireyselOdevKontrolService.gorevGetir(oturum, hedef)).baslik,
        'Defter Kontrol',
      );
      expect(
        await db.query('OdevKontrol', where: 'OdevId = ?', whereArgs: [hedef]),
        hasLength(2),
      );
      expect((await db.query('OdevKontrolSonuc')).map((r) => r['Durum']), [
        'Yapti',
        'Yapti',
      ]);
      expect((await db.query('OdevDegerlendirmePuani')).map((r) => r['Puan']), [
        30,
        30,
      ]);
      expect(
        (await db.query(
          'OdevOgrenci',
          where: 'OdevId = ?',
          whereArgs: [hedef],
        )).single['Aktif'],
        1,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'farklı sınıf/tür/ödev seçimi ve eski oturum hiçbir kaydı değiştirmez',
    () async {
      final a = await gorev('Defter Kontrol');
      final b = await gorev('Defter', sinif: 2);
      final c = await gorev('Başka ödev');
      final once = await durum();
      for (final ids in [
        {a, b},
        {a, c},
      ]) {
        await expectLater(
          BireyselOdevKontrolService.defterGorevleriniBirlestir(oturum, ids),
          throwsException,
        );
        expect(await durum(), once);
      }
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
      await expectLater(
        BireyselOdevKontrolService.gorevleriSil(oturum, {a}),
        throwsException,
      );
      expect(await durum(), once);
    },
  );
  test(
    'silme yalnız seçili ödevin bağlı kayıtlarını kaldırır; pasif de silinebilir',
    () async {
      final a = await gorev('Silinecek', tur: OdevGorevTuru.proje);
      final b = await gorev('Korunacak');
      await puanliKontrol(a);
      await BireyselOdevKontrolService.gorevPasiflestir(oturum, a);
      await BireyselOdevKontrolService.gorevleriSil(oturum, {a});
      expect((await db.query('OdevTanim')).single['OdevId'], b);
      for (final t in tablolar.skip(2)) {
        expect(await db.query(t), isEmpty);
      }
      expect(await db.query('Ogrenci'), hasLength(2));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test('silme ve birleştirme hatası bağlı kayıtları da geri alır', () async {
    final a = await gorev('Defter', tur: OdevGorevTuru.proje);
    final b = await gorev('Nesne Defter', tur: OdevGorevTuru.proje);
    await puanliKontrol(a);
    await puanliKontrol(b);
    final once = await durum();
    await db.execute(
      "CREATE TRIGGER silme_engel BEFORE DELETE ON OdevTanim BEGIN SELECT RAISE(ABORT, 'Test'); END",
    );
    await expectLater(
      BireyselOdevKontrolService.gorevleriSil(oturum, {a}),
      throwsException,
    );
    expect(await durum(), once);
    await expectLater(
      BireyselOdevKontrolService.defterGorevleriniBirlestir(oturum, {a, b}),
      throwsException,
    );
    expect(await durum(), once);
  });
  test('birleşen ölçütler 100 puanı aşarsa kayıtlar korunur', () async {
    final a = await gorev('Defter', tur: OdevGorevTuru.proje);
    final b = await gorev('Nesne Defter', tur: OdevGorevTuru.proje);
    await puanliKontrol(a);
    await puanliKontrol(b);
    await db.update('OdevDegerlendirmeOlcutu', {'AzamiPuan': 60});
    final once = await durum();
    await expectLater(
      BireyselOdevKontrolService.defterGorevleriniBirlestir(oturum, {a, b}),
      throwsException,
    );
    expect(await durum(), once);
  });
  Future<void> tikla(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
    await t.tap(f.last);
    await t.pumpAndSettle();
  }

  testWidgets('tüm sınıflar açılır; seçim ve silme iptali kayıtları korur', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final a = await gorev('Defter Kontrol');
    await gorev('Diğer sınıf ödevi', sinif: 2);
    await t.pumpWidget(const MaterialApp(home: OdevKontrolScreen()));
    await t.pumpAndSettle();
    await tikla(t, find.byTooltip('Filtreler'));
    expect(find.text('Tüm sınıflar'), findsOneWidget);
    expect(find.text('Tüm dersler'), findsOneWidget);
    expect(find.text('Tümü (2)'), findsOneWidget);
    expect(find.text('Diğer sınıf ödevi'), findsOneWidget);
    await tikla(t, find.byKey(ValueKey('odev-sec-$a')));
    await tikla(t, find.byTooltip('Seçili ödevleri sil'));
    await tikla(t, find.text('Vazgeç'));
    expect(await db.query('OdevTanim'), hasLength(2));
    await tikla(t, find.byTooltip('Seçili ödevleri sil'));
    await tikla(t, find.text('Sil'));
    expect(await db.query('OdevTanim'), hasLength(1));
    expect(find.text('Diğer sınıf ödevi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('tüm sınıflarda dersler alfabetik, tekil ve seçilebilir', (
    t,
  ) async {
    final adlar = ['Şiir', 'İngilizce', 'Çizim', 'Cebir', 'Işık'];
    for (var i = 0; i < adlar.length; i++) {
      final id = i + 2;
      await db.insert('Ders', {
        'DersId': id,
        'DersAdi': adlar[i],
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersSaati', {'DersSaatiId': id, 'SiraNo': id});
      await db.insert('DersProgrami', {
        'SinifSubeId': 2,
        'DersId': id,
        'DersSaatiId': id,
        'Gun': 'Salı',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    final dersler = await BireyselOdevKontrolService.dersler(oturum, null);
    expect(dersler.map((d) => d.dersAdi), [
      'Cebir',
      'Çizim',
      'Ders',
      'Işık',
      'İngilizce',
      'Şiir',
    ]);
    expect(
      (await BireyselOdevKontrolService.dersler(
        oturum,
        1,
      )).map((d) => d.dersAdi),
      ['Ders'],
    );
    await gorev('Diğer ders ödevi');
    await BireyselOdevKontrolService.gorevOlustur(
      oturum,
      sinifSubeId: 2,
      dersId: 5,
      gorevTuru: OdevGorevTuru.normalOdev,
      baslik: 'Cebir ödevi',
      baslangicTarihi: DateTime(2026, 9, 1),
      ogrenciIdleri: [2],
    );
    await t.pumpWidget(const MaterialApp(home: OdevKontrolScreen()));
    await t.pumpAndSettle();
    await tikla(t, find.byTooltip('Filtreler'));
    final alan = t.widget<DropdownButtonFormField<int>>(
      find.byKey(const ValueKey('ders-0-0')),
    );
    expect(alan.onChanged, isNotNull);
    await tikla(t, find.byKey(const ValueKey('ders-0-0')));
    await tikla(t, find.text('Cebir'));
    expect(find.text('Cebir ödevi'), findsOneWidget);
    expect(find.text('Diğer ders ödevi'), findsNothing);
    await tikla(t, find.byKey(const ValueKey('sinif-0')));
    await tikla(t, find.text('9-C'));
    expect(find.text('Tüm dersler'), findsOneWidget);
    expect(find.text('Diğer ders ödevi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('seçili defterler onayla tek ödevde birleşir', (t) async {
    final a = await gorev('Defter Kontrol');
    final b = await gorev('Nesne Defter');
    await t.pumpWidget(const MaterialApp(home: OdevKontrolScreen()));
    await t.pumpAndSettle();
    await tikla(t, find.byKey(ValueKey('odev-sec-$a')));
    await tikla(t, find.byKey(ValueKey('odev-sec-$b')));
    await tikla(t, find.byTooltip('Defter ödevlerini birleştir'));
    await tikla(t, find.text('Birleştir'));
    expect(await db.query('OdevTanim'), hasLength(1));
    expect(find.text('Defter Kontrol'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
