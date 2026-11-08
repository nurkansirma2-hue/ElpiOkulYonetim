/// Excel'den gelen metin korunur; tür ve şeflik tanımı tahmin edilmez.
class SeflikProgramSaatiAdayi {
  const SeflikProgramSaatiAdayi({
    required this.gun,
    required this.dersSaatiNo,
    required this.hamMetin,
  });

  final String gun;
  final int dersSaatiNo;
  final String hamMetin;
}

class SeflikProgramSaatiGirdisi extends SeflikProgramSaatiAdayi {
  const SeflikProgramSaatiGirdisi({
    required super.gun,
    required super.dersSaatiNo,
    required super.hamMetin,
    required this.baslangic,
    required this.bitis,
  });

  final String baslangic;
  final String bitis;
}

/// Program başlangıcından itibaren geçerlidir; bitiş yeni programla kapanır.
class SeflikProgramiImportu {
  SeflikProgramiImportu({
    required this.baslangicTarihi,
    this.bitisTarihi,
    required List<SeflikProgramSaatiGirdisi> saatler,
  }) : saatler = List.unmodifiable(saatler);

  final DateTime baslangicTarihi;
  final DateTime? bitisTarihi;
  final List<SeflikProgramSaatiGirdisi> saatler;
}

enum SeflikTuru {
  alan('Alan', 'Alan Şefliği'),
  atolyeLaboratuvar('AtolyeLaboratuvar', 'Atölye/Laboratuvar Şefliği');

  const SeflikTuru(this.kayitDegeri, this.baslik);
  final String kayitDegeri;
  final String baslik;

  static SeflikTuru oku(Object? deger) => values.firstWhere(
    (tur) => tur.kayitDegeri == deger,
    orElse: () => throw FormatException('Geçersiz şeflik türü: $deger'),
  );
}

enum SeflikMekanTuru {
  atolye('Atolye', 'Atölye'),
  laboratuvar('Laboratuvar', 'Laboratuvar');

  const SeflikMekanTuru(this.kayitDegeri, this.baslik);
  final String kayitDegeri;
  final String baslik;

  static SeflikMekanTuru oku(Object? deger) => values.firstWhere(
    (tur) => tur.kayitDegeri == deger,
    orElse: () => throw FormatException('Geçersiz mekân türü: $deger'),
  );
}

/// Takvim günü saat dilimi dönüşümü yapılmadan YYYY-MM-DD olarak saklanır.
String seflikTarihYaz(DateTime tarih) {
  if (tarih.year < 1 || tarih.year > 9999) {
    throw ArgumentError('Tarih yılı 1 ile 9999 arasında olmalıdır.');
  }
  return '${tarih.year.toString().padLeft(4, '0')}-'
      '${tarih.month.toString().padLeft(2, '0')}-'
      '${tarih.day.toString().padLeft(2, '0')}';
}

DateTime _tarihOku(Object? deger) {
  final metin = deger?.toString() ?? '';
  final tarih = DateTime.tryParse(metin);
  if (tarih == null || seflikTarihYaz(tarih) != metin) {
    throw FormatException('Geçersiz şeflik tarihi: $deger');
  }
  return tarih;
}

bool _aktifOku(Object? deger) {
  if (deger == 1) return true;
  if (deger == 0) return false;
  throw FormatException('Geçersiz aktiflik değeri: $deger');
}

class BireyselSeflikOturumu {
  const BireyselSeflikOturumu({
    required this.ogretmenProfilId,
    required this.egitimOgretimYili,
  });

  final int ogretmenProfilId;
  final String egitimOgretimYili;
}

class SeflikTanim {
  const SeflikTanim({
    required this.seflikId,
    required this.ogretmenProfilId,
    required this.egitimOgretimYili,
    required this.seflikTuru,
    required this.haftalikSaat,
    required this.baslangicTarihi,
    required this.aktif,
    required this.olusturmaTarihi,
    this.bitisTarihi,
    this.guncellemeTarihi,
  });

  final int seflikId, ogretmenProfilId, haftalikSaat;
  final String egitimOgretimYili, olusturmaTarihi;
  final SeflikTuru seflikTuru;
  final DateTime baslangicTarihi;
  final DateTime? bitisTarihi;
  final bool aktif;
  final String? guncellemeTarihi;

  factory SeflikTanim.fromMap(Map<String, Object?> map) {
    final saat = map['HaftalikSaat'] as int;
    final baslangic = _tarihOku(map['BaslangicTarihi']);
    final bitis = map['BitisTarihi'] == null
        ? null
        : _tarihOku(map['BitisTarihi']);
    if (saat <= 0 || (bitis != null && bitis.isBefore(baslangic))) {
      throw const FormatException(
        'Kayıtlı şeflik saati veya tarih aralığı geçersiz.',
      );
    }
    return SeflikTanim(
      seflikId: map['SeflikId'] as int,
      ogretmenProfilId: map['OgretmenProfilId'] as int,
      egitimOgretimYili: map['EgitimOgretimYili'] as String,
      seflikTuru: SeflikTuru.oku(map['SeflikTuru']),
      haftalikSaat: saat,
      baslangicTarihi: baslangic,
      bitisTarihi: bitis,
      aktif: _aktifOku(map['Aktif']),
      olusturmaTarihi: map['OlusturmaTarihi'] as String,
      guncellemeTarihi: map['GuncellemeTarihi'] as String?,
    );
  }
}

class SeflikMekan {
  const SeflikMekan({
    required this.mekanId,
    required this.ogretmenProfilId,
    required this.mekanAdi,
    required this.mekanTuru,
    required this.aktif,
    required this.olusturmaTarihi,
    this.aciklama,
    this.guncellemeTarihi,
  });

  final int mekanId, ogretmenProfilId;
  final String mekanAdi, olusturmaTarihi;
  final SeflikMekanTuru mekanTuru;
  final bool aktif;
  final String? aciklama, guncellemeTarihi;

  factory SeflikMekan.fromMap(Map<String, Object?> map) => SeflikMekan(
    mekanId: map['MekanId'] as int,
    ogretmenProfilId: map['OgretmenProfilId'] as int,
    mekanAdi: map['MekanAdi'] as String,
    mekanTuru: SeflikMekanTuru.oku(map['MekanTuru']),
    aktif: _aktifOku(map['Aktif']),
    aciklama: map['Aciklama'] as String?,
    olusturmaTarihi: map['OlusturmaTarihi'] as String,
    guncellemeTarihi: map['GuncellemeTarihi'] as String?,
  );
}

class SeflikDetay {
  SeflikDetay({required this.tanim, required List<SeflikMekan> mekanlar})
    : mekanlar = List<SeflikMekan>.unmodifiable(mekanlar);

  final SeflikTanim tanim;
  final List<SeflikMekan> mekanlar;
}
