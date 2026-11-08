import 'dart:typed_data';

enum OdevGorevTuru {
  normalOdev('NormalOdev', 'Normal ödev'),
  rutinKontrol('RutinKontrol', 'Haftalık uygulama / rutin kontrol'),
  proje('Proje', 'Proje ödevi'),
  performans('Performans', 'Performans / uygulama görevi');

  const OdevGorevTuru(this.kayitDegeri, this.baslik);
  final String kayitDegeri;
  final String baslik;

  static OdevGorevTuru oku(Object? deger) => values.firstWhere(
    (tur) => tur.kayitDegeri == deger,
    orElse: () => throw FormatException('Geçersiz görev türü: $deger'),
  );
}

enum OdevKontrolDurumu {
  yapti('Yapti', '+', 'Tam'),
  kismen('Kismen', '±', 'Yarı'),
  yapmadi('Yapmadi', '−', 'Eksik'),
  gelmedi('Gelmedi', 'G', 'Gelmedi'),
  mazeretli('Mazeretli', 'M', 'Mazeretli'),
  kontrolEdilmedi('KontrolEdilmedi', '·', 'Henüz kontrol edilmedi'),
  manuel('Manuel', 'P', 'Manuel puan');

  const OdevKontrolDurumu(this.kayitDegeri, this.sembol, this.baslik);
  final String kayitDegeri;
  final String sembol;
  final String baslik;

  bool get degerlendirmeDisi => this == gelmedi || this == mazeretli;
  static const hizli = [yapti, kismen, yapmadi, gelmedi, mazeretli];
  static const secilebilir = [
    yapti,
    kismen,
    yapmadi,
    gelmedi,
    mazeretli,
    kontrolEdilmedi,
    manuel,
  ];
  bool get bekliyor => this == kontrolEdilmedi;
  bool get puanlanabilir => !degerlendirmeDisi && !bekliyor;

  static OdevKontrolDurumu oku(Object? deger) => values.firstWhere(
    (durum) => durum.kayitDegeri == deger,
    orElse: () => throw FormatException('Geçersiz kontrol durumu: $deger'),
  );
}

/// Gün alanları SQLite'ta saat dilimi dönüşümü yapılmadan YYYY-MM-DD tutulur.
String odevTarihYaz(DateTime tarih) {
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
  if (tarih == null || odevTarihYaz(tarih) != metin) {
    throw FormatException('Geçersiz ödev tarihi: $deger');
  }
  return tarih;
}

class OdevDersSecenegi {
  const OdevDersSecenegi({required this.dersId, required this.dersAdi});
  final int dersId;
  final String dersAdi;

  factory OdevDersSecenegi.fromMap(Map<String, Object?> map) =>
      OdevDersSecenegi(
        dersId: map['DersId'] as int,
        dersAdi: map['DersAdi'] as String,
      );
}

class OdevTanim {
  const OdevTanim({
    required this.odevId,
    required this.ogretmenProfilId,
    required this.egitimOgretimYili,
    required this.dersId,
    required this.sinifSubeId,
    required this.gorevTuru,
    required this.baslik,
    required this.baslangicTarihi,
    required this.aktif,
    required this.olusturmaTarihi,
    this.donem,
    this.aciklama,
    this.teslimTarihi,
    this.guncellemeTarihi,
    this.tamamlandi = false,
    this.dersUygulamalari = false,
  });

  final int odevId, ogretmenProfilId, dersId, sinifSubeId;
  final int? donem;
  final String egitimOgretimYili, baslik, olusturmaTarihi;
  final String? aciklama, guncellemeTarihi;
  final OdevGorevTuru gorevTuru;
  final DateTime baslangicTarihi;
  final DateTime? teslimTarihi;
  final bool aktif;
  final bool tamamlandi;
  final bool dersUygulamalari;

  factory OdevTanim.fromMap(Map<String, Object?> map) => OdevTanim(
    odevId: map['OdevId'] as int,
    ogretmenProfilId: map['OgretmenProfilId'] as int,
    egitimOgretimYili: map['EgitimOgretimYili'] as String,
    dersId: map['DersId'] as int,
    sinifSubeId: map['SinifSubeId'] as int,
    donem: map['Donem'] as int?,
    tamamlandi: map['Tamamlandi'] == 1,
    dersUygulamalari: map['DersUygulamalari'] == 1,
    gorevTuru: OdevGorevTuru.oku(map['GorevTuru']),
    baslik: map['Baslik'] as String,
    aciklama: map['Aciklama'] as String?,
    baslangicTarihi: _tarihOku(map['BaslangicTarihi']),
    teslimTarihi: map['TeslimTarihi'] == null
        ? null
        : _tarihOku(map['TeslimTarihi']),
    aktif: map['Aktif'] == 1,
    olusturmaTarihi: map['OlusturmaTarihi'] as String,
    guncellemeTarihi: map['GuncellemeTarihi'] as String?,
  );
}

class OdevOgrenci {
  const OdevOgrenci({
    required this.odevOgrenciId,
    required this.odevId,
    required this.ogrenciId,
    required this.okulNo,
    required this.ad,
    required this.soyad,
    required this.aktif,
    this.fotoVerisi,
    this.fotoYolu,
  });
  final int odevOgrenciId, odevId, ogrenciId;
  final String okulNo, ad, soyad;
  final Uint8List? fotoVerisi;
  final String? fotoYolu;
  final bool aktif;
  String get adSoyad => '$ad $soyad'.trim();

  /// OdevOgrenci ile Ogrenci birleşiminden okunur; Aktif katılım durumudur.
  factory OdevOgrenci.fromMap(Map<String, Object?> map) => OdevOgrenci(
    odevOgrenciId: map['OdevOgrenciId'] as int,
    odevId: map['OdevId'] as int,
    ogrenciId: map['OgrenciId'] as int,
    okulNo: map['OkulNo'] as String,
    ad: map['Ad'] as String,
    soyad: map['Soyad'] as String,
    fotoVerisi: map['FotoVerisi'] is List<int>
        ? Uint8List.fromList(map['FotoVerisi'] as List<int>)
        : null,
    fotoYolu: map['DosyaYolu'] as String?,
    aktif: map['Aktif'] == 1,
  );
}

class OdevKontrol {
  const OdevKontrol({
    required this.odevKontrolId,
    required this.odevId,
    required this.kontrolTarihi,
    required this.siraNo,
    required this.aktif,
    this.aciklama,
  });
  final int odevKontrolId, odevId, siraNo;
  final DateTime kontrolTarihi;
  final String? aciklama;
  final bool aktif;

  factory OdevKontrol.fromMap(Map<String, Object?> map) => OdevKontrol(
    odevKontrolId: map['OdevKontrolId'] as int,
    odevId: map['OdevId'] as int,
    kontrolTarihi: _tarihOku(map['KontrolTarihi']),
    siraNo: map['SiraNo'] as int,
    aciklama: map['Aciklama'] as String?,
    aktif: map['Aktif'] == 1,
  );
}

class OdevKontrolSonuc {
  const OdevKontrolSonuc({
    required this.odevKontrolSonucId,
    required this.odevId,
    required this.odevKontrolId,
    required this.ogrenciId,
    required this.durum,
    this.aciklama,
    this.notDegeri,
  });
  final int odevKontrolSonucId, odevId, odevKontrolId, ogrenciId;
  final OdevKontrolDurumu durum;
  final String? aciklama;
  final int? notDegeri;
  double? get puan => durum.degerlendirmeDisi || durum.bekliyor
      ? null
      : notDegeri != null
      ? (notDegeri! < 0 ? 0 : notDegeri!).toDouble()
      : durum == OdevKontrolDurumu.yapti
      ? 10
      : durum == OdevKontrolDurumu.kismen
      ? 5
      : 0;
  String get gosterim => durum == OdevKontrolDurumu.gelmedi
      ? 'G (Gelmedi)'
      : durum == OdevKontrolDurumu.mazeretli
      ? 'M (Mazeretli)'
      : durum == OdevKontrolDurumu.manuel
      ? '${notDegeri!}'
      : durum.bekliyor
      ? '—'
      : durum.sembol;
  static OdevKontrolDurumu notDurumu(int? n, Object? eski) => n == null
      ? OdevKontrolDurumu.oku(eski)
      : switch (n) {
          < 0 || > 10 => throw FormatException('Geçersiz ödev puanı: $n'),
          10 => OdevKontrolDurumu.yapti,
          5 => OdevKontrolDurumu.kismen,
          0 => OdevKontrolDurumu.yapmadi,
          _ => OdevKontrolDurumu.manuel,
        };
  static int? hizliNot(OdevKontrolDurumu d) => switch (d) {
    OdevKontrolDurumu.yapti => 10,
    OdevKontrolDurumu.kismen => 5,
    OdevKontrolDurumu.yapmadi => 0,
    _ => null,
  };

  factory OdevKontrolSonuc.fromMap(Map<String, Object?> map) =>
      OdevKontrolSonuc(
        odevKontrolSonucId: map['OdevKontrolSonucId'] as int,
        odevId: map['OdevId'] as int,
        odevKontrolId: map['OdevKontrolId'] as int,
        ogrenciId: map['OgrenciId'] as int,
        durum: notDurumu(map['NotDegeri'] as int?, map['Durum']),
        notDegeri: map['NotDegeri'] as int?,
        aciklama: map['Aciklama'] as String?,
      );
}

class OdevSonucGirdisi {
  const OdevSonucGirdisi({
    required this.ogrenciId,
    required this.durum,
    this.aciklama,
    this.notDegeri,
  });
  final int? notDegeri;
  final int ogrenciId;
  final OdevKontrolDurumu durum;
  final String? aciklama;
}
