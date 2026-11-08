import 'dart:typed_data';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:excel2003/excel2003.dart';
// Paket OLE okuyucusunu dışa aktarmıyor; aynı okuyucuyu kullanarak kopyalamayı önle.
// ignore: implementation_imports
import 'package:excel2003/src/ole2/ole2_reader.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite/sqflite.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/import_sonuc.dart';
import '../models/bireysel_seflik.dart';
import '../models/ortak_import.dart';
import '../models/mesajlasma.dart';
import 'calisma_modu_service.dart';
import 'xls_import_okuyucu.dart';

class BireyselGunlukDersSaatiAdayi {
  const BireyselGunlukDersSaatiAdayi({
    required this.gun,
    required this.dersSaatiNo,
    required this.baslangic,
    required this.bitis,
    required this.hamMetin,
  });

  final String gun;
  final int dersSaatiNo;
  final String baslangic;
  final String bitis;
  final String hamMetin;

  String get saatAraligi => '$baslangic - $bitis';
}

class BireyselDersProgramiKaydi {
  const BireyselDersProgramiKaydi({
    required this.gun,
    required this.dersSaatiNo,
    required this.saatAraligi,
    required this.dersAdi,
    required this.sinif,
    required this.derslik,
  });

  final String gun;
  final int dersSaatiNo;
  final String saatAraligi;
  final String dersAdi;
  final String sinif;
  final String derslik;
  bool get gorevMi => dersAdi == 'Koordinatörlük' && sinif.isEmpty;
}

class BireyselDersProgramiOnIzleme {
  const BireyselDersProgramiOnIzleme({
    required this.sayfaSayisi,
    required this.doluHucreSayisi,
    required this.ogretmenBulundu,
    required this.ogretmenEslesmeleri,
    required this.gunlukDersSaatAdaylari,
    required this.dersler,
    this.seflikSaatleri = const [],
    this.uyarilar = const [],
    this.baslangicTarihi,
  });

  final int sayfaSayisi;
  final int doluHucreSayisi;
  final bool ogretmenBulundu;
  final List<String> ogretmenEslesmeleri;
  final List<BireyselGunlukDersSaatiAdayi> gunlukDersSaatAdaylari;
  final List<BireyselDersProgramiKaydi> dersler;
  final List<SeflikProgramSaatiAdayi> seflikSaatleri;
  final List<String> uyarilar;
  final DateTime? baslangicTarihi;
}

class BireyselOgrenciOnIzleme {
  BireyselOgrenciOnIzleme._(this._ogretmenId, this._yil, this._kayitlar,
      this._hatalar, this._kapsamDisi, this._tekrar,
      {Set<String> ekSinifKodlari = const {}})
      : _ekSinifKodlari = Set.unmodifiable(ekSinifKodlari);

  final int _ogretmenId;
  final String _yil;
  final List<Map<String, dynamic>> _kayitlar;
  final List<String> _hatalar;
  final int _kapsamDisi;
  final int _tekrar;
  final Set<String> _ekSinifKodlari;

  ImportSonuc get sonuc => ImportSonuc.fromJson({
    'basarili': _hatalar.isEmpty && _kayitlar.isNotEmpty,
    'kayitTipi': 'Öğrenci',
    'mesaj': _hatalar.isEmpty
        ? 'Ön izleme hazır. Kontrol edip onayladığınızda cihazınıza kaydedilir.'
        : 'Hataları düzeltip dosyayı yeniden seçin. Henüz kayıt yapılmadı.',
    'kayitlar': _kayitlar,
    'hataliKayit': _hatalar.length,
    'hataListesi': _hatalar,
    'islemAdimlari': [
      'Eğitim yılı: $_yil',
      'Ders verdiğiniz sınıflardaki öğrenci sayısı: ${_kayitlar.where((k) => !_ekSinifKodlari.contains(k['sinif'])).length}',
      if (_ekSinifKodlari.isNotEmpty)
        'Ders programınız dışındaki sınıflar Kaydet adımında ayrıca seçilebilir.',
      'Ders programınız dışındaki satırlar: $_kapsamDisi',
      'Birleştirilen aynı öğrenci satırları: $_tekrar',
      'Dosyada olmayan mevcut öğrenciler silinmez.',
    ],
  });
}

class BireyselFotoKaydi {
  BireyselFotoKaydi._(this.ogrenciId, this.okulNo, this.adSoyad, this.sinif,
      this.mimeTuru, Uint8List veri) : fotoVerisi = veri.asUnmodifiableView();
  final int ogrenciId;
  final String okulNo, adSoyad, sinif, mimeTuru;
  final Uint8List fotoVerisi;
}

class BireyselFotoOgrenciHucresi {
  BireyselFotoOgrenciHucresi({
    required this.sayfa,
    required this.satir,
    required this.sutun,
    required this.okulNo,
    required this.ad,
    required this.soyad,
    Uint8List? fotoVerisi,
  }) : fotoVerisi = fotoVerisi?.asUnmodifiableView();

  final int sayfa, satir, sutun;
  final String okulNo, ad, soyad;
  final Uint8List? fotoVerisi;
  String get id => '$sayfa:$satir:$sutun';
  String get adSoyad => '$ad $soyad';
}

class BireyselFotoExcelDosyasi {
  BireyselFotoExcelDosyasi(
    List<XlsImportSayfasi> sayfalar,
    List<BireyselFotoOgrenciHucresi> hucreler,
  ) : sayfalar = List.unmodifiable(sayfalar),
      hucreler = List.unmodifiable(hucreler);

  final List<XlsImportSayfasi> sayfalar;
  final List<BireyselFotoOgrenciHucresi> hucreler;
}

class BireyselFotoOnIzleme {
  BireyselFotoOnIzleme._(
    this._ogretmenId,
    this._yil,
    List<Map<String, dynamic>> ogrenciKayitlari,
    List<BireyselFotoKaydi> kayitlar,
    List<String> hatalar,
    this._kapsamDisi, {
    List<String> uyarilar = const [],
  })  : ogrenciKayitlari = List.unmodifiable(ogrenciKayitlari),
        kayitlar = List.unmodifiable(kayitlar),
        hatalar = List.unmodifiable(hatalar),
        uyarilar = List.unmodifiable(uyarilar);

  final int _ogretmenId, _kapsamDisi;
  final String _yil;
  final List<Map<String, dynamic>> ogrenciKayitlari;
  final List<BireyselFotoKaydi> kayitlar;
  final List<String> hatalar;
  final List<String> uyarilar;

  bool get kaydedilebilir =>
      ogrenciKayitlari.isNotEmpty && kayitlar.isNotEmpty && hatalar.isEmpty;

  ImportSonuc get sonuc => ImportSonuc.fromJson({
    'basarili': kaydedilebilir,
    'kayitTipi': 'Fotoğraf',
    'mesaj': kaydedilebilir
        ? 'Kayıtlı öğrenci ve fotoğraf eşleşmelerini kontrol edip onaylayın.'
        : 'Fotoğraflar kaydedilmedi. Eşleştirme uyarılarını kontrol edin.',
    'toplamKayit': kayitlar.length,
    'hataliKayit': hatalar.length,
    'hataListesi': hatalar,
    'islemAdimlari': [
      'Eğitim yılı: $_yil',
      'Öğrencilerim listesiyle eşleşen fotoğraf: ${kayitlar.length}',
      'Eşleşmeyen veya seçilmeyen fotoğraf: $_kapsamDisi',
      'Yalnız onaylanan mevcut öğrencilerin fotoğrafları eklenir veya güncellenir.',
      'Öğrenci bilgileri korunur. Eşleşmeleri Excel üzerinden elle de seçebilirsiniz.',
      ...uyarilar.take(10),
      if (uyarilar.length > 10) '${uyarilar.length - 10} ek eşleştirme uyarısı daha var.',
    ],
  });
}

class _XlsFotoAdayi {
  _XlsFotoAdayi(this.okulNo, this.veri, this.mime, this.yer, this.hata);
  final String? okulNo;
  final Uint8List? veri;
  final String mime, yer, hata;
}

class _OfficeArtKaydi {
  _OfficeArtKaydi(this.tur, this.surum, this.ornek, this.veri);
  final int tur, surum, ornek;
  final Uint8List veri;
}


class BireyselImportService {
  BireyselImportService._();

  // Boş/olmayan opsiyonel kolon mevcut veli bilgisini silmez.
  static Map<String, Object?> _iletisimVerisi(Map<String, dynamic> kayit) {
    final ad = (kayit['veliAdi'] ?? '').toString().trim();
    final telefon = (kayit['veliTelefonu'] ?? '').toString().trim();
    if (ad.length > 200 || telefon.length > 50 ||
        (telefon.isNotEmpty && mesajTelefonNormalize(telefon) == null)) {
      throw const FormatException('Veli adı veya telefonu geçersiz. Ön izlemeyi düzeltin.');
    }
    return {if (ad.isNotEmpty || telefon.isNotEmpty) 'VeliTuru': 'Diger',
      if (ad.isNotEmpty) 'VeliAdi': ad,
      if (telefon.isNotEmpty) 'VeliTelefonu': telefon};
  }

  static Future<List<Map<String, Object?>>> _fotoOgrencileri(
      DatabaseExecutor db, int ogretmenId, String yil) async {
    final ekIdler = await ogrenciEkSinifIdleriniGetir(db, ogretmenId, yil);
    final ekKosulu = ekIdler.isEmpty ? ''
        : ' OR s.SinifSubeId IN (${List.filled(ekIdler.length, '?').join(',')})';
    return db.rawQuery('''
    SELECT DISTINCT o.OgrenciId, o.OkulNo, o.Ad, o.Soyad, s.SinifKodu, s.SinifSubeId
    FROM Ogrenci o
    INNER JOIN OgrenciSinifKayit k ON k.OgrenciId = o.OgrenciId AND k.Aktif = 1
    INNER JOIN SinifSube s ON s.SinifSubeId = k.SinifSubeId AND s.Aktif = 1
    WHERE o.Aktif = 1 AND k.EgitimOgretimYili = ? AND s.EgitimOgretimYili = ?
      AND (EXISTS (SELECT 1 FROM GecerliDersProgrami dp WHERE dp.SinifSubeId = s.SinifSubeId
        AND dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ? AND dp.Aktif = 1)$ekKosulu)
    ''', [yil, yil, ogretmenId, yil, ...ekIdler]);
  }

  static Future<BireyselFotoOnIzleme> fotoOnIzlemeHazirla({
    required String dosyaAdi,
    required Uint8List dosyaBytes,
    Map<String, String>? sinifHucreleri,
  }) async {
    final atamalar = sinifHucreleri == null
        ? null : Map<String, String>.unmodifiable(sinifHucreleri);
    await _bireyselModuDogrula();
    if (!dosyaAdi.toLowerCase().endsWith('.xls')) {
      throw const FormatException('Fotoğraf import için fotoğraflı e-Okul XLS dosyasını seçin.');
    }
    if (dosyaBytes.isEmpty || dosyaBytes.length > 50 * 1024 * 1024) {
      throw const FormatException('Dosya boş veya 50 MB sınırından büyük.');
    }
    final db = await LocalDatabase.instance.database;
    final profil = await _ogrenciImportProfili(db);
    final id = profil['OgretmenProfilId'] as int;
    final yil = profil['EgitimOgretimYili'].toString();
    final ogrenciler = await _fotoOgrencileri(db, id, yil);
    if (ogrenciler.isEmpty) {
      throw StateError('Önce Öğrenci Import ile öğrencilerinizi kaydedin. Fotoğraflar Öğrencilerim listesindeki kayıtlarla eşleştirilir.');
    }
    final kaynak = Uint8List.fromList(dosyaBytes);
    final (hucreler, adaylar) = await Isolate.run(() => (
      _fotoOgrenciHucreleriniOku(XlsImportOkuyucu.oku(kaynak), const []),
      _xlsFotograflariOku(kaynak),
    ));
    final hucreHaritasi = {for (final h in hucreler) h.id: h};
    if (atamalar != null && atamalar.isEmpty) {
      throw StateError('Önce öğrenci hücrelerini seçip kayıtlı sınıflarına atayın.');
    }
    if (atamalar != null && atamalar.keys.any((k) => !hucreHaritasi.containsKey(k))) {
      throw const FormatException('Seçilen öğrenci hücreleri dosyayla uyuşmuyor. Yeniden seçin.');
    }
    final kaynakNolar = <String, List<BireyselFotoOgrenciHucresi>>{};
    for (final h in hucreler) {
      kaynakNolar.putIfAbsent(h.okulNo, () => []).add(h);
    }
    final seciliNolar = atamalar?.keys.map((k) => hucreHaritasi[k]!.okulNo).toSet();
    if (seciliNolar != null && seciliNolar.any((no) => kaynakNolar[no]!.length != 1)) {
      throw const FormatException('Seçilen bir okul numarası dosyada birden fazla öğrenci hücresinde var. Fotoğraf eşleşmesi belirsiz; tekrarları düzeltin.');
    }
    final mevcutNolar = <String, List<Map<String, Object?>>>{};
    for (final o in ogrenciler) {
      final no = int.tryParse(o['OkulNo'].toString())?.toString();
      if (no != null) mevcutNolar.putIfAbsent(no, () => []).add(o);
    }
    final fotoSayilari = <String, int>{};
    for (final a in adaylar) {
      if (a.okulNo != null) fotoSayilari[a.okulNo!] = (fotoSayilari[a.okulNo!] ?? 0) + 1;
    }
    final kayitlar = <BireyselFotoKaydi>[];
    final ogrenciKayitlari = <Map<String, dynamic>>[];
    final hatalar = <String>[];
    final uyarilar = <String>[];
    final kullanilan = <String>{};
    var atlanan = 0;
    for (final aday in adaylar) {
      final no = aday.okulNo;
      if (no == null || (seciliNolar != null && !seciliNolar.contains(no))) {
        atlanan++;
        continue;
      }
      String? sorun;
      final kaynaklar = kaynakNolar[no];
      final eslesmeler = mevcutNolar[no];
      if (aday.hata.isNotEmpty || aday.veri == null) {
        sorun = 'Fotoğraf okunamadı.';
      } else if (kaynaklar == null || kaynaklar.length != 1 || fotoSayilari[no] != 1) {
        sorun = 'Dosyadaki öğrenci veya fotoğraf eşleşmesi belirsiz.';
      } else if (eslesmeler == null || eslesmeler.isEmpty) {
        sorun = 'Öğrencilerim listesinde kayıt yok; önce Öğrenci Import yapın.';
      } else if (eslesmeler.length != 1) {
        sorun = 'Öğrencilerim listesinde aynı numara için birden fazla kayıt var.';
      } else {
        final o = eslesmeler.single;
        final h = kaynaklar.single;
        if (importNormalize(h.adSoyad) != importNormalize('${o['Ad']} ${o['Soyad']}')) {
          sorun = 'Okul numarası bulundu ancak ad soyad eşleşmedi.';
        } else if (atamalar != null &&
            _ogrenciSinifAnahtari(atamalar[h.id] ?? '') != _ogrenciSinifAnahtari(o['SinifKodu'].toString())) {
          sorun = 'Seçilen sınıf öğrencinin Öğrencilerim listesindeki sınıfıyla eşleşmiyor.';
        }
      }
      if (sorun == null) {
        try {
          final codec = await ui.instantiateImageCodec(aday.veri!, targetWidth: 128);
          try {
            final frame = await codec.getNextFrame();
            frame.image.dispose();
          } finally { codec.dispose(); }
        } catch (e) {
          sorun = 'Fotoğraf açılamadı. Orijinal hata: $e';
        }
      }
      if (sorun != null) {
        atlanan++;
        final mesaj = '$no: $sorun';
        if (seciliNolar != null) { hatalar.add(mesaj); }
        else { uyarilar.add(mesaj); }
        continue;
      }
      final o = eslesmeler!.single;
      kullanilan.add(no);
      final adSoyad = '${o['Ad']} ${o['Soyad']}';
      ogrenciKayitlari.add(Map<String, dynamic>.unmodifiable({
        'ogrenciId': o['OgrenciId'], 'okulNo': o['OkulNo'],
        'ad': o['Ad'], 'soyad': o['Soyad'], 'adSoyad': adSoyad,
        'sinif': o['SinifKodu'], 'sinifSubeId': o['SinifSubeId'],
      }));
      kayitlar.add(BireyselFotoKaydi._(o['OgrenciId'] as int,
        o['OkulNo'].toString(), adSoyad, o['SinifKodu'].toString(), aday.mime, aday.veri!));
    }
    if (seciliNolar != null) {
      for (final no in seciliNolar.difference(kullanilan)) {
        if (!hatalar.any((h) => h.startsWith('$no:'))) {
          hatalar.add('$no: Seçilen öğrenci hücresinin fotoğrafı eşleştirilemedi.');
        }
      }
    }
    if (kayitlar.isEmpty) hatalar.add('Öğrencilerim listesiyle güvenli biçimde eşleşen fotoğraf bulunamadı. Excel hücrelerinden elle eşleştirmeyi deneyebilirsiniz.');
    return BireyselFotoOnIzleme._(id, yil, ogrenciKayitlari,
      kayitlar, hatalar, atlanan, uyarilar: uyarilar);
  }

  static Future<List<String>> fotoImportSiniflariniGetir() async {
    await _bireyselModuDogrula();
    final db = await LocalDatabase.instance.database;
    final profil = await _ogrenciImportProfili(db);
    final ogrenciler = await _fotoOgrencileri(
      db, profil['OgretmenProfilId'] as int,
      profil['EgitimOgretimYili'].toString(),
    );
    if (ogrenciler.isEmpty) {
      throw StateError('Fotoğraf eklemek için önce Öğrenci Import ile öğrencileri yükleyin.');
    }
    final kodlar = ogrenciler.map((s) => s['SinifKodu'].toString()).toSet().toList();
    kodlar.sort((a, b) {
      final seviyeA = int.tryParse(a.split('-').first) ?? 0;
      final seviyeB = int.tryParse(b.split('-').first) ?? 0;
      final fark = seviyeA.compareTo(seviyeB);
      return fark == 0 ? a.compareTo(b) : fark;
    });
    return List.unmodifiable(kodlar);
  }

  /// Kaynak hücre adreslerini korur; ön izleme henüz kayıt yapmaz.
  static Future<BireyselFotoExcelDosyasi> fotoExcelOku(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('Dosya boş veya 50 MB sınırından büyük.');
    }
    final kaynak = Uint8List.fromList(bytes);
    return Isolate.run(() {
      final sayfalar = XlsImportOkuyucu.oku(kaynak);
      final fotograflar = _xlsFotograflariOku(kaynak);
      return BireyselFotoExcelDosyasi(
        sayfalar, _fotoOgrenciHucreleriniOku(sayfalar, fotograflar),
      );
    });
  }

  static List<BireyselFotoOgrenciHucresi> _fotoOgrenciHucreleriniOku(
    List<XlsImportSayfasi> sayfalar,
    List<_XlsFotoAdayi> fotograflar,
  ) {
    final sonuc = <BireyselFotoOgrenciHucresi>[];
    final noFotograflari = <String, List<_XlsFotoAdayi>>{};
    for (final foto in fotograflar) {
      if (foto.okulNo != null && foto.hata.isEmpty) {
        noFotograflari.putIfAbsent(foto.okulNo!, () => []).add(foto);
      }
    }
    for (var s = 0; s < sayfalar.length; s++) {
      final satirlar = sayfalar[s].satirlar;
      for (var r = 0; r < satirlar.length; r++) {
        for (var c = 0; c < satirlar[r].length; c++) {
          final metin = _ogrenciHucreMetni(satirlar[r][c]);
          final birlesik = _ogrenciKartBirlesikHucreAyir(metin);
          final no = int.tryParse(birlesik?[0] ?? metin);
          if (no == null || no <= 0 ||
              (birlesik == null && !RegExp(r'^\d+$').hasMatch(metin))) {
            continue;
          }
          final adSoyad = birlesik == null
              ? _ogrenciKartAdSoyadBul(satirlar, r, c)
              : [birlesik[1], birlesik[2]];
          if (adSoyad == null) continue;
          final eslesen = noFotograflari['$no'];
          sonuc.add(BireyselFotoOgrenciHucresi(
            sayfa: s, satir: r, sutun: c, okulNo: '$no',
            ad: adSoyad[0], soyad: adSoyad[1],
            fotoVerisi: eslesen?.length == 1 ? eslesen!.single.veri : null,
          ));
        }
      }
    }
    final noSayilari = <String, int>{};
    for (final hucre in sonuc) {
      noSayilari[hucre.okulNo] = (noSayilari[hucre.okulNo] ?? 0) + 1;
    }
    return List.unmodifiable([
      for (final hucre in sonuc)
        if (noSayilari[hucre.okulNo] == 1) hucre
        else BireyselFotoOgrenciHucresi(
          sayfa: hucre.sayfa, satir: hucre.satir, sutun: hucre.sutun,
          okulNo: hucre.okulNo, ad: hucre.ad, soyad: hucre.soyad,
        ),
    ]);
  }

  static Future<ImportSonuc> fotograflariKaydet(BireyselFotoOnIzleme onIzleme) async {
    await _bireyselModuDogrula();
    if (!onIzleme.kaydedilebilir) {
      throw StateError('Önce kayıtlı öğrencilerle geçerli fotoğraf eşleşmeleri hazırlayın.');
    }
    final db = await LocalDatabase.instance.database;
    return db.transaction((txn) async {
      final profil = await _ogrenciImportProfili(txn);
      if (profil['OgretmenProfilId'] != onIzleme._ogretmenId ||
          profil['EgitimOgretimYili'] != onIzleme._yil) {
        throw StateError('Öğretmen veya eğitim yılı değişti. Ön izlemeyi yenileyin.');
      }
      final ogrenciler = await _fotoOgrencileri(txn, onIzleme._ogretmenId, onIzleme._yil);
      final simdi = DateTime.now().toIso8601String();
      var eklenen = 0, guncellenen = 0;
      for (final foto in onIzleme.kayitlar) {
        final kaynaklar = onIzleme.ogrenciKayitlari.where((o) =>
          o['ogrenciId'] == foto.ogrenciId && o['okulNo'].toString() == foto.okulNo).toList();
        final mevcutOgrenciler = ogrenciler.where((o) =>
          int.tryParse(o['OkulNo'].toString()) == int.tryParse(foto.okulNo)).toList();
        if (kaynaklar.length != 1 || mevcutOgrenciler.length != 1) {
          throw StateError('Öğrenci veya sınıf kapsamı değişti. Fotoğraf ön izlemesini yenileyin.');
        }
        final k = kaynaklar.single, o = mevcutOgrenciler.single;
        if (o['OgrenciId'] != foto.ogrenciId || o['OkulNo'] != foto.okulNo ||
            o['Ad'] != k['ad'] || o['Soyad'] != k['soyad'] ||
            o['SinifSubeId'] != k['sinifSubeId'] || o['SinifKodu'] != foto.sinif ||
            k['sinif'] != foto.sinif || k['adSoyad'] != foto.adSoyad) {
          throw StateError('Öğrenci bilgileri veya sınıfı değişti. Fotoğraf ön izlemesini yenileyin.');
        }
        final mevcut = await txn.query('OgrenciFotograf',
          where: 'OgrenciId = ?', whereArgs: [foto.ogrenciId]);
        final veri = <String, Object?>{
          'OgrenciId': foto.ogrenciId, 'DosyaYolu': '',
          'DosyaAdi': '${foto.okulNo}.${foto.mimeTuru == 'image/png' ? 'png' : 'jpg'}',
          'FotoVerisi': foto.fotoVerisi, 'MimeTuru': foto.mimeTuru,
          'Aktif': 1, 'GuncellemeTarihi': simdi,
        };
        if (mevcut.isEmpty) {
          await txn.insert('OgrenciFotograf', {...veri, 'OlusturmaTarihi': simdi});
          eklenen++;
        } else {
          await txn.update('OgrenciFotograf', veri,
            where: 'OgrenciId = ?', whereArgs: [foto.ogrenciId]);
          guncellenen++;
        }
      }
      await _bireyselModuDogrula();
      return ImportSonuc.fromJson({
        'basarili': true, 'kayitTipi': 'Fotoğraf',
        'mesaj': 'Fotoğraflar Öğrencilerim listesindeki mevcut öğrencilere kaydedildi.',
        'toplamKayit': onIzleme.kayitlar.length, 'fotoKayit': onIzleme.kayitlar.length,
        'eklenenKayit': eklenen, 'guncellenenKayit': guncellenen,
        'islemAdimlari': ['Fotoğraf eklendi: $eklenen',
          'Fotoğraf güncellendi: $guncellenen', 'Öğrenci ve sınıf bilgileri korunmuştur.'],
      });
    });
  }

  // MS-XLS OfficeArtClientAnchorSheet, MS-ODRAW FBSE / FOPT(pib).
  // Hücre/OLE okuma mevcut excel2003 paketinden; burada yalnız çizimler okunur.
  static List<_XlsFotoAdayi> _xlsFotograflariOku(Uint8List bytes) {
    final ole = Ole2Reader()..openBytes(bytes);
    final entry = ole.findEntry('Workbook') ?? ole.findEntry('Book');
    if (entry == null) throw const FormatException('XLS çalışma kitabı bulunamadı.');
    final workbook = ole.readEntry(entry);
    final data = ByteData.sublistView(workbook);
    final global = BytesBuilder(copy: false);
    final cizimler = <int, BytesBuilder>{};
    final sayfaKonumlari = <int, int>{};
    var sayfa = -1;
    BytesBuilder? devam;
    for (var p = 0; p + 4 <= workbook.length;) {
      if (sayfaKonumlari.containsKey(p)) sayfa = sayfaKonumlari[p]!;
      final tur = data.getUint16(p, Endian.little), boy = data.getUint16(p + 2, Endian.little);
      final bas = p + 4, son = bas + boy;
      if (son > workbook.length) throw const FormatException('Eksik XLS kaydı.');
      if (tur == 0x85 && sayfa == -1 && boy >= 8) {
        sayfaKonumlari[data.getUint32(bas, Endian.little)] = sayfaKonumlari.length;
      }
      if (tur == 0xEB && sayfa == -1) {
        devam = global;
      } else if (tur == 0xEC && sayfa >= 0) {
        devam = cizimler.putIfAbsent(sayfa, () => BytesBuilder(copy: false));
      } else if (tur != 0x3C && tur != 0x5D) {
        devam = null;
      }

      if (devam != null && tur != 0x5D) {
        devam.add(Uint8List.sublistView(workbook, bas, son));
      }
      p = son;
    }
    final resimler = <(Uint8List?, String)>[];
    for (final kayit in _officeArtKayitlari(global.toBytes(), derin: true)) {
      if (kayit.tur != 0xF007) continue;
      final bse = kayit.veri;
      if (bse.length < 36) throw const FormatException('Eksik fotoğraf kaydı.');
      final bas = 36 + bse[33];
      if (bas + 8 > bse.length) { resimler.add((null, 'Gömülü olmayan fotoğraf desteklenmiyor.')); continue; }
      final blip = _officeArtKayitlari(Uint8List.sublistView(bse, bas)).first;
      final png = blip.tur == 0xF01E && [0x6E0, 0x6E1].contains(blip.ornek);
      final jpeg = blip.tur == 0xF01D && [0x46A, 0x46B, 0x6E2, 0x6E3].contains(blip.ornek);
      if (!png && !jpeg) { resimler.add((null, 'Fotoğraf biçimi desteklenmiyor; JPEG veya PNG olmalı.')); continue; }
      final offset = (blip.ornek.isOdd ? 32 : 16) + 1;
      if (offset >= blip.veri.length || blip.veri.length > 10 * 1024 * 1024) {
        resimler.add((null, 'Fotoğraf boş veya 10 MB sınırından büyük.')); continue;
      }
      resimler.add((Uint8List.fromList(blip.veri.sublist(offset)), png ? 'image/png' : 'image/jpeg'));
    }
    final reader = XlsReader.fromBytes(bytes);
    final sonuc = <_XlsFotoAdayi>[];
    for (final cizim in cizimler.entries) {
      final sheet = reader.sheet(cizim.key);
      final numaralar = <(String, int, int)>[];
      for (final cell in sheet.cells) {
        for (final m in RegExp(r'\b\d{1,10}\b').allMatches(_ogrenciHucreMetni(cell.value))) {
          final no = int.tryParse(m[0]!);
          if (no != null && no > 0) numaralar.add(('$no', cell.row, cell.col));
        }
      }
      for (final sekil in _officeArtKayitlari(cizim.value.toBytes(), derin: true)) {
        if (sekil.tur != 0xF004) continue;
        int? resimId, satir, sutun;
        for (final ozellik in _officeArtKayitlari(sekil.veri)) {
          final veri = ByteData.sublistView(ozellik.veri);
          if (ozellik.tur == 0xF00B) {
            if (ozellik.ornek * 6 > ozellik.veri.length) throw const FormatException('Eksik çizim özellikleri.');
            for (var i = 0; i < ozellik.ornek; i++) {
              final op = veri.getUint16(i * 6, Endian.little);
              if (op & 0x3FFF == 0x104) {
                if (op & 0x8000 != 0) throw const FormatException('Bağlantılı fotoğraf desteklenmiyor.');
                resimId = veri.getUint32(i * 6 + 2, Endian.little);
              }
            }
          } else if (ozellik.tur == 0xF010 && ozellik.veri.length == 18) {
            sutun = veri.getUint16(2, Endian.little);
            satir = veri.getUint16(6, Endian.little);
          }
        }
        if (resimId == null) continue;
        final yer = 'Sayfa ${cizim.key + 1}, fotoğraf satırı ${(satir ?? -1) + 1}';
        if (satir == null || sutun == null || resimId < 1 || resimId > resimler.length) {
          sonuc.add(_XlsFotoAdayi(null, null, '', yer, 'Fotoğraf konumu veya bağlantısı okunamadı.')); continue;
        }
        final foto = resimler[resimId - 1];
        if (foto.$1 == null) { sonuc.add(_XlsFotoAdayi(null, null, '', yer, foto.$2)); continue; }
        // Yakın hücre sırası korunur; uzak hücreye düşülmez.
        var adaylar = numaralar.where((n) => n.$2 >= satir! && n.$2 <= satir + 12 && (n.$3 - sutun!).abs() <= 3).toList();
        if (adaylar.isEmpty) {
          adaylar = numaralar.where((n) => n.$2 >= satir! - 1 && n.$2 <= satir + 15 && (n.$3 - sutun!).abs() <= 6).toList();
        }
        adaylar.sort((a, b) {
          final fark = (a.$2 - satir!).abs().compareTo((b.$2 - satir).abs());
          return fark != 0 ? fark : (a.$3 - sutun!).abs().compareTo((b.$3 - sutun).abs());
        });
        final yakin = adaylar.isEmpty ? <(String, int, int)>[] : adaylar.where((n) =>
          (n.$2 - satir!).abs() == (adaylar.first.$2 - satir).abs() &&
          (n.$3 - sutun!).abs() == (adaylar.first.$3 - sutun).abs()).toList();
        final nolar = yakin.map((n) => n.$1).toSet();
        sonuc.add(nolar.length == 1
          ? _XlsFotoAdayi(nolar.single, foto.$1, foto.$2, yer, '')
          : _XlsFotoAdayi(null, null, '', yer, 'Okul numarası bulunamadı veya eşleşme belirsiz.'));
      }
    }
    if (sonuc.isEmpty) throw const FormatException('XLS dosyasında gömülü öğrenci fotoğrafı bulunamadı.');
    return sonuc;
  }

  static Iterable<_OfficeArtKaydi> _officeArtKayitlari(Uint8List bytes,
      {bool derin = false, int seviye = 0}) sync* {
    if (seviye > 32) throw const FormatException('Çizim yapısı çok derin.');
    final data = ByteData.sublistView(bytes);
    for (var p = 0; p < bytes.length;) {
      if (p + 8 > bytes.length) throw const FormatException('Eksik çizim başlığı.');
      final flags = data.getUint16(p, Endian.little);
      final tur = data.getUint16(p + 2, Endian.little);
      final son = p + 8 + data.getUint32(p + 4, Endian.little);
      if (son > bytes.length) throw const FormatException('Eksik çizim verisi.');
      final veri = Uint8List.sublistView(bytes, p + 8, son);
      yield _OfficeArtKaydi(tur, flags & 15, flags >> 4, veri);
      if (derin && flags & 15 == 15) {
        yield* _officeArtKayitlari(veri, derin: true, seviye: seviye + 1);
      }
      p = son;
    }
  }



  static Future<void> _bireyselModuDogrula() async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError('Öğrenci import yalnız bireysel öğretmen modunda kullanılabilir.');
    }
  }

  static Future<Map<String, Object?>> _ogrenciImportProfili(DatabaseExecutor db) async {
    final profiller = await db.query('OgretmenProfil', where: 'Aktif = 1',
        orderBy: 'OgretmenProfilId DESC', limit: 1);
    if (profiller.isEmpty || (profiller.first['EgitimOgretimYili'] ?? '').toString().trim().isEmpty) {
      throw StateError('Önce bireysel öğretmen kurulumunu tamamlayın.');
    }
    return profiller.first;
  }

  static Future<List<Map<String, Object?>>> _ogrenciImportSiniflari(
      DatabaseExecutor db, int ogretmenId, String yil) => db.rawQuery('''
    SELECT DISTINCT s.SinifSubeId, s.SinifKodu
    FROM SinifSube s INNER JOIN GecerliDersProgrami dp ON dp.SinifSubeId = s.SinifSubeId
    WHERE dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ?
      AND s.EgitimOgretimYili = ? AND dp.Aktif = 1 AND s.Aktif = 1
    ''', [ogretmenId, yil, yil]);

  static String _ogrenciSinifAnahtari(String metin) {
    final deger = _normalize(metin);
    final baslik = RegExp(r'\b(\d{1,2})\s+sinif\s+([a-z])\s+subesi(?:\s|$)').firstMatch(deger);
    if (baslik != null) return '${int.parse(baslik[1]!)}${baslik[2]}';
    // Özel eğitim türü normal A şubesiyle aynı sınıf olarak eşleştirilmez.
    final ozel = RegExp(r'\b(\d{1,2})\s+sinif\s+([a-z ]+?)\s+([a-z])\s+subesi(?:\s|$)').firstMatch(deger);
    if (ozel != null) return '${int.parse(ozel[1]!)}${ozel[2]!.replaceAll(' ', '')}${ozel[3]}';
    final ozelKisa = RegExp(r'^(\d{1,2})\s+([a-z ]+?)\s+([a-z])$').firstMatch(deger);
    if (ozelKisa != null) {
      return '${int.parse(ozelKisa[1]!)}${ozelKisa[2]!.replaceAll(' ', '')}${ozelKisa[3]}';
    }
    final kisa = RegExp(r'^(\d{1,2})\s*([a-z])$').firstMatch(deger);
    return kisa == null ? '' : '${int.parse(kisa[1]!)}${kisa[2]}';
  }

  static Map<String, Object?>? _ekOgrenciSinifi(String anahtar, {String hamSinif = ''}) {
    final m = RegExp(r'^(\d{1,2})([a-z]*)([a-z])$').firstMatch(anahtar);
    if (m == null || int.parse(m[1]!) <= 0) return null;
    var tur = m[2]!;
    if (tur.isNotEmpty) {
      final metin = hamSinif.replaceAll(RegExp(r'\s+'), ' ').trim();
      final baslik = RegExp(
        r'\b\d{1,2}\s*[.]?\s*[Ss][ıiİI]n[ıiİI]f\s*-?\s*(.*?)\s*[/ -]\s*[A-Za-zÇĞİÖŞÜçğıöşü]\s+[ŞşSs]ubesi',
        caseSensitive: false,
      ).firstMatch(metin);
      final kisa = RegExp(r'^\d{1,2}\s*[- ]\s*(.*?)\s*[-/ ]\s*[A-Za-zÇĞİÖŞÜçğıöşü]$')
          .firstMatch(metin);
      final kaynakTur = baslik?.group(1) ?? kisa?.group(1);
      if (kaynakTur != null && _normalize(kaynakTur).replaceAll(' ', '') == tur) {
        tur = kaynakTur.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
      tur = tur.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
    }
    return {'SinifSubeId': null,
      'SinifKodu': '${int.parse(m[1]!)}-${tur.isEmpty ? '' : '$tur-'}${m[3]!.toUpperCase()}'};
  }

  /// Açıkça onaylanan ek sınıfların kapsamı profil ve eğitim yılına bağlıdır.
  static Future<Set<int>> ogrenciEkSinifIdleriniGetir(
      DatabaseExecutor db, int ogretmenId, String yil) async {
    final rows = await db.query('UygulamaAyarlari', columns: ['Deger'],
      where: 'Anahtar = ?', whereArgs: ['ogrenci_ek_sinif:$ogretmenId:$yil']);
    if (rows.isEmpty) return const <int>{};
    final value = jsonDecode(rows.single['Deger'] as String);
    if (value is! List || value.any((v) => v is! int || v <= 0)) {
      throw StateError('Kayıtlı ek sınıf kapsamı okunamadı.');
    }
    return Set<int>.unmodifiable(value.cast<int>());
  }

  static Map<String, int> ogrenciEkSinifOzeti(ImportOnIzleme preview) {
    final p = preview.veri;
    if (p is! BireyselOgrenciOnIzleme || preview.engeller.isNotEmpty) return const {};
    final sayilar = <String, int>{};
    for (final k in p._kayitlar) {
      final sinif = k['sinif'] as String;
      if (p._ekSinifKodlari.contains(sinif)) {
        sayilar[sinif] = (sayilar[sinif] ?? 0) + 1;
      }
    }
    final kodlar = sayilar.keys.toList()..sort((a, b) {
      final seviye = int.parse(RegExp(r'^\d+').stringMatch(a)!).compareTo(
        int.parse(RegExp(r'^\d+').stringMatch(b)!));
      return seviye == 0 ? a.compareTo(b) : seviye;
    });
    return Map.unmodifiable({for (final k in kodlar) k: sayilar[k]!});
  }

  static String _ogrenciHucreMetni(dynamic deger) {
    if (deger is num && deger.isFinite && deger == deger.roundToDouble()) {
      return deger.toInt().toString();
    }
    return (deger ?? '').toString().trim();
  }

  static List<String>? _ogrenciKartAdSoyadAyir(String metin) {
    final temiz = metin.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (temiz.isEmpty || RegExp(r'\d').hasMatch(temiz)) {
      return null;
    }

    if (!RegExp(
      r"^[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû' -]+$",
    ).hasMatch(temiz)) {
      return null;
    }

    final norm = _normalize(temiz);
    if (norm.isEmpty ||
        [
          'sinif',
          'subesi',
          'ogrenci',
          'kocaeli',
          'valiligi',
          'mudurlugu',
          'alani',
          'alan',
          'rehber',
          'ogretmen',
          'toplam',
          'kiz',
          'erkek',
        ].any((e) => norm.split(' ').contains(e))) {
      return null;
    }

    final parcalar = temiz.split(' ').where((e) => e.isNotEmpty).toList();
    if (parcalar.length < 2) {
      return null;
    }

    return <String>[
      parcalar.sublist(0, parcalar.length - 1).join(' '),
      parcalar.last,
    ];
  }

  static List<String>? _ogrenciKartBirlesikHucreAyir(String metin) {
    final satirlar = metin
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (satirlar.length < 2) {
      return null;
    }

    final hamNo = satirlar.last;
    if (!RegExp(r'^\d{1,10}$').hasMatch(hamNo)) {
      return null;
    }

    final adSoyad = _ogrenciKartAdSoyadAyir(
      satirlar.sublist(0, satirlar.length - 1).join(' '),
    );
    if (adSoyad == null) {
      return null;
    }

    return <String>[hamNo, adSoyad[0], adSoyad[1]];
  }
  static List<String>? _ogrenciKartAdSoyadBul(
    List<List<dynamic>> sayfa,
    int satir,
    int sutun,
  ) {
    for (var satirFarki = 1; satirFarki <= 3; satirFarki++) {
      final hedefSatir = satir - satirFarki;
      if (hedefSatir < 0 || hedefSatir >= sayfa.length) {
        continue;
      }

      final adaylar = <MapEntry<int, List<String>>>[];
      for (var sutunFarki = 0; sutunFarki <= 3; sutunFarki++) {
        final sutunlar = sutunFarki == 0
            ? <int>[sutun]
            : <int>[sutun - sutunFarki, sutun + sutunFarki];

        for (final hedefSutun in sutunlar) {
          if (hedefSutun < 0 || hedefSutun >= sayfa[hedefSatir].length) {
            continue;
          }

          final adSoyad = _ogrenciKartAdSoyadAyir(
            _ogrenciHucreMetni(sayfa[hedefSatir][hedefSutun]),
          );
          if (adSoyad != null) {
            adaylar.add(MapEntry(sutunFarki, adSoyad));
          }
        }

        if (adaylar.isNotEmpty) {
          break;
        }
      }

      if (adaylar.length == 1) {
        return adaylar.single.value;
      }

      if (adaylar.length > 1 &&
          adaylar.every((e) =>
              _normalize(e.value.join(' ')) ==
              _normalize(adaylar.first.value.join(' ')))) {
        return adaylar.first.value;
      }
    }

    return null;
  }

  static Future<BireyselOgrenciOnIzleme> ogrenciOnIzlemeHazirla({
    required String dosyaAdi, required Uint8List dosyaBytes,
    bool programDisiniDahilEt = false,
  }) async {
    await _bireyselModuDogrula();
    final db = await LocalDatabase.instance.database;
    final profil = await _ogrenciImportProfili(db);
    final ogretmenId = profil['OgretmenProfilId'] as int;
    final yil = profil['EgitimOgretimYili'].toString();
    final siniflar = await _ogrenciImportSiniflari(db, ogretmenId, yil);
    if (siniflar.isEmpty) throw StateError('Önce Ders Programım bölümünden ders programınızı yükleyin.');
    final sinifEslesmeleri = <String, Map<String, Object?>>{};
    for (final sinif in siniflar) {
      final anahtar = _ogrenciSinifAnahtari(sinif['SinifKodu'].toString());
      if (anahtar.isEmpty) throw StateError('Sınıf kodu tanınamadı: ${sinif['SinifKodu']}');
      if (sinifEslesmeleri.containsKey(anahtar)) {
        throw StateError('Ders programında birden fazla eşleşen sınıf var: ${sinif['SinifKodu']}');
      }
      sinifEslesmeleri[anahtar] = sinif;
    }

    Map<String, Object?>? sinifiBul(String anahtar, {String hamSinif = ''}) {
      final sinif = sinifEslesmeleri[anahtar];
      if (sinif != null || !programDisiniDahilEt) return sinif;
      final ek = _ekOgrenciSinifi(anahtar, hamSinif: hamSinif);
      if (ek != null) sinifEslesmeleri[anahtar] = ek;
      return ek;
    }

    final sayfalar = <List<List<dynamic>>>[];
    final uzanti = dosyaAdi.split('.').last.toLowerCase();
    if (uzanti == 'xlsx') {
      for (final tablo in SpreadsheetDecoder.decodeBytes(dosyaBytes).tables.values) {
        sayfalar.add(tablo.rows);
      }
    } else if (uzanti == 'xls') {
      sayfalar.addAll(XlsImportOkuyucu.oku(dosyaBytes).map((s) => s.satirlar));
    } else {
      throw const FormatException('Öğrenci listesi XLS veya XLSX olmalıdır.');
    }

    final kayitlar = <String, Map<String, dynamic>>{};
    final hatalar = <String>[];
    var kapsamDisi = 0;
    var tekrar = 0;
    for (var s = 0; s < sayfalar.length; s++) {
      var sinifAnahtari = '';
      var alan = '';
      var rehber = '';
      var noSutunu = -1, adSutunu = -1, soyadSutunu = -1, cinsiyetSutunu = -1;
      var cinsiyetSonSutunu = -1;
      var sinifSutunu = -1;
      var veliAdiSutunu = -1, veliTelefonSutunu = -1;
      for (var r = 0; r < sayfalar[s].length; r++) {
        final satir = sayfalar[s][r].map(_ogrenciHucreMetni).toList();
        if (satir.every((e) => e.isEmpty)) continue;
        final norm = satir.map(_normalize).toList();
        final yer = 'Sayfa ${s + 1}, satır ${r + 1}';
        final baslik = satir.join(' ');
        if (_normalize(baslik).contains('subesi') && _normalize(baslik).contains('sinif')) {
          sinifAnahtari = _ogrenciSinifAnahtari(baslik);
          if (sinifAnahtari.isNotEmpty) {
            sinifiBul(sinifAnahtari, hamSinif: baslik);
          }
          alan = RegExp(r'\(([^)]+)\)').firstMatch(baslik)?.group(1)?.trim() ?? '';
          rehber = '';
          noSutunu = adSutunu = soyadSutunu = cinsiyetSutunu = sinifSutunu = -1;
          cinsiyetSonSutunu = -1;
          veliAdiSutunu = veliTelefonSutunu = -1;
          if (sinifAnahtari.isEmpty) hatalar.add('$yer: Sınıf başlığı tanınamadı: $baslik');
          continue;
        }
        final rehberIndex = norm.indexWhere((e) => e.startsWith('sinif ogretmeni'));
        if (rehberIndex >= 0) {
          final metin = satir[rehberIndex];
          rehber = metin.contains(':') ? metin.substring(metin.indexOf(':') + 1).trim() : '';
          if (rehber.isEmpty && rehberIndex + 1 < satir.length) rehber = satir[rehberIndex + 1];
          continue;
        }
        final noBasligi = norm.indexWhere((e) => ['ogrenci no', 'okul no', 'ogrenci numarasi', 'okul numarasi'].contains(e));
        if (noBasligi >= 0) {
          noSutunu = noBasligi;
          adSutunu = norm.indexWhere((e) => e == 'adi' || e == 'ad');
          soyadSutunu = norm.indexWhere((e) => e == 'soyadi' || e == 'soyad');
          cinsiyetSutunu = norm.indexWhere((e) => e == 'cinsiyeti' || e == 'cinsiyet');
          cinsiyetSonSutunu = cinsiyetSutunu < 0 ? -1
              : norm.indexWhere((e) => e.isNotEmpty, cinsiyetSutunu + 1);
          if (cinsiyetSutunu >= 0 && cinsiyetSonSutunu < 0) {
            cinsiyetSonSutunu = satir.length;
          }
          sinifSutunu = norm.indexWhere((e) => e == 'sinif' || e == 'sinifi');
          veliAdiSutunu = norm.indexWhere((e) => ['veli adi', 'veli ad soyad', 'velisi'].contains(e));
          veliTelefonSutunu = norm.indexWhere((e) => ['veli telefonu', 'veli telefon', 'veli cep telefonu'].contains(e));
          if (adSutunu < 0 || soyadSutunu < 0) hatalar.add('$yer: Adı ve Soyadı sütunları bulunamadı.');
          continue;
        }
        final ilk = norm.firstWhere((e) => e.isNotEmpty, orElse: () => '');
        if (['ogrenci sayisi', 'toplam ogrenci', 'kiz ogrenci', 'erkek ogrenci',
          'sinif mudur', 'sinif baskani', 't c', 'kocaeli valiligi', 'sinif listesi']
            .any((e) => ilk.startsWith(e))) {
          continue;
        }
        if (noSutunu < 0) {
          final sinif = sinifiBul(sinifAnahtari);
          if (sinif == null) {
            if (sinifAnahtari.isNotEmpty) {
              kapsamDisi++;
            }
            continue;
          }

          var kartKaydiBulundu = false;
          for (var c = 0; c < satir.length; c++) {
            final birlesikKayit = _ogrenciKartBirlesikHucreAyir(satir[c]);
            final String hamNo;
            final List<String>? adSoyad;

            if (birlesikKayit != null) {
              hamNo = birlesikKayit[0];
              adSoyad = <String>[birlesikKayit[1], birlesikKayit[2]];
            } else {
              hamNo = satir[c];
              if (!RegExp(r'^\d+$').hasMatch(hamNo)) {
                continue;
              }

              adSoyad = _ogrenciKartAdSoyadBul(
                sayfalar[s],
                r,
                c,
              );
            }

            final no = int.tryParse(hamNo);
            if (no == null || no <= 0 || adSoyad == null) {
              continue;
            }

            final ad = adSoyad[0];
            final soyad = adSoyad[1];
            final kayit = <String, dynamic>{
              'okulNo': '$no',
              'ad': ad,
              'soyad': soyad,
              'adSoyad': '$ad $soyad',
              'cinsiyet': '',
              'sinif': sinif['SinifKodu'],
              'sinifSubeId': sinif['SinifSubeId'],
              'alan': alan,
              'rehberOgretmen': rehber,
            };

            final onceki = kayitlar['$no'];
            if (onceki != null) {
              if (kayit.keys.any((k) =>
                  _normalize('${onceki[k]}') !=
                  _normalize('${kayit[k]}'))) {
                hatalar.add(
                  '$yer: $no numaralı öğrencinin bilgileri veya sınıfı çelişiyor.',
                );
              } else {
                tekrar++;
              }
            } else {
              kayitlar['$no'] =
                  Map<String, dynamic>.unmodifiable(kayit);
            }

            kartKaydiBulundu = true;
          }

          if (kartKaydiBulundu) {
            continue;
          }

          continue;
        }
        String hucre(int i) => i >= 0 && i < satir.length ? satir[i] : '';
        final anahtar = sinifSutunu >= 0 ? _ogrenciSinifAnahtari(hucre(sinifSutunu)) : sinifAnahtari;
        if (anahtar.isEmpty) {
          hatalar.add('$yer: Öğrencinin sınıfı belirlenemedi.');
          continue;
        }
        final sinif = sinifiBul(anahtar, hamSinif: sinifSutunu >= 0 ? hucre(sinifSutunu) : '');
        if (sinif == null) { kapsamDisi++; continue; }
        final hamNo = hucre(noSutunu);
        final no = RegExp(r'^\d+$').hasMatch(hamNo) ? int.tryParse(hamNo) : null;
        final ad = hucre(adSutunu), soyad = hucre(soyadSutunu);
        // Raporun imza/toplam alanındaki artık hücreler öğrenci değildir.
        if (hamNo.isEmpty && ad.isEmpty && soyad.isEmpty) {
          continue;
        }
        var hamCinsiyet = hucre(cinsiyetSutunu);
        if (hamCinsiyet.isEmpty && cinsiyetSutunu >= 0) {
          // e-Okul birleşik başlıkta metni sola, değeri sağa koyabilir.
          // Yalnız aynı başlığın alanı taranır; diğer sütunlara geçilmez.
          hamCinsiyet = [
            for (var c = cinsiyetSutunu + 1; c < cinsiyetSonSutunu; c++)
              if (hucre(c).isNotEmpty) hucre(c),
          ].join(' ');
        }
        final cinsiyet = _normalize(hamCinsiyet);
        if (no == null || no <= 0 || ad.isEmpty || soyad.isEmpty ||
            !['', 'kiz', 'erkek'].contains(cinsiyet)) {
          hatalar.add('$yer: Okul no, ad, soyad veya cinsiyet hatalı (No: $hamNo).');
          continue;
        }
        final kayit = <String, dynamic>{
          'okulNo': '$no', 'ad': ad, 'soyad': soyad, 'adSoyad': '$ad $soyad',
          'cinsiyet': cinsiyet == 'kiz' ? 'Kız' : cinsiyet == 'erkek' ? 'Erkek' : '',
          'sinif': sinif['SinifKodu'], 'sinifSubeId': sinif['SinifSubeId'],
          'alan': alan, 'rehberOgretmen': rehber,
          'veliAdi': hucre(veliAdiSutunu), 'veliTelefonu': hucre(veliTelefonSutunu),
        };
        try { _iletisimVerisi(kayit); } catch (_) {
          hatalar.add('$yer: Okul no, ad, soyad veya cinsiyet hatalı (No: $hamNo). Veli adı veya telefonu geçersiz.');
          continue;
        }
        final onceki = kayitlar['$no'];
        if (onceki != null) {
          if (kayit.keys.any((k) => _normalize('${onceki[k]}') != _normalize('${kayit[k]}'))) {
            hatalar.add('$yer: $no numaralı öğrencinin bilgileri veya sınıfı çelişiyor.');
          } else { tekrar++; }
        } else {
          kayitlar['$no'] = Map<String, dynamic>.unmodifiable(kayit);
        }
      }
    }
    if (kayitlar.isEmpty) {
      hatalar.add(programDisiniDahilEt
        ? 'Dosyada geçerli öğrenci bulunamadı.'
        : 'Ders verdiğiniz sınıflara ait geçerli öğrenci bulunamadı.');
    }
    return BireyselOgrenciOnIzleme._(ogretmenId, yil,
        List<Map<String, dynamic>>.unmodifiable(kayitlar.values),
        List<String>.unmodifiable(hatalar), kapsamDisi, tekrar,
        ekSinifKodlari: {for (final k in kayitlar.values)
          if (k['sinifSubeId'] == null) k['sinif'] as String});
  }

  static Future<ImportSonuc> ogrencileriKaydet(BireyselOgrenciOnIzleme onIzleme,
      {Set<String>? seciliOkulNolari, Set<String> ekSiniflar = const {}}) async {
    final secimler = seciliOkulNolari == null ? null : Set<String>.of(seciliOkulNolari);
    final ekSecimler = Set<String>.of(ekSiniflar);
    await _bireyselModuDogrula();
    if (onIzleme._hatalar.isNotEmpty || onIzleme._kayitlar.isEmpty) {
      throw StateError('Hatasız bir ön izleme hazırlamadan kayıt yapılamaz.');
    }
    if (secimler != null && (secimler.isEmpty || secimler.any((no) =>
        !onIzleme._kayitlar.any((k) => k['okulNo'] == no)))) {
      throw StateError('Aktarılacak geçerli öğrencileri seçin.');
    }
    if (!onIzleme._ekSinifKodlari.containsAll(ekSecimler)) {
      throw StateError('Seçilen ek sınıflar ön izlemeyle uyuşmuyor.');
    }
    final kayitlar = onIzleme._kayitlar.where((k) =>
        (secimler == null || secimler.contains(k['okulNo'])) &&
        (!onIzleme._ekSinifKodlari.contains(k['sinif']) || ekSecimler.contains(k['sinif'])))
        .map((k) => Map<String, dynamic>.of(k)).toList();
    if (kayitlar.isEmpty) throw StateError('Aktarılacak geçerli öğrencileri seçin.');
    final db = await LocalDatabase.instance.database;
    return db.transaction((txn) async {
      final profil = await _ogrenciImportProfili(txn);
      if (profil['OgretmenProfilId'] != onIzleme._ogretmenId ||
          profil['EgitimOgretimYili'] != onIzleme._yil) {
        throw StateError('Öğretmen veya eğitim yılı değişti. Ön izlemeyi yeniden hazırlayın.');
      }
      final siniflar = await _ogrenciImportSiniflari(txn, onIzleme._ogretmenId, onIzleme._yil);
      for (final kayit in kayitlar) {
        if (onIzleme._ekSinifKodlari.contains(kayit['sinif'])) {
          continue;
        }
        if (!siniflar.any((s) => s['SinifSubeId'] == kayit['sinifSubeId'] && s['SinifKodu'] == kayit['sinif'])) {
          throw StateError('Ders programındaki sınıflar değişti. Ön izlemeyi yeniden hazırlayın.');
        }
      }
      var eklenen = 0, guncellenen = 0, atlanan = 0;
      final simdi = DateTime.now().toIso8601String();
      final ekIdler = <int>{};
      for (final kod in kayitlar.map((k) => k['sinif'] as String).toSet()
          .where(onIzleme._ekSinifKodlari.contains)) {
        final mevcut = await txn.query('SinifSube',
          where: 'SinifKodu = ? AND EgitimOgretimYili = ?', whereArgs: [kod, onIzleme._yil]);
        final int id;
        if (mevcut.isEmpty) {
          id = await txn.insert('SinifSube', {'SinifKodu': kod,
            'SinifSeviyesi': int.parse(RegExp(r'^\d+').stringMatch(kod)!),
            'Sube': kod.split('-').last, 'EgitimOgretimYili': onIzleme._yil,
            'Aktif': 1, 'OlusturmaTarihi': simdi});
        } else {
          id = mevcut.single['SinifSubeId'] as int;
          if (mevcut.single['Aktif'] != 1) {
            await txn.update('SinifSube', {'Aktif': 1, 'GuncellemeTarihi': simdi},
              where: 'SinifSubeId = ?', whereArgs: [id]);
          }
        }
        ekIdler.add(id);
        for (final k in kayitlar.where((k) => k['sinif'] == kod)) {
          k['sinifSubeId'] = id;
        }
      }
      for (final kayit in kayitlar) {
        final mevcut = await txn.query('Ogrenci',
            where: "OkulNo = ? OR (OkulNo <> '' AND OkulNo NOT GLOB '*[^0-9]*' AND CAST(OkulNo AS INTEGER) = ?)",
            whereArgs: [kayit['okulNo'], int.parse(kayit['okulNo'] as String)]);
        if (mevcut.length > 1) {
          throw StateError('${kayit['okulNo']} okul numarası için birden fazla mevcut öğrenci var. Kayıt yapılmadı.');
        }
        // Değişmeyen öğrenci, üyelik ve sınıf metaverisi yeniden yazılmaz.
        if (mevcut.isNotEmpty) {
          final ogrenci = mevcut.single;
          final uyelikler = await txn.query('OgrenciSinifKayit',
            where: 'OgrenciId = ? AND EgitimOgretimYili = ? AND Aktif = 1',
            whereArgs: [ogrenci['OgrenciId'], onIzleme._yil]);
          final sinif = await txn.query('SinifSube', where: 'SinifSubeId = ?',
            whereArgs: [kayit['sinifSubeId']]);
          if (ogrenci['OkulNo'] == kayit['okulNo'] && ogrenci['Ad'] == kayit['ad'] &&
              ogrenci['Soyad'] == kayit['soyad'] && ogrenci['Aktif'] == 1 &&
              (kayit['cinsiyet'] == '' || ogrenci['Cinsiyet'] == kayit['cinsiyet']) &&
              _iletisimVerisi(kayit).entries.every((e) => ogrenci[e.key] == e.value) &&
              uyelikler.length == 1 && uyelikler.single['SinifSubeId'] == kayit['sinifSubeId'] &&
              sinif.length == 1 &&
              (kayit['alan'] == '' || sinif.single['Alan'] == kayit['alan']) &&
              (kayit['rehberOgretmen'] == '' || sinif.single['RehberOgretmen'] == kayit['rehberOgretmen'])) {
            atlanan++;
            continue;
          }
        }
        final veri = <String, Object?>{
          'OkulNo': kayit['okulNo'], 'Ad': kayit['ad'], 'Soyad': kayit['soyad'],
          ..._iletisimVerisi(kayit),
          if (kayit['cinsiyet'] != '') 'Cinsiyet': kayit['cinsiyet'],
          'Aktif': 1, 'GuncellemeTarihi': simdi,
        };
        final int ogrenciId;
        if (mevcut.isEmpty) {
          ogrenciId = await txn.insert('Ogrenci', {...veri, 'OlusturmaTarihi': simdi});
          eklenen++;
        } else {
          ogrenciId = mevcut.first['OgrenciId'] as int;
          await txn.update('Ogrenci', veri, where: 'OgrenciId = ?', whereArgs: [ogrenciId]);
          guncellenen++;
        }
        final sinifId = kayit['sinifSubeId'];
        // Yalnız bu öğrencinin aynı yıldaki eski sınıf üyeliğini pasifleştir.
        await txn.update('OgrenciSinifKayit', {'Aktif': 0, 'GuncellemeTarihi': simdi},
            where: 'OgrenciId = ? AND EgitimOgretimYili = ? AND SinifSubeId <> ? AND Aktif = 1',
            whereArgs: [ogrenciId, onIzleme._yil, sinifId]);
        final uyelik = await txn.query('OgrenciSinifKayit',
            where: 'OgrenciId = ? AND SinifSubeId = ? AND EgitimOgretimYili = ?',
            whereArgs: [ogrenciId, sinifId, onIzleme._yil]);
        if (uyelik.isEmpty) {
          await txn.insert('OgrenciSinifKayit', {'OgrenciId': ogrenciId,
            'SinifSubeId': sinifId, 'EgitimOgretimYili': onIzleme._yil,
            'Aktif': 1, 'OlusturmaTarihi': simdi});
        } else {
          await txn.update('OgrenciSinifKayit', {'Aktif': 1, 'GuncellemeTarihi': simdi},
              where: 'OgrenciSinifKayitId = ?', whereArgs: [uyelik.first['OgrenciSinifKayitId']]);
        }
        if (kayit['alan'] != '' || kayit['rehberOgretmen'] != '') {
          await txn.update('SinifSube', {
            if (kayit['alan'] != '') 'Alan': kayit['alan'],
            if (kayit['rehberOgretmen'] != '') 'RehberOgretmen': kayit['rehberOgretmen'],
            'GuncellemeTarihi': simdi,
          }, where: 'SinifSubeId = ?', whereArgs: [sinifId]);
        }
      }
      if (ekIdler.isNotEmpty) {
        final izinler = {...await ogrenciEkSinifIdleriniGetir(
          txn, onIzleme._ogretmenId, onIzleme._yil), ...ekIdler}.toList()..sort();
        await txn.insert('UygulamaAyarlari', {
          'Anahtar': 'ogrenci_ek_sinif:${onIzleme._ogretmenId}:${onIzleme._yil}',
          'Deger': jsonEncode(izinler), 'GuncellemeTarihi': simdi,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _bireyselModuDogrula();
      return ImportSonuc.fromJson({'basarili': true, 'kayitTipi': 'Öğrenci',
        'mesaj': 'Öğrenciler bu cihazın SQLite veritabanına kaydedildi.',
        'eklenenKayit': eklenen, 'guncellenenKayit': guncellenen,
        'kayitlar': kayitlar,
        'islemAdimlari': ['Eğitim yılı: ${onIzleme._yil}',
          'Değişmediği için atlanan: $atlanan', 'Dosyada olmayan öğrenciler korunmuştur.']});
    });
  }

  static Future<ImportOnIzleme> ortakFotoOzelOku(ImportDosya dosya,
      {Map<String, String>? sinifHucreleri}) async {
    final p = await fotoOnIzlemeHazirla(dosyaAdi: dosya.ad, dosyaBytes: dosya.bytes,
      sinifHucreleri: sinifHucreleri);
    return ImportOnIzleme([
      for (final foto in p.kayitlar)
        ImportKaydi(foto.okulNo, 'Fotoğraf eşleşmesi', {
          'okulNo': foto.okulNo, 'adSoyad': foto.adSoyad, 'sinif': foto.sinif,
        }),
    ], veri: p, engeller: p.hatalar, bilgiler: p.sonuc.islemAdimlari,
      onceAtlanan: p._kapsamDisi);
  }

  static Future<ImportOzet> ortakFotograflariKaydet(ImportOnIzleme preview, Set<String> selected) async {
    final p = preview.veri;
    final eligible = preview.kayitlar.where((r) => r.aktarilabilir).map((r) => r.id).toSet();
    if (p is! BireyselFotoOnIzleme || preview.engeller.isNotEmpty || selected.isEmpty || !eligible.containsAll(selected)) {
      throw StateError('Öğrenci ve fotoğraf eşleşmelerini kontrol edip seçin.');
    }
    final subset = BireyselFotoOnIzleme._(p._ogretmenId, p._yil,
      p.ogrenciKayitlari.where((r) => selected.contains(r['okulNo'].toString())).toList(),
      p.kayitlar.where((r) => selected.contains(r.okulNo)).toList(), p.hatalar, p._kapsamDisi,
      uyarilar: p.uyarilar);
    final result = await fotograflariKaydet(subset);
    return ImportOzet(eklenen: result.eklenenKayit, guncellenen: result.guncellenenKayit,
      atlanan: preview.onceAtlanan + preview.kayitlar.length - selected.length,
      hatali: result.hataliKayit, mesaj: '${result.mesaj}\n${result.islemAdimlari.join('\n')}');
  }

  /// Standart tablo eşleştirmesinin yerel öğrenci iş kurallarına bağlandığı nokta.
  static Future<ImportOnIzleme> ortakOgrenciTumSinifOnIzlemeHazirla(
      List<ImportKaynakSatiri> satirlar) =>
      ortakOgrenciOnIzlemeHazirla(satirlar, programDisiniDahilEt: true);

  static Future<ImportOnIzleme> ortakOgrenciOnIzlemeHazirla(
      List<ImportKaynakSatiri> satirlar, {bool programDisiniDahilEt = false}) async {
    await _bireyselModuDogrula();
    final db = await LocalDatabase.instance.database;
    final profil = await _ogrenciImportProfili(db);
    final ogretmenId = profil['OgretmenProfilId'] as int;
    final yil = profil['EgitimOgretimYili'].toString();
    final siniflar = await _ogrenciImportSiniflari(db, ogretmenId, yil);
    if (siniflar.isEmpty) throw StateError('Önce ders programınızı yükleyin.');
    final sinifEslesmeleri = <String, Map<String, Object?>>{};
    for (final sinif in siniflar) {
      final key = _ogrenciSinifAnahtari(sinif['SinifKodu'].toString());
      if (key.isEmpty || sinifEslesmeleri.containsKey(key)) {
        throw StateError('Ders programındaki sınıf eşleştirmesi belirsiz.');
      }
      sinifEslesmeleri[key] = sinif;
    }
    final ekSinifKodlari = <String>{};
    if (programDisiniDahilEt) {
      for (final satir in satirlar) {
        final key = _ogrenciSinifAnahtari(satir.degerler['sinif'] ?? '');
        if (sinifEslesmeleri.containsKey(key)) continue;
        final ek = _ekOgrenciSinifi(key, hamSinif: satir.degerler['sinif'] ?? '');
        if (ek == null) continue;
        sinifEslesmeleri[key] = ek;
        ekSinifKodlari.add(ek['SinifKodu'] as String);
      }
    }
    final dogrulama = ortakOgrenciSatirlariniDogrula(satirlar, sinifEslesmeleri).toList();
    final mevcutOgrenciler = await db.query('Ogrenci', columns: ['OkulNo']);
    final numaraSayilari = <String, int>{};
    for (final ogrenci in mevcutOgrenciler) {
      final raw = ogrenci['OkulNo'].toString();
      final key = RegExp(r'^\d+$').hasMatch(raw) ? int.tryParse(raw)?.toString() : null;
      if (key != null) numaraSayilari[key] = (numaraSayilari[key] ?? 0) + 1;
    }
    for (var i = 0; i < dogrulama.length; i++) {
      final row = dogrulama[i];
      if (row.aktarilabilir && (numaraSayilari[row.id] ?? 0) > 1) {
        dogrulama[i] = ImportKaydi(row.id, row.konum, row.degerler,
          durum: ImportDurumu.hatali, mesajlar: const ['Bu okul numarası için birden fazla mevcut öğrenci var.']);
      }
    }
    final kayitlar = <Map<String, dynamic>>[];
    for (final row in dogrulama.where((r) => r.aktarilabilir)) {
      final sinif = sinifEslesmeleri[_ogrenciSinifAnahtari(row.degerler['sinif']!)]!;
      kayitlar.add(Map.unmodifiable(<String, dynamic>{...row.degerler,
        'sinifSubeId': sinif['SinifSubeId']}));
    }
    final ekAdet = kayitlar.where((k) => ekSinifKodlari.contains(k['sinif'])).length;
    return ImportOnIzleme([
      for (final row in dogrulama)
        if (row.aktarilabilir && ekSinifKodlari.contains(row.degerler['sinif']))
          ImportKaydi(row.id, row.konum, row.degerler,
            durum: ImportDurumu.atlanan, mesajlar: [
              'Ders programınızda yok. Kaydet adımında sınıfı ayrıca seçebilirsiniz.',
              ...row.mesajlar,
            ])
        else row,
    ],
      veri: BireyselOgrenciOnIzleme._(ogretmenId, yil, List.unmodifiable(kayitlar), const [], 0, 0,
        ekSinifKodlari: ekSinifKodlari),
      bilgiler: ['Eğitim yılı: $yil',
        if (programDisiniDahilEt)
          'Ders programınızda olmayan sınıflar otomatik kaydedilmez. Kaydet adımında öğrenci sayılarıyla gösterilir ve seçebilirsiniz.'
        else 'Yalnız ders verdiğiniz sınıflar aktarılabilir.',
        if (ekAdet > 0) 'Ayrıca onayınızı bekleyen öğrenci: $ekAdet. Hatalı ve tekrarlanan satırlar bu sayıya dahil değildir.',
        'Dosyada olmayan öğrenciler ve boş opsiyonel alanların mevcut değerleri korunur.']);
  }

  /// Saf doğrulama: SQLite'a yazmadan kapsam, tekrar ve çelişkileri belirler.
  static List<ImportKaydi> ortakOgrenciSatirlariniDogrula(
      List<ImportKaynakSatiri> satirlar, Map<String, Map<String, Object?>> siniflar) {
    final rows = <ImportKaydi>[];
    final numaralar = <String, int>{};
    final celiskiler = <String>{};
    for (final source in satirlar) {
      final values = <String, String>{for (final key in
        ['okulNo', 'ad', 'soyad', 'cinsiyet', 'sinif', 'alan', 'rehberOgretmen', 'veliAdi', 'veliTelefonu'])
          key: source.degerler[key]?.trim() ?? ''};
      final errors = <String>[];
      final rawNo = values['okulNo']!;
      final no = RegExp(r'^\d+$').hasMatch(rawNo) ? int.tryParse(rawNo) : null;
      if (no == null || no <= 0) { errors.add('Okul numarası pozitif tam sayı olmalıdır.'); }
      else { values['okulNo'] = '$no'; }
      if (values['ad']!.isEmpty) errors.add('Ad boş bırakılamaz.');
      if (values['soyad']!.isEmpty) errors.add('Soyad boş bırakılamaz.');
      if (values['veliAdi']!.length > 200) errors.add('Veli adı en fazla 200 karakter olmalıdır.');
      final telefon = values['veliTelefonu']!;
      if (telefon.isNotEmpty) {
        final normal = mesajTelefonNormalize(telefon);
        if (telefon.length > 50 || normal == null) {
          errors.add('Veli telefonu geçersiz. Türkiye için 05xx…; diğer ülkeler için +ülke kodu kullanın.');
        } else { values['veliTelefonu'] = normal; }
      }
      final gender = _normalize(values['cinsiyet']!);
      if (!['', 'kiz', 'erkek'].contains(gender)) errors.add('Cinsiyet Kız veya Erkek olmalıdır.');
      values['cinsiyet'] = gender == 'kiz' ? 'Kız' : gender == 'erkek' ? 'Erkek' : '';
      final sinifKey = _ogrenciSinifAnahtari(values['sinif']!);
      final sinif = siniflar[sinifKey];
      if (sinifKey.isEmpty) errors.add('Sınıf/şube tanınamadı.');
      if (sinif != null) values['sinif'] = sinif['SinifKodu'].toString();
      values['adSoyad'] = '${values['ad']} ${values['soyad']}'.trim();
      if (errors.isNotEmpty) {
        rows.add(ImportKaydi('hata:${source.id}', source.konum, values,
          durum: ImportDurumu.hatali, mesajlar: List.unmodifiable(errors)));
        continue;
      }
      if (sinif == null) {
        rows.add(ImportKaydi('kapsam:${source.id}', source.konum, values,
          durum: ImportDurumu.atlanan, mesajlar: const ['Ders verdiğiniz sınıfların dışında.']));
        continue;
      }
      final key = values['okulNo']!;
      final previousIndex = numaralar[key];
      if (previousIndex != null) {
        final previous = rows[previousIndex];
        final conflict = celiskiler.contains(key) || values.keys.any((k) =>
            _normalize(values[k]!) != _normalize(previous.degerler[k] ?? ''));
        if (conflict) {
          celiskiler.add(key);
          for (var i = previousIndex; i < rows.length; i++) {
            if (rows[i].degerler['okulNo'] == key) {
              final conflicting = rows[i];
              rows[i] = ImportKaydi(conflicting.id, conflicting.konum, conflicting.degerler,
                durum: ImportDurumu.hatali, mesajlar: const ['Aynı okul numarası için çelişkili bilgiler var.']);
            }
          }
        }
        rows.add(ImportKaydi('tekrar:${source.id}', source.konum, values,
          durum: conflict ? ImportDurumu.hatali : ImportDurumu.atlanan,
          mesajlar: [conflict ? 'Aynı okul numarası için çelişkili bilgiler var.' : 'Aynı öğrenci dosyada tekrar ediyor.']));
        continue;
      }
      numaralar[key] = rows.length;
      final warnings = [if (values['cinsiyet']!.isEmpty) 'Cinsiyet belirtilmemiş; mevcut değer korunur.'];
      rows.add(ImportKaydi(key, source.konum, values,
        durum: warnings.isEmpty ? ImportDurumu.uygun : ImportDurumu.uyarili,
        mesajlar: List.unmodifiable(warnings)));
    }
    // Alan ve rehber öğretmen öğrenciye değil sınıfa aittir; son satır kazanamaz.
    final classValues = <String, Map<String, Set<String>>>{};
    for (final row in rows.where((r) => r.aktarilabilir)) {
      final metadata = classValues.putIfAbsent(row.degerler['sinif']!, () => {});
      for (final field in ['alan', 'rehberOgretmen']) {
        final value = _normalize(row.degerler[field]!);
        if (value.isNotEmpty) metadata.putIfAbsent(field, () => {}).add(value);
      }
    }
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.aktarilabilir && (classValues[row.degerler['sinif']]?.values.any((v) => v.length > 1) ?? false)) {
        rows[i] = ImportKaydi(row.id, row.konum, row.degerler,
          durum: ImportDurumu.hatali, mesajlar: const ['Aynı sınıf için alan veya rehber öğretmen bilgileri çelişiyor.']);
      }
    }
    return List.unmodifiable(rows);
  }

  static Future<ImportOnIzleme> ortakOgrenciOzelOku(ImportDosya dosya) async {
    final preview = await ogrenciOnIzlemeHazirla(dosyaAdi: dosya.ad, dosyaBytes: dosya.bytes,
      programDisiniDahilEt: true);
    final kayitHatalari = <String>[];
    final engeller = <String>[];
    final celiskiliNumaralar = <String>{};
    for (final hata in preview._hatalar) {
      // Konumu bilinen başlık/kayıt hataları diğer bölümlerin aktarımını kilitlemez.
      if (hata.startsWith('Sayfa ') &&
          (hata.contains('Adı ve Soyadı sütunları bulunamadı.') ||
           hata.contains('Sınıf başlığı tanınamadı:') ||
           hata.contains('Öğrencinin sınıfı belirlenemedi.') ||
           hata.contains('Okul no, ad, soyad veya cinsiyet hatalı') ||
           hata.contains('numaralı öğrencinin bilgileri veya sınıfı çelişiyor.'))) {
        kayitHatalari.add(hata);
        final no = RegExp(r': (\d+) numaralı öğrencinin').firstMatch(hata)?.group(1);
        if (no != null) celiskiliNumaralar.add(no);
      } else {
        engeller.add(hata);
      }
    }
    final guvenliKayitlar = preview._kayitlar.where(
      (k) => !celiskiliNumaralar.contains(k['okulNo'].toString()),
    ).toList();
    final ortak = await ortakOgrenciTumSinifOnIzlemeHazirla([
      for (final k in guvenliKayitlar)
        ImportKaynakSatiri(k['okulNo'].toString(), 'e-Okul kaydı',
          {for (final e in k.entries) e.key: e.value?.toString() ?? ''}),
    ]);
    return ImportOnIzleme([
      ...ortak.kayitlar,
      for (final kayit in preview._kayitlar.where((k) =>
          celiskiliNumaralar.contains(k['okulNo'].toString()))) ImportKaydi(kayit['okulNo'].toString(),
        'e-Okul kaydı', {for (final e in kayit.entries) e.key: e.value.toString()},
        durum: ImportDurumu.hatali,
        mesajlar: const ['Bu okul numarasının bilgileri veya sınıfı çelişiyor.']),
      for (var i = 0; i < kayitHatalari.length; i++)
        ImportKaydi('bolum-hatasi:$i', kayitHatalari[i].split(':').first, {},
          durum: ImportDurumu.hatali, mesajlar: [kayitHatalari[i]]),
    ], veri: ortak.veri, engeller: engeller, bilgiler: [
      ...ortak.bilgiler,
      if (kayitHatalari.isNotEmpty) 'Hatalı kayıt/bölümler aktarılmaz. Tanınmayan başlıklar için özel düzeni kapatıp ilgili sayfada kolonları elle eşleştirebilirsiniz.',
    ],
      onceAtlanan: preview._kapsamDisi + preview._tekrar);
  }

  static Future<ImportOzet> ortakOgrencileriKaydet(ImportOnIzleme preview, Set<String> selected,
      {Set<String> ekSiniflar = const {}}) async {
    final ekSecimler = Set<String>.of(ekSiniflar);
    final ozet = ogrenciEkSinifOzeti(preview);
    if (preview.engeller.isNotEmpty || preview.veri is! BireyselOgrenciOnIzleme ||
        (selected.isEmpty && ekSecimler.isEmpty) || !ozet.keys.toSet().containsAll(ekSecimler) ||
        selected.any((id) => !preview.kayitlar.any((r) =>
          r.id == id && r.aktarilabilir))) { throw StateError('Geçerli ön izleme ve seçim gerekli.'); }
    final p = preview.veri! as BireyselOgrenciOnIzleme;
    final tumSecimler = {...selected,
      for (final k in p._kayitlar)
        if (ekSecimler.contains(k['sinif'])) k['okulNo'] as String};
    final sonuc = await ogrencileriKaydet(p,
      seciliOkulNolari: tumSecimler, ekSiniflar: ekSecimler);
    final hatali = preview.kayitlar.where((r) => r.durum == ImportDurumu.hatali).length;
    return ImportOzet(eklenen: sonuc.eklenenKayit, guncellenen: sonuc.guncellenenKayit,
      atlanan: preview.onceAtlanan + preview.kayitlar.length - hatali -
          sonuc.eklenenKayit - sonuc.guncellenenKayit,
      hatali: hatali, mesaj: '${sonuc.mesaj}${ekSecimler.isEmpty ? '' : '\nEk sınıf: ${ekSecimler.length} • Öğrenci: ${ekSecimler.fold<int>(0, (toplam, kod) => toplam + ozet[kod]!)}'}');
  }



  static const List<String> _gunler = <String>[
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
  ];

  static Future<BireyselDersProgramiOnIzleme> dersProgramiOnIzlemeHazirla({
    required Uint8List dosyaBytes,
    required String adSoyad,
    required String dosyaUzantisi,
  }) async {
    final temizAdSoyad = adSoyad.trim();
    final temizUzanti = dosyaUzantisi.trim().toLowerCase();

    if (temizAdSoyad.isEmpty) {
      throw Exception(
        'Bireysel ders programı ön izlemesi hazırlanamadı. '
        'Öğretmen adı boş bırakılamaz.',
      );
    }

    if (dosyaBytes.isEmpty) {
      throw Exception(
        'Bireysel ders programı ön izlemesi hazırlanamadı. '
        'Seçilen dosya boş.',
      );
    }

    if (temizUzanti != 'xls' && temizUzanti != 'xlsx') {
      throw Exception(
        'Bireysel ders programı ön izlemesi hazırlanamadı. '
        'Yalnız XLS ve XLSX dosyaları destekleniyor.',
      );
    }

    try {
      if (temizUzanti == 'xls') {
        return _xlsOnIzlemeHazirla(
          dosyaBytes: dosyaBytes,
          adSoyad: temizAdSoyad,
        );
      }

      return _xlsxOnIzlemeHazirla(
        dosyaBytes: dosyaBytes,
        adSoyad: temizAdSoyad,
      );
    } catch (e) {
      throw Exception(
        'Bireysel ders programı Excel dosyası okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static BireyselDersProgramiOnIzleme _xlsxOnIzlemeHazirla({
    required Uint8List dosyaBytes,
    required String adSoyad,
  }) {
    final decoder = SpreadsheetDecoder.decodeBytes(dosyaBytes);
    return _programSayfalariniOku(
      sayfalar: {for (final e in decoder.tables.entries) e.key: e.value.rows},
      adSoyad: adSoyad,
    );
  }

  // Öğretmen başlığı programın kapsamını, saat başlıkları sütunları belirler.
  // Satır/sütun numaraları veya okulun varsayılan saatleri kullanılmaz.
  static BireyselDersProgramiOnIzleme _programSayfalariniOku({
    required Map<String, List<List<dynamic>>> sayfalar,
    required String adSoyad,
  }) {
    final adaylar = <BireyselDersProgramiOnIzleme>[];
    final eslesmeler = <String>{};
    for (final sayfa in sayfalar.entries) {
      final rows = sayfa.value;
      final basliklar = <int>[];
      for (var r = 0; r < rows.length; r++) {
        if (rows[r].any((v) => _ogretmenAdiEslesiyor(
              hucreMetni: (v ?? '').toString(), adSoyad: adSoyad))) {
          basliklar.add(r);
        }
      }
      if (basliklar.isEmpty && _normalize(sayfa.key) == _normalize(adSoyad)) {
        basliklar.add(-1);
      }
      for (final baslik in basliklar) {
        final yer = '$adSoyad (Excel sekmesi: ${sayfa.key}, başlık satırı: ${baslik + 1})';
        eslesmeler.add(yer);
        var son = rows.length;
        // Aynı sayfada alt alta yer alan başka öğretmenin programına geçilmez.
        for (var r = baslik + 1; r < rows.length; r++) {
          if (rows[r].any((v) {
            final t = _normalize((v ?? '').toString());
            return t.startsWith('sayin ') || t.startsWith('ogretmen ') ||
                t.startsWith('ad soyad ');
          })) {
            son = r;
            break;
          }
        }
        final aday = _programBlogunuOku(rows, baslik + 1, son, yer, sayfalar.length) ??
            _sutunGunluProgramiOku(rows, baslik + 1, son, yer, sayfalar.length);
        if (aday != null) {
          adaylar.add(BireyselDersProgramiOnIzleme(
            sayfaSayisi: aday.sayfaSayisi, doluHucreSayisi: aday.doluHucreSayisi,
            ogretmenBulundu: aday.ogretmenBulundu, ogretmenEslesmeleri: aday.ogretmenEslesmeleri,
            gunlukDersSaatAdaylari: aday.gunlukDersSaatAdaylari, dersler: aday.dersler,
            seflikSaatleri: aday.seflikSaatleri, uyarilar: aday.uyarilar,
            baslangicTarihi: _programBaslangicTarihiniBul(rows.sublist(baslik + 1, son)),
          ));
        }
      }
    }
    if (adaylar.length > 1) {
      throw const FormatException(
        'Öğretmen adına ait birden fazla program bulundu. '
        'Aktarılacak programı ayrı bir dosyada seçin; programlar birleştirilmedi.',
      );
    }
    if (adaylar.isNotEmpty) return adaylar.single;
    return BireyselDersProgramiOnIzleme(
      sayfaSayisi: sayfalar.length, doluHucreSayisi: 0,
      ogretmenBulundu: eslesmeler.isNotEmpty,
      ogretmenEslesmeleri: eslesmeler.toList(),
      gunlukDersSaatAdaylari: const [], dersler: const [],
      uyarilar: eslesmeler.isEmpty ? const [] : const [
        'Öğretmen adı bulundu ancak altında gün ve ders saatleriyle tanımlanan '
        'bir program okunamadı. Henüz kayıt yapılmadı.',
      ],
    );
  }

  static String _programHucre(List<List<dynamic>> rows, int r, int c) =>
      r >= 0 && r < rows.length && c >= 0 && c < rows[r].length
          ? (rows[r][c] ?? '').toString().trim() : '';

  static DateTime? _programBaslangicTarihiniBul(List<List<dynamic>> rows) {
    final tarihler = <DateTime>{};
    for (final v in rows.expand((r) => r)) {
      final metin = (v ?? '').toString();
      if (!_normalize(metin).contains('itibaren')) continue;
      final m = RegExp(r'(\d{1,2})[./-](\d{1,2})[./-](\d{4})\s+tarihinden', caseSensitive: false).firstMatch(metin);
      if (m == null) continue;
      final gun = int.parse(m[1]!), ay = int.parse(m[2]!), yil = int.parse(m[3]!);
      final tarih = DateTime(yil, ay, gun);
      if (tarih.day == gun && tarih.month == ay && tarih.year == yil) tarihler.add(tarih);
    }
    return tarihler.length == 1 ? tarihler.single : null;
  }

  // Günlerin sütun başlığı, saatlerin satır olduğu düzeni aynı okuyucuya uyarla.
  static BireyselDersProgramiOnIzleme? _sutunGunluProgramiOku(
      List<List<dynamic>> rows, int bas, int son, String yer, int sayfaSayisi) {
    for (var h = bas; h < son; h++) {
      final gunler = <int, String>{};
      for (var c = 0; c < rows[h].length; c++) {
        final gun = _gunAdiBul(_programHucre(rows, h, c));
        if (gun != null) gunler[c] = gun;
      }
      if (gunler.length < 2) continue;
      final ilkGun = gunler.keys.reduce((a, b) => a < b ? a : b);
      final baslik = <dynamic>[''];
      final gunSatirlari = <int, List<dynamic>>{
        for (final e in gunler.entries) e.key: [e.value],
      };
      for (var r = h + 1; r < son; r++) {
        int? no;
        (String, String)? saat;
        for (var c = 0; c < ilkGun; c++) {
          final t = _programHucre(rows, r, c);
          final birlesik = _dersSaatiMetniniAyristir(t);
          no ??= birlesik?.$1 ?? _programDersNo(t);
          saat ??= _programSaatAraligi(t);
        }
        if (no == null || saat == null) continue;
        baslik.add('$no. ${saat.$1} - ${saat.$2}');
        for (final c in gunler.keys) {
          gunSatirlari[c]!.add(_programHucre(rows, r, c));
        }
      }
      if (baslik.length > 1) {
        final uyarlanmis = <List<dynamic>>[baslik, ...gunSatirlari.values];
        return _programBlogunuOku(uyarlanmis, 0, uyarlanmis.length, yer, sayfaSayisi);
      }
    }
    return null;
  }

  static (String, String)? _programSaatAraligi(String text) {
    final m = RegExp(r'(\d{1,2}[:.]\d{2})\s*[-–—]\s*(\d{1,2}[:.]\d{2})')
        .firstMatch(text);
    if (m == null) return null;
    final bas = _saatNormalize(m[1]!.replaceAll('.', ':'));
    final bit = _saatNormalize(m[2]!.replaceAll('.', ':'));
    if (bas.isEmpty || bit.isEmpty || bas.compareTo(bit) >= 0) return null;
    return (bas, bit);
  }

  static int? _programDersNo(String text) {
    final m = RegExp(r'^\s*(\d{1,2})\s*\.?\s*(?:ders)?\s*$', caseSensitive: false)
        .firstMatch(text);
    final no = m == null ? null : int.tryParse(m[1]!);
    return no != null && no > 0 && no <= 20 ? no : null;
  }

  static BireyselDersProgramiOnIzleme? _programBlogunuOku(
      List<List<dynamic>> rows, int bas, int son, String yer, int sayfaSayisi) {
    // Saatlerin bulunduğu satır aranır. Numara aynı hücrede veya üst başlıktadır.
    for (var h = bas; h < son; h++) {
      final saatler = <int, (int, String, String)>{};
      for (var c = 0; c < rows[h].length; c++) {
        final text = _programHucre(rows, h, c);
        final saat = _programSaatAraligi(text);
        if (saat == null) continue;
        final birlesik = _dersSaatiMetniniAyristir(
            text.replaceAll('\n', ' ').replaceAll('–', '-').replaceAll('—', '-'));
        int? no = birlesik?.$1;
        for (var r = h - 1; no == null && r >= bas; r--) {
          final ust = _programHucre(rows, r, c);
          if (_normalize(ust).contains('ogle') || _normalize(ust).contains('ara')) break;
          no = _programDersNo(ust);
        }
        if (no != null) saatler[c] = (no, saat.$1, saat.$2);
      }
      if (saatler.isEmpty) continue;
      if (saatler.values.map((e) => e.$1).toSet().length != saatler.length) {
        throw const FormatException('Saat başlıklarında aynı ders numarası birden fazla kez var.');
      }
      // Gün sütunu da sabit değildir; başlıklardan önceki sütunlarda aranır.
      var gunSutunu = -1;
      final ilkSaatSutunu = saatler.keys.reduce((a, b) => a < b ? a : b);
      for (var c = 0; c < ilkSaatSutunu; c++) {
        if (List.generate(son - h - 1, (i) => h + i + 1)
            .any((r) => _gunAdiBul(_programHucre(rows, r, c)) != null)) {
          gunSutunu = c;
          break;
        }
      }
      if (gunSutunu < 0) continue;
      final dersler = <BireyselDersProgramiKaydi>[];
      final seflikler = <SeflikProgramSaatiAdayi>[];
      final uyarilar = <String>[];
      final gunler = <String>{};
      final kullanilan = <String>{};
      var r = h + 1;
      while (r < son) {
        final gun = _gunAdiBul(_programHucre(rows, r, gunSutunu));
        if (gun == null) { r++; continue; }
        gunler.add(gun);
        final ilk = r;
        r++;
        // Birleşim alt hücreleri gün adını tekrarlayabilir veya boş bırakabilir.
        while (r < son) {
          final sonrakiGun = _gunAdiBul(_programHucre(rows, r, gunSutunu));
          if (sonrakiGun != null && sonrakiGun != gun) break;
          final degerler = saatler.keys.map((c) => _programHucre(rows, r, c))
              .where((t) => t.isNotEmpty).toList();
          if (degerler.isEmpty) {
            if (sonrakiGun == gun || rows[r].every((v) => (v ?? '').toString().trim().isEmpty)) {
              r++; continue;
            }
            break;
          }
          // Yalnız sınıf/oda satırları eklenir; yeni ders veya alt bilgi yutulmaz.
          if (!degerler.every((t) => t.split(RegExp(r'[\r\n]+')).every((line) =>
              _derslikSatiriMi(line) ||
              RegExp(r'^\s*(?:9|10|11|12)\s*-\s*[A-ZÇĞİÖŞÜ0-9]+\s*$', caseSensitive: false).hasMatch(line)))) {
            break;
          }
          r++;
        }
        for (final entry in saatler.entries) {
          final c = entry.key, saat = entry.value;
          final anaMetin = _programHucre(rows, ilk, c);
          if (anaMetin.isEmpty) continue;
          final key = '$gun|${saat.$1}';
          if (!kullanilan.add(key)) {
            throw FormatException('$gun ${saat.$1}. saat için birden fazla kayıt bulundu.');
          }
          final norm = _normalize(anaMetin.replaceAll('İ', 'i'));
          if (RegExp(r'^(?:(?:alan|atolye|laboratuvar|atolye laboratuvar) )?sefl(?:ik|igi)$').hasMatch(norm)) {
            seflikler.add(SeflikProgramSaatiAdayi(gun: gun, dersSaatiNo: saat.$1, hamMetin: anaMetin));
            continue;
          }
          if (norm == 'koordinatorluk') {
            dersler.add(BireyselDersProgramiKaydi(gun: gun, dersSaatiNo: saat.$1,
              saatAraligi: '${saat.$2} - ${saat.$3}', dersAdi: 'Koordinatörlük', sinif: '', derslik: ''));
            continue;
          }
          final metin = <String>{for (var k = ilk; k < r; k++) _programHucre(rows, k, c)}
              .where((t) => t.isNotEmpty).join('\n');
          final kayit = _xlsxHucreMetniniAyristir(
            gun: gun, dersSaatiNo: saat.$1, hamMetin: metin,
            saatAraligi: '${saat.$2} - ${saat.$3}',
          );
          if (kayit != null) {
            dersler.add(kayit);
          } else {
            uyarilar.add('$gun ${saat.$1}. saat: Ders/sınıf bilgisi ayrıştırılamadı: $anaMetin');
          }
        }
        // Program sona erdiyse imza ve alt bilgileri tarama dışında bırak.
        if (r < son && _gunAdiBul(_programHucre(rows, r, gunSutunu)) == null &&
            rows[r].any((v) => (v ?? '').toString().trim().isNotEmpty)) {
          break;
        }
      }
      if (gunler.isEmpty) continue;
      return BireyselDersProgramiOnIzleme(
        sayfaSayisi: sayfaSayisi,
        doluHucreSayisi: rows.sublist(bas, son).expand((r) => r)
            .where((v) => v != null && v.toString().trim().isNotEmpty).length,
        ogretmenBulundu: true, ogretmenEslesmeleri: [yer],
        gunlukDersSaatAdaylari: [for (final gun in _gunler.where(gunler.contains))
          for (final saat in saatler.values)
            BireyselGunlukDersSaatiAdayi(gun: gun, dersSaatiNo: saat.$1,
                baslangic: saat.$2, bitis: saat.$3, hamMetin: '${saat.$1}. ${saat.$2} - ${saat.$3}')],
        dersler: List.unmodifiable(dersler), seflikSaatleri: List.unmodifiable(seflikler),
        uyarilar: List.unmodifiable(uyarilar),
      );
    }
    return null;
  }

  static (int, String, String)? _dersSaatiMetniniAyristir(String metin) {
    final m = RegExp(r'^\s*(\d{1,2})\.?\s+(\d{1,2}[:.]\d{2})\s*[-–—]\s*(\d{1,2}[:.]\d{2})\s*$')
        .firstMatch(metin);
    if (m == null) return null;
    final no = _programDersNo(m[1]!);
    final saat = _programSaatAraligi('${m[2]} - ${m[3]}');
    return no == null || saat == null ? null : (no, saat.$1, saat.$2);
  }

  static String _saatNormalize(String deger) {
    final parcalar = deger.trim().split(':');
    if (parcalar.length != 2) return '';
    final saat = int.tryParse(parcalar[0]), dakika = int.tryParse(parcalar[1]);
    if (saat == null || dakika == null || saat < 0 || saat > 23 || dakika < 0 || dakika > 59) return '';
    return '${saat.toString().padLeft(2, '0')}:${dakika.toString().padLeft(2, '0')}';
  }

  static BireyselDersProgramiKaydi? _xlsxHucreMetniniAyristir({
    required String gun,
    required int dersSaatiNo,
    required String hamMetin,
    required String saatAraligi,
  }) {
    final satirlar = hamMetin
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (satirlar.isEmpty) {
      return null;
    }

    final sinifDeseni = RegExp(
      r'\b(?:9|10|11|12)\s*-\s*[A-ZÇĞİÖŞÜ0-9]+(?:\s+EĞİTİM)?\b',
      caseSensitive: false,
    );

    final karisikBilgisayarliTasarimDeseni = RegExp(
      r'^UYGBU[İI]LLGALAMBA-(\d)L,ARI$',
      caseSensitive: false,
    );

    String sinif = '';
    final dersAdiSatirlari = <String>[];
    final derslikSatirlari = <String>[];

    for (final satir in satirlar) {
      final sinifEslesmesi = sinifDeseni.firstMatch(satir);

      if (sinifEslesmesi != null) {
        sinif = sinifEslesmesi.group(0)?.trim() ?? '';
        continue;
      }

      final karisikEslesme =
          karisikBilgisayarliTasarimDeseni.firstMatch(satir);

      if (karisikEslesme != null) {
        dersAdiSatirlari.add('UYGULAMALARI');
        derslikSatirlari.add(
          'BİLGLAB-${karisikEslesme.group(1)}',
        );
        continue;
      }

      if (_derslikSatiriMi(satir)) {
        final temizDerslik = satir
            .replaceAll(RegExp(r'[,;]+$'), '')
            .trim();

        if (temizDerslik.isNotEmpty) {
          derslikSatirlari.add(temizDerslik);
        }

        continue;
      }

      dersAdiSatirlari.add(satir);
    }

    final dersAdi = dersAdiSatirlari
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final derslik = derslikSatirlari
        .join(', ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (dersAdi.isEmpty || sinif.isEmpty) {
      return null;
    }

    return BireyselDersProgramiKaydi(
      gun: gun,
      dersSaatiNo: dersSaatiNo,
      saatAraligi: saatAraligi,
      dersAdi: dersAdi,
      sinif: sinif,
      derslik: derslik,
    );
  }

  static bool _derslikSatiriMi(String satir) {
    final normalizeSatir = _normalize(satir);

    return normalizeSatir.contains('lab') ||
        normalizeSatir.contains('atolye') ||
        normalizeSatir.contains('derslik') ||
        normalizeSatir.contains('ulastirma lab') ||
        normalizeSatir.contains('buro lab');
  }

  static BireyselDersProgramiOnIzleme _xlsOnIzlemeHazirla({
    required Uint8List dosyaBytes,
    required String adSoyad,
  }) {
    final reader = XlsReader.fromBytes(dosyaBytes);
    reader.open();
    final sayfalar = <String, List<List<dynamic>>>{};
    for (var i = 0; i < reader.sheetCount; i++) {
      final sheet = reader.sheet(i);
      sayfalar[sheet.name] = [
        for (var r = 0; r < sheet.lastRow; r++)
          [for (var c = 0; c < sheet.lastCol; c++) sheet.cell(r, c)],
      ];
    }
    return _programSayfalariniOku(sayfalar: sayfalar, adSoyad: adSoyad);
  }

  static String? _gunAdiBul(String metin) {
    final normalizeMetin = _normalize(metin);

    for (final gun in _gunler) {
      if (normalizeMetin == _normalize(gun)) {
        return gun;
      }
    }

    return null;
  }

  static bool _ogretmenAdiEslesiyor({
    required String hucreMetni,
    required String adSoyad,
  }) {
    final aranan = _normalize(adSoyad.replaceAll('İ', 'i'));

    if (aranan.isEmpty) {
      return false;
    }

    final hucre = _normalize(hucreMetni.replaceAll('İ', 'i'));

    if (hucre == aranan) {
      return true;
    }

    final parcalar = hucreMetni
        .split(RegExp(r'[\r\n|;/,+]+'))
        .map(_normalize)
        .where((e) => e.isNotEmpty);

    for (final parca in parcalar) {
      if (parca == aranan) {
        return true;
      }
    }

    return _kelimeSinirliIceriyor(
      kaynak: hucre,
      aranan: aranan,
    );
  }

  static bool _kelimeSinirliIceriyor({
    required String kaynak,
    required String aranan,
  }) {
    if (!kaynak.contains(aranan)) {
      return false;
    }

    final desen = RegExp(
      r'(^| )' + RegExp.escape(aranan) + r'( |$)',
    );

    return desen.hasMatch(kaynak);
  }

  static String _normalize(String deger) {
    var sonuc = deger.trim().toLowerCase();

    const donusumler = <String, String>{
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
      'â': 'a',
      'î': 'i',
      'û': 'u',
    };

    donusumler.forEach((eski, yeni) {
      sonuc = sonuc.replaceAll(eski, yeni);
    });

    sonuc = sonuc
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return sonuc;
  }
}
