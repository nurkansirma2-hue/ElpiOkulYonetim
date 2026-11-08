import 'dart:convert';

class RaporBaslik {
  RaporBaslik({this.kaynak = 'metin', this.metin = '', this.goster = true,
    this.konum = 'ustOrta'});
  String kaynak;
  String metin;
  bool goster;
  String konum;
  static const konumlar = {'ustSol': 'Üst sol', 'ustOrta': 'Üst orta',
    'ustSag': 'Üst sağ', 'altSol': 'Alt sol', 'altOrta': 'Alt orta', 'altSag': 'Alt sağ'};
  static const kaynaklar = {'metin': 'Serbest başlık', 'okul': 'Okul adı',
    'ogretmen': 'Öğretmen', 'sinif': 'Sınıf', 'ders': 'Ders', 'tarih': 'Tarih', 'yil': 'Eğitim yılı'};
  String yazi(Map<String, String> bilgiler) {
    if (!goster) return '';
    if (kaynak == 'metin') return metin.trim();
    final deger = bilgiler[kaynak]?.trim() ?? '';
    return deger.isEmpty ? '' : metin.trim().isEmpty ? deger : '${metin.trim()}: $deger';
  }
  Map<String, dynamic> toJson() => {'kaynak': kaynak, 'metin': metin, 'goster': goster, 'konum': konum};
  factory RaporBaslik.fromJson(Map<String, dynamic> j) => RaporBaslik(
    kaynak: j['kaynak'] as String, metin: j['metin'] as String, goster: j['goster'] as bool,
    konum: j['konum'] as String? ?? 'ustOrta');
}

class RaporSutun {
  RaporSutun({required this.kaynak, required this.baslik, this.genislik = 2, this.goster = true});
  String kaynak;
  String baslik;
  double genislik;
  bool goster;
  static const kaynaklar = {'sira': 'Sıra', 'okulNo': 'Okul No', 'adSoyad': 'Ad Soyad',
    'sinif': 'Sınıf', 'alan': 'Alan', 'cinsiyet': 'Cinsiyet', 'fotograf': 'Fotoğraf', 'bos': 'Özel / boş sütun'};
  Map<String, dynamic> toJson() => {'kaynak': kaynak, 'baslik': baslik, 'genislik': genislik, 'goster': goster};
  factory RaporSutun.fromJson(Map<String, dynamic> j) => RaporSutun(
    kaynak: j['kaynak'] as String, baslik: j['baslik'] as String, genislik: (j['genislik'] as num).toDouble(),
    goster: j['goster'] as bool? ?? true);
}

class RaporSablonu {
  RaporSablonu({required this.ad, required this.basliklar, required this.sutunlar,
    this.yatay = false, this.yaziBoyutu = 10, this.satirYuksekligi = 26,
    this.tekSayfayaSigdir = true, this.mudurKonumu = 'yok', this.mudurGoster = true,
    this.ortakTasarim});
  String ad;
  List<RaporBaslik> basliklar;
  List<RaporSutun> sutunlar;
  bool yatay;
  bool tekSayfayaSigdir;
  String mudurKonumu;
  bool mudurGoster;
  // Eski kayıt alanları korunur; ortak editörün ek özellikleri burada saklanır.
  Map<String, dynamic>? ortakTasarim;
  double yaziBoyutu, satirYuksekligi;
  static const mudurKonumlari = {'yok': 'Gösterme', 'ustSol': 'Üst sol',
    'ustOrta': 'Üst orta', 'ustSag': 'Üst sağ', 'altSol': 'Alt sol',
    'altOrta': 'Alt orta', 'altSag': 'Alt sağ'};
  List<RaporSutun> get gorunenSutunlar => sutunlar.where((s) => s.goster).toList();

  void dogrula() {
    if (ad.trim().isEmpty || ad.length > 80) throw const FormatException('Şablon adı 1–80 karakter olmalı.');
    if (basliklar.length + (mudurGoster && mudurKonumu != 'yok' ? 1 : 0) > 16) {
      throw const FormatException('Müdür dahil en fazla 16 bilgi alanı eklenebilir.');
    }
    if (sutunlar.isEmpty || sutunlar.length > 16) throw const FormatException('1–16 sütun seçin.');
    if (gorunenSutunlar.isEmpty) throw const FormatException('En az bir görünür sütun seçin.');
    if (!mudurKonumlari.containsKey(mudurKonumu)) throw const FormatException('Okul müdürünün konumu geçersiz.');
    if (!yaziBoyutu.isFinite || yaziBoyutu < 6 || yaziBoyutu > 18 ||
        !satirYuksekligi.isFinite || satirYuksekligi < 16 || satirYuksekligi > 100) {
      throw const FormatException('Yazı boyutu 6–18, satır yüksekliği 16–100 olmalı.');
    }
    for (final b in basliklar) {
      if (!RaporBaslik.kaynaklar.containsKey(b.kaynak) || b.metin.length > 160) {
        throw const FormatException('Başlık türü geçersiz veya metin 160 karakterden uzun.');
      }
      if (!RaporBaslik.konumlar.containsKey(b.konum)) throw const FormatException('Başlığın konumu geçersiz.');
    }
    for (final s in sutunlar) {
      if (!RaporSutun.kaynaklar.containsKey(s.kaynak) || s.baslik.trim().isEmpty || s.baslik.length > 50 ||
          !s.genislik.isFinite || s.genislik < 1 || s.genislik > 8) {
        throw const FormatException('Sütun adı 1–50 karakter, genişlik 1–8 arasında olmalı.');
      }
    }
  }
  Map<String, dynamic> toJson() => {'surum': 1, 'ad': ad, 'yatay': yatay,
    if (ortakTasarim != null) 'ortakTasarim': ortakTasarim,
    'tekSayfayaSigdir': tekSayfayaSigdir, 'mudurKonumu': mudurKonumu, 'mudurGoster': mudurGoster,
    'yaziBoyutu': yaziBoyutu, 'satirYuksekligi': satirYuksekligi,
    'basliklar': basliklar.map((b) => b.toJson()).toList(), 'sutunlar': sutunlar.map((s) => s.toJson()).toList()};
  factory RaporSablonu.fromJson(Map<String, dynamic> j) {
    if (j['surum'] != 1) throw const FormatException('Şablon sürümü desteklenmiyor.');
    final sonuc = RaporSablonu(ad: j['ad'] as String, yatay: j['yatay'] as bool,
      tekSayfayaSigdir: j['tekSayfayaSigdir'] as bool? ?? true,
      mudurKonumu: j['mudurKonumu'] as String? ?? 'yok',
      mudurGoster: j['mudurGoster'] as bool? ?? true,
      ortakTasarim: j['ortakTasarim'] == null ? null :
          Map<String, dynamic>.from(jsonDecode(jsonEncode(j['ortakTasarim'])) as Map),
      yaziBoyutu: (j['yaziBoyutu'] as num).toDouble(), satirYuksekligi: (j['satirYuksekligi'] as num).toDouble(),
      basliklar: (j['basliklar'] as List).map((v) => RaporBaslik.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
      sutunlar: (j['sutunlar'] as List).map((v) => RaporSutun.fromJson(Map<String, dynamic>.from(v as Map))).toList());
    sonuc.dogrula();
    return sonuc;
  }
  RaporSablonu kopya() => RaporSablonu.fromJson(toJson());
  static List<RaporSablonu> hazirSablonlar() => ['Standart Sınıf Listesi', 'Fotoğraflı Liste', 'İmza Listesi', 'Değerlendirme Çizelgesi']
    .map((ad) => RaporSablonu(ad: ad,
      satirYuksekligi: ad == 'Fotoğraflı Liste' ? 56 : 26,
      basliklar: [RaporBaslik(kaynak: 'okul'), RaporBaslik(metin: ad),
        RaporBaslik(kaynak: 'sinif', metin: 'Sınıf'), RaporBaslik(kaynak: 'ders', metin: 'Ders'),
        RaporBaslik(kaynak: 'ogretmen', metin: 'Öğretmen'),
        RaporBaslik(kaynak: 'tarih', metin: 'Tarih')],
      sutunlar: [RaporSutun(kaynak: 'sira', baslik: 'Sıra', genislik: 1),
        if (ad == 'Fotoğraflı Liste') RaporSutun(kaynak: 'fotograf', baslik: 'Fotoğraf'),
        RaporSutun(kaynak: 'okulNo', baslik: 'Okul No'), RaporSutun(kaynak: 'adSoyad', baslik: 'Ad Soyad', genislik: 5),
        if (ad == 'İmza Listesi') RaporSutun(kaynak: 'bos', baslik: 'İmza', genislik: 4),
        if (ad == 'Değerlendirme Çizelgesi') ...[
          RaporSutun(kaynak: 'bos', baslik: 'Proje'), RaporSutun(kaynak: 'bos', baslik: 'Not'),
          RaporSutun(kaynak: 'bos', baslik: 'Açıklama', genislik: 4)],
      ])).toList();
}
