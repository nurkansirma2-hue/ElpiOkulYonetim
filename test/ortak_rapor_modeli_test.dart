import 'dart:convert';

import 'package:elpi_okul_yonetim/raporlama/rapor_modeli.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tanim = RaporTanimi(
    id: 'depo.envanter',
    listeEtiketi: 'Envanter',
    bilgiAlanlari: [
      RaporAlanTanimi(id: 'isletme', etiket: 'İşletme'),
      RaporAlanTanimi(id: 'depo', etiket: 'Depo'),
      RaporAlanTanimi(id: 'sorumlu', etiket: 'Sorumlu'),
      RaporAlanTanimi(id: 'baslik', etiket: 'Serbest başlık', serbestMetin: true),
    ],
    sutunAlanlari: [
      RaporAlanTanimi(id: 'sira', etiket: 'Sıra', tur: RaporHucreTuru.sira),
      RaporAlanTanimi(id: 'kod', etiket: 'Stok kodu'),
      RaporAlanTanimi(id: 'urun', etiket: 'Ürün'),
      RaporAlanTanimi(id: 'miktar', etiket: 'Miktar'),
      RaporAlanTanimi(id: 'resim', etiket: 'Görsel', tur: RaporHucreTuru.resim),
      RaporAlanTanimi(id: 'bos', etiket: 'Boş alan', tur: RaporHucreTuru.bos),
    ],
  );
  const veri = RaporVerisi(
    bilgiler: {'isletme': 'Örnek Ticaret', 'depo': 'Merkez', 'sorumlu': 'Derya Kaya'},
    satirlar: [
      {'kod': 'A-101', 'urun': 'Bağlantı kablosu', 'miktar': 12},
      {'kod': 'A-102', 'urun': 'Adaptör', 'miktar': 3},
    ],
  );

  RaporTasarimi tasarimOlustur() => RaporTasarimi(
    ad: 'Aylık envanter',
    bilgiler: [
      RaporBilgiAlani(alanId: 'isletme'),
      RaporBilgiAlani(alanId: 'depo', onEtiket: 'Depo', konum: 'ustSol'),
      RaporBilgiAlani(alanId: 'sorumlu', altMetin: 'Depo sorumlusu', konum: 'altSag'),
    ],
    sutunlar: [
      RaporTabloSutunu(alanId: 'sira', baslik: 'Sıra', genislik: 1),
      RaporTabloSutunu(alanId: 'kod', baslik: 'Stok kodu'),
      RaporTabloSutunu(alanId: 'urun', baslik: 'Ürün', genislik: 5),
      RaporTabloSutunu(alanId: 'miktar', baslik: 'Adet', goster: false),
    ],
  );

  test('Okul dışı envanter kataloğu, verisi ve tasarımı birlikte doğrulanır', () {
    expect(tanim.dogrula, returnsNormally);
    final tasarim = tasarimOlustur();
    expect(() => tasarim.dogrula(tanim), returnsNormally);
    expect(tasarim.bilgiler[1].yazi(veri.bilgiler), 'Depo: Merkez');
    expect(tasarim.bilgiler.last.yazi(veri.bilgiler), 'Derya Kaya');
    expect(tasarim.bilgiler.last.altMetin, 'Depo sorumlusu');
    expect(tasarim.gorunenSutunlar.map((s) => s.alanId), ['sira', 'kod', 'urun']);
    expect(veri.satirlar.last['miktar'], 3);
  });

  test('JSON turu rapor kapsamını, sıralamayı, gizli alanı ve alt metni korur', () {
    final tasarim = tasarimOlustur()
      ..yatay = true
      ..tekSayfayaSigdir = false
      ..yaziBoyutu = 12
      ..satirYuksekligi = 32;
    tasarim.bilgiler[1].goster = false;
    final json = jsonDecode(jsonEncode(tasarim.toJson(tanim.id))) as Map<String, dynamic>;
    final okunan = RaporTasarimi.fromJson(json, tanim);
    expect(okunan.toJson(tanim.id), tasarim.toJson(tanim.id));
    expect(okunan.bilgiler.last.konum, 'altSag');
    expect(okunan.bilgiler.last.altMetin, 'Depo sorumlusu');
    expect(okunan.bilgiler[1].goster, isFalse);
    expect(okunan.sutunlar.last.goster, isFalse);
  });

  test('Kopya düzenlemeleri asıl tasarımın listelerini ve alanlarını değiştirmez', () {
    final asil = tasarimOlustur();
    final kopya = asil.kopya(tanim);
    kopya.bilgiler.first.konum = 'altSol';
    kopya.sutunlar.first.goster = false;
    kopya.sutunlar.removeLast();
    expect(asil.bilgiler.first.konum, 'ustOrta');
    expect(asil.sutunlar.first.goster, isTrue);
    expect(asil.sutunlar, hasLength(4));
  });

  test('Başka rapor kapsamı, eksik kapsam ve bilinmeyen sürüm reddedilir', () {
    final json = tasarimOlustur().toJson(tanim.id);
    expect(() => RaporTasarimi.fromJson({...json, 'raporId': 'servis.isEmri'}, tanim), throwsFormatException);
    expect(() => RaporTasarimi.fromJson({...json}..remove('raporId'), tanim), throwsFormatException);
    expect(() => RaporTasarimi.fromJson({...json, 'surum': 2}, tanim), throwsFormatException);
  });

  test('Katalog içinde kimlikler tekildir; bilgi ve sütun aynı kimliği kullanabilir', () {
    const ortak = RaporAlanTanimi(id: 'kod', etiket: 'Kod');
    const uygun = RaporTanimi(id: 'kodlar', bilgiAlanlari: [ortak], sutunAlanlari: [ortak]);
    expect(uygun.dogrula, returnsNormally);
    const bilgiTekrari = RaporTanimi(id: 'kodlar', bilgiAlanlari: [ortak, ortak], sutunAlanlari: [ortak]);
    const sutunTekrari = RaporTanimi(id: 'kodlar', bilgiAlanlari: [], sutunAlanlari: [ortak, ortak]);
    expect(bilgiTekrari.dogrula, throwsFormatException);
    expect(sutunTekrari.dogrula, throwsFormatException);
  });

  test('Katalog dışı bilgi veya sütun kimliği sessizce boş çıktıya çevrilmez', () {
    final bilgi = tasarimOlustur()..bilgiler.first.alanId = 'baskaAlan';
    final sutun = tasarimOlustur()..sutunlar.first.alanId = 'baskaAlan';
    expect(() => bilgi.dogrula(tanim), throwsFormatException);
    expect(() => sutun.dogrula(tanim), throwsFormatException);
  });

  test('Serbest başlık metni sıralamadan ve veri alanından bağımsız korunur', () {
    final tasarim = tasarimOlustur();
    tasarim.bilgiler.addAll([
      RaporBilgiAlani(alanId: 'baslik', sabitMetin: '  Sayım tutanağı  '),
      RaporBilgiAlani(alanId: 'baslik', sabitMetin: 'İkinci açıklama', konum: 'altSol'),
    ]);
    final ilk = tasarim.bilgiler.removeAt(3);
    tasarim.bilgiler.insert(0, ilk);
    final kopya = tasarim.kopya(tanim);
    expect(kopya.bilgiler.first.yazi({'baslik': 'Dış veri'}), 'Sayım tutanağı');
    expect(kopya.bilgiler.last.yazi({}), 'İkinci açıklama');
    expect(kopya.bilgiler.last.konum, 'altSol');
    final yetkisiz = tasarimOlustur()..bilgiler.first.sabitMetin = 'Sabit';
    expect(() => yetkisiz.dogrula(tanim), throwsFormatException);
    kopya.bilgiler.first.sabitMetin = 'x' * 161;
    expect(() => kopya.dogrula(tanim), throwsFormatException);
  });

  test('Tekrarlanan tasarım alanları ve 16 bilgiye kadar yerleşim desteklenir', () {
    final tasarim = tasarimOlustur();
    tasarim.bilgiler = List.generate(16, (i) => RaporBilgiAlani(
      alanId: 'depo', onEtiket: 'Bölüm $i', konum: RaporBilgiAlani.konumlar.keys.elementAt(i % 6)));
    tasarim.sutunlar.addAll([
      RaporTabloSutunu(alanId: 'bos', baslik: 'Sayım'),
      RaporTabloSutunu(alanId: 'bos', baslik: 'Onay'),
    ]);
    expect(() => tasarim.dogrula(tanim), returnsNormally);
    tasarim.bilgiler.add(RaporBilgiAlani(alanId: 'depo'));
    expect(() => tasarim.dogrula(tanim), throwsFormatException);
  });

  test('Son görünür sütunu gizleme, geçersiz ölçü ve konum reddedilir', () {
    final tumuGizli = tasarimOlustur();
    for (final sutun in tumuGizli.sutunlar) { sutun.goster = false; }
    expect(() => tumuGizli.dogrula(tanim), throwsFormatException);
    final gecersizKonum = tasarimOlustur()..bilgiler.first.konum = 'sayfaDisi';
    expect(() => gecersizKonum.dogrula(tanim), throwsFormatException);
    for (final olcu in [double.nan, double.infinity, 5.0, 19.0]) {
      final tasarim = tasarimOlustur()..yaziBoyutu = olcu;
      expect(() => tasarim.dogrula(tanim), throwsFormatException);
    }
    final dar = tasarimOlustur()..sutunlar.first.genislik = 0;
    expect(() => dar.dogrula(tanim), throwsFormatException);
  });

  test('Bilgi yazısı eksik, gizli ve karmaşık değerleri göstermez', () {
    final bilgi = RaporBilgiAlani(alanId: 'deger', onEtiket: '  Değer  ', altMetin: 'İkinci satır');
    expect(bilgi.yazi({'deger': '  Merkez  '}), 'Değer: Merkez');
    expect(bilgi.yazi({'deger': 12}), 'Değer: 12');
    expect(bilgi.yazi({'deger': true}), 'Değer: true');
    for (final ham in [null, ' ', <String>['kapalı'], {'ad': 'kapalı'}, double.nan]) {
      expect(bilgi.yazi({'deger': ham}), isEmpty);
    }
    bilgi.goster = false;
    expect(bilgi.yazi({'deger': 'Merkez'}), isEmpty);
  });

  test('Yeni seçim alanlarının eksikliği varsayılanlarla okunur; bozuk tür reddedilir', () {
    final json = tasarimOlustur().toJson(tanim.id);
    final bilgiler = json['bilgiler'] as List;
    final sutunlar = json['sutunlar'] as List;
    (bilgiler.first as Map).remove('konum');
    (bilgiler.first as Map).remove('altMetin');
    (sutunlar.first as Map).remove('goster');
    final okunan = RaporTasarimi.fromJson(json, tanim);
    expect(okunan.bilgiler.first.konum, 'ustOrta');
    expect(okunan.bilgiler.first.altMetin, isEmpty);
    expect(okunan.sutunlar.first.goster, isTrue);
    expect(() => RaporTasarimi.fromJson({...json, 'bilgiler': 'yanlış'}, tanim), throwsFormatException);
  });
}
