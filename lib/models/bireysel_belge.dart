class BelgeArsivi {
  const BelgeArsivi({
    required this.id,
    required this.okulId,
    required this.ogretmenProfilId,
    required this.okulAdi,
    required this.ogretmenAdi,
  });

  final String id, okulId, okulAdi, ogretmenAdi;
  final int ogretmenProfilId;

  factory BelgeArsivi.fromMap(Map<String, Object?> row) => BelgeArsivi(
    id: row['ArsivId'] as String,
    okulId: row['OkulId'] as String,
    ogretmenProfilId: row['OgretmenProfilId'] as int,
    okulAdi: row['OkulAdi'] as String,
    ogretmenAdi: row['OgretmenAdi'] as String,
  );
}

class BireyselBelge {
  const BireyselBelge({
    required this.id,
    required this.arsivId,
    required this.dosyaAdi,
    required this.goreliYol,
    required this.uzanti,
    required this.boyut,
    required this.icerikOzeti,
    required this.egitimOgretimYili,
    required this.eklenmeTarihi,
    required this.durum,
    this.klasorId,
    this.belgeTuru = 'Genel belge',
    this.analiz,
    this.silinmeTarihi,
    this.turElleSecildi = false,
    this.sonImport,
  });

  final String id, arsivId, dosyaAdi, goreliYol, uzanti;
  final String? icerikOzeti;
  final String egitimOgretimYili, durum;
  final String? klasorId, analiz, silinmeTarihi;
  final String belgeTuru;
  final bool turElleSecildi;
  final String? sonImport;
  final int boyut;
  final DateTime eklenmeTarihi;
  bool get acilabilir => durum == 'Hazir';

  factory BireyselBelge.fromMap(Map<String, Object?> row) => BireyselBelge(
    id: row['BelgeId'] as String,
    arsivId: row['ArsivId'] as String,
    dosyaAdi: row['DosyaAdi'] as String,
    goreliYol: row['GoreliYol'] as String,
    uzanti: row['Uzanti'] as String,
    boyut: row['Boyut'] as int,
    icerikOzeti: row['IcerikOzeti'] as String?,
    egitimOgretimYili: row['EgitimOgretimYili'] as String,
    eklenmeTarihi: DateTime.parse(row['EklenmeTarihi'] as String),
    durum: row['Durum'] as String,
    klasorId: row['KlasorId'] as String?,
    belgeTuru: row['BelgeTuru'] as String? ?? 'Genel belge',
    analiz: row['Analiz'] as String?,
    silinmeTarihi: row['SilinmeTarihi'] as String?,
    turElleSecildi: row['TurElleSecildi'] == 1,
    sonImport: row['SonImport'] as String?,
  );
}

class BelgeKlasoru {
  const BelgeKlasoru(this.id, this.ad);
  final String id, ad;
}

class BelgeImportKaydi {
  const BelgeImportKaydi(
    this.modul,
    this.yil,
    this.tarih,
    this.eklenen,
    this.guncellenen,
    this.mesaj,
  );
  final String modul, yil, mesaj;
  final DateTime tarih;
  final int eklenen, guncellenen;
}

class BelgeImportKaynagi {
  const BelgeImportKaynagi(this.arsivId, this.belgeId, this.yil);
  final String arsivId, belgeId, yil;
}

class BelgeEklemeSonucu {
  const BelgeEklemeSonucu(this.belge, {required this.zatenVar});
  final BireyselBelge belge;
  final bool zatenVar;
}

class BelgeArsivListesi {
  const BelgeArsivListesi(this.aktif, this.arsivler);
  final BelgeArsivi aktif;
  final List<BelgeArsivi> arsivler;
}
