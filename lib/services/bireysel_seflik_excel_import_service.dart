import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'bireysel_ders_programi_service.dart';
import 'bireysel_seflik_yillik_plan_service.dart';

class SeflikExcelImportSonucu {
  const SeflikExcelImportSonucu(this.taslak, this.sayfaAdi, this.haftaSayisi, this.bilgiler);
  final SeflikYillikPlanTaslagi taslak;
  final String sayfaAdi;
  final int haftaSayisi;
  final List<String> bilgiler;
}

/// Excel'deki haftalık faaliyetleri gerçek ders programı saatlerine yerleştirir.
class BireyselSeflikExcelImportService {
  BireyselSeflikExcelImportService._();
  static const _aylar = <String, int>{
    'OCAK': 1, 'SUBAT': 2, 'MART': 3, 'NISAN': 4, 'MAYIS': 5,
    'HAZIRAN': 6, 'TEMMUZ': 7, 'AGUSTOS': 8, 'EYLUL': 9,
    'EKIM': 10, 'KASIM': 11, 'ARALIK': 12,
  };

  static String _norm(String s) => s.toUpperCase()
      .replaceAll('İ', 'I').replaceAll('İ', 'I')
      .replaceAll('Ş', 'S').replaceAll('Ğ', 'G')
      .replaceAll('Ü', 'U').replaceAll('Ö', 'O')
      .replaceAll('Ç', 'C').replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String _cell(List<Data?> satir, int i) =>
      i < satir.length ? (satir[i]?.value?.toString() ?? '').trim() : '';

  static Future<Uint8List?> dosyaSec() async {
    final secim = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (secim == null || secim.files.isEmpty) return null;
    final dosya = secim.files.single;
    if (dosya.size > 15 * 1024 * 1024) {
      throw const FormatException('Excel dosyası 15 MB sınırını aşıyor.');
    }
    if (dosya.bytes != null) return dosya.bytes!;
    if (dosya.path == null) throw StateError('Dosya okunamadı.');
    return File(dosya.path!).readAsBytes();
  }

  static DateTime? _haftaBasi(String metin, int ilkYil) {
    final temiz = _norm(metin);
    final aylar = _aylar.keys.where(temiz.contains).toList();
    final sayilar = RegExp(r'\d+').allMatches(metin)
        .map((m) => int.parse(m.group(0)!)).toList();
    if (aylar.isEmpty || sayilar.isEmpty) return null;
    final ay = _aylar[aylar.first]!;
    final gun = sayilar.first;
    final yil = ay >= 9 ? ilkYil : ilkYil + 1;
    if (gun < 1 || gun > DateTime(yil, ay + 1, 0).day) return null;
    return DateTime(yil, ay, gun);
  }

  /// Excel paketinin bazı Office style kayıtlarını çözemediği dosyalarda
  /// sadece okuma amaçlı bir kopyanın stillerini sadeleştirir.
  /// Orijinal dosya ve hücre verileri değiştirilmez.
  static Excel _excelOku(Uint8List bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } on ArgumentError catch (e) {
      if (!e.toString().contains('Damaged Excel file: styles')) rethrow;
      // Bu dosyalarda OOXML etiketleri x: önekiyle yazılmış olabiliyor.
      // excel 2.x okuyucusu bu ad alanlı styleSheet'i desteklemiyor.
      // Yalnız bellekteki kopyanın XML etiketlerini normalleştir.
      final archive = ZipDecoder().decodeBytes(bytes);
      final yeni = Archive();
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final icerik = f.content as List<int>;
        if (f.name.endsWith('.xml') || f.name.endsWith('.rels')) {
          final metin = utf8.decode(icerik);
          final temiz = metin
              .replaceAllMapped(RegExp(r'<(/?)x:'), (m) => '<${m.group(1)}')
              .replaceAll('xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"',
                  'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"');
          final veri = Uint8List.fromList(utf8.encode(temiz));
          yeni.addFile(ArchiveFile(f.name, veri.length, veri));
        } else {
          yeni.addFile(ArchiveFile(f.name, icerik.length, icerik));
        }
      }
      return Excel.decodeBytes(Uint8List.fromList(ZipEncoder().encode(yeni)!));
    }
  }

  static Future<SeflikExcelImportSonucu> onIzleme({
    required Uint8List bytes,
    required String ogretmenAdi,
    required int ogretmenProfilId,
    required String egitimOgretimYili,
  }) async {
    final eslesme = RegExp(r'^(\d{4})\D+(\d{4})$')
        .firstMatch(egitimOgretimYili);
    if (eslesme == null ||
        int.parse(eslesme.group(2)!) != int.parse(eslesme.group(1)!) + 1) {
      throw FormatException('Eğitim öğretim yılı geçersiz.');
    }
    final ilkYil = int.parse(eslesme.group(1)!);
    final excel = _excelOku(bytes);
    final ad = _norm(ogretmenAdi);
    final sayfalar = excel.tables.entries.where((e) =>
        _norm(e.key) == ad).toList();
    if (sayfalar.length != 1) {
      throw StateError('Excel içinde öğretmen adına eşleşen tek sayfa bulunamadı. '
          'Aktif profil: $ogretmenAdi');
    }
    final sheet = sayfalar.single.value;
    final satirlar = sheet.rows;
    if (satirlar.length < 7 ||
        _norm(_cell(satirlar[5], 0)) != 'AY' ||
        _norm(_cell(satirlar[5], 1)) != 'HAFTA' ||
        _norm(_cell(satirlar[5], 4)) != 'YAPILACAKCALISMALAR') {
      throw FormatException('Şeflik Excel dosyasının sütunları beklenen biçimde değil.');
    }
    final dosyaYil = RegExp(r'(\d{4})\s*[-–]\s*(\d{4})')
        .firstMatch(_cell(satirlar[1], 0));
    if (dosyaYil == null || dosyaYil.group(1) != eslesme.group(1) ||
        dosyaYil.group(2) != eslesme.group(2)) {
      throw StateError('Excel eğitim öğretim yılı aktif profille eşleşmiyor.');
    }
    final faaliyetler = <SeflikYillikFaaliyet>[];
    final uyarilar = <String>[];
    final bilgiler = <String>[];
    final gorulen = <int>{};
    for (var i = 6; i < satirlar.length; i++) {
      final row = satirlar[i];
      final no = int.tryParse(_cell(row, 1).replaceAll('.0', ''));
      if (no == null) continue;
      if (!gorulen.add(no)) throw FormatException('Excel haftası tekrar ediyor: $no');
      final bas = _haftaBasi(_cell(row, 2), ilkYil);
      final konu = _cell(row, 4);
      final beklenenSaat = int.tryParse(_cell(row, 3).replaceAll('.0', ''));
      if (bas == null || konu.isEmpty || beklenenSaat == null) {
        uyarilar.add('$no. hafta: Tarih, saat veya faaliyet eksik.');
        continue;
      }
      final tatil = _norm(konu).contains('TATIL');
      var toplam = 0;
      for (var offset = 0; offset < 5; offset++) {
        final tarih = bas.add(Duration(days: offset));
        if (tarih.weekday > DateTime.friday) continue;
        final program = await BireyselDersProgramiService.haftalikProgramiGetir(
          ogretmenProfilId: ogretmenProfilId,
          egitimOgretimYili: egitimOgretimYili, tarih: tarih);
        final gunSaatleri = program.where(
          (s) => s.seflikMi && s.gunNo == tarih.weekday).toList();
        if (tatil) continue;
        for (final saat in gunSaatleri) {
          toplam++;
          faaliyetler.add(SeflikYillikFaaliyet(
            tarih: tarih, gun: saat.gun,
            dersSaatiNo: saat.dersSaatiNo,
            baslangic: saat.baslangic, bitis: saat.bitis,
            faaliyet: konu,
          ));
        }
      }
      if (!tatil && toplam != beklenenSaat) {
        bilgiler.add('$no. hafta: Excel $beklenenSaat saat, '
            'ders programı $toplam saat. Plan ders programındaki $toplam saate uyarlandı.');
      }
    }
    if (gorulen.isEmpty) {
      throw FormatException('Excel içinde haftalık faaliyet bulunamadı.');
    }
    if (faaliyetler.isEmpty) uyarilar.add('İçe aktarılabilecek şeflik saati bulunamadı.');
    return SeflikExcelImportSonucu(
      SeflikYillikPlanTaslagi(
        egitimOgretimYili: egitimOgretimYili,
        faaliyetler: List.unmodifiable(faaliyetler),
        uyarilar: List.unmodifiable(uyarilar)),
      sayfalar.single.key, gorulen.length,
      List.unmodifiable(bilgiler));
  }
}
