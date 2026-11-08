import 'dart:convert';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/models/rapor_sablonu.dart';
import 'package:elpi_okul_yonetim/raporlama/rapor_modeli.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_rapor_uyarlayici.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RaporSablonu eskiSablon() => RaporSablonu(
    ad: 'Ders listesi',
    basliklar: [
      RaporBaslik(kaynak: 'okul', konum: 'ustSol'),
      RaporBaslik(metin: 'Ders listesi'),
      RaporBaslik(kaynak: 'ders', metin: 'Ders', konum: 'ustSag'),
      RaporBaslik(kaynak: 'ogretmen', metin: 'Öğretmen', goster: false),
    ],
    sutunlar: [
      RaporSutun(kaynak: 'okulNo', baslik: 'Okul No'),
      RaporSutun(kaynak: 'adSoyad', baslik: 'Ad Soyad', genislik: 5),
      RaporSutun(kaynak: 'fotograf', baslik: 'Fotoğraf', goster: false),
    ],
    mudurKonumu: 'altSag',
    yatay: true,
    tekSayfayaSigdir: false,
    yaziBoyutu: 12,
    satirYuksekligi: 30,
  );

  test('Eski okul şablonu ortak alanlara görünürlük, metin ve konum kaybetmeden uyarlanır', () {
    final eski = eskiSablon();
    final ortak = OgrenciRaporUyarlayici.tasarim(eski);
    final tanim = OgrenciRaporUyarlayici.tanim(eski);
    expect(() => ortak.dogrula(tanim), returnsNormally);
    expect(ortak.bilgiler.map((b) => b.alanId), ['okul', 'metin', 'ders', 'ogretmen', 'mudur']);
    expect(ortak.bilgiler[1].sabitMetin, 'Ders listesi');
    expect(ortak.bilgiler[1].yazi({}), 'Ders listesi');
    expect(ortak.bilgiler[2].onEtiket, 'Ders');
    expect(ortak.bilgiler[2].konum, 'ustSag');
    expect(ortak.bilgiler[3].goster, isFalse);
    expect(ortak.bilgiler.last.altMetin, 'Okul Müdürü');
    expect(ortak.bilgiler.last.konum, 'altSag');
    expect(ortak.sutunlar.last.goster, isFalse);
    expect(ortak.sutunlar[1].genislik, 5);
    expect(ortak.yatay, isTrue);
    expect(ortak.tekSayfayaSigdir, isFalse);
    expect(ortak.yaziBoyutu, 12);
    expect(ortak.satirYuksekligi, 30);
  });

  test('İlk sürüm JSON yeni alanlar olmadan okunur ve ortak tasarıma dönüşür', () {
    final json = eskiSablon().toJson()
      ..remove('tekSayfayaSigdir')
      ..remove('mudurKonumu')
      ..remove('mudurGoster');
    for (final baslik in json['basliklar'] as List) { (baslik as Map).remove('konum'); }
    for (final sutun in json['sutunlar'] as List) { (sutun as Map).remove('goster'); }
    final eski = RaporSablonu.fromJson(json);
    final ortak = OgrenciRaporUyarlayici.tasarim(eski);
    expect(() => ortak.dogrula(OgrenciRaporUyarlayici.tanim(eski)), returnsNormally);
    expect(ortak.bilgiler.first.konum, 'ustOrta');
    expect(ortak.bilgiler.last.goster, isFalse);
    expect(ortak.bilgiler.last.konum, 'altSag');
    expect(ortak.sutunlar.every((s) => s.goster), isTrue);
    expect(ortak.tekSayfayaSigdir, isTrue);
  });

  test('Ortak tasarım ve legacy JSON turu alt metni, sıralamayı ve gizli konumu korur', () {
    final eski = eskiSablon();
    final ortak = OgrenciRaporUyarlayici.tasarim(eski);
    final tanim = OgrenciRaporUyarlayici.tanim(eski);
    ortak.bilgiler[2].altMetin = 'Uygulama grubu';
    final mudur = ortak.bilgiler.removeLast()
      ..goster = false
      ..konum = 'altSol'
      ..altMetin = 'Kurum sorumlusu';
    ortak.bilgiler.insert(0, mudur);
    ortak.sutunlar.insert(0, ortak.sutunlar.removeAt(1));
    OgrenciRaporUyarlayici.geriAktar(ortak, eski);
    expect(eski.sutunlar.map((s) => s.kaynak), ['adSoyad', 'okulNo', 'fotograf']);
    expect(eski.mudurGoster, isFalse);
    expect(eski.mudurKonumu, 'altSol');
    final kayit = RaporSablonu.fromJson(jsonDecode(jsonEncode(eski.toJson())) as Map<String, dynamic>);
    final okunan = OgrenciRaporUyarlayici.tasarim(kayit);
    expect(okunan.toJson(tanim.id), ortak.toJson(tanim.id));
    expect(okunan.bilgiler.first.altMetin, 'Kurum sorumlusu');
    expect(okunan.bilgiler.first.goster, isFalse);
    expect(okunan.bilgiler[3].altMetin, 'Uygulama grubu');
    expect(okunan.sutunlar.last.goster, isFalse);
  });

  test('İç içe ortak JSON kopyası asıl kayıtla mutable alan paylaşmaz', () {
    final eski = eskiSablon();
    OgrenciRaporUyarlayici.geriAktar(OgrenciRaporUyarlayici.tasarim(eski), eski);
    final kopya = eski.kopya();
    final kopyaBilgileri = kopya.ortakTasarim!['bilgiler'] as List;
    (kopyaBilgileri.first as Map)['konum'] = 'altOrta';
    final asilBilgiler = eski.ortakTasarim!['bilgiler'] as List;
    expect((asilBilgiler.first as Map)['konum'], 'ustSol');
  });

  test('On altı başlıkta gizli müdür limit dışında eklenmez; görünür müdür limitte sayılır', () {
    final eski = eskiSablon()
      ..basliklar = List.generate(16, (i) => RaporBaslik(metin: 'Başlık $i'))
      ..mudurGoster = false;
    expect(eski.dogrula, returnsNormally);
    final ortak = OgrenciRaporUyarlayici.tasarim(eski);
    expect(ortak.bilgiler, hasLength(16));
    expect(ortak.bilgiler.any((b) => b.alanId == 'mudur'), isFalse);
    expect(() => ortak.dogrula(OgrenciRaporUyarlayici.tanim(eski)), returnsNormally);
    eski.mudurGoster = true;
    expect(eski.dogrula, throwsFormatException);
    eski.basliklar.removeLast();
    expect(eski.dogrula, returnsNormally);
    final mudurlu = OgrenciRaporUyarlayici.tasarim(eski);
    expect(mudurlu.bilgiler, hasLength(16));
    expect(mudurlu.bilgiler.last.alanId, 'mudur');
    expect(mudurlu.bilgiler.last.goster, isTrue);
  });

  test('Farklı adla kaydedilen legacy kopyanın adı ortak snapshot adını geçersiz kılar', () {
    final eski = eskiSablon();
    OgrenciRaporUyarlayici.geriAktar(OgrenciRaporUyarlayici.tasarim(eski), eski);
    final yeni = RaporSablonu.fromJson({...eski.toJson(), 'ad': 'Yeni kayıt'});
    expect(yeni.ortakTasarim!['ad'], 'Ders listesi');
    expect(OgrenciRaporUyarlayici.tasarim(yeni).ad, 'Yeni kayıt');
    expect(eski.ad, 'Ders listesi');
  });

  test('Düzenleme taslağında boş sütun başlığı eşitlenir; kayıt doğrulaması reddeder', () {
    final eski = eskiSablon();
    final ortak = OgrenciRaporUyarlayici.tasarim(eski);
    final tanim = OgrenciRaporUyarlayici.tanim(eski);
    ortak.sutunlar.first.baslik = '';
    expect(() => OgrenciRaporUyarlayici.geriAktar(ortak, eski, dogrula: false), returnsNormally);
    expect(eski.sutunlar.first.baslik, isEmpty);
    expect(((eski.ortakTasarim!['sutunlar'] as List).first as Map)['baslik'], isEmpty);
    expect(() => ortak.dogrula(tanim), throwsFormatException);
    expect(eski.dogrula, throwsFormatException);
    expect(() => OgrenciRaporUyarlayici.geriAktar(ortak, eski), throwsFormatException);
    ortak.sutunlar.first.baslik = 'Numara';
    expect(() => OgrenciRaporUyarlayici.geriAktar(ortak, eski), returnsNormally);
    expect(OgrenciRaporUyarlayici.tasarim(eski).sutunlar.first.baslik, 'Numara');
  });

  test('Öğrenci veri adaptörü satır sırası ve resim baytlarını korur, proje anahtarlarını çevirir', () {
    final eski = eskiSablon();
    final foto = Uint8List.fromList([1, 2, 3]);
    final veri = OgrenciRaporUyarlayici.veri(eski, [
      {'OkulNo': '10', 'Ad': 'Ada', 'Soyad': 'Demir', 'SinifKodu': '9-A', 'FotoVerisi': foto},
      {'OkulNo': '20', 'Ad': 'Deniz', 'Soyad': null, 'SinifKodu': '10-B'},
    ], {'okul': 'Test Okulu', 'mudur': 'Ayşe Yönetici', 'kapsamDisi': 'Gösterilmez'});
    expect(veri.satirlar.map((s) => s['okulNo']), ['10', '20']);
    expect(veri.satirlar.map((s) => s['adSoyad']), ['Ada Demir', 'Deniz']);
    expect(veri.satirlar.map((s) => s['sinif']), ['9-A', '10-B']);
    expect(identical(veri.satirlar.first['fotograf'], foto), isTrue);
    expect(veri.bilgiler['okul'], 'Test Okulu');
    expect(veri.bilgiler['mudur'], 'Ayşe Yönetici');
    expect(veri.bilgiler.containsKey('kapsamDisi'), isFalse);
    expect(OgrenciRaporUyarlayici.tanim(eski).sutunAlanlari
        .singleWhere((a) => a.id == 'fotograf').tur, RaporHucreTuru.resim);
  });
}
