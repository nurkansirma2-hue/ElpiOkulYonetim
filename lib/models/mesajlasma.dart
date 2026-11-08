const odevBildirimArsivModulu = 'OdevBildirimArsiv';

/// TR yerel numaraları 90 ile, diğer ülkeler +/00 ülke koduyla girilir.
/// Harfleri veya iki numarayı temizleyerek yanlış alıcı üretmeyiz.
String? mesajTelefonNormalize(String raw) {
  var value = raw.trim();
  if (value.isEmpty || !RegExp(r'^\+?[0-9\s().-]+$').hasMatch(value)) {
    return null;
  }
  final uluslararasi = value.startsWith('+') || value.startsWith('00');
  value = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (value.startsWith('00')) value = value.substring(2);
  if (!uluslararasi) {
    if (value.length == 11 && value.startsWith('0')) value = value.substring(1);
    if (value.length == 10) value = '90$value';
    if (!value.startsWith('90') || value.length != 12) return null;
  }
  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(value)) return null;
  if (value.startsWith('90') &&
      (value.length != 12 || !RegExp(r'^90[2-5][0-9]{9}$').hasMatch(value))) {
    return null;
  }
  return value;
}

enum MesajKisiTuru {
  ogrenci('Ogrenci', 'Öğrenci'),
  veli('Veli', 'Veli'),
  ogretmen('Ogretmen', 'Öğretmen');

  const MesajKisiTuru(this.kod, this.baslik);
  final String kod, baslik;
}

/// Veli iletişimi öğrenci kaydından çözülür; ayrı telefon kopyası yoktur.
class MesajKisi {
  const MesajKisi({
    required this.tur,
    required this.kisiId,
    required this.sinifId,
    required this.ad,
    required this.telefon,
    required this.aciklama,
    this.veliTuru,
    this.telefonAciklamasi,
  });
  final MesajKisiTuru tur;
  final String kisiId, ad, telefon, aciklama;
  final int sinifId;
  final String? veliTuru;
  final String? telefonAciklamasi;
  String get secimAnahtari => '${tur.kod}:$kisiId';
  String get bagAnahtari => '$secimAnahtari:$sinifId';
  String? get normalizeTelefon => mesajTelefonNormalize(telefon);
  Map<String, Object?> get anlikGoruntu => {
    'ad': ad,
    'telefon': telefon,
    'aciklama': aciklama,
    'veliTuru': veliTuru,
    if (telefonAciklamasi != null) 'telefonAciklamasi': telefonAciklamasi,
  };
}

class MesajKisiOnIzleme {
  MesajKisiOnIzleme(Iterable<MesajKisi> kisiler) {
    final tekil = <String, MesajKisi>{};
    for (final k in kisiler) {
      final eski = tekil[k.bagAnahtari];
      if (eski != null &&
          (eski.ad != k.ad ||
              eski.telefon != k.telefon ||
              eski.aciklama != k.aciklama ||
              eski.veliTuru != k.veliTuru ||
              eski.telefonAciklamasi != k.telefonAciklamasi)) {
        throw const FormatException('Aynı alıcı için çelişen bilgiler var.');
      }
      tekil[k.bagAnahtari] = k;
    }
    secilenler = List.unmodifiable(tekil.values);
    gecersizler = List.unmodifiable(
      secilenler.where((k) => k.normalizeTelefon == null),
    );
    final gruplar = <String, List<MesajKisi>>{};
    for (final k in secilenler.where((k) => k.normalizeTelefon != null)) {
      (gruplar[k.normalizeTelefon!] ??= []).add(k);
    }
    telefonGruplari = Map.unmodifiable({
      for (final e in gruplar.entries)
        e.key: List<MesajKisi>.unmodifiable(e.value),
    });
  }
  late final List<MesajKisi> secilenler, gecersizler;
  late final Map<String, List<MesajKisi>> telefonGruplari;
  int get kisiSayisi => secilenler.map((k) => k.secimAnahtari).toSet().length;
  int get eksikSayisi => gecersizler.map((k) => k.secimAnahtari).toSet().length;
}

class MesajBaglami {
  const MesajBaglami(
    this.okulId,
    this.ogretmenId,
    this.ogretmenAdi,
    this.okulAdi,
    this.yil,
  );
  final String okulId, ogretmenAdi, okulAdi, yil;
  final int ogretmenId;
  bool ayni(MesajBaglami b) =>
      okulId == b.okulId &&
      ogretmenId == b.ogretmenId &&
      ogretmenAdi == b.ogretmenAdi &&
      okulAdi == b.okulAdi &&
      yil == b.yil;
}

class MesajOgrencisi {
  const MesajOgrencisi(
    this.id,
    this.okulNo,
    this.ad,
    this.sinifId,
    this.sinif,
    this.veliAdi,
    this.telefon, {
    this.veliTuru,
    this.veliIliskisiTanimli = true,
    this.telefonAciklamasi,
  });
  final int id, sinifId;
  final String okulNo, ad, sinif, veliAdi, telefon;
  final String? veliTuru;
  final bool veliIliskisiTanimli;
  final String? telefonAciklamasi;
  String get aciklama => '$sinif • $okulNo • $ad';
  String? get normalizeTelefon => mesajTelefonNormalize(telefon);
}

class MesajAliciAdayi {
  MesajAliciAdayi(this.telefon, this.ad, List<MesajOgrencisi> ogrenciler)
    : ogrenciler = List.unmodifiable(ogrenciler);
  final String telefon, ad;
  final List<MesajOgrencisi> ogrenciler;
}

class MesajOnIzleme {
  MesajOnIzleme(List<MesajOgrencisi> secilenler)
    : secilenler = List.unmodifiable(secilenler) {
    final groups = <String, List<MesajOgrencisi>>{};
    final invalid = <MesajOgrencisi>[];
    for (final o in secilenler) {
      final tel = o.normalizeTelefon;
      if (tel == null) {
        invalid.add(o);
      } else {
        groups.putIfAbsent(tel, () => []).add(o);
      }
    }
    gecersizler = List.unmodifiable(invalid);
    alicilar = List.unmodifiable(
      groups.entries.map(
        (e) => MesajAliciAdayi(
          e.key,
          e.value
              .map((o) => o.veliAdi.isEmpty ? '${o.ad} velisi' : o.veliAdi)
              .toSet()
              .join(' / '),
          e.value,
        ),
      ),
    );
  }
  final List<MesajOgrencisi> secilenler;
  late final List<MesajOgrencisi> gecersizler;
  late final List<MesajAliciAdayi> alicilar;
  int get birlestirilen =>
      secilenler.length - gecersizler.length - alicilar.length;
}

class MesajAlicisi {
  MesajAlicisi(
    Map<String, Object?> r, {
    List<Map<String, Object?>> baglar = const [],
  }) : id = r['AliciId'] as int,
       sira = r['Sira'] as int,
       telefon = r['Telefon'] as String,
       ad = r['AliciAdi'] as String,
       ogrenciler = r['Ogrenciler'] as String,
       durum = r['Durum'] as String,
       onayTarihi = r['OnayTarihi'] as String?,
       hata = r['Hata'] as String?,
       smsDurumu = r['SmsDurumu'] as String?,
       baglar = List.unmodifiable(
         baglar.map((r) => Map<String, Object?>.unmodifiable(r)),
       );
  final List<Map<String, Object?>> baglar;
  final int id, sira;
  final String telefon, ad, ogrenciler, durum;
  final String? onayTarihi, hata, smsDurumu;
  bool get bitti => durum == 'Onaylandi' || durum == 'Atlandi';
}

class MesajKuyrugu {
  MesajKuyrugu(Map<String, Object?> r, List<MesajAlicisi> alicilar)
    : id = r['KuyrukId'] as String,
      metin = r['Metin'] as String,
      kaynakModul = r['KaynakModul'] as String,
      kaynakKayit = r['KaynakKayit'] as String?,
      tarih = r['OlusturmaTarihi'] as String,
      alicilar = List.unmodifiable(alicilar);
  final String id, metin, kaynakModul, tarih;
  final String? kaynakKayit;
  final List<MesajAlicisi> alicilar;
  bool get arsivlendi => kaynakModul == odevBildirimArsivModulu;
  MesajAlicisi? get siradaki {
    if (arsivlendi) return null;
    for (final a in alicilar) {
      if (!a.bitti) return a;
    }
    return null;
  }

  bool get smsBaslatildi => alicilar.any((a) => a.smsDurumu != null);
  bool get tamamlandi =>
      arsivlendi ||
      (smsBaslatildi
          ? alicilar.every((a) => a.smsDurumu != null)
          : siradaki == null);
  int get smsIstenen => alicilar.where((a) => a.smsDurumu == 'Istendi').length;
  int get smsBelirsiz =>
      alicilar.where((a) => a.smsDurumu == 'Belirsiz').length;

  int get onaylanan => alicilar.where((a) => a.durum == 'Onaylandi').length;
  int get atlanan => alicilar.where((a) => a.durum == 'Atlandi').length;
}
