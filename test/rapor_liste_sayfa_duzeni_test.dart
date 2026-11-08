import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/models/rapor_sablonu.dart';
import 'package:elpi_okul_yonetim/services/rapor_service.dart';
import 'package:flutter_test/flutter_test.dart';

// PDF içeriğini gömülü Unicode haritasıyla okur; native PDF eklentisi istemez.
class _PdfIcerigi {
  _PdfIcerigi(Uint8List bytes) : ham = latin1.decode(bytes) {
    final nesneler = <int, String>{
      for (final e in RegExp(r'(\d+)\s+0\s+obj\b([\s\S]*?)endobj').allMatches(ham))
        int.parse(e.group(1)!): e.group(2)!,
    };
    String? akis(String nesne) {
      final baslangic = RegExp(r'\bstream\r?\n').firstMatch(nesne);
      final uzunluk = RegExp(r'/Length\s+(\d+)').firstMatch(nesne);
      if (baslangic == null || uzunluk == null) return null;
      final veri = latin1.encode(nesne.substring(baslangic.end,
        baslangic.end + int.parse(uzunluk.group(1)!)));
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
        for (final e in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(karakterler))
          int.parse(e.group(1)!, radix: 16): String.fromCharCode(int.parse(e.group(2)!, radix: 16)),
      };
    }
    final sonuc = StringBuffer();
    for (final nesne in nesneler.values) {
      final metin = akis(nesne);
      if (metin == null || !metin.contains('TJ')) continue;
      fontBoyutlari.addAll(RegExp(r'/\w+\s+([-+\d.]+)\s+Tf').allMatches(metin)
        .map((e) => double.parse(e.group(1)!)));
      Map<int, String>? font;
      for (final e in RegExp(r'/(\w+)\s+[-+\d.]+\s+Tf|<([0-9A-Fa-f]+)>').allMatches(metin)) {
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
      // Bölge widget'ları kendi yerel koordinatlarında çizilir. PDF'nin q/Q
      // grafik yığını ve cm dönüşümleri sayfa koordinatını verir.
      var matris = <double>[1, 0, 0, 1, 0, 0];
      final yigin = <List<double>>[];
      final islemler = RegExp(r'([-+\d.]+)\s+([-+\d.]+)\s+([-+\d.]+)\s+'
        r'([-+\d.]+)\s+([-+\d.]+)\s+([-+\d.]+)\s+cm\b|\b(q|Q)\b|\bBT\b([\s\S]*?)\bET\b');
      for (final blok in islemler.allMatches(metin)) {
        if (blok.group(1) != null) {
          final m = [for (var i = 1; i <= 6; i++) double.parse(blok.group(i)!)];
          final onceki = matris;
          matris = [
            onceki[0] * m[0] + onceki[2] * m[1], onceki[1] * m[0] + onceki[3] * m[1],
            onceki[0] * m[2] + onceki[2] * m[3], onceki[1] * m[2] + onceki[3] * m[3],
            onceki[0] * m[4] + onceki[2] * m[5] + onceki[4],
            onceki[1] * m[4] + onceki[3] * m[5] + onceki[5],
          ];
          continue;
        }
        if (blok.group(7) == 'q') { yigin.add(List.of(matris)); continue; }
        if (blok.group(7) == 'Q') { matris = yigin.removeLast(); continue; }
        final icerik = blok.group(8)!;
        final fontAdi = RegExp(r'/(\w+)\s+[-+\d.]+\s+Tf').firstMatch(icerik);
        final yer = RegExp(r'([-+\d.]+)\s+([-+\d.]+)\s+Td').firstMatch(icerik);
        if (fontAdi == null || yer == null) continue;
        final harita = fontlar[fontAdi.group(1)!];
        if (harita == null) continue;
        final yazi = StringBuffer();
        for (final hex in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(icerik)) {
          final kodlar = hex.group(1)!;
          for (var i = 0; i + 4 <= kodlar.length; i += 4) {
            yazi.write(harita[int.parse(kodlar.substring(i, i + 4), radix: 16)] ?? '');
          }
        }
        final x = double.parse(yer.group(1)!);
        final y = double.parse(yer.group(2)!);
        konumlar.add((metin: yazi.toString(), x: matris[0] * x + matris[2] * y + matris[4],
          y: matris[1] * x + matris[3] * y + matris[5]));
      }
    }
    metin = sonuc.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final String ham;
  late final String metin;
  final fontBoyutlari = <double>[];
  final konumlar = <({String metin, double x, double y})>[];
  int get sayfaSayisi => RegExp(r'/Type\s*/Page\b').allMatches(ham).length;
  bool get dikey {
    final kutu = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(ham)!;
    return double.parse(kutu.group(1)!) < double.parse(kutu.group(2)!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bilgiler = {
    'okul': 'Derince Ticaret Mesleki ve Teknik Anadolu Lisesi',
    'sinif': '9-C', 'ders': 'Matematik', 'ogretmen': 'Nurkan Sırma',
    'tarih': '13.10.2026', 'mudur': 'Mehmet Yılmaz',
  };
  List<Map<String, Object?>> ogrenciler(int sayi) => List.generate(sayi, (i) => {
    'OkulNo': '${3000 + i}', 'Ad': 'Öğrenci ${(i + 1).toString().padLeft(4, '0')}',
    'Soyad': 'Deneme', 'SinifKodu': '9-C',
  });
  RaporSablonu degerlendirme() => RaporSablonu.hazirSablonlar().last
    ..mudurKonumu = 'altSag';
  Future<_PdfIcerigi> olustur(String ad, RaporSablonu sablon, int sayi, {
    Map<String, String> raporBilgileri = bilgiler,
    List<Map<String, Object?>>? veri,
  }) async {
    final bytes = await RaporService.dinamikSinifListesi(
      sablon: sablon, ogrenciler: veri ?? ogrenciler(sayi), bilgiler: raporBilgileri);
    final qaDizini = Platform.environment['RAPOR_QA_DIR'] ?? const String.fromEnvironment('RAPOR_QA_DIR');
    if (qaDizini.isNotEmpty) {
      await Directory(qaDizini).create(recursive: true);
      await File('$qaDizini/$ad.pdf').writeAsBytes(bytes);
    }
    return _PdfIcerigi(bytes);
  }
  void tumOgrencilerVar(_PdfIcerigi pdf, int sayi) {
    for (var i = 1; i <= sayi; i++) {
      expect(pdf.metin, contains('Öğrenci ${i.toString().padLeft(4, '0')} Deneme'));
    }
  }

  test('Hazır şablonlar dikeydir, sınıftan sonra dersi gösterir', () {
    for (final sablon in RaporSablonu.hazirSablonlar()) {
      expect(sablon.yatay, isFalse);
      expect(sablon.tekSayfayaSigdir, isTrue);
      final kaynaklar = sablon.basliklar.map((b) => b.kaynak).toList();
      expect(kaynaklar[kaynaklar.indexOf('sinif') + 1], 'ders');
    }
  });

  test('Eski sürüm 1 JSON okunur, yeni seçenekler kopyalanır ve doğrulanır', () {
    final eski = degerlendirme().toJson()
      ..remove('tekSayfayaSigdir')
      ..remove('mudurKonumu')
      ..remove('mudurGoster');
    for (final baslik in eski['basliklar'] as List) {
      (baslik as Map).remove('konum');
    }
    for (final sutun in eski['sutunlar'] as List) {
      (sutun as Map).remove('goster');
    }
    final sablon = RaporSablonu.fromJson(eski);
    expect(sablon.tekSayfayaSigdir, isTrue);
    expect(sablon.mudurKonumu, 'yok');
    expect(sablon.mudurGoster, isTrue);
    expect(sablon.basliklar.every((b) => b.konum == 'ustOrta'), isTrue);
    expect(sablon.sutunlar.every((s) => s.goster), isTrue);
    sablon.tekSayfayaSigdir = false;
    sablon.mudurKonumu = 'ustSol';
    sablon.mudurGoster = false;
    sablon.basliklar.first.konum = 'altSag';
    sablon.basliklar.first.goster = false;
    sablon.sutunlar.first.goster = false;
    final kopya = sablon.kopya();
    expect(kopya.tekSayfayaSigdir, isFalse);
    expect(kopya.mudurKonumu, 'ustSol');
    expect(kopya.mudurGoster, isFalse);
    expect(kopya.basliklar.first.konum, 'altSag');
    expect(kopya.basliklar.first.goster, isFalse);
    expect(kopya.sutunlar.first.goster, isFalse);
    kopya.mudurKonumu = 'gecersiz';
    expect(kopya.dogrula, throwsFormatException);
  });

  for (final sayi in [24, 40]) {
    test('$sayi öğrenci, ders ve müdür okunabilir tek dikey sayfaya sığar', () async {
      final pdf = await olustur('degerlendirme_$sayi', degerlendirme(), sayi);
      expect(pdf.sayfaSayisi, 1);
      expect(pdf.dikey, isTrue);
      expect(pdf.metin, contains(bilgiler['okul']!));
      expect(pdf.metin, contains('Sınıf: 9-C'));
      expect(pdf.metin, contains('Ders: Matematik'));
      expect(pdf.metin, contains('Mehmet Yılmaz Okul Müdürü'));
      expect(pdf.metin, contains('1 / 1'));
      expect(pdf.fontBoyutlari, everyElement(greaterThanOrEqualTo(8)));
      tumOgrencilerVar(pdf, sayi);
    });
  }

  test('Sığdırma kapatıldığında normal ölçülerle birden fazla sayfa üretir', () async {
    final sablon = degerlendirme()..tekSayfayaSigdir = false;
    final pdf = await olustur('normal_40', sablon, 40);
    expect(pdf.sayfaSayisi, greaterThan(1));
    tumOgrencilerVar(pdf, 40);
  });

  test('Çok büyük liste kayıpsız sayfalanır, başlıklar ve sayfa numarası tekrarlanır', () async {
    final pdf = await olustur('buyuk_liste_1000', degerlendirme(), 1000);
    expect(pdf.sayfaSayisi, greaterThan(1));
    expect(RegExp('Ad Soyad').allMatches(pdf.metin).length, pdf.sayfaSayisi);
    expect(RegExp('Okul Müdürü').allMatches(pdf.metin).length, pdf.sayfaSayisi);
    for (var i = 1; i <= pdf.sayfaSayisi; i++) {
      expect(pdf.metin, contains('$i / ${pdf.sayfaSayisi}'));
    }
    tumOgrencilerVar(pdf, 1000);
  });

  test('Müdürün altı konumu desteklenir, boş müdür bilgisi blok eklemez', () async {
    for (final konum in RaporSablonu.mudurKonumlari.keys.where((k) => k != 'yok')) {
      final sablon = degerlendirme()..mudurKonumu = konum;
      final pdf = await olustur('mudur_$konum', sablon, 40);
      expect(pdf.sayfaSayisi, 1);
      expect(pdf.metin, contains('Mehmet Yılmaz Okul Müdürü'));
    }
    final bos = await olustur('mudur_bos', degerlendirme(), 40,
      raporBilgileri: {...bilgiler, 'mudur': '   '});
    expect(bos.metin, isNot(contains('Okul Müdürü')));
    final gizli = await olustur('mudur_gizli', degerlendirme()..mudurKonumu = 'yok', 40);
    expect(gizli.metin, isNot(contains('Mehmet Yılmaz')));
    final kapaliSablon = degerlendirme()..mudurGoster = false;
    final kapali = await olustur('mudur_kapali', kapaliSablon, 40);
    expect(kapali.metin, isNot(contains('Mehmet Yılmaz')));
    expect(kapaliSablon.mudurKonumu, 'altSag');
  });

  test('Fotoğraf satırları 40 altına sıkışmaz, bütün öğrenciler korunur', () async {
    final sablon = RaporSablonu.hazirSablonlar()[1]
      ..satirYuksekligi = 16
      ..mudurKonumu = 'altOrta';
    final veri = ogrenciler(24);
    veri.first['FotoVerisi'] = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    final pdf = await olustur('fotografli_24', sablon, 24, veri: veri);
    expect(pdf.sayfaSayisi, greaterThan(1));
    expect(RegExp(r'/Subtype\s*/Image\b').hasMatch(pdf.ham), isTrue);
    tumOgrencilerVar(pdf, 24);
  });

  test('Başlangıç yazısı 8 altındaysa sığdırma yazıyı daha da küçültmez', () async {
    final pdf = await olustur('kucuk_yazi_40', degerlendirme()..yaziBoyutu = 7, 40);
    expect(pdf.fontBoyutlari, everyElement(greaterThanOrEqualTo(7)));
    tumOgrencilerVar(pdf, 40);
  });

  test('Dar sütun koruması devam eder', () async {
    final sablon = degerlendirme();
    sablon.sutunlar.addAll(List.generate(5, (i) => RaporSutun(
      kaynak: 'bos', baslik: 'Ek $i', genislik: 8)));
    expect(RaporService.dinamikSinifListesi(sablon: sablon,
      ogrenciler: ogrenciler(1), bilgiler: bilgiler), throwsStateError);
  });

  test('Gizli sütunlar PDF verisine, genişliğe ve fotoğraf yüksekliğine girmez', () async {
    final sablon = degerlendirme();
    sablon.sutunlar.addAll([
      RaporSutun(kaynak: 'fotograf', baslik: 'Gizli Fotoğraf', goster: false),
      RaporSutun(kaynak: 'alan', baslik: 'Gizli Alan', genislik: 8, goster: false),
      for (var i = 0; i < 5; i++) RaporSutun(kaynak: 'bos', baslik: 'Gizli $i',
        genislik: 8, goster: false),
    ]);
    sablon.basliklar.add(RaporBaslik(metin: 'Gizli Başlık', goster: false, konum: 'altSol'));
    final veri = ogrenciler(40);
    for (final ogrenci in veri) {
      ogrenci['Alan'] = 'Yazdırılmamalı';
      ogrenci['FotoVerisi'] = Uint8List.fromList([1, 2, 3]);
    }
    final pdf = await olustur('gizli_alanlar_40', sablon, 40, veri: veri);
    expect(pdf.sayfaSayisi, 1);
    expect(pdf.metin, isNot(contains('Gizli')));
    expect(pdf.metin, isNot(contains('Yazdırılmamalı')));
    expect(RegExp(r'/Subtype\s*/Image\b').hasMatch(pdf.ham), isFalse);
    tumOgrencilerVar(pdf, 40);
    expect(sablon.sutunlar.length, 13);
    expect(sablon.gorunenSutunlar.length, 6);
  });

  test('Son görünür sütun gizlenemez; hatalı başlık bölgesi reddedilir', () {
    final sablon = degerlendirme();
    for (final sutun in sablon.sutunlar) { sutun.goster = false; }
    expect(sablon.dogrula, throwsFormatException);
    sablon.sutunlar.first.goster = true;
    sablon.basliklar.first.konum = 'bilinmeyen';
    expect(sablon.dogrula, throwsFormatException);
  });

  test('Sütun sırası PDF başlığı ve öğrenci hücrelerinde korunur', () async {
    final sablon = degerlendirme();
    final sutunlar = sablon.sutunlar;
    sablon.sutunlar = [sutunlar[2], sutunlar[1], sutunlar[0], ...sutunlar.skip(3)];
    final pdf = await olustur('sutun_sirasi', sablon, 24);
    expect(pdf.metin, contains('Ad Soyad Okul No Sıra Proje Not Açıklama'));
    expect(pdf.metin, contains('Öğrenci 0001 Deneme 3000 1'));
    tumOgrencilerVar(pdf, 24);
  });

  test('Altı başlık bölgesi doğru konuma yerleşir ve bölge içi sıra korunur', () async {
    final sablon = degerlendirme()
      ..basliklar = [
        for (final konum in RaporBaslik.konumlar.keys)
          RaporBaslik(metin: konum, konum: konum),
        RaporBaslik(metin: 'ikinciSol', konum: 'ustSol'),
      ];
    final pdf = await olustur('alti_bolge_40', sablon, 40);
    expect(pdf.sayfaSayisi, 1);
    for (final konum in RaporBaslik.konumlar.keys) {
      final yer = pdf.konumlar.firstWhere((y) => y.metin == konum);
      expect(yer.y, konum.startsWith('ust') ? greaterThan(600) : lessThan(200));
      if (konum.endsWith('Sol')) {
        expect(yer.x, lessThan(206));
      } else if (konum.endsWith('Sag')) {
        expect(yer.x, greaterThan(388));
      } else {
        expect(yer.x, inExclusiveRange(206, 388));
      }
    }
    final ilk = pdf.konumlar.firstWhere((y) => y.metin == 'ustSol');
    final ikinci = pdf.konumlar.firstWhere((y) => y.metin == 'ikinciSol');
    expect(ilk.y, greaterThan(ikinci.y));
    final altSag = pdf.konumlar.firstWhere((y) => y.metin == 'altSag');
    final mudur = pdf.konumlar.firstWhere((y) => y.metin.trim().startsWith('Mehmet'));
    expect(mudur.x, greaterThan(388));
    expect(mudur.y, lessThan(altSag.y));
    tumOgrencilerVar(pdf, 40);
  });

  test('Uzun bölge metinleri kesilmeden sarılır, alt bilgiler her sayfada korunur', () async {
    const uzun = 'Uzun okul başlığı farklı bölgelere yerleştirilirken bütün sözcükleri '
      'okunur kalmalı ve satır sonlarında hiçbir bilgi kesilmemeli.';
    final sablon = degerlendirme()
      ..basliklar = [
        RaporBaslik(metin: uzun, konum: 'ustSol'),
        RaporBaslik(metin: 'Orta Başlık', konum: 'ustOrta'),
        RaporBaslik(kaynak: 'ders', metin: 'Ders', konum: 'ustSag'),
        RaporBaslik(metin: 'Alt Bilgi', konum: 'altSol'),
        RaporBaslik(kaynak: 'tarih', metin: 'Tarih', konum: 'altOrta'),
      ];
    final pdf = await olustur('uzun_bolgeler_80', sablon, 80);
    expect(pdf.sayfaSayisi, greaterThan(1));
    expect(RegExp(RegExp.escape(uzun)).allMatches(pdf.metin).length, pdf.sayfaSayisi);
    expect(RegExp('Alt Bilgi').allMatches(pdf.metin).length, pdf.sayfaSayisi);
    expect(RegExp('Tarih: 13.10.2026').allMatches(pdf.metin).length, pdf.sayfaSayisi);
    tumOgrencilerVar(pdf, 80);
  });
}
