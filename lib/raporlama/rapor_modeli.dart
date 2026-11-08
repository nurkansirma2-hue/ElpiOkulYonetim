enum RaporHucreTuru { metin, resim, sira, bos }

/// Alan kimlikleri uygulamanın veri adaptörü tarafından belirlenir.
class RaporAlanTanimi {
  const RaporAlanTanimi({
    required this.id,
    required this.etiket,
    this.tur = RaporHucreTuru.metin,
    this.serbestMetin = false,
  });

  final String id;
  final String etiket;
  final RaporHucreTuru tur;
  final bool serbestMetin;
}

/// Değerler gösterime hazırdır; tarih, para ve birim biçimini adaptör belirler.
class RaporVerisi {
  const RaporVerisi({required this.bilgiler, required this.satirlar});

  final Map<String, Object?> bilgiler;
  final List<Map<String, Object?>> satirlar;
}

/// Aynı alan kimliği bilgi ve sütun kataloglarının ikisinde de kullanılabilir.
/// Bir katalog içindeki kimlikler ise tekildir. Katalog listeleri değiştirilmez.
class RaporTanimi {
  const RaporTanimi({
    required this.id,
    required this.bilgiAlanlari,
    required this.sutunAlanlari,
    this.listeEtiketi = 'Liste',
  });

  final String id;
  final List<RaporAlanTanimi> bilgiAlanlari;
  final List<RaporAlanTanimi> sutunAlanlari;
  final String listeEtiketi;

  void dogrula() {
    if (id.trim().isEmpty || id != id.trim() || id.length > 120) {
      throw const FormatException('Rapor kimliği 1–120 karakter olmalı ve boşlukla başlamamalı veya bitmemeli.');
    }
    if (listeEtiketi.trim().isEmpty || listeEtiketi.length > 160) {
      throw const FormatException('Liste etiketi 1–160 karakter olmalı.');
    }
    if (sutunAlanlari.isEmpty) {
      throw const FormatException('En az bir sütun alanı tanımlayın.');
    }
    _alanlariDogrula(bilgiAlanlari);
    _alanlariDogrula(sutunAlanlari);
  }

  static void _alanlariDogrula(List<RaporAlanTanimi> alanlar) {
    final kimlikler = <String>{};
    for (final alan in alanlar) {
      if (alan.id.trim().isEmpty || alan.id != alan.id.trim() || alan.id.length > 120) {
        throw const FormatException('Alan kimliği 1–120 karakter olmalı ve boşlukla başlamamalı veya bitmemeli.');
      }
      if (!kimlikler.add(alan.id)) {
        throw const FormatException('Aynı katalogdaki alan kimlikleri tekil olmalı.');
      }
      if (alan.etiket.trim().isEmpty || alan.etiket.length > 160) {
        throw const FormatException('Alan etiketi 1–160 karakter olmalı.');
      }
    }
  }
}

class RaporBilgiAlani {
  RaporBilgiAlani({
    required this.alanId,
    this.onEtiket = '',
    this.altMetin = '',
    this.goster = true,
    this.konum = 'ustOrta',
    this.sabitMetin,
  });

  String alanId;
  String onEtiket;
  String altMetin;
  bool goster;
  String konum;
  String? sabitMetin;

  static const konumlar = {
    'ustSol': 'Üst sol', 'ustOrta': 'Üst orta', 'ustSag': 'Üst sağ',
    'altSol': 'Alt sol', 'altOrta': 'Alt orta', 'altSag': 'Alt sağ',
  };

  String yazi(Map<String, Object?> bilgiler) {
    if (!goster) return '';
    final ham = sabitMetin ?? bilgiler[alanId];
    final String deger;
    if (ham is String) {
      deger = ham.trim();
    } else if (ham is bool || (ham is num && ham.isFinite)) {
      deger = ham.toString();
    } else {
      return '';
    }
    if (deger.isEmpty) return '';
    final etiket = onEtiket.trim();
    return etiket.isEmpty ? deger : '$etiket: $deger';
  }

  Map<String, dynamic> toJson() => {
    'alanId': alanId, 'onEtiket': onEtiket, 'altMetin': altMetin,
    'goster': goster, 'konum': konum,
    if (sabitMetin != null) 'sabitMetin': sabitMetin,
  };

  factory RaporBilgiAlani.fromJson(Map<String, dynamic> json) => RaporBilgiAlani(
    alanId: json['alanId'] as String,
    onEtiket: json['onEtiket'] as String? ?? '',
    altMetin: json['altMetin'] as String? ?? '',
    goster: json['goster'] as bool? ?? true,
    konum: json['konum'] as String? ?? 'ustOrta',
    sabitMetin: json['sabitMetin'] as String?,
  );
}

class RaporTabloSutunu {
  RaporTabloSutunu({
    required this.alanId,
    required this.baslik,
    this.genislik = 2,
    this.goster = true,
  });

  String alanId;
  String baslik;
  double genislik;
  bool goster;

  Map<String, dynamic> toJson() => {
    'alanId': alanId, 'baslik': baslik, 'genislik': genislik, 'goster': goster,
  };

  factory RaporTabloSutunu.fromJson(Map<String, dynamic> json) => RaporTabloSutunu(
    alanId: json['alanId'] as String,
    baslik: json['baslik'] as String,
    genislik: (json['genislik'] as num?)?.toDouble() ?? 2,
    goster: json['goster'] as bool? ?? true,
  );
}

class RaporTasarimi {
  RaporTasarimi({
    required this.ad,
    required this.bilgiler,
    required this.sutunlar,
    this.yatay = false,
    this.tekSayfayaSigdir = true,
    this.yaziBoyutu = 10,
    this.satirYuksekligi = 26,
  });

  String ad;
  List<RaporBilgiAlani> bilgiler;
  List<RaporTabloSutunu> sutunlar;
  bool yatay;
  bool tekSayfayaSigdir;
  double yaziBoyutu;
  double satirYuksekligi;

  List<RaporTabloSutunu> get gorunenSutunlar => sutunlar.where((s) => s.goster).toList();

  void dogrula(RaporTanimi tanim) {
    tanim.dogrula();
    if (ad.trim().isEmpty || ad.length > 80) {
      throw const FormatException('Şablon adı 1–80 karakter olmalı.');
    }
    if (bilgiler.length > 16) {
      throw const FormatException('En fazla 16 bilgi alanı eklenebilir.');
    }
    if (sutunlar.isEmpty || sutunlar.length > 16) {
      throw const FormatException('1–16 sütun seçin.');
    }
    if (gorunenSutunlar.isEmpty) {
      throw const FormatException('En az bir görünür sütun seçin.');
    }
    if (!yaziBoyutu.isFinite || yaziBoyutu < 6 || yaziBoyutu > 18 ||
        !satirYuksekligi.isFinite || satirYuksekligi < 16 || satirYuksekligi > 100) {
      throw const FormatException('Yazı boyutu 6–18, satır yüksekliği 16–100 olmalı.');
    }
    final bilgiKatalogu = {for (final alan in tanim.bilgiAlanlari) alan.id: alan};
    final sutunKimlikleri = tanim.sutunAlanlari.map((a) => a.id).toSet();
    for (final bilgi in bilgiler) {
      if (!bilgiKatalogu.containsKey(bilgi.alanId) ||
          bilgi.onEtiket.length > 160 || bilgi.altMetin.length > 160) {
        throw const FormatException('Bilgi alanı katalogda bulunmalı; etiket ve alt metin en fazla 160 karakter olmalı.');
      }
      if (bilgi.sabitMetin != null &&
          (!bilgiKatalogu[bilgi.alanId]!.serbestMetin || bilgi.sabitMetin!.length > 160)) {
        throw const FormatException('Sabit metin yalnız serbest metin alanında kullanılabilir ve en fazla 160 karakter olmalı.');
      }
      if (!RaporBilgiAlani.konumlar.containsKey(bilgi.konum)) {
        throw const FormatException('Bilgi alanının konumu geçersiz.');
      }
    }
    for (final sutun in sutunlar) {
      if (!sutunKimlikleri.contains(sutun.alanId) ||
          sutun.baslik.trim().isEmpty || sutun.baslik.length > 50 ||
          !sutun.genislik.isFinite || sutun.genislik < 1 || sutun.genislik > 8) {
        throw const FormatException('Sütun katalogda bulunmalı; başlık 1–50 karakter, genişlik 1–8 arasında olmalı.');
      }
    }
  }

  Map<String, dynamic> toJson(String raporId) => {
    'surum': 1, 'raporId': raporId, 'ad': ad,
    'bilgiler': bilgiler.map((b) => b.toJson()).toList(),
    'sutunlar': sutunlar.map((s) => s.toJson()).toList(),
    'yatay': yatay, 'tekSayfayaSigdir': tekSayfayaSigdir,
    'yaziBoyutu': yaziBoyutu, 'satirYuksekligi': satirYuksekligi,
  };

  factory RaporTasarimi.fromJson(Map<String, dynamic> json, RaporTanimi tanim) {
    if (json['surum'] != 1) {
      throw const FormatException('Rapor tasarımı sürümü desteklenmiyor.');
    }
    if (json['raporId'] != tanim.id) {
      throw const FormatException('Bu tasarım farklı bir rapora ait.');
    }
    try {
      final tasarim = RaporTasarimi(
        ad: json['ad'] as String,
        bilgiler: (json['bilgiler'] as List).map((b) =>
          RaporBilgiAlani.fromJson(Map<String, dynamic>.from(b as Map))).toList(),
        sutunlar: (json['sutunlar'] as List).map((s) =>
          RaporTabloSutunu.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
        yatay: json['yatay'] as bool? ?? false,
        tekSayfayaSigdir: json['tekSayfayaSigdir'] as bool? ?? true,
        yaziBoyutu: (json['yaziBoyutu'] as num?)?.toDouble() ?? 10,
        satirYuksekligi: (json['satirYuksekligi'] as num?)?.toDouble() ?? 26,
      );
      tasarim.dogrula(tanim);
      return tasarim;
    } on TypeError {
      throw const FormatException('Rapor tasarımının JSON alanları geçersiz.');
    } on ArgumentError {
      throw const FormatException('Rapor tasarımının JSON alanları geçersiz.');
    }
  }

  RaporTasarimi kopya(RaporTanimi tanim) => RaporTasarimi.fromJson(toJson(tanim.id), tanim);
}
