import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/raporlama/rapor_modeli.dart';
import 'package:elpi_okul_yonetim/raporlama/rapor_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pdf {
  _Pdf(Uint8List bytes) : ham = latin1.decode(bytes) {
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
      final yazi = akis(nesne);
      if (yazi == null || !yazi.contains('TJ')) continue;
      fontBoyutlari.addAll(RegExp(r'/\w+\s+([-+\d.]+)\s+Tf').allMatches(yazi)
        .map((e) => double.parse(e.group(1)!)));
      Map<int, String>? font;
      for (final e in RegExp(r'/(\w+)\s+[-+\d.]+\s+Tf|<([0-9A-Fa-f]+)>').allMatches(yazi)) {
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
    metin = sonuc.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  final String ham;
  late final String metin;
  final fontBoyutlari = <double>[];
  int get sayfalar => RegExp(r'/Type\s*/Page\b').allMatches(ham).length;
}

void main() {
  late ByteData normal;
  late ByteData kalin;
  setUpAll(() async {
    // Font dosyalarını test sağlar; ortak motor asset yolu veya Flutter bilmez.
    normal = ByteData.sublistView(await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes());
    kalin = ByteData.sublistView(await File('assets/fonts/NotoSans-Bold.ttf').readAsBytes());
  });

  const tanim = RaporTanimi(id: 'depo_sayimi', listeEtiketi: 'Envanter',
    bilgiAlanlari: [
      RaporAlanTanimi(id: 'baslik', etiket: 'Başlık'),
      RaporAlanTanimi(id: 'depo', etiket: 'Depo'),
      RaporAlanTanimi(id: 'donem', etiket: 'Dönem'),
      RaporAlanTanimi(id: 'sorumlu', etiket: 'Sorumlu'),
      RaporAlanTanimi(id: 'aciklama', etiket: 'Açıklama'),
      RaporAlanTanimi(id: 'gizli', etiket: 'Gizli Bilgi'),
      RaporAlanTanimi(id: 'serbest', etiket: 'Serbest Metin', serbestMetin: true),
    ],
    sutunAlanlari: [
      RaporAlanTanimi(id: 'sira', etiket: 'Sıra', tur: RaporHucreTuru.sira),
      RaporAlanTanimi(id: 'urun', etiket: 'Ürün'),
      RaporAlanTanimi(id: 'miktar', etiket: 'Miktar'),
      RaporAlanTanimi(id: 'not', etiket: 'Not', tur: RaporHucreTuru.bos),
      RaporAlanTanimi(id: 'gorsel', etiket: 'Görsel', tur: RaporHucreTuru.resim),
    ]);
  const bilgiler = <String, Object?>{
    'baslik': 'Envanter Sayım Çizelgesi', 'depo': 'Merkez Depo',
    'donem': 'Ekim 2026', 'sorumlu': 'Aylin Çelik',
    'aciklama': 'Kontrol tamamlandı', 'gizli': 'Yazdırılmaması gereken bilgi',
  };
  RaporTasarimi tasarim() => RaporTasarimi(ad: 'Depo sayımı', bilgiler: [
    RaporBilgiAlani(alanId: 'baslik'),
    RaporBilgiAlani(alanId: 'depo'),
    RaporBilgiAlani(alanId: 'donem', onEtiket: 'Dönem'),
    RaporBilgiAlani(alanId: 'sorumlu', altMetin: 'Depo Sorumlusu', konum: 'altSag'),
  ], sutunlar: [
    RaporTabloSutunu(alanId: 'sira', baslik: 'Sıra', genislik: 1),
    RaporTabloSutunu(alanId: 'urun', baslik: 'Ürün', genislik: 5),
    RaporTabloSutunu(alanId: 'miktar', baslik: 'Miktar'),
    RaporTabloSutunu(alanId: 'not', baslik: 'Kontrol Notu', genislik: 4),
  ]);
  List<Map<String, Object?>> satirlar(int sayi) => List.generate(sayi, (i) => {
    'urun': 'Ürün ${(i + 1).toString().padLeft(4, '0')}', 'miktar': i + 22,
    'not': 'Boş hücre bu değeri kullanmamalı',
  });
  Future<_Pdf> olustur(String dosya, RaporTasarimi sablon, int sayi, {
    Map<String, Object?> ustBilgiler = bilgiler,
    List<Map<String, Object?>>? kayitlar,
  }) async {
    final bytes = await RaporPdfService.olustur(tanim: tanim, tasarim: sablon,
      veri: RaporVerisi(bilgiler: ustBilgiler, satirlar: kayitlar ?? satirlar(sayi)),
      normalFont: normal, kalinFont: kalin);
    final qaDizini = Platform.environment['RAPOR_QA_DIR'] ?? const String.fromEnvironment('RAPOR_QA_DIR');
    if (qaDizini.isNotEmpty) {
      await Directory(qaDizini).create(recursive: true);
      await File('$qaDizini/$dosya.pdf').writeAsBytes(bytes);
    }
    return _Pdf(bytes);
  }
  void tumKayitlarVar(_Pdf pdf, int sayi) {
    for (var i = 1; i <= sayi; i++) {
      expect(pdf.metin, contains('Ürün ${i.toString().padLeft(4, '0')}'));
    }
  }

  test('Okul dışı alanlar enjekte edilen fontlarla okunabilir tek sayfaya sığar', () async {
    final pdf = await olustur('ortak_envanter_40', tasarim(), 40);
    expect(pdf.sayfalar, 1);
    expect(pdf.metin, contains('Envanter Sayım Çizelgesi'));
    expect(pdf.metin, contains('Dönem: Ekim 2026'));
    expect(pdf.metin, contains('Aylin Çelik Depo Sorumlusu'));
    expect(pdf.metin, isNot(contains('Boş hücre bu değeri kullanmamalı')));
    expect(pdf.fontBoyutlari, everyElement(greaterThanOrEqualTo(8)));
    expect(pdf.metin, contains('1 / 1'));
    tumKayitlarVar(pdf, 40);
  });

  test('Her bilgi alanı alt bölgede diğer alanlarla aynı sırayı izler', () async {
    final sablon = tasarim();
    sablon.bilgiler.add(RaporBilgiAlani(alanId: 'aciklama', konum: 'altSag'));
    final pdf = await olustur('ortak_alt_bolge_sirasi', sablon, 24);
    expect(pdf.metin, contains('Aylin Çelik Depo Sorumlusu Kontrol tamamlandı'));
    final sorumlu = sablon.bilgiler.removeAt(3);
    sablon.bilgiler.add(sorumlu);
    final ters = await olustur('ortak_alt_bolge_ters_sira', sablon, 24);
    expect(ters.metin, contains('Kontrol tamamlandı Aylin Çelik Depo Sorumlusu'));
  });

  test('Serbest metin, veri kaynağında bulunmadan diğer alanlarla aynı yolu izler', () async {
    final sablon = tasarim();
    sablon.bilgiler.add(RaporBilgiAlani(alanId: 'serbest',
      sabitMetin: 'Sayım sonrası arşivlenecek', altMetin: 'İşletme içi belge', konum: 'altSol'));
    final pdf = await olustur('ortak_serbest_metin', sablon, 24);
    expect(pdf.metin, contains('Sayım sonrası arşivlenecek İşletme içi belge'));
    tumKayitlarVar(pdf, 24);
  });

  test('Boş ana değer sabit alt metni ve gizli bilgileri de gizler', () async {
    final sablon = tasarim();
    sablon.bilgiler.add(RaporBilgiAlani(alanId: 'gizli', altMetin: 'Gizli Alt Metin', goster: false));
    final pdf = await olustur('ortak_bos_bilgi', sablon, 40,
      ustBilgiler: {...bilgiler, 'sorumlu': '   '});
    expect(pdf.metin, isNot(contains('Depo Sorumlusu')));
    expect(pdf.metin, isNot(contains('Gizli Alt Metin')));
    expect(pdf.metin, isNot(contains('Yazdırılmaması gereken bilgi')));
    tumKayitlarVar(pdf, 40);
  });

  test('Sütun sırası ve gizlenen resim alanının ölçü hesabı korunur', () async {
    final sablon = tasarim();
    final onceki = sablon.sutunlar;
    sablon.sutunlar = [onceki[2], onceki[1], onceki[0], onceki[3],
      RaporTabloSutunu(alanId: 'gorsel', baslik: 'Gizli Görsel', genislik: 8, goster: false)];
    final kayitlar = satirlar(40);
    for (final kayit in kayitlar) { kayit['gorsel'] = Uint8List.fromList([1, 2, 3]); }
    final pdf = await olustur('ortak_sutun_sirasi', sablon, 40, kayitlar: kayitlar);
    expect(pdf.sayfalar, 1);
    expect(pdf.metin, contains('Miktar Ürün Sıra Kontrol Notu'));
    expect(pdf.metin, contains('22 Ürün 0001 1'));
    expect(pdf.metin, isNot(contains('Gizli Görsel')));
    expect(RegExp(r'/Subtype\s*/Image\b').hasMatch(pdf.ham), isFalse);
    tumKayitlarVar(pdf, 40);
  });

  test('Sığdırma kapalıyken ölçüler korunur; büyük veri kayıpsız sayfalanır', () async {
    final normal = await olustur('ortak_normal_40', tasarim()..tekSayfayaSigdir = false, 40);
    expect(normal.sayfalar, greaterThan(1));
    final buyuk = await olustur('ortak_buyuk_1000', tasarim(), 1000);
    expect(buyuk.sayfalar, greaterThan(1));
    expect(RegExp('Kontrol Notu').allMatches(buyuk.metin).length, buyuk.sayfalar);
    expect(RegExp('Depo Sorumlusu').allMatches(buyuk.metin).length, buyuk.sayfalar);
    tumKayitlarVar(buyuk, 1000);
  });

  test('Genel resim türü bütün kayıtları ve okunabilir resim yüksekliğini korur', () async {
    final sablon = tasarim()..satirYuksekligi = 16;
    sablon.sutunlar.insert(1, RaporTabloSutunu(alanId: 'gorsel', baslik: 'Görsel'));
    final kayitlar = satirlar(24);
    kayitlar.first['gorsel'] = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    final pdf = await olustur('ortak_resimli_24', sablon, 24, kayitlar: kayitlar);
    expect(pdf.sayfalar, greaterThan(1));
    expect(RegExp(r'/Subtype\s*/Image\b').hasMatch(pdf.ham), isTrue);
    tumKayitlarVar(pdf, 24);
  });

  test('Boş kayıt ve okunamayacak kadar dar sütun güvenli hata verir', () async {
    expect(olustur('bos', tasarim(), 0), throwsStateError);
    final dar = tasarim();
    dar.sutunlar.addAll(List.generate(5, (i) =>
      RaporTabloSutunu(alanId: 'not', baslik: 'Ek $i', genislik: 8)));
    expect(olustur('dar', dar, 1), throwsStateError);
  });
}
