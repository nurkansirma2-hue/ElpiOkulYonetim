import 'odev_kontrol.dart';

class DersUygulamasi {
  DersUygulamasi.fromMap(Map<String, Object?> r)
    : id = r['UygulamaId'] as int,
      odevId = r['OdevId'] as int,
      sira = r['Sira'] as int,
      ad = r['Ad'] as String,
      aktif = r['Aktif'] == 1,
      adet = (r['Adet'] as int?) ?? 1;
  final int id, odevId, sira, adet;
  final String ad;
  final bool aktif;
}

class UygulamaSonucGirdisi {
  const UygulamaSonucGirdisi(
    this.ogrenciId,
    this.uygulamaId,
    this.durum, {
    this.notDegeri,
    this.aciklama,
    this.yapilan,
    this.adet,
  });
  final int ogrenciId, uygulamaId;
  final OdevKontrolDurumu durum;
  final int? notDegeri;
  final int? yapilan, adet;
  final String? aciklama;
}

class UygulamaSonucu {
  UygulamaSonucu.fromMap(Map<String, Object?> r)
    : uygulamaId = r['UygulamaId'] as int,
      ogrenciId = r['OgrenciId'] as int,
      kontrolId = r['OdevKontrolId'] as int,
      tarih = DateTime.parse(r['KontrolTarihi'] as String),
      durum = OdevKontrolDurumu.oku(r['Durum']),
      notDegeri = r['NotDegeri'] as int?,
      aciklama = r['Aciklama'] as String?,
      yapilan = r['Yapilan'] as int?,
      adet = r['Adet'] as int?;
  final int uygulamaId, ogrenciId, kontrolId;
  final DateTime tarih;
  final OdevKontrolDurumu durum;
  final int? notDegeri;
  final int? yapilan, adet;
  final String? aciklama;
  double? get puan =>
      yapilan != null && adet != null && !durum.degerlendirmeDisi && !durum.bekliyor
      ? yapilan! / adet! * 10
      : OdevKontrolSonuc(
          odevKontrolSonucId: 0,
          odevId: 0,
          odevKontrolId: kontrolId,
          ogrenciId: ogrenciId,
          durum: durum,
          notDegeri: notDegeri,
        ).puan;
}

class UygulamaIlerleme {
  UygulamaIlerleme(
    Iterable<DersUygulamasi> uygulamalar,
    Iterable<UygulamaSonucu> sonuclar,
  ) {
    final aktif = uygulamalar.where((u) => u.aktif).map((u) => u.id).toSet();
    toplam = aktif.length;
    final son = {
      for (final s in sonuclar)
        if (aktif.contains(s.uygulamaId)) s.uygulamaId: s,
    };
    degerlendirilen = son.values.where((s) => !s.durum.bekliyor).length;
    bekleyen = toplam - degerlendirilen;
    hesapDisi = son.values.where((s) => s.durum.degerlendirmeDisi).length;
    final puanlar = son.values.map((s) => s.puan).whereType<double>().toList();
    ortalama = puanlar.isEmpty
        ? null
        : puanlar.reduce((a, b) => a + b) / puanlar.length;
  }
  late final int toplam, degerlendirilen, bekleyen, hesapDisi;
  late final double? ortalama;
}
