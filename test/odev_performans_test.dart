import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/odev_kontrol.dart';
import 'package:elpi_okul_yonetim/services/bireysel_odev_kontrol_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'support/windows_memory_database.dart';
import 'support/eski_yedek_fixture.dart';
import 'package:elpi_okul_yonetim/database/odev_not_semasi.dart';
import 'package:elpi_okul_yonetim/models/performans_notu.dart';
import 'package:elpi_okul_yonetim/screens/performans_not_screen.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_detay_screen.dart';
import 'package:elpi_okul_yonetim/widgets/odev_puan_dialog.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker.platform = _ExcelPicker('');
  setUpAll(() async {
    if (const bool.fromEnvironment('ODEV_GORSEL')) {
      await (FontLoader(
        'NotoSans',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
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
    donem: 1,
  );

  Future<int> kontrol(
    int gid,
    int? n, {
    OdevKontrolDurumu? durum,
    int ogrenci = 1,
  }) async {
    final k = await BireyselOdevKontrolService.kontrolOlustur(
      oturum,
      gid,
      kontrolTarihi: DateTime(2026, 10, 1),
    );
    if (n != null || durum != null) {
      await BireyselOdevKontrolService.sonuclariKaydet(oturum, k, [
        OdevSonucGirdisi(
          ogrenciId: ogrenci,
          durum: durum ?? OdevKontrolSonuc.notDurumu(n, null),
          notDegeri: n,
        ),
      ]);
    }
    return k;
  }

  Future<PerformansVerisi> p([int grup = 1, int sinif = 1, int donem = 1]) =>
      PerformansNotService.oku(oturum, sinif, 1, donem, grup);
  Future<PerformansVerisi> sec(Set<int> ids, [int grup = 1]) async {
    await PerformansNotService.odevleriSec(oturum, await p(grup), ids);
    return p(grup);
  }

  test(
    'hızlı durum ve manuel 0–10 tek model; G/M hariç, K sıfır, boş farklı',
    () async {
      final g = await gorev('Puanlar');
      for (final d in OdevKontrolDurumu.hizli) {
        final k = await kontrol(g, null, durum: d);
        final s = (await BireyselOdevKontrolService.sonuclar(oturum, k)).single;
        expect(s.durum, d);
        expect(s.notDegeri, OdevKontrolSonuc.hizliNot(d));
        if (d.degerlendirmeDisi) expect(s.puan, isNull);
      }
      for (final n in List.generate(11, (i) => i)) {
        final k = await kontrol(g, n);
        final s = (await BireyselOdevKontrolService.sonuclar(oturum, k)).single;
        expect(s.puan, n);
      }
      final bos = await kontrol(g, null);
      expect(
        (await BireyselOdevKontrolService.sonuclar(
          oturum,
          bos,
        )).single.durum.bekliyor,
        true,
      );
      for (final n in [-4, 11]) {
        await expectLater(
          kontrol(g, n, durum: OdevKontrolDurumu.manuel),
          throwsException,
        );
      }
      expect((await db.rawQuery('PRAGMA foreign_key_check')), isEmpty);
    },
  );
  test('gerçek eski kolonlara v28 eklenir; durum ve veri korunur', () async {
    final eski = WindowsMemoryDatabase();
    try {
      await eski.execute(
        'CREATE TABLE OdevTanim (OdevId INTEGER PRIMARY KEY, Baslik TEXT)',
      );
      await eski.execute(
        'CREATE TABLE OdevKontrolSonuc (OdevKontrolSonucId INTEGER PRIMARY KEY, Durum TEXT)',
      );
      await eski.insert('OdevTanim', {'OdevId': 1, 'Baslik': 'Eski görev'});
      await eski.insert('OdevKontrolSonuc', {
        'OdevKontrolSonucId': 1,
        'Durum': 'Gelmedi',
      });
      await eski.transaction(OdevNotSemasi.hazirla);
      expect((await eski.query('OdevTanim')).single['Tamamlandi'], 0);
      final sonuc = (await eski.query('OdevKontrolSonuc')).single;
      expect(sonuc['NotDegeri'], isNull);
      expect(sonuc['Durum'], 'Gelmedi');
      await expectLater(
        eski.update('OdevKontrolSonuc', {'NotDegeri': 11}),
        throwsA(anything),
      );
      await eski.transaction(OdevNotSemasi.hazirla);
      expect((await eski.query('OdevTanim')).single['Baslik'], 'Eski görev');
    } finally {
      await eski.close();
    }
  });
  test('yeni ödev ilk kontrol ve ekiyle atomik kaydedilir', () async {
    Future<int> olustur(Uint8List bytes) =>
        BireyselOdevKontrolService.gorevOlustur(
          oturum,
          sinifSubeId: 1,
          dersId: 1,
          gorevTuru: OdevGorevTuru.normalOdev,
          baslik: 'Yeni',
          baslangicTarihi: DateTime(2026, 10, 1),
          ogrenciIdleri: [1],
          kontrolBaslat: true,
          ekAdi: 'odev.txt',
          ekVeri: bytes,
        );
    await expectLater(olustur(Uint8List(0)), throwsException);
    for (final t in [...tablolar, 'OdevEk']) {
      expect(await db.query(t), isEmpty);
    }
    await olustur(Uint8List.fromList([1, 2]));
    expect(await db.query('OdevTanim'), hasLength(1));
    expect(await db.query('OdevKontrol'), hasLength(1));
    expect(await db.query('OdevKontrolSonuc'), hasLength(1));
    expect(await db.query('OdevEk'), hasLength(1));
  });
  test(
    'P2 kriterleri ayrı saklanır, üst sınır ve yeniden açılış korunur',
    () async {
      var veri = await p(2);
      await PerformansNotService.kriterKaydet(
        oturum,
        veri,
        veri.ogrenciler.single,
        {for (final k in veri.kriterler) k.id: k.azami},
      );
      veri = await p(2);
      expect(veri.ogrenciler.single.kriterPuani, 100);
      expect((await p()).ogrenciler.single.kriterPuani, isNull);
      await PerformansNotService.agirlikKaydet(oturum, veri, 0);
      veri = await p(2);
      expect(veri.ogrenciler.single.oneri, 100);
      await PerformansNotService.notlariKaydet(oturum, veri, {1: 95});
      final yeniden = await BireyselOdevKontrolService.hazirla();
      final okunan = await PerformansNotService.oku(yeniden, 1, 1, 1, 2);
      expect(okunan.ogrenciler.single.nihai, 95);
      expect(okunan.ogrenciler.single.guncel, true);
      await expectLater(
        PerformansNotService.kriterKaydet(
          oturum,
          okunan,
          okunan.ogrenciler.single,
          {'hazirlik': 16},
        ),
        throwsException,
      );
      expect((await p(2)).ogrenciler.single.nihai, 95);
    },
  );
  test('Excel nihai P1/P2 notlarını ve eksik durumunu doğru taşır', () async {
    final g = await gorev('Excel');
    await kontrol(g, 8);
    final veri = await sec({g});
    await PerformansNotService.notlariKaydet(oturum, veri, {1: 85});
    final alan = await Directory.systemTemp.createTemp('performans_excel_');
    final onceki = FilePicker.platform;
    try {
      final yol = '${alan.path}/notlar.xlsx';
      FilePicker.platform = _ExcelPicker(yol);
      expect(await PerformansNotService.excelAktar(oturum, 1, 1, 1), yol);
      final kitap = Excel.decodeBytes(await File(yol).readAsBytes());
      final satirlar = kitap.tables.values.first.rows;
      final row = satirlar.singleWhere(
        (r) => r.first?.value.toString() == '1 • Öğrenci 1',
      );
      expect(row[1]?.value.toString(), '85');
      expect(row[2]?.value.toString() ?? '', '');
      expect(row[3]?.value.toString(), 'Eksik / yeniden kontrol edin');
    } finally {
      FilePicker.platform = onceki;
      await alan.delete(recursive: true);
    }
  });
  test(
    'v27 durumları migration ile yeniden yorumlanmaz; migration idempotent',
    () async {
      final g = await gorev('Eski');
      final k = await kontrol(g, null);
      await db.update('OdevKontrolSonuc', {
        'Durum': 'KontrolEdilmedi',
        'NotDegeri': null,
      });
      final onceki = await db.query('OdevKontrolSonuc');
      await db.transaction(OdevNotSemasi.hazirla);
      expect(await db.query('OdevKontrolSonuc'), onceki);
      expect(
        (await BireyselOdevKontrolService.sonuclar(
          oturum,
          k,
        )).single.durum.bekliyor,
        true,
      );
      await db.update('OdevKontrolSonuc', {'Durum': 'Gelmedi'});
      expect(
        (await BireyselOdevKontrolService.sonuclar(oturum, k)).single.durum,
        OdevKontrolDurumu.gelmedi,
      );
    },
  );
  test(
    'ödevler eşit ağırlıklı kontrol ortalaması; P1/P2 bağımsız ve ortak ödev seçilebilir',
    () async {
      final a = await gorev('A'), b = await gorev('B');
      await kontrol(a, 10);
      await kontrol(a, 0);
      await kontrol(b, 8);
      final onceki = await db.query('OdevTanim');
      var veri = await sec({a, b});
      expect(veri.ogrenciler.single.odev.puan, 65);
      expect(veri.ogrenciler.single.oneri, isNull);
      await sec({b}, 2);
      expect((await p(2)).ogrenciler.single.odev.puan, 80);
      expect((await p()).secilenler, {a, b});
      expect(await db.query('OdevTanim'), onceki);
      await sec({a});
      expect((await p()).ogrenciler.single.odev.puan, 50);
    },
  );
  test(
    'G/M hesap dışıdır; eksik ve boş değerlendirme farklıdır',
    () async {
      final a = await gorev('A'), b = await gorev('B');
      await kontrol(a, null, durum: OdevKontrolDurumu.gelmedi);
      await kontrol(a, null, durum: OdevKontrolDurumu.mazeretli);
      await kontrol(b, 0);
      var veri = await sec({a, b});
      var s = veri.ogrenciler.single;
      expect(s.odev.puan, 0);
      expect(s.odev.dahil, 1);
      expect(s.odev.disarida, 2);
      expect(s.odev.bos, 0);
      await kontrol(b, null);
      s = (await p()).ogrenciler.single;
      expect(s.odev.puan, 0);
      expect(s.odev.bos, 1);
    },
  );
  test('ödeve dahil edilmeyen öğrenciye sıfır veya boş yazılmaz', () async {
    final a = await gorev('A');
    await kontrol(a, 10);
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 2,
      'SinifSubeId': 1,
      'EgitimOgretimYili': oturum.yil,
      'OlusturmaTarihi': 'test',
    });
    final veri = await sec({a});
    final s = veri.ogrenciler.singleWhere((s) => s.ogrenci['OgrenciId'] == 2);
    expect(s.odev.puan, isNull);
    expect(s.odev.bos, 0);
  });
  test(
    'kriterler 100; ağırlık kullanıcı seçimi; nihai not öneriden ayrı; eskime tespit edilir',
    () async {
      for (final kriterler in performansKriterSablonlari.values) {
        expect(kriterler.fold<int>(0, (s, k) => s + k.azami), 100);
      }
      final a = await gorev('A');
      final k = await kontrol(a, 8);
      var veri = await sec({a});
      await PerformansNotService.kriterKaydet(
        oturum,
        veri,
        veri.ogrenciler.single,
        {for (final k in veri.kriterler) k.id: k.azami},
      );
      veri = await p();
      expect(veri.ogrenciler.single.kriterPuani, 100);
      expect(veri.ogrenciler.single.oneri, isNull);
      await PerformansNotService.agirlikKaydet(oturum, veri, 50);
      veri = await p();
      expect(veri.ogrenciler.single.oneri, 90);
      await PerformansNotService.notlariKaydet(oturum, veri, {1: 85});
      veri = await p();
      expect(veri.ogrenciler.single.nihai, 85);
      expect(veri.ogrenciler.single.guncel, true);
      await BireyselOdevKontrolService.sonuclariKaydet(oturum, k, [
        const OdevSonucGirdisi(
          ogrenciId: 1,
          durum: OdevKontrolDurumu.yapmadi,
          notDegeri: 0,
        ),
      ]);
      expect((await p()).ogrenciler.single.guncel, false);
      await expectLater(
        PerformansNotService.notlariKaydet(oturum, veri, {1: 85}),
        throwsException,
      );
      expect((await p()).ogrenciler.single.nihai, 85);
    },
  );
  test(
    'boş kontrol tamamlanmadan öneri yok; elle not ve gerçek sıfır saklanabilir',
    () async {
      final a = await gorev('A');
      await kontrol(a, 10);
      await kontrol(a, null);
      var veri = await sec({a});
      await PerformansNotService.agirlikKaydet(oturum, veri, 100);
      veri = await p();
      expect(veri.ogrenciler.single.oneri, isNull);
      await PerformansNotService.notlariKaydet(oturum, veri, {1: 0});
      expect((await p()).ogrenciler.single.nihai, 0);
    },
  );
  test(
    'yanlış sınıf/dönem, aşırı kriter ve eski seçim atomik reddedilir',
    () async {
      final a = await gorev('A'), b = await gorev('B', sinif: 2);
      var veri = await sec({a});
      await expectLater(
        PerformansNotService.odevleriSec(oturum, veri, {b}),
        throwsException,
      );
      await expectLater(
        PerformansNotService.kriterKaydet(
          oturum,
          veri,
          veri.ogrenciler.single,
          {'bilgi': 21},
        ),
        throwsException,
      );
      final eski = veri;
      await PerformansNotService.agirlikKaydet(oturum, veri, 100);
      await expectLater(
        PerformansNotService.odevleriSec(oturum, eski, {}),
        throwsException,
      );
      expect((await p()).secilenler, {a});
      veri = await p(1, 1, 2);
      await expectLater(
        PerformansNotService.odevleriSec(oturum, veri, {a}),
        throwsException,
      );
    },
  );
  test(
    'ekler sahiplik ve 10 MB kontrolüyle saklanır; ödev sıfırlaması performansı kapsar',
    () async {
      final a = await gorev('A');
      await kontrol(a, 8);
      await sec({a});
      await OdevDosyaService.ekle(
        oturum,
        a,
        'test.txt',
        Uint8List.fromList([65, 66]),
      );
      final ek = (await OdevDosyaService.liste(oturum, a)).single;
      expect((await OdevDosyaService.oku(oturum, a, ek['Id'] as int))['Veri'], [
        65,
        66,
      ]);
      await expectLater(
        OdevDosyaService.ekle(oturum, a, '../a', Uint8List.fromList([1])),
        throwsException,
      );
      final bakim = BireyselBakimService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final plan = (await bakim.sifirlamaEnvanteri()).planla({'odev'});
      expect(plan.tablolar, containsAll(OdevNotSemasi.tablolar));
      await bakim.seciliModulleriSifirla(plan, onayMetni: 'SIFIRLA');
      for (final t in [...tablolar, ...OdevNotSemasi.tablolar]) {
        expect(await db.query(t), isEmpty);
      }
      expect(await db.query('Ogrenci'), hasLength(2));
    },
  );
  test(
    'v28 yedek geri yüklenir; v27 ödev ve sonuçlar kayıpsız uyarlanır',
    () async {
      final alan = await Directory.systemTemp.createTemp('odev_test_');
      addTearDown(() => alan.delete(recursive: true));
      final a = await gorev('A');
      await kontrol(a, 8);
      await sec({a});
      final bakim = BireyselBakimService(
        databaseGetir: () async => db,
        alanGetir: () async => alan,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final y = await bakim.yedekle();
      await bakim.geriYukle(
        await bakim.incele(y.dosya),
        onayMetni: 'GERİ YÜKLE',
      );
      expect((await p()).ogrenciler.single.odev.puan, 80);
      final archive = ZipDecoder().decodeBytes(await y.dosya.readAsBytes());
      final m =
          jsonDecode(
                utf8.decode(
                  archive.findFile('yedek.json')!.content as List<int>,
                ),
              )
              as Map;
      m['sema'] = 27;
      eskiYedekAlanlariniAyir(m, 27);
      for (final t in OdevNotSemasi.tablolar) {
        (m['tablolar'] as Map).remove(t);
        (m['kolonlar'] as Map).remove(t);
      }
      for (final (t, col) in [
        ('OdevKontrolSonuc', 'NotDegeri'),
        ('OdevTanim', 'Tamamlandi'),
      ]) {
        (m['kolonlar'][t] as List).remove(col);
        for (final r in m['tablolar'][t] as List) {
          (r as Map).remove(col);
        }
      }
      final bytes = utf8.encode(jsonEncode(m));
      final f = File('${alan.path}/v27.zip');
      await f.writeAsBytes(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile('yedek.json', bytes.length, bytes)),
        )!,
      );
      await bakim.geriYukle(await bakim.incele(f), onayMetni: 'GERİ YÜKLE');
      expect((await db.query('OdevTanim')).single['Tamamlandi'], 0);
      expect((await db.query('OdevKontrolSonuc')).single['NotDegeri'], isNull);
      expect(await db.query('PerformansTanim'), isEmpty);
    },
  );
  testWidgets('320 px performans filtreleri ve boş sınıf taşmaz', (t) async {
    t.view.physicalSize = const Size(320, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(home: PerformansNotScreen(oturum: oturum)));
    await t.pumpAndSettle();
    expect(find.text('Not Hesaplama'), findsOneWidget);
    expect(find.text('Performans 1'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  Future<void> tikla(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .last,
        maxScrolls: 80,
      );
    }
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
    await t.tap(f.last);
    await t.pumpAndSettle();
  }

  testWidgets(
    '40 öğrenci dar ekranda hızlı not, toplu uygulama, geri alma ve vurgu temizliği',
    (t) async {
      t.view.physicalSize = const Size(320, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (var i = 3; i <= 41; i++) {
        await db.insert('Ogrenci', {
          'OgrenciId': i,
          'OkulNo': '$i',
          'Ad': 'Uzun öğrenci adı $i',
          'Soyad': 'Örnek soyadı',
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciSinifKayit', {
          'OgrenciId': i,
          'SinifSubeId': 1,
          'EgitimOgretimYili': oturum.yil,
          'OlusturmaTarihi': 'test',
        });
      }
      final g = await BireyselOdevKontrolService.gorevOlustur(
        oturum,
        sinifSubeId: 1,
        dersId: 1,
        gorevTuru: OdevGorevTuru.normalOdev,
        baslik: 'Kırk kişilik sınıf',
        baslangicTarihi: DateTime(2026, 9, 1),
        ogrenciIdleri: [1, ...List.generate(39, (i) => i + 3)],
        kontrolBaslat: true,
        donem: 1,
      );
      final k = (await BireyselOdevKontrolService.kontroller(
        oturum,
        g,
      )).single.odevKontrolId;
      await t.pumpWidget(
        MaterialApp(
          home: OdevKontrolDetayScreen(oturum: oturum, odevId: g),
        ),
      );
      await t.pumpAndSettle();
      await tikla(t, find.byKey(const ValueKey('durum-1-yapti')));
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('satir-puan-1')))
            .controller!
            .text,
        '10',
      );
      expect(find.text('Kaydedilmedi'), findsOneWidget);
      await tikla(t, find.text('Kaydet'));
      await tikla(t, find.byKey(const ValueKey('durum-1-yapti')));
      expect(find.text('Kaydedilmedi'), findsNothing);
      await tikla(t, find.text('Toplu giriş'));
      await tikla(t, find.text('Toplu uygula'));
      await tikla(t, find.byKey(const ValueKey('toplu-durum')));
      await tikla(t, find.text('Özel puan (0–10)').last);
      await t.enterText(find.byKey(const ValueKey('toplu-puan')), '8');
      await tikla(t, find.text('Uygula'));
      await tikla(t, find.text('Geri Al'));
      expect(
        (await BireyselOdevKontrolService.sonuclar(
          oturum,
          k,
        )).singleWhere((s) => s.ogrenciId == 1).puan,
        10,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'manuel puan klavye açıkken doğrulanır ve boş ile sıfır ayrılır',
    (t) async {
      t.view.physicalSize = const Size(320, 720);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      int? kayit;
      OdevKontrolDurumu? durum;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  builder: (_) => OdevPuanDialog(
                    ad: '1 • Uzun öğrenci adı',
                    durum: OdevKontrolDurumu.kontrolEdilmedi,
                    notDegeri: null,
                    aciklama: '',
                    kaydet: (n, d, a) async {
                      kayit = n;
                      durum = d;
                    },
                  ),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Aç'));
      await t.pumpAndSettle();
      final alan = find.byKey(const ValueKey('manuel-odev-puani'));
      await t.scrollUntilVisible(
        alan,
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .last,
      );
      await t.ensureVisible(alan);
      await t.enterText(alan, '11');
      await tikla(t, find.text('Kaydet'));
      expect(find.textContaining('0–10'), findsWidgets);
      expect(kayit, isNull);
      await t.ensureVisible(alan);
      await t.enterText(alan, '0');
      await tikla(t, find.text('Kaydet'));
      expect(kayit, 0);
      expect(durum, OdevKontrolDurumu.yapmadi);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'performans sonucu öğretmen onayıyla kaydedilir; taslak ayrı tutulur',
    (t) async {
      final g = await gorev('P1 görevi');
      await kontrol(g, 8);
      var veri = await sec({g});
      await PerformansNotService.agirlikKaydet(oturum, veri, 100);
      await t.pumpWidget(
        MaterialApp(home: PerformansNotScreen(oturum: oturum)),
      );
      await t.pumpAndSettle();
      final row = find.widgetWithText(ListTile, '1 • Öğrenci 1');
      await t.scrollUntilVisible(
        row,
        160,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .last,
      );
      await t.pumpAndSettle();
      await t.tap(row);
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.byKey(const ValueKey('nihai-performans-puani')),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('nihai-performans-puani')),
        '85',
      );
      await tikla(t, find.text('Uygula'));
      expect((await p()).ogrenciler.single.nihai, isNull);
      await t.runAsync(() async {
        await t.tap(find.text('Notları Kaydet'));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await t.pumpAndSettle();
      expect((await p()).ogrenciler.single.nihai, 85);
      expect(t.takeException(), isNull);
    },
  );
  Widget gorselApp(Widget home) => RepaintBoundary(
    key: const ValueKey('odev-gorsel-root'),
    child: MaterialApp(debugShowCheckedModeBanner: false, home: home),
  );
  Future<void> gorsel(WidgetTester t, String ad) async {
    if (!const bool.fromEnvironment('ODEV_GORSEL')) return;
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('odev-gorsel-root')),
      );
      final img = await boundary.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File('build/odev_gorsel/$ad.png');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(data!.buffer.asUint8List());
      img.dispose();
    });
  }

  for (final genislik in [320.0, 390.0]) {
    for (final olcek in [1.0, 1.3, 2.0]) {
      testWidgets('Ödev sonuçları $genislik px ve $olcek yazıda taşmaz', (
        t,
      ) async {
        t.view.physicalSize = Size(genislik, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final id = await gorev('Uygulama Kontrolü');
        final k = await kontrol(id, 10);
        await t.pumpWidget(
          gorselApp(
            Builder(
              builder: (c) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: TextScaler.linear(olcek)),
                child: OdevKontrolDetayScreen(oturum: oturum, odevId: id),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await tikla(t, find.text('Bilgiler'));
        await tikla(t, find.byKey(const ValueKey('odev-sonuc-ozeti')));
        for (final ad in ['Tam', 'Yarı', 'Eksik', 'Gelmedi', 'Mazeretli']) {
          expect(find.text(ad), findsOneWidget);
        }
        await tikla(t, find.text('Kapat'));
        await tikla(t, find.byTooltip('Bilgileri kapat'));
        expect(
          (await BireyselOdevKontrolService.sonuclar(oturum, k)).single.puan,
          10,
        );
        expect(t.takeException(), isNull);
        if (genislik == 320 && olcek == 1.3) {
          await gorsel(t, 'sonuc_tasma_duzeltme');
        }
      });
    }
  }

  testWidgets('eski Yaptı puanı görünür; yeni seçim 10 puan kaydeder', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final g = await gorev('Windows Forms Mini Proje');
    final k = await kontrol(g, null);
    await db.update('OdevKontrolSonuc', {'Durum': 'Yapti', 'NotDegeri': null});
    await t.pumpWidget(
      gorselApp(OdevKontrolDetayScreen(oturum: oturum, odevId: g)),
    );
    await t.pumpAndSettle();
    await gorsel(t, '01_odev_detayi');
    await tikla(t, find.byKey(const ValueKey('satir-puan-1')));
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('satir-puan-1')))
          .controller!
          .text,
      '10',
    );
    await gorsel(t, '02_not_girisi');
    await tikla(t, find.byKey(const ValueKey('puan-1')));
    await tikla(t, find.byKey(const ValueKey('detay-hizli-kismen')));
    await tikla(t, find.byKey(const ValueKey('detay-hizli-yapti')));
    final field = find.byKey(const ValueKey('manuel-odev-puani'));
    expect(t.widget<TextField>(field).controller!.text, '10');
    await gorsel(t, '03_ogrenci_puani');
    await tikla(t, find.text('Kaydet'));
    expect(find.text('Ödev Not Girişi'), findsOneWidget);
    expect(
      (await BireyselOdevKontrolService.sonuclar(oturum, k)).single.puan,
      10,
    );
    await tikla(t, find.text('Öğrenci 1'));
    expect(find.text('Öğrenci Detayı'), findsOneWidget);
    await gorsel(t, '11_ogrenci_detayi');
    expect(find.text('10'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tikla(t, find.text('Toplu giriş'));
      await tikla(t, find.text('Toplu uygula'));
    await gorsel(t, '12_toplu_islem');
    await tikla(t, find.byTooltip('Kapat'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('kriter tam sayfa kaydedilir ve özet tabloya yansır', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final g = await gorev('Değişkenler Uygulaması');
    await kontrol(g, 8);
    await sec({g});
    await t.pumpWidget(gorselApp(PerformansNotScreen(oturum: oturum)));
    await t.pumpAndSettle();
    await gorsel(t, '04_not_hesaplama');
    await tikla(t, find.text('Ödev Seçimi ve Hesaplama'));
    await gorsel(t, '05_odev_secimi');
    await t.pageBack();
    await t.pumpAndSettle();
    await tikla(t, find.text('Kriterleri Değerlendir'));
    for (final k in performansKriterSablonlari[1]!) {
      final f = find.byKey(ValueKey('kriter-${k.id}'));
      if (f.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          f,
          160,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await t.ensureVisible(f);
      await t.enterText(f, '${k.azami}');
    }
    await gorsel(t, '06_kriterler');
    await tikla(t, find.text('Kaydet'));
    expect((await p()).ogrenciler.single.kriterPuani, 100);
    await tikla(t, find.text('Hesaplama ağırlığını belirle'));
    await t.enterText(find.byKey(const ValueKey('performans-agirlik')), '50');
    await tikla(t, find.text('Kaydet'));
    await tikla(t, find.widgetWithText(ListTile, '1 • Öğrenci 1'));
    await gorsel(t, '07_hesaplama_sonucu');
    final f = find.byKey(const ValueKey('nihai-performans-puani'));
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        160,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(f);
    await t.enterText(f, '95');
    await tikla(t, find.text('Uygula'));
    await tikla(t, find.text('Notları Kaydet'));
    expect((await p()).ogrenciler.single.nihai, 95);
    await tikla(t, find.text('Özet'));
    await gorsel(t, '08_performans_ozeti');
    expect(find.byType(Table), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('ödev listesi ve yeni ödev üst Kaydet ile çalışır', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final ad in [
      'Değişkenler Uygulaması',
      'If-Else Uygulamaları',
      'Döngüler Çalışması',
      'Windows Forms Mini Proje',
      'SQLite CRUD',
      'Haftalık Kontrol - 1',
    ]) {
      await gorev(ad);
    }
    await t.pumpWidget(gorselApp(const OdevKontrolScreen()));
    await t.pumpAndSettle();
    await gorsel(t, '09_odevlerim');
    await tikla(t, find.byTooltip('Yeni Ödev'));
    await gorsel(t, '10_yeni_odev');
    final f = find.widgetWithText(TextFormField, 'Başlık');
    await t.enterText(f, 'Yeni deneme');
    await tikla(t, find.text('Kaydet'));
    expect(
      (await db.query(
        'OdevTanim',
        where: 'Baslik=?',
        whereArgs: ['Yeni deneme'],
      )),
      hasLength(1),
    );
    expect(find.text('Ödev Not Girişi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test(
    'geçmiş yıl okunur, başka yılın notuna güncel oturumla yazılamaz',
    () async {
      final g = await gorev('Geçmiş');
      await kontrol(g, 8);
      await sec({g});
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
      await db.update('OkulProfil', {'EgitimYili': '2027-2028'});
      final yeni = await BireyselOdevKontrolService.hazirla();
      final eski = await PerformansNotService.oku(
        yeni,
        1,
        1,
        1,
        1,
        yil: '2026-2027',
      );
      expect(eski.ogrenciler.single.odev.puan, 80);
      await expectLater(
        PerformansNotService.agirlikKaydet(yeni, eski, 50),
        throwsException,
      );
    },
  );
}

class _ExcelPicker extends FilePicker {
  _ExcelPicker(this.yol);
  final String yol;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => yol;
}
