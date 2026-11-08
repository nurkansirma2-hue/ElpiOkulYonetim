class OkulBilgi {
  final int okulId;
  final String? okulAdi;
  final String? telefon;
  final String? email;
  final String? adres;
  final String? konum;

  OkulBilgi({
    required this.okulId,
    this.okulAdi,
    this.telefon,
    this.email,
    this.adres,
    this.konum,
  });

  factory OkulBilgi.fromJson(Map<String, dynamic> json) {
    return OkulBilgi(
      okulId: json['okulId'] ?? json['OkulId'] ?? 0,
      okulAdi: json['okulAdi'] ?? json['OkulAdi'],
      telefon: json['telefon'] ?? json['Telefon'],
      email: json['email'] ?? json['Email'],
      adres: json['adres'] ?? json['Adres'],
      konum: json['konum'] ?? json['Konum'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'okulId': okulId,
      'okulAdi': okulAdi,
      'telefon': telefon,
      'email': email,
      'adres': adres,
      'konum': konum,
    };
  }
}