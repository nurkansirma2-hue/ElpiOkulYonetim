import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/rapor_sablonu.dart';
import 'package:elpi_okul_yonetim/screens/admin_import_screen.dart';
import 'package:elpi_okul_yonetim/screens/rapor_olustur_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_odev_kontrol_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// Native yazıcı/raster çağrıları yalnız testte devre dışı bırakılır.
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

class _TestPrinting extends PrintingPlatform {
  @override
  Future<PrintingInfo> info() async => PrintingInfo.unavailable;

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      const Stream<PdfRaster>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Bu testte üretilen PDF'nin gömülü Unicode eşlemesini kullanır. Böylece
// yalnız PDF üretildiği değil, her öğrencinin sınıfının gerçekten yazıldığı
// kontrol edilir; sistemde PDF okuyucu veya native raster eklentisi gerekmez.
String _pdfMetni(Uint8List bytes) {
  final pdf = latin1.decode(bytes);
  final nesneler = <int, String>{
    for (final eslesme in RegExp(
      r'(\d+)\s+0\s+obj\b([\s\S]*?)endobj',
    ).allMatches(pdf))
      int.parse(eslesme.group(1)!): eslesme.group(2)!,
  };
  String? akis(String nesne) {
    final baslangic = RegExp(r'\bstream\r?\n').firstMatch(nesne);
    final uzunluk = RegExp(r'/Length\s+(\d+)').firstMatch(nesne);
    if (baslangic == null || uzunluk == null) return null;
    final veri = latin1.encode(nesne.substring(
      baslangic.end,
      baslangic.end + int.parse(uzunluk.group(1)!),
    ));
    return latin1.decode(nesne.contains('/FlateDecode') ? zlib.decode(veri) : veri);
  }

  final fontlar = <String, Map<int, String>>{};
  for (final nesne in nesneler.values) {
    final ad = RegExp(r'/Name\s*/(\w+)').firstMatch(nesne);
    final unicode = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R').firstMatch(nesne);
    if (ad == null || unicode == null) continue;
    final cmap = akis(nesneler[int.parse(unicode.group(1)!)]!)!;
    final karakterler = cmap.split('beginbfchar').last.split('endbfchar').first;
    fontlar[ad.group(1)!] = {
      for (final e in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(karakterler))
        int.parse(e.group(1)!, radix: 16):
            String.fromCharCode(int.parse(e.group(2)!, radix: 16)),
    };
  }

  final sonuc = StringBuffer();
  for (final nesne in nesneler.values) {
    final metin = akis(nesne);
    if (metin == null || !metin.contains('TJ')) continue;
    Map<int, String>? font;
    for (final e in RegExp(
      r'/(\w+)\s+[-+\d.]+\s+Tf|<([0-9A-Fa-f]+)>',
    ).allMatches(metin)) {
      if (e.group(1) != null) {
        font = fontlar[e.group(1)!];
      } else if (font != null) {
        final kodlar = e.group(2)!;
        for (var i = 0; i + 4 <= kodlar.length; i += 4) {
          sonuc.write(font[int.parse(kodlar.substring(i, i + 4), radix: 16)] ?? '');
        }
        sonuc.write(' ');
      }
    }
  }
  return sonuc.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const yil = '2026/2027';
  late Database db;
  late PrintingPlatform oncekiPrinting;

  Future<void> sinifEkle(int id, String kod, int seviye, {
    String egitimYili = yil,
    bool aktif = true,
  }) async {
    await db.insert('SinifSube', {
      'SinifSubeId': id, 'SinifKodu': kod, 'SinifSeviyesi': seviye,
      'EgitimOgretimYili': egitimYili, 'Aktif': aktif ? 1 : 0,
      'OlusturmaTarihi': 'test',
    });
  }

  Future<void> programEkle(int sinifId, {
    int dersId = 1,
    int profilId = 1,
    String egitimYili = yil,
    bool aktif = true,
    int? surumId,
  }) async {
    await db.insert('DersProgrami', {
      'SinifSubeId': sinifId, 'DersId': dersId, 'DersSaatiId': 1,
      'Gun': 'Pazartesi', 'Baslangic': '08:00', 'Bitis': '08:40',
      'OgretmenProfilId': profilId, 'EgitimOgretimYili': egitimYili,
      'Aktif': aktif ? 1 : 0, 'ProgramSurumId': surumId,
      'OlusturmaTarihi': 'test',
    });
  }

  Future<void> ogrenciEkle(int id, String no, String ad, int sinifId, {
    String soyad = 'Öğrenci',
    bool ogrenciAktif = true,
    bool kayitAktif = true,
    String kayitYili = yil,
  }) async {
    await db.insert('Ogrenci', {
      'OgrenciId': id, 'OkulNo': no, 'Ad': ad, 'Soyad': soyad,
      'Aktif': ogrenciAktif ? 1 : 0, 'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': id, 'SinifSubeId': sinifId,
      'EgitimOgretimYili': kayitYili, 'Aktif': kayitAktif ? 1 : 0,
      'OlusturmaTarihi': 'test',
    });
  }

  Future<void> ekSinifIzniEkle(List<int> siniflar, {
    int profilId = 1,
    String egitimYili = yil,
  }) async {
    await db.insert('UygulamaAyarlari', {
      'Anahtar': 'ogrenci_ek_sinif:$profilId:$egitimYili',
      'Deger': jsonEncode(siniflar), 'GuncellemeTarihi': 'test',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Finder sinifSecimi() => find.byWidgetPredicate(
    (w) => w is DropdownButton<int> &&
        w.items!.any((item) => item.value == 0),
  );

  Finder dersSecimi() => find.descendant(
    of: find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('liste-ders-secimi-')),
    matching: find.byType(DropdownButton<String>),
  );

  Finder metinAlani(String etiket) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == etiket,
  );

  Future<void> dersSec(WidgetTester tester, String ad) async {
    await tester.ensureVisible(dersSecimi());
    await tester.tap(dersSecimi());
    await tester.pumpAndSettle();
    await tester.tap(find.text(ad).last);
    await tester.pumpAndSettle();
  }

  Future<void> ekraniAc(WidgetTester tester, {bool buyukYazi = false}) async {
    await tester.pumpWidget(MaterialApp(
      builder: buyukYazi ? (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.5),
        ),
        child: child!,
      ) : null,
      home: const RaporOlusturScreen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> sinifSec(WidgetTester tester, String ad) async {
    await tester.tap(sinifSecimi());
    await tester.pumpAndSettle();
    await tester.tap(find.text(ad).last);
    await tester.pumpAndSettle();
  }

  Future<void> kayitliTasarimiAc(WidgetTester tester, String ad) async {
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tasarım'));
    await tester.pumpAndSettle();
    final secim = find.byWidgetPredicate((w) => w is DropdownButton<String> &&
        w.items!.any((item) => item.value == 'k0'));
    await tester.tap(secim);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydım: $ad').last);
    await tester.pumpAndSettle();
  }

  Future<void> tasarimdaGorunurYap(WidgetTester tester, Finder hedef) async {
    if (hedef.evaluate().isEmpty &&
        (hedef.toString().contains('ortak-bilgi-goster-') ||
         hedef.toString().contains('ortak-bilgi-konum-'))) {
      final liste = find.byKey(const ValueKey('ortak-bilgi-sirasi'));
      await tasarimdaGorunurYap(tester, liste);
      final kaydirma = find.descendant(of: liste,
          matching: find.byType(Scrollable)).first;
      final konum = tester.state<ScrollableState>(kaydirma).position;
      konum.jumpTo(0);
      await tester.pumpAndSettle();
      for (var i = 0; i < 16 && hedef.evaluate().isEmpty; i++) {
        konum.jumpTo((konum.pixels + 180).clamp(0, konum.maxScrollExtent).toDouble());
        await tester.pumpAndSettle();
      }
    }
    if (hedef.evaluate().isEmpty) {
      final anaKaydirma = find.descendant(of: find.byType(ListView).first,
          matching: find.byType(Scrollable)).first;
      final konum = tester.state<ScrollableState>(anaKaydirma).position;
      konum.jumpTo(0);
      await tester.pumpAndSettle();
      for (var i = 0; i < 40 && hedef.evaluate().isEmpty; i++) {
        konum.jumpTo((konum.pixels + 250).clamp(0, konum.maxScrollExtent).toDouble());
        await tester.pumpAndSettle();
      }
    }
    await tester.ensureVisible(hedef);
    await tester.pumpAndSettle();
    if (hedef.toString().contains('ortak-bilgi-goster-') ||
        hedef.toString().contains('ortak-bilgi-konum-')) {
      // İç listenin kayması dış listedeki eski hedef dikdörtgenini değiştirir.
      // Dış kaydırmayı listenin tamamına hizalayarak gerçek dokunmayı koru.
      await tester.ensureVisible(find.byKey(const ValueKey('ortak-bilgi-sirasi')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> isaretDegistir(WidgetTester tester, String anahtar) async {
    final secim = find.byKey(ValueKey(anahtar));
    await tasarimdaGorunurYap(tester, secim);
    await tester.tap(secim);
    await tester.pumpAndSettle();
  }

  Future<String> onIzlemeMetni(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ön izleme / Yazdır'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    final bytes = await tester.runAsync(() async => await preview.build(PdfPageFormat.a4));
    return _pdfMetni(bytes!);
  }

  Future<RaporSablonu> tasarimiKaydet(WidgetTester tester,
      BireyselListeOturumu oturum, String ad) async {
    await tester.tap(find.byTooltip('Şablonu kaydet'));
    await tester.pumpAndSettle();
    await tester.enterText(metinAlani('Şablon adı'), ad);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    return (await BireyselListeService.sablonlar(oturum))
        .singleWhere((sablon) => sablon.ad == ad);
  }

  Future<void> uzunBasipBirak(WidgetTester tester, Finder kaynak,
      Finder hedef) async {
    // Kaynak ve hedef aynı anda görünür kalmalı; hedefi tek başına üste
    // hizalamak üst bölgedeki kaynağı ekranın dışına kaydırır.
    await tasarimdaGorunurYap(tester,
        find.byKey(const ValueKey('ortak-yerlesim-paneli')));
    expect(kaynak.hitTestable(), findsOneWidget);
    expect(hedef.hitTestable(), findsOneWidget);
    final dokunma = await tester.startGesture(tester.getCenter(kaynak));
    await tester.pump(const Duration(milliseconds: 700));
    await dokunma.moveTo(tester.getCenter(hedef));
    await tester.pump(const Duration(milliseconds: 200));
    await dokunma.up();
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await LocalDatabase.instance.close();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    oncekiPrinting = PrintingPlatform.instance;
    PrintingPlatform.instance = _TestPrinting();
    for (var id = 1; id <= 2; id++) {
      await db.insert('OgretmenProfil', {
        'OgretmenProfilId': id, 'AdSoyad': 'Öğretmen $id',
        'OkulAdi': 'Test Okulu', 'EgitimOgretimYili': yil,
        'Aktif': id == 1 ? 1 : 0, 'OlusturmaTarihi': 'test',
      });
    }
    await db.insert('Ders', {
      'DersId': 1, 'DersAdi': 'Matematik', 'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    await sinifEkle(1, '9-A', 9);
    await sinifEkle(2, '10-B', 10);
    await sinifEkle(3, '9-C', 9);
    await sinifEkle(4, '10-C', 10, aktif: false);
    await sinifEkle(5, '11-A', 11);
    await sinifEkle(6, '11-B', 11);
    await sinifEkle(7, '12-A', 12);
    await sinifEkle(8, '8-A', 8, egitimYili: '2025/2026');
    await sinifEkle(9, '12-B', 12);
    await sinifEkle(10, '12-C', 12);
    await sinifEkle(11, '12-D', 12);
    await programEkle(1);
    await programEkle(1); // Aynı sınıfta iki ders öğrenciyi çoğaltmaz.
    await programEkle(2);
    await programEkle(4);
    await programEkle(5, profilId: 2);
    await programEkle(6, egitimYili: '2025/2026');
    await programEkle(7, aktif: false);
    await programEkle(8);
    for (var id = 1; id <= 3; id++) {
      await db.insert('DersProgramiSurum', {
        'ProgramSurumId': id, 'OgretmenProfilId': 1,
        'EgitimOgretimYili': yil, 'Aktif': id == 2 ? 0 : 1,
        'BaslangicTarihi': id == 3 ? '2999-01-01' : null,
        'BitisTarihi': id == 1 ? '2000-01-01' : null,
        'OlusturmaTarihi': 'test',
      });
      await programEkle(id + 8, surumId: id);
    }
    await ogrenciEkle(1, '10', 'Deniz', 1, soyad: 'Dokuz');
    await ogrenciEkle(2, '2', 'Ada', 1, soyad: 'Dokuz');
    await ogrenciEkle(3, '1', 'Bora', 2, soyad: 'On');
    await ogrenciEkle(4, '104', 'Pasif öğrenci', 1, ogrenciAktif: false);
    await ogrenciEkle(5, '105', 'Pasif kayıt', 1, kayitAktif: false);
    await ogrenciEkle(6, '106', 'Eski yıl kaydı', 1, kayitYili: '2025/2026');
    for (var sinif = 3; sinif <= 11; sinif++) {
      await ogrenciEkle(sinif + 10, '${sinif + 110}', 'Kapsam dışı $sinif', sinif);
    }
  });

  tearDown(() async {
    PrintingPlatform.instance = oncekiPrinting;
    await LocalDatabase.instance.close();
  });

  test('Tüm sınıflar aktif profil, yıl ve geçerli program kapsamıyla sıralanır', () async {
    final oturum = await BireyselListeService.hazirla();
    expect(oturum.siniflar.map((s) => s.sinifSubeId), [1, 2]);
    final ogrenciler = await BireyselListeService.ogrenciler(oturum, null);
    expect(ogrenciler.map((o) => o['OgrenciId']), [2, 1, 3]);
    expect(ogrenciler.map((o) => o['SinifKodu']), ['9-A', '9-A', '10-B']);
    expect(ogrenciler.map((o) => o['OkulNo']), ['2', '10', '1']);
  });

  test('Tek sınıf seçimi kapsamı ve sayısal okul numarası sırasını korur', () async {
    final oturum = await BireyselListeService.hazirla();
    expect((await BireyselListeService.ogrenciler(oturum, 1))
        .map((o) => o['OgrenciId']), [2, 1]);
    expect((await BireyselListeService.ogrenciler(oturum, 2))
        .map((o) => o['OgrenciId']), [3]);
    expect(await BireyselListeService.ogrenciler(oturum, 5), isEmpty);
    expect(await BireyselListeService.ogrenciler(oturum, 999), isEmpty);
  });

  test('Ders seçenekleri sınıfa özel, tekil ve geçerli program kapsamındadır', () async {
    for (final ders in {
      2: 'Fizik',
      3: 'Kimya',
      4: 'Biyoloji',
      5: 'Tarih',
      6: 'Coğrafya',
      7: 'Müzik',
      8: 'Resim',
      9: 'Felsefe',
    }.entries) {
      await db.insert('Ders', {
        'DersId': ders.key,
        'DersAdi': ders.value,
        'OlusturmaTarihi': 'test',
      });
    }
    await programEkle(1, dersId: 2);
    await programEkle(1, dersId: 2);
    await programEkle(2, dersId: 3);
    await programEkle(1, dersId: 4, profilId: 2);
    await programEkle(1, dersId: 5, egitimYili: '2025/2026');
    await programEkle(1, dersId: 6, aktif: false);
    await programEkle(1, dersId: 7, surumId: 1);
    await programEkle(1, dersId: 8, surumId: 2);
    await programEkle(1, dersId: 9, surumId: 3);
    await db.insert('Ders', {
      'DersId': 10, 'DersAdi': 'Pasif ders', 'Aktif': 0,
      'OlusturmaTarihi': 'test',
    });
    await programEkle(1, dersId: 10);
    await ekSinifIzniEkle([3]);

    final oturum = await BireyselListeService.hazirla(ekSiniflariDahilEt: true);
    expect(oturum.sinifDersleri[1], unorderedEquals(['Matematik', 'Fizik']));
    expect(oturum.sinifDersleri[2], unorderedEquals(['Matematik', 'Kimya']));
    expect(oturum.sinifDersleri[3] ?? const <String>[], isEmpty);
    expect(oturum.sinifDersleri.keys, everyElement(isIn([1, 2, 3])));
    expect(oturum.okul, 'Test Okulu');
  });

  test('Müdür aynı profil ve okul için yıllar arasında hatırlanır', () async {
    final oturum = await BireyselListeService.hazirla();
    expect(oturum.mudur, isEmpty);
    await BireyselListeService.mudurKaydet(oturum, '  Ayşe Yönetici  ');
    expect((await BireyselListeService.hazirla()).mudur, 'Ayşe Yönetici');

    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'},
      where: 'OgretmenProfilId = ?', whereArgs: [1]);
    final yeniYil = await BireyselListeService.hazirla();
    expect(yeniYil.mudur, 'Ayşe Yönetici');
    await expectLater(BireyselListeService.mudurKaydet(oturum, 'Eski yıl'),
      throwsA(isA<StateError>()));
    await BireyselListeService.mudurKaydet(yeniYil, '');
    expect((await BireyselListeService.hazirla()).mudur, isEmpty);
  });

  test('Müdür bilgisi diğer profil ve okula karışmaz; eski oturum yazamaz', () async {
    final oturum = await BireyselListeService.hazirla();
    await BireyselListeService.mudurKaydet(oturum, 'Ayşe Yönetici');
    await db.update('OgretmenProfil', {'OkulAdi': 'Başka Okul'},
      where: 'OgretmenProfilId = ?', whereArgs: [1]);
    expect((await BireyselListeService.hazirla()).mudur, isEmpty);
    await expectLater(BireyselListeService.mudurKaydet(oturum, 'Yanlış okul'),
      throwsA(isA<StateError>()));
    await db.update('OgretmenProfil', {'OkulAdi': 'Test Okulu'},
      where: 'OgretmenProfilId = ?', whereArgs: [1]);
    expect((await BireyselListeService.hazirla()).mudur, 'Ayşe Yönetici');

    await db.update('OgretmenProfil', {'Aktif': 1},
      where: 'OgretmenProfilId = ?', whereArgs: [2]);
    expect((await BireyselListeService.hazirla()).mudur, isEmpty);
    await expectLater(BireyselListeService.mudurKaydet(oturum, 'Yanlış profil'),
      throwsA(isA<StateError>()));
    final prefs = await SharedPreferences.getInstance();
    final digerProfil = await BireyselListeService.hazirla();
    await prefs.setString('calisma_modu', 'okul');
    await expectLater(BireyselListeService.mudurKaydet(digerProfil, 'Yanlış mod'),
      throwsA(isA<StateError>()));
  });

  test('Ek sınıf izni yalnız açıkça dahil edilen profil ve yıl kapsamına eklenir', () async {
    await ekSinifIzniEkle([1, 3, 4, 8, 999]);
    await ekSinifIzniEkle([5], profilId: 2);
    await ekSinifIzniEkle([6], egitimYili: '2025/2026');
    await ogrenciEkle(31, '301', 'Ek sınıfta pasif öğrenci', 3, ogrenciAktif: false);
    await ogrenciEkle(32, '302', 'Ek sınıfta pasif kayıt', 3, kayitAktif: false);
    await ogrenciEkle(33, '303', 'Ek sınıfta eski yıl', 3, kayitYili: '2025/2026');

    final oturum = await BireyselListeService.hazirla(ekSiniflariDahilEt: true);
    expect(oturum.ekSiniflariDahilEt, isTrue);
    expect(oturum.siniflar.map((s) => s.sinifSubeId), [1, 3, 2]);
    final ogrenciler = await BireyselListeService.ogrenciler(oturum, null);
    expect(ogrenciler.map((o) => o['OgrenciId']), [2, 1, 13, 3]);
    expect((await BireyselListeService.ogrenciler(oturum, 3))
        .map((o) => o['OgrenciId']), [13]);
    expect(await BireyselListeService.ogrenciler(oturum, 4), isEmpty);
    expect(await BireyselListeService.ogrenciler(oturum, 5), isEmpty);
    expect(await BireyselListeService.ogrenciler(oturum, 6), isEmpty);
    expect(await BireyselListeService.ogrenciler(oturum, 8), isEmpty);

    await ekSinifIzniEkle([]);
    expect(await BireyselListeService.ogrenciler(oturum, 3), isEmpty);
  });

  test('Varsayılan liste ve Ödev Kontrol ek sınıf izninden etkilenmez', () async {
    await ekSinifIzniEkle([3]);
    final oturum = await BireyselListeService.hazirla();
    expect(oturum.ekSiniflariDahilEt, isFalse);
    expect(oturum.siniflar.map((s) => s.sinifSubeId), [1, 2]);
    expect(await BireyselListeService.ogrenciler(oturum, 3), isEmpty);
    final odevOturumu = await BireyselOdevKontrolService.hazirla();
    expect(odevOturumu.ekSiniflariDahilEt, isFalse);
    expect(odevOturumu.siniflar.map((s) => s.sinifSubeId), [1, 2]);
    expect(await BireyselOdevKontrolService.ogrenciSecenekleri(odevOturumu, 3), isEmpty);
  });

  test('Ders programı olmasa da izinli ek sınıf okunur; izinsiz sınıflar açılmaz', () async {
    await db.update('DersProgrami', {'Aktif': 0});
    await ekSinifIzniEkle([3]);
    final oturum = await BireyselListeService.hazirla(ekSiniflariDahilEt: true);
    expect(oturum.siniflar.map((s) => s.sinifSubeId), [3]);
    expect((await BireyselListeService.ogrenciler(oturum, null))
        .map((o) => o['OgrenciId']), [13]);
    expect((await BireyselListeService.hazirla()).siniflar, isEmpty);
  });

  test('Mod, profil veya eğitim yılı değişince eski liste oturumu reddedilir', () async {
    await ekSinifIzniEkle([3]);
    final oturum = await BireyselListeService.hazirla(ekSiniflariDahilEt: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calisma_modu', 'okul');
    await expectLater(BireyselListeService.ogrenciler(oturum, null),
      throwsA(isA<StateError>()));
    await prefs.setString('calisma_modu', 'bireysel');
    await db.update('OgretmenProfil', {'Aktif': 1},
      where: 'OgretmenProfilId = ?', whereArgs: [2]);
    await expectLater(BireyselListeService.ogrenciler(oturum, null),
      throwsA(isA<StateError>()));
    await db.update('OgretmenProfil', {'Aktif': 0},
      where: 'OgretmenProfilId = ?', whereArgs: [2]);
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'},
      where: 'OgretmenProfilId = ?', whereArgs: [1]);
    await expectLater(BireyselListeService.ogrenciler(oturum, 1),
      throwsA(isA<StateError>()));
  });

  testWidgets('Dar ekranda tüm sınıflar açılır; sınıf ve numara görünür, filtre değişir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await ekraniAc(tester, buyukYazi: true);
    expect(tester.widget<DropdownButton<int>>(sinifSecimi()).value, 0);
    expect(find.text('3 öğrenci'), findsOneWidget);
    expect(find.text('Ada Dokuz'), findsOneWidget);
    expect(find.text('Sınıf: 9-A • No: 2'), findsOneWidget);
    final listeKaydirma = find.descendant(
      of: find.byType(ListView), matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text('Bora On'), 150,
      scrollable: listeKaydirma);
    await tester.ensureVisible(find.text('Bora On'));
    await tester.pumpAndSettle();
    expect(find.text('Bora On'), findsOneWidget);
    expect(find.text('Sınıf: 10-B • No: 1'), findsOneWidget);
    await tester.drag(listeKaydirma, const Offset(0, 600));
    await tester.pumpAndSettle();
    await sinifSec(tester, '10-B');
    expect(find.text('1 öğrenci'), findsOneWidget);
    expect(find.text('Ada Dokuz'), findsNothing);
    expect(find.text('Bora On'), findsOneWidget);
    await sinifSec(tester, 'Tüm Sınıflar');
    expect(find.text('3 öğrenci'), findsOneWidget);
    expect(find.text('Ada Dokuz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ders seçimi sınıf değişince geçerli dersi korur ve tek dersi seçer',
      (tester) async {
    await db.insert('Ders', {
      'DersId': 2, 'DersAdi': 'Fizik', 'OlusturmaTarihi': 'test',
    });
    await programEkle(1, dersId: 2);
    await ekSinifIzniEkle([3]);
    await tester.binding.setSurfaceSize(const Size(320, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await ekraniAc(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tasarım'));
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).value, '');

    await sinifSec(tester, '9-A');
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).value, '');
    await dersSec(tester, 'Fizik');
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).value, 'Fizik');
    await sinifSec(tester, '10-B');
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).value, 'Matematik');
    await sinifSec(tester, '9-A');
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).value, 'Matematik');
    await sinifSec(tester, '9-C');
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).value, '');
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).items!
        .map((item) => item.value), ['', '__elle__']);

    await dersSec(tester, 'Elle yaz');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tasarım'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(metinAlani('Ders'));
    await tester.enterText(metinAlani('Ders'), 'Serbest ders adı');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<TextField>(metinAlani('Ders')).controller!.text,
        'Serbest ders adı');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Okul ve müdür otomatik dolar; ders ve müdür dikey PDF çıktısına geçer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final oturum = await BireyselListeService.hazirla();
    await BireyselListeService.mudurKaydet(oturum, 'Ayşe Yönetici');
    await ekraniAc(tester);
    await sinifSec(tester, '9-A');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tasarım'));
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(dersSecimi()).value, 'Matematik');
    expect(tester.widget<TextField>(metinAlani('Okul adı')).controller!.text,
        'Test Okulu');
    expect(tester.widget<TextField>(metinAlani('Okul müdürü')).controller!.text,
        'Ayşe Yönetici');
    expect(metinAlani('Ders'), findsNothing);

    await tester.ensureVisible(metinAlani('Okul müdürü'));
    await tester.enterText(metinAlani('Okul müdürü'), 'Mehmet Yönetici');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect((await BireyselListeService.hazirla()).mudur, 'Mehmet Yönetici');
    await isaretDegistir(tester, 'ortak-bilgi-goster-6');
    final mudurKonumu = find.byKey(const ValueKey('ortak-bilgi-konum-6'));
    await tasarimdaGorunurYap(tester, mudurKonumu);
    await tester.tap(mudurKonumu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt sağ').last);
    await tester.pumpAndSettle();
    await tasarimdaGorunurYap(tester, metinAlani('Okul müdürü'));
    await tester.enterText(metinAlani('Okul müdürü'), 'Ara kayıt');
    await tester.enterText(metinAlani('Okul müdürü'), '');
    await tester.enterText(metinAlani('Okul müdürü'), 'Son Yönetici');

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ön izleme / Yazdır'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    expect(preview.initialPageFormat!.width, lessThan(preview.initialPageFormat!.height));
    final bytes = await tester.runAsync(() async => await preview.build(PdfPageFormat.a4));
    final metin = _pdfMetni(bytes!);
    expect(metin, contains('Test Okulu'));
    expect(metin, contains('9-A'));
    expect(metin, contains('Matematik'));
    expect(metin, contains('Son Yönetici'));
    expect(metin, contains('Okul Müdürü'));
    expect((await BireyselListeService.hazirla()).mudur, 'Son Yönetici');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Göster gizle değerleri korur; gizli alan ve sütun PDFye eklenmez',
      (tester) async {
    final oturum = await BireyselListeService.hazirla();
    await BireyselListeService.mudurKaydet(oturum, 'Ayşe Yönetici');
    await BireyselListeService.sablonKaydet(oturum, RaporSablonu(
      ad: 'Görünürlük testi',
      mudurKonumu: 'altSag',
      basliklar: [
        RaporBaslik(kaynak: 'okul'),
        RaporBaslik(kaynak: 'ogretmen', metin: 'Öğretmen'),
      ],
      sutunlar: [
        RaporSutun(kaynak: 'okulNo', baslik: 'Okul No'),
        RaporSutun(kaynak: 'adSoyad', baslik: 'Ad Soyad'),
        RaporSutun(kaynak: 'sinif', baslik: 'Sınıf alanı'),
      ],
    ));
    await ekraniAc(tester);
    await kayitliTasarimiAc(tester, 'Görünürlük testi');
    await isaretDegistir(tester, 'ortak-bilgi-goster-0');
    await tasarimdaGorunurYap(tester, metinAlani('Okul adı'));
    expect(tester.widget<TextField>(metinAlani('Okul adı')).controller!.text,
        'Test Okulu');
    await isaretDegistir(tester, 'ortak-bilgi-goster-0');
    expect(tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('ortak-bilgi-goster-0'))).value, isTrue);
    await isaretDegistir(tester, 'ortak-bilgi-goster-0');
    await isaretDegistir(tester, 'ortak-bilgi-goster-2');
    await tasarimdaGorunurYap(tester, metinAlani('Okul müdürü'));
    expect(tester.widget<TextField>(metinAlani('Okul müdürü')).controller!.text,
        'Ayşe Yönetici');
    await isaretDegistir(tester, 'ortak-sutun-goster-0');
    await isaretDegistir(tester, 'ortak-sutun-goster-2');
    await isaretDegistir(tester, 'ortak-sutun-goster-1');
    expect(tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('ortak-sutun-goster-1'))).value, isTrue);
    expect(find.text('En az bir görünür sütun seçin.'), findsOneWidget);
    final kayit = await tasarimiKaydet(tester, oturum, 'Gizli alanlar');
    expect(kayit.basliklar.first.goster, isFalse);
    expect(kayit.mudurGoster, isFalse);
    expect(kayit.sutunlar.map((s) => s.kaynak), ['okulNo', 'adSoyad', 'sinif']);
    expect(kayit.sutunlar.map((s) => s.goster), [false, true, false]);

    final metin = await onIzlemeMetni(tester);
    expect(metin, contains('Ada Dokuz'));
    expect(metin, contains('Öğretmen 1'));
    expect(metin, isNot(contains('Test Okulu')));
    expect(metin, isNot(contains('Ayşe Yönetici')));
    expect(metin, isNot(contains('Okul No')));
    expect(metin, isNot(contains('Sınıf alanı')));
    expect(metin, isNot(contains('9-A')));
    expect(metin, isNot(contains('10-B')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Başlık ve müdür sürüklenir; sütun sırası kayda ve PDFye geçer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final oturum = await BireyselListeService.hazirla();
    await BireyselListeService.mudurKaydet(oturum, 'Ayşe Yönetici');
    await BireyselListeService.sablonKaydet(oturum, RaporSablonu(
      ad: 'Yerleşim testi',
      mudurKonumu: 'altSol',
      basliklar: [RaporBaslik(kaynak: 'okul'), RaporBaslik(kaynak: 'ogretmen')],
      sutunlar: [
        RaporSutun(kaynak: 'okulNo', baslik: 'Okul No'),
        RaporSutun(kaynak: 'adSoyad', baslik: 'Ad Soyad'),
        RaporSutun(kaynak: 'sinif', baslik: 'Sınıf'),
      ],
    ));
    await ekraniAc(tester);
    await kayitliTasarimiAc(tester, 'Yerleşim testi');
    final panel = find.byKey(const ValueKey('ortak-yerlesim-paneli'));
    await tasarimdaGorunurYap(tester, panel);
    await tester.tap(find.descendant(of: panel,
        matching: find.text('Sürükle bırak yerleşimi')));
    await tester.pumpAndSettle();
    final altSag = find.byKey(const ValueKey('ortak-bolge-altSag'));
    final okul = find.byKey(const ValueKey('ortak-bilgi-surukle-0'));
    await uzunBasipBirak(tester, okul, altSag);
    expect(find.descendant(of: altSag, matching: okul), findsOneWidget);
    final mudur = find.byKey(const ValueKey('ortak-bilgi-surukle-2'));
    await uzunBasipBirak(tester, mudur, altSag);
    expect(find.descendant(of: altSag, matching: mudur), findsOneWidget);
    final panelBaslik = find.descendant(of: panel,
        matching: find.text('Sürükle bırak yerleşimi'));
    await tasarimdaGorunurYap(tester, panelBaslik);
    await tester.tap(panelBaslik);
    await tester.pumpAndSettle();

    final ilk = find.byKey(const ValueKey('ortak-sutun-sirala-0'));
    final ikinci = find.byKey(const ValueKey('ortak-sutun-sirala-1'));
    await tasarimdaGorunurYap(tester,
        find.byKey(const ValueKey('ortak-sutun-sirasi')));
    expect(ilk.hitTestable(), findsOneWidget);
    expect(ikinci.hitTestable(), findsOneWidget);
    final satirBoyu = tester.getSize(find.byKey(const ValueKey('ortak-sutun-goster-0'))).height;
    // Parmağın gerçek hareketi gibi ara konumlardan geçerek boşluğu taşı.
    await tester.timedDragFrom(tester.getCenter(ilk), Offset(0, satirBoyu),
        const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final kayit = await tasarimiKaydet(tester, oturum, 'Taşınmış alanlar');
    expect(kayit.basliklar.first.konum, 'altSag');
    expect(kayit.mudurKonumu, 'altSag');
    expect(kayit.sutunlar.map((s) => s.kaynak), ['adSoyad', 'okulNo', 'sinif']);
    final metin = await onIzlemeMetni(tester);
    expect(metin.indexOf('Ad Soyad'), lessThan(metin.indexOf('Okul No')));
    expect(metin, contains('Test Okulu'));
    expect(metin, contains('Ayşe Yönetici'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dar ve büyük yazılı tasarımda altı bölge ile görünürlük kontrolleri açılır',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await ekraniAc(tester, buyukYazi: true);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tasarım'));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('ortak-yerlesim-paneli'));
    await tasarimdaGorunurYap(tester, panel);
    await tester.tap(find.descendant(of: panel,
        matching: find.text('Sürükle bırak yerleşimi')));
    await tester.pumpAndSettle();
    for (final konum in RaporBaslik.konumlar.keys) {
      expect(find.byKey(ValueKey('ortak-bolge-$konum')), findsOneWidget);
    }
    await isaretDegistir(tester, 'ortak-bilgi-goster-0');
    await isaretDegistir(tester, 'ortak-bilgi-goster-0');
    await isaretDegistir(tester, 'ortak-sutun-goster-0');
    await isaretDegistir(tester, 'ortak-sutun-goster-0');
    await tasarimdaGorunurYap(tester,
        find.byKey(const ValueKey('ortak-bilgi-goster-0')));
    expect(tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('ortak-bilgi-goster-0'))).value, isTrue);
    await tasarimdaGorunurYap(tester,
        find.byKey(const ValueKey('ortak-sutun-goster-0')));
    expect(tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('ortak-sutun-goster-0'))).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Import dönüşü tüm sınıflar seçimini korur ve yeni öğrenciyi yükler',
      (tester) async {
    await ekraniAc(tester);
    await tester.tap(find.text('Öğrenci Import'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminImportScreen), findsOneWidget);
    await ogrenciEkle(30, '3', 'Cem', 2, soyad: 'Yeni');
    await ekSinifIzniEkle([3]);
    Navigator.of(tester.element(find.byType(AdminImportScreen))).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<int>>(sinifSecimi()).value, 0);
    expect(find.text('5 öğrenci'), findsOneWidget);
    expect(find.text('Ada Dokuz'), findsOneWidget);
    final listeKaydirma = find.descendant(
      of: find.byType(ListView), matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text('Cem Yeni'), 150,
      scrollable: listeKaydirma);
    await tester.ensureVisible(find.text('Cem Yeni'));
    await tester.pumpAndSettle();
    expect(find.text('Cem Yeni'), findsOneWidget);
    expect(find.text('Sınıf: 10-B • No: 3'), findsOneWidget);
    expect(tester.widget<DropdownButton<int>>(sinifSecimi()).items!
        .any((item) => item.value == 3), isTrue);
    await sinifSec(tester, '9-C');
    expect(find.text('1 öğrenci'), findsOneWidget);
    expect(find.text('Kapsam dışı 3 Öğrenci'), findsOneWidget);
    expect(find.text('Sınıf: 9-C • No: 113'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Öğrenci listesi tamamen boşsa fotoğraf için önce öğrenci importu istenir',
      (tester) async {
    await db.update('Ogrenci', {'Aktif': 0});
    await ekraniAc(tester);
    await tester.tap(find.text('Fotoğraf Import'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminImportScreen), findsNothing);
    expect(find.text('Fotoğraf eklemek için önce Öğrenci Import ile öğrencileri yükleyin.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seçili sınıf boş olsa da başka sınıfta öğrenci varsa fotoğraf importu açılır',
      (tester) async {
    await sinifEkle(12, '9-D', 9);
    await programEkle(12);
    await ekraniAc(tester);
    await sinifSec(tester, '9-D');
    expect(find.text('0 öğrenci'), findsOneWidget);
    await tester.tap(find.text('Fotoğraf Import'));
    await tester.pumpAndSettle();
    final import = tester.widget<AdminImportScreen>(find.byType(AdminImportScreen));
    expect(import.bireyselFoto, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Birleşik PDF sınıfları yazar; sınıf sütunu kayıtlı şablonu değiştirmez',
      (tester) async {
    await ekSinifIzniEkle([3]);
    final oturum = await BireyselListeService.hazirla();
    final sablon = RaporSablonu(
      ad: 'Özel liste',
      basliklar: [RaporBaslik(kaynak: 'sinif', metin: 'Sınıf')],
      sutunlar: [
        RaporSutun(kaynak: 'okulNo', baslik: 'Okul No'),
        RaporSutun(kaynak: 'adSoyad', baslik: 'Ad Soyad', genislik: 5),
      ],
    );
    final sinifliKopya = sablon.kopya()
      ..sutunlar.add(RaporSutun(kaynak: 'sinif', baslik: 'Sınıf'));
    expect(() => sinifliKopya.dogrula(), returnsNormally);
    expect(RaporSablonu.fromJson(sinifliKopya.toJson()).sutunlar.last.kaynak, 'sinif');
    await BireyselListeService.sablonKaydet(oturum, sablon);
    final once = (await db.query('UygulamaAyarlari',
      where: 'Anahtar LIKE ?', whereArgs: ['liste_sablonu:%'])).single['Deger'];
    await ekraniAc(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tasarım'));
    await tester.pumpAndSettle();
    final sablonSecimi = find.byWidgetPredicate(
      (w) => w is DropdownButton<String> &&
          w.items!.any((item) => item.value == 'k0'),
    );
    await tester.tap(sablonSecimi);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydım: Özel liste').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ön izleme / Yazdır'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(find.byType(PdfPreview), findsOneWidget);
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    final bytes = await tester.runAsync(() async => await preview.build(PdfPageFormat.a4));
    final pdfBytes = bytes!;
    expect(latin1.decode(pdfBytes.take(5).toList()), '%PDF-');
    final metin = _pdfMetni(pdfBytes);
    expect(metin, contains('Tüm Sınıflar'));
    expect(metin, contains('9-A'));
    expect(metin, contains('10-B'));
    expect(metin, contains('9-C'));
    expect(metin, contains('Kapsam dışı 3 Öğrenci'));
    expect(metin, contains('Ad Soyad'));
    expect((await db.query('UygulamaAyarlari',
      where: 'Anahtar LIKE ?', whereArgs: ['liste_sablonu:%'])).single['Deger'], once);
    expect((await BireyselListeService.sablonlar(oturum)).single.sutunlar
        .any((s) => s.kaynak == 'sinif'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
