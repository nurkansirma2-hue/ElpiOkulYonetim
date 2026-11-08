class GunlukPlanSinifSecenegi {
  const GunlukPlanSinifSecenegi({
    required this.sinifSubeId,
    required this.sinifKodu,
    required this.sinifSeviyesi,
  });

  final int sinifSubeId;
  final String sinifKodu;
  final int sinifSeviyesi;
}

class BireyselGunlukPlan {
  const BireyselGunlukPlan({
    this.id,
    this.surum = 0,
    required this.okulId,
    required this.ogretmenProfilId,
    required this.egitimOgretimYili,
    required this.ogretmenAdi,
    required this.okulAdi,
    required this.dersAdi,
    required this.sinifKodu,
    required this.dersId,
    required this.sinifSubeId,
    required this.sinifSeviyesi,
    required this.tarih,
    this.konu = '',
    this.kazanim = '',
    this.ogrenmeCiktisi = '',
    this.yontemTeknik = '',
    this.aracGerec = '',
    this.degerlendirme = '',
    this.dersinIslenisi = '',
    this.etkinlikler = '',
    this.belgeId,
    this.planBilgisi = const {},
  });

  // Ek alanlar, kaynak anlık görüntüleri ve geçmiş mevcut ayar deposunda saklanır.
  final Map<String, dynamic> planBilgisi;
  String get unite => planBilgisi['unite'] as String? ?? '';
  String get kazanimAciklamasi =>
      planBilgisi['kazanimAciklamasi'] as String? ?? '';
  String get aciklamalar => planBilgisi['aciklamalar'] as String? ?? '';
  String get haftaTarih =>
      planBilgisi['haftaTarih'] as String? ??
      tarih.toIso8601String().substring(0, 10);
  String get dersSaati => planBilgisi['dersSaati'] as String? ?? 'Belirtilmedi';

  final int? id;
  final int surum;
  final String okulId;
  final int ogretmenProfilId;
  final String egitimOgretimYili;
  final String ogretmenAdi;
  final String okulAdi;
  final String dersAdi;
  final String sinifKodu;
  final int dersId;
  final int sinifSubeId;
  final int sinifSeviyesi;
  final DateTime tarih;
  final String konu;
  final String kazanim;
  final String ogrenmeCiktisi;
  final String yontemTeknik;
  final String aracGerec;
  final String degerlendirme;
  final String dersinIslenisi;
  final String etkinlikler;
  final String? belgeId;

  BireyselGunlukPlan copyWith({
    DateTime? tarih,
    Map<String, dynamic>? planBilgisi,
    String? unite,
    String? kazanimAciklamasi,
    String? aciklamalar,
    String? konu,
    String? kazanim,
    String? ogrenmeCiktisi,
    String? yontemTeknik,
    String? aracGerec,
    String? degerlendirme,
    String? dersinIslenisi,
    String? etkinlikler,
  }) => BireyselGunlukPlan(
    id: id,
    surum: surum,
    okulId: okulId,
    ogretmenProfilId: ogretmenProfilId,
    egitimOgretimYili: egitimOgretimYili,
    ogretmenAdi: ogretmenAdi,
    okulAdi: okulAdi,
    dersAdi: dersAdi,
    sinifKodu: sinifKodu,
    dersId: dersId,
    sinifSubeId: sinifSubeId,
    sinifSeviyesi: sinifSeviyesi,
    tarih: tarih ?? this.tarih,
    konu: konu ?? this.konu,
    kazanim: kazanim ?? this.kazanim,
    ogrenmeCiktisi: ogrenmeCiktisi ?? this.ogrenmeCiktisi,
    yontemTeknik: yontemTeknik ?? this.yontemTeknik,
    aracGerec: aracGerec ?? this.aracGerec,
    degerlendirme: degerlendirme ?? this.degerlendirme,
    dersinIslenisi: dersinIslenisi ?? this.dersinIslenisi,
    etkinlikler: etkinlikler ?? this.etkinlikler,
    belgeId: belgeId,
    planBilgisi: Map.unmodifiable({
      ...this.planBilgisi,
      ...?planBilgisi,
      if (unite != null) 'unite': unite,
      if (kazanimAciklamasi != null) 'kazanimAciklamasi': kazanimAciklamasi,
      if (aciklamalar != null) 'aciklamalar': aciklamalar,
    }),
  );

  factory BireyselGunlukPlan.fromMap(Map<String, Object?> row) =>
      BireyselGunlukPlan(
        id: row['GunlukPlanId'] as int,
        surum: row['Surum'] as int,
        okulId: row['OkulId'] as String,
        ogretmenProfilId: row['OgretmenProfilId'] as int,
        egitimOgretimYili: row['EgitimOgretimYili'] as String,
        ogretmenAdi: row['OgretmenAdi'] as String,
        okulAdi: row['OkulAdi'] as String,
        dersAdi: row['DersAdi'] as String,
        sinifKodu: row['SinifKodu'] as String,
        dersId: row['DersId'] as int,
        sinifSubeId: row['SinifSubeId'] as int,
        sinifSeviyesi: row['SinifSeviyesi'] as int,
        tarih: DateTime.parse(row['Tarih'] as String),
        konu: row['Konu'] as String,
        kazanim: row['Kazanim'] as String,
        ogrenmeCiktisi: row['OgrenmeCiktisi'] as String,
        yontemTeknik: row['YontemTeknik'] as String,
        aracGerec: row['AracGerec'] as String,
        degerlendirme: row['Degerlendirme'] as String,
        dersinIslenisi: row['DersinIslenisi'] as String,
        etkinlikler: row['Etkinlikler'] as String,
        belgeId: row['BelgeId'] as String?,
      );

  Map<String, Object?> get icerikAlanlari => {
    'Konu': konu,
    'Kazanim': kazanim,
    'OgrenmeCiktisi': ogrenmeCiktisi,
    'YontemTeknik': yontemTeknik,
    'AracGerec': aracGerec,
    'Degerlendirme': degerlendirme,
    'DersinIslenisi': dersinIslenisi,
    'Etkinlikler': etkinlikler,
  };
}
