class ImportSonuc {
  final bool basarili;
  final String mesaj;
  final String kayitTipi;

  final int toplamKayit;
  final int eklenenKayit;
  final int guncellenenKayit;
  final int hataliKayit;
  final int fotoKayit;

  final List<String> hataListesi;
  final List<String> islemAdimlari;
  final List<dynamic> kayitlar;

  ImportSonuc({
    required this.basarili,
    required this.mesaj,
    required this.kayitTipi,
    required this.toplamKayit,
    required this.eklenenKayit,
    required this.guncellenenKayit,
    required this.hataliKayit,
    required this.fotoKayit,
    required this.hataListesi,
    required this.islemAdimlari,
    required this.kayitlar,
  });

  factory ImportSonuc.fromJson(Map<String, dynamic> json) {
    final kayitlarList = _toList(json['kayitlar'] ?? json['Kayitlar']);

    return ImportSonuc(
      basarili: _toBool(json['basarili'] ?? json['Basarili']),
      mesaj: _toString(json['mesaj'] ?? json['Mesaj']),
      kayitTipi: _toString(json['kayitTipi'] ?? json['KayitTipi']),

      toplamKayit: _toInt(
        json['toplamKayit'] ??
            json['ToplamKayit'] ??
            json['toplamKayitSayisi'] ??
            json['ToplamKayitSayisi'] ??
            kayitlarList.length,
      ),

      eklenenKayit: _toInt(json['eklenenKayit'] ?? json['EklenenKayit']),
      guncellenenKayit:
      _toInt(json['guncellenenKayit'] ?? json['GuncellenenKayit']),
      hataliKayit: _toInt(json['hataliKayit'] ?? json['HataliKayit']),
      fotoKayit: _toInt(json['fotoKayit'] ?? json['FotoKayit']),

      hataListesi: _toStringList(
        json['hataListesi'] ?? json['HataListesi'] ?? json['hatalar'],
      ),
      islemAdimlari: _toStringList(
        json['islemAdimlari'] ?? json['IslemAdimlari'],
      ),
      kayitlar: kayitlarList,
    );
  }

  static bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    final text = value.toString().toLowerCase().trim();
    return text == 'true' || text == '1';
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  static String _toString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static List<dynamic> _toList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    return [];
  }
}