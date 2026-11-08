import 'dart:convert';

class OkulBilgiModel {
  final int okulId;
  final String okulAdi;
  final String kisaAd;
  final String kurumKodu;
  final String okulTuru;
  final String il;
  final String ilce;
  final String adres;
  final String konum;
  final String telefon;
  final String email;
  final String webSitesi;
  final String mudurAdi;
  final String mudurYardimcilari;
  final String aktifEgitimYili;
  final String aktifDonem;
  final int toplamOgrenciSayisi;
  final int toplamOgretmenSayisi;
  final int toplamPersonelSayisi;
  final int toplamSinifSayisi;
  final int toplamSubeSayisi;
  final int derslikSayisi;
  final int laboratuvarSayisi;
  final int atolyeSayisi;
  final bool kutuphaneVarMi;
  final bool sporSalonuVarMi;
  final bool konferansSalonuVarMi;
  final bool pansiyonVarMi;
  final String okulBaslangicSaati;
  final String okulBitisSaati;
  final int gunlukDersSaati;
  final bool tamGunMu;
  final bool haftaSonuAcikMi;
  final String logoYolu;
  final String okulResimYolu;
  final bool aktif;

  const OkulBilgiModel({
    required this.okulId,
    required this.okulAdi,
    required this.kisaAd,
    required this.kurumKodu,
    required this.okulTuru,
    required this.il,
    required this.ilce,
    required this.adres,
    required this.konum,
    required this.telefon,
    required this.email,
    required this.webSitesi,
    required this.mudurAdi,
    required this.mudurYardimcilari,
    required this.aktifEgitimYili,
    required this.aktifDonem,
    required this.toplamOgrenciSayisi,
    required this.toplamOgretmenSayisi,
    required this.toplamPersonelSayisi,
    required this.toplamSinifSayisi,
    required this.toplamSubeSayisi,
    required this.derslikSayisi,
    required this.laboratuvarSayisi,
    required this.atolyeSayisi,
    required this.kutuphaneVarMi,
    required this.sporSalonuVarMi,
    required this.konferansSalonuVarMi,
    required this.pansiyonVarMi,
    required this.okulBaslangicSaati,
    required this.okulBitisSaati,
    required this.gunlukDersSaati,
    required this.tamGunMu,
    required this.haftaSonuAcikMi,
    required this.logoYolu,
    required this.okulResimYolu,
    required this.aktif,
  });

  factory OkulBilgiModel.bos() {
    return const OkulBilgiModel(
      okulId: 0,
      okulAdi: '',
      kisaAd: '',
      kurumKodu: '',
      okulTuru: '',
      il: '',
      ilce: '',
      adres: '',
      konum: '',
      telefon: '',
      email: '',
      webSitesi: '',
      mudurAdi: '',
      mudurYardimcilari: '',
      aktifEgitimYili: '',
      aktifDonem: '',
      toplamOgrenciSayisi: 0,
      toplamOgretmenSayisi: 0,
      toplamPersonelSayisi: 0,
      toplamSinifSayisi: 0,
      toplamSubeSayisi: 0,
      derslikSayisi: 0,
      laboratuvarSayisi: 0,
      atolyeSayisi: 0,
      kutuphaneVarMi: false,
      sporSalonuVarMi: false,
      konferansSalonuVarMi: false,
      pansiyonVarMi: false,
      okulBaslangicSaati: '',
      okulBitisSaati: '',
      gunlukDersSaati: 0,
      tamGunMu: true,
      haftaSonuAcikMi: false,
      logoYolu: '',
      okulResimYolu: '',
      aktif: true,
    );
  }

  factory OkulBilgiModel.fromMap(Map<String, dynamic> map) {
    return OkulBilgiModel(
      okulId: _toInt(map['okulId'] ?? map['OkulId']),
      okulAdi: _toStr(map['okulAdi'] ?? map['OkulAdi']),
      kisaAd: _toStr(map['kisaAd'] ?? map['KisaAd']),
      kurumKodu: _toStr(map['kurumKodu'] ?? map['KurumKodu']),
      okulTuru: _toStr(map['okulTuru'] ?? map['OkulTuru']),
      il: _toStr(map['il'] ?? map['Il']),
      ilce: _toStr(map['ilce'] ?? map['Ilce']),
      adres: _toStr(map['adres'] ?? map['Adres']),
      konum: _toStr(map['konum'] ?? map['Konum']),
      telefon: _toStr(map['telefon'] ?? map['Telefon']),
      email: _toStr(map['email'] ?? map['Email']),
      webSitesi: _toStr(map['webSitesi'] ?? map['WebSitesi']),
      mudurAdi: _toStr(map['mudurAdi'] ?? map['MudurAdi']),
      mudurYardimcilari: _toStr(map['mudurYardimcilari'] ?? map['MudurYardimcilari']),
      aktifEgitimYili: _toStr(map['aktifEgitimYili'] ?? map['AktifEgitimYili']),
      aktifDonem: _toStr(map['aktifDonem'] ?? map['AktifDonem']),
      toplamOgrenciSayisi: _toInt(map['toplamOgrenciSayisi'] ?? map['ToplamOgrenciSayisi']),
      toplamOgretmenSayisi: _toInt(map['toplamOgretmenSayisi'] ?? map['ToplamOgretmenSayisi']),
      toplamPersonelSayisi: _toInt(map['toplamPersonelSayisi'] ?? map['ToplamPersonelSayisi']),
      toplamSinifSayisi: _toInt(map['toplamSinifSayisi'] ?? map['ToplamSinifSayisi']),
      toplamSubeSayisi: _toInt(map['toplamSubeSayisi'] ?? map['ToplamSubeSayisi']),
      derslikSayisi: _toInt(map['derslikSayisi'] ?? map['DerslikSayisi']),
      laboratuvarSayisi: _toInt(map['laboratuvarSayisi'] ?? map['LaboratuvarSayisi']),
      atolyeSayisi: _toInt(map['atolyeSayisi'] ?? map['AtolyeSayisi']),
      kutuphaneVarMi: _toBool(map['kutuphaneVarMi'] ?? map['KutuphaneVarMi']),
      sporSalonuVarMi: _toBool(map['sporSalonuVarMi'] ?? map['SporSalonuVarMi']),
      konferansSalonuVarMi: _toBool(map['konferansSalonuVarMi'] ?? map['KonferansSalonuVarMi']),
      pansiyonVarMi: _toBool(map['pansiyonVarMi'] ?? map['PansiyonVarMi']),
      okulBaslangicSaati: _timeToStr(map['okulBaslangicSaati'] ?? map['OkulBaslangicSaati']),
      okulBitisSaati: _timeToStr(map['okulBitisSaati'] ?? map['OkulBitisSaati']),
      gunlukDersSaati: _toInt(map['gunlukDersSaati'] ?? map['GunlukDersSaati']),
      tamGunMu: _toBool(map['tamGunMu'] ?? map['TamGunMu']),
      haftaSonuAcikMi: _toBool(map['haftaSonuAcikMi'] ?? map['HaftaSonuAcikMi']),
      logoYolu: _toStr(map['logoYolu'] ?? map['LogoYolu']),
      okulResimYolu: _toStr(map['okulResimYolu'] ?? map['OkulResimYolu']),
      aktif: _toBool(map['aktif'] ?? map['Aktif']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'okulId': okulId,
      'okulAdi': okulAdi.trim(),
      'kisaAd': kisaAd.trim(),
      'kurumKodu': kurumKodu.trim(),
      'okulTuru': okulTuru.trim(),
      'il': il.trim(),
      'ilce': ilce.trim(),
      'adres': adres.trim(),
      'konum': konum.trim(),
      'telefon': telefon.trim(),
      'email': email.trim(),
      'webSitesi': webSitesi.trim(),
      'mudurAdi': mudurAdi.trim(),
      'mudurYardimcilari': mudurYardimcilari.trim(),
      'aktifEgitimYili': aktifEgitimYili.trim(),
      'aktifDonem': aktifDonem.trim(),
      'toplamOgrenciSayisi': toplamOgrenciSayisi,
      'toplamOgretmenSayisi': toplamOgretmenSayisi,
      'toplamPersonelSayisi': toplamPersonelSayisi,
      'toplamSinifSayisi': toplamSinifSayisi,
      'toplamSubeSayisi': toplamSubeSayisi,
      'derslikSayisi': derslikSayisi,
      'laboratuvarSayisi': laboratuvarSayisi,
      'atolyeSayisi': atolyeSayisi,
      'kutuphaneVarMi': kutuphaneVarMi,
      'sporSalonuVarMi': sporSalonuVarMi,
      'konferansSalonuVarMi': konferansSalonuVarMi,
      'pansiyonVarMi': pansiyonVarMi,
      'okulBaslangicSaati': okulBaslangicSaati.trim(),
      'okulBitisSaati': okulBitisSaati.trim(),
      'gunlukDersSaati': gunlukDersSaati,
      'tamGunMu': tamGunMu,
      'haftaSonuAcikMi': haftaSonuAcikMi,
      'logoYolu': logoYolu.trim(),
      'okulResimYolu': okulResimYolu.trim(),
      'aktif': aktif,
    };
  }

  String toJson() => jsonEncode(toMap());

  OkulBilgiModel copyWith({
    int? okulId,
    String? okulAdi,
    String? kisaAd,
    String? kurumKodu,
    String? okulTuru,
    String? il,
    String? ilce,
    String? adres,
    String? konum,
    String? telefon,
    String? email,
    String? webSitesi,
    String? mudurAdi,
    String? mudurYardimcilari,
    String? aktifEgitimYili,
    String? aktifDonem,
    int? toplamOgrenciSayisi,
    int? toplamOgretmenSayisi,
    int? toplamPersonelSayisi,
    int? toplamSinifSayisi,
    int? toplamSubeSayisi,
    int? derslikSayisi,
    int? laboratuvarSayisi,
    int? atolyeSayisi,
    bool? kutuphaneVarMi,
    bool? sporSalonuVarMi,
    bool? konferansSalonuVarMi,
    bool? pansiyonVarMi,
    String? okulBaslangicSaati,
    String? okulBitisSaati,
    int? gunlukDersSaati,
    bool? tamGunMu,
    bool? haftaSonuAcikMi,
    String? logoYolu,
    String? okulResimYolu,
    bool? aktif,
  }) {
    return OkulBilgiModel(
      okulId: okulId ?? this.okulId,
      okulAdi: okulAdi ?? this.okulAdi,
      kisaAd: kisaAd ?? this.kisaAd,
      kurumKodu: kurumKodu ?? this.kurumKodu,
      okulTuru: okulTuru ?? this.okulTuru,
      il: il ?? this.il,
      ilce: ilce ?? this.ilce,
      adres: adres ?? this.adres,
      konum: konum ?? this.konum,
      telefon: telefon ?? this.telefon,
      email: email ?? this.email,
      webSitesi: webSitesi ?? this.webSitesi,
      mudurAdi: mudurAdi ?? this.mudurAdi,
      mudurYardimcilari: mudurYardimcilari ?? this.mudurYardimcilari,
      aktifEgitimYili: aktifEgitimYili ?? this.aktifEgitimYili,
      aktifDonem: aktifDonem ?? this.aktifDonem,
      toplamOgrenciSayisi: toplamOgrenciSayisi ?? this.toplamOgrenciSayisi,
      toplamOgretmenSayisi: toplamOgretmenSayisi ?? this.toplamOgretmenSayisi,
      toplamPersonelSayisi: toplamPersonelSayisi ?? this.toplamPersonelSayisi,
      toplamSinifSayisi: toplamSinifSayisi ?? this.toplamSinifSayisi,
      toplamSubeSayisi: toplamSubeSayisi ?? this.toplamSubeSayisi,
      derslikSayisi: derslikSayisi ?? this.derslikSayisi,
      laboratuvarSayisi: laboratuvarSayisi ?? this.laboratuvarSayisi,
      atolyeSayisi: atolyeSayisi ?? this.atolyeSayisi,
      kutuphaneVarMi: kutuphaneVarMi ?? this.kutuphaneVarMi,
      sporSalonuVarMi: sporSalonuVarMi ?? this.sporSalonuVarMi,
      konferansSalonuVarMi: konferansSalonuVarMi ?? this.konferansSalonuVarMi,
      pansiyonVarMi: pansiyonVarMi ?? this.pansiyonVarMi,
      okulBaslangicSaati: okulBaslangicSaati ?? this.okulBaslangicSaati,
      okulBitisSaati: okulBitisSaati ?? this.okulBitisSaati,
      gunlukDersSaati: gunlukDersSaati ?? this.gunlukDersSaati,
      tamGunMu: tamGunMu ?? this.tamGunMu,
      haftaSonuAcikMi: haftaSonuAcikMi ?? this.haftaSonuAcikMi,
      logoYolu: logoYolu ?? this.logoYolu,
      okulResimYolu: okulResimYolu ?? this.okulResimYolu,
      aktif: aktif ?? this.aktif,
    );
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  static String _toStr(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    return text == 'true' || text == '1';
  }

  static String _timeToStr(dynamic value) {
    final text = _toStr(value);
    if (text.isEmpty) return '';
    final parts = text.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return text;
  }
}
