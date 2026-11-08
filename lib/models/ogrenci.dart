class Ogrenci {
  final int ogrenciId;
  final String ad;
  final String soyad;
  final String okulNo;
  final String? sinifKodu;
  final String? alan;
  final String? fotoYolu;

  final String? cinsiyet;
  final String? telefon;
  final String? mail;
  final String? adres;
  final String? veliAdi;
  final String? veliTelefonu;
  final String? yolTarifi;

  Ogrenci({
    required this.ogrenciId,
    required this.ad,
    required this.soyad,
    required this.okulNo,
    this.sinifKodu,
    this.alan,
    this.fotoYolu,
    this.cinsiyet,
    this.telefon,
    this.mail,
    this.adres,
    this.veliAdi,
    this.veliTelefonu,
    this.yolTarifi,
  });

  String get adSoyad => '$ad $soyad'.trim();

  factory Ogrenci.fromJson(Map<String, dynamic> json) {
    return Ogrenci(
      ogrenciId: _intDeger(json, [
        'ogrenciId',
        'OgrenciId',
      ]),
      ad: _stringDeger(json, [
        'ad',
        'Ad',
      ]),
      soyad: _stringDeger(json, [
        'soyad',
        'Soyad',
      ]),
      okulNo: _stringDeger(json, [
        'okulNo',
        'OkulNo',
        'okulNumarasi',
        'OkulNumarasi',
      ]),
      sinifKodu: _nullableStringDeger(json, [
        'sinifKodu',
        'SinifKodu',
        'sinif',
        'Sinif',
      ]),
      alan: _nullableStringDeger(json, [
        'alan',
        'Alan',
      ]),
      fotoYolu: _nullableStringDeger(json, [
        'fotoYolu',
        'FotoYolu',
        'fotografYolu',
        'FotografYolu',
        'resimYolu',
        'ResimYolu',
      ]),
      cinsiyet: _nullableStringDeger(json, [
        'cinsiyet',
        'Cinsiyet',
      ]),
      telefon: _nullableStringDeger(json, [
        'telefon',
        'Telefon',
      ]),
      mail: _nullableStringDeger(json, [
        'mail',
        'Mail',
        'email',
        'Email',
        'ePosta',
        'EPosta',
      ]),
      adres: _nullableStringDeger(json, [
        'adres',
        'Adres',
      ]),
      veliAdi: _nullableStringDeger(json, [
        'veliAdi',
        'VeliAdi',
      ]),
      veliTelefonu: _nullableStringDeger(json, [
        'veliTelefonu',
        'VeliTelefonu',
      ]),
      yolTarifi: _nullableStringDeger(json, [
        'yolTarifi',
        'YolTarifi',
      ]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ogrenciId': ogrenciId,
      'ad': ad,
      'soyad': soyad,
      'okulNo': okulNo,
      'sinifKodu': sinifKodu,
      'alan': alan,
      'fotoYolu': fotoYolu,
      'cinsiyet': cinsiyet,
      'telefon': telefon,
      'mail': mail,
      'adres': adres,
      'veliAdi': veliAdi,
      'veliTelefonu': veliTelefonu,
      'yolTarifi': yolTarifi,
    };
  }

  static int _intDeger(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) {
        final value = json[key];
        if (value is int) return value;
        return int.tryParse(value.toString()) ?? 0;
      }
    }
    return 0;
  }

  static String _stringDeger(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) {
        return json[key].toString().trim();
      }
    }
    return '';
  }

  static String? _nullableStringDeger(
      Map<String, dynamic> json,
      List<String> keys,
      ) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) {
        final text = json[key].toString().trim();
        if (text.isEmpty) return null;
        return text;
      }
    }
    return null;
  }
}