import '../models/rapor_sablonu.dart';
import '../raporlama/rapor_modeli.dart';

/// Okul alanlarını ortak rapor sözleşmesine bağlar; veri sorgusu yapmaz.
class OgrenciRaporUyarlayici {
  static const _tanim = RaporTanimi(
    id: 'ogrenci_listesi',
    listeEtiketi: 'Öğrenci listesi',
    bilgiAlanlari: [
      RaporAlanTanimi(id: 'okul', etiket: 'Okul adı'),
      RaporAlanTanimi(id: 'metin', etiket: 'Rapor başlığı', serbestMetin: true),
      RaporAlanTanimi(id: 'sinif', etiket: 'Sınıf'),
      RaporAlanTanimi(id: 'ders', etiket: 'Ders'),
      RaporAlanTanimi(id: 'ogretmen', etiket: 'Öğretmen'),
      RaporAlanTanimi(id: 'tarih', etiket: 'Tarih'),
      RaporAlanTanimi(id: 'yil', etiket: 'Eğitim yılı'),
      RaporAlanTanimi(id: 'mudur', etiket: 'Okul müdürü'),
    ],
    sutunAlanlari: [
      RaporAlanTanimi(id: 'sira', etiket: 'Sıra', tur: RaporHucreTuru.sira),
      RaporAlanTanimi(id: 'okulNo', etiket: 'Okul No'),
      RaporAlanTanimi(id: 'adSoyad', etiket: 'Ad Soyad'),
      RaporAlanTanimi(id: 'sinif', etiket: 'Sınıf'),
      RaporAlanTanimi(id: 'alan', etiket: 'Alan'),
      RaporAlanTanimi(id: 'cinsiyet', etiket: 'Cinsiyet'),
      RaporAlanTanimi(id: 'fotograf', etiket: 'Fotoğraf', tur: RaporHucreTuru.resim),
      RaporAlanTanimi(id: 'bos', etiket: 'Özel / boş sütun', tur: RaporHucreTuru.bos),
    ],
  );

  static RaporTanimi tanim(RaporSablonu sablon) => _tanim;

  static RaporTasarimi tasarim(RaporSablonu sablon) {
    final kayit = sablon.ortakTasarim;
    if (kayit != null) {
      return RaporTasarimi.fromJson({...kayit, 'ad': sablon.ad}, _tanim);
    }
    return RaporTasarimi(
      ad: sablon.ad,
      bilgiler: [
        for (final b in sablon.basliklar) RaporBilgiAlani(
          alanId: b.kaynak, onEtiket: b.kaynak == 'metin' ? '' : b.metin,
          sabitMetin: b.kaynak == 'metin' ? b.metin : null,
          goster: b.goster, konum: b.konum),
        if (sablon.basliklar.length < 16)
        RaporBilgiAlani(alanId: 'mudur', altMetin: 'Okul Müdürü',
          goster: sablon.mudurGoster && sablon.mudurKonumu != 'yok',
          konum: sablon.mudurKonumu == 'yok' ? 'altSag' : sablon.mudurKonumu),
      ],
      sutunlar: [
        for (final s in sablon.sutunlar) RaporTabloSutunu(
          alanId: s.kaynak, baslik: s.baslik, genislik: s.genislik, goster: s.goster),
      ],
      yatay: sablon.yatay, tekSayfayaSigdir: sablon.tekSayfayaSigdir,
      yaziBoyutu: sablon.yaziBoyutu, satirYuksekligi: sablon.satirYuksekligi,
    );
  }

  static RaporVerisi veri(RaporSablonu sablon,
      List<Map<String, Object?>> ogrenciler, Map<String, String> bilgiler) => RaporVerisi(
    bilgiler: {for (final alan in _tanim.bilgiAlanlari) alan.id: bilgiler[alan.id]},
    satirlar: [for (final o in ogrenciler) {
      'okulNo': o['OkulNo'],
      'adSoyad': '${o['Ad'] ?? ''} ${o['Soyad'] ?? ''}'.trim(),
      'sinif': o['SinifKodu'], 'alan': o['Alan'], 'cinsiyet': o['Cinsiyet'],
      'fotograf': o['FotoVerisi'],
    }],
  );

  /// Mevcut SQLite anahtarları ve sürüm 1 kayıtları değişmeden kullanılabilir.
  static void geriAktar(RaporTasarimi ortak, RaporSablonu sablon, {bool dogrula = true}) {
    if (dogrula) ortak.dogrula(_tanim);
    sablon
      ..ad = ortak.ad
      ..basliklar = [for (final b in ortak.bilgiler.where((b) => b.alanId != 'mudur'))
        RaporBaslik(kaynak: b.alanId,
          metin: b.alanId == 'metin' ? b.sabitMetin ?? '' : b.onEtiket,
          goster: b.goster, konum: b.konum)]
      ..sutunlar = [for (final s in ortak.sutunlar) RaporSutun(
        kaynak: s.alanId, baslik: s.baslik, genislik: s.genislik, goster: s.goster)]
      ..yatay = ortak.yatay
      ..tekSayfayaSigdir = ortak.tekSayfayaSigdir
      ..yaziBoyutu = ortak.yaziBoyutu
      ..satirYuksekligi = ortak.satirYuksekligi;
    final mudurler = ortak.bilgiler.where((b) => b.alanId == 'mudur');
    sablon.mudurGoster = mudurler.isNotEmpty && mudurler.first.goster;
    if (mudurler.isNotEmpty) sablon.mudurKonumu = mudurler.first.konum;
    sablon.ortakTasarim = ortak.toJson(_tanim.id);
    if (dogrula) sablon.dogrula();
  }
}
