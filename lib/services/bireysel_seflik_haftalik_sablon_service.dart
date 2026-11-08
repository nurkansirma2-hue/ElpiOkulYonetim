import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import '../database/local_database.dart';
import 'bireysel_profil_service.dart';

import 'package:excel/excel.dart';

import 'belge_disari_aktar_service.dart';

/// Haftalık şeflik saati seçim formu. Yıllık faaliyet importundan ayrıdır.
class BireyselSeflikHaftalikSablonService {
  BireyselSeflikHaftalikSablonService._();

  static const _gunler = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma',
  ];

  static Uint8List olustur({required String yil, required String ogretmen}) {
    final excel = Excel.createExcel();
    final sayfa = excel['HaftalikSeflik'];
    sayfa.appendRow(['HAFTALIK ATÖLYE ŞEFLİĞİ SAAT SEÇİMİ']);
    sayfa.appendRow(['Eğitim Öğretim Yılı', yil]);
    sayfa.appendRow(['Öğretmen', ogretmen]);
    sayfa.appendRow(['Açıklama',
      'Şeflik yapılacak satırların Görev sütununa Şeflik yazın. '
      'Başlangıç/Bitiş saatlerini okulun gerçek ders saatlerine göre girin.']);
    sayfa.appendRow([]);
    sayfa.appendRow(['Gün', 'Ders Saati', 'Başlangıç', 'Bitiş', 'Görev']);
    for (final gun in _gunler) {
      for (var saat = 1; saat <= 11; saat++) {
        sayfa.appendRow([gun, '$saat', '', '', '']);
      }
    }
    sayfa.appendRow([]);
    sayfa.appendRow(['UYARI',
      'Bu formda seçilen saatler Dolu haftalık şablonu içe aktar düğmesiyle '
      'önizlenip onaylanarak ders programına kaydedilir.']);
    return Uint8List.fromList(excel.encode()!);
  }

  static Future<String?> indir({
    required String yil, required String ogretmen,
  }) => BelgeDisariAktarService.kaydet(
    'Haftalik_Seflik_Saat_Sablonu_${yil.replaceAll('-', '_')}.xlsx',
    olustur(yil: yil, ogretmen: ogretmen),
  );
  static String _deger(List<String> satir, int index) =>
      index < satir.length ? satir[index].trim() : '';

  /// XLSX dosyasındaki hücreleri doğrudan okur; styles.xml'e erişmez.
  /// Böylece Excel 2.x paketindeki "Damaged Excel file: styles"
  /// istisnası önizleme sırasında oluşmaz.
  static List<List<String>> _satirlariOku(Uint8List bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final dosyalar = <String, ArchiveFile>{
      for (final f in zip.files)
        if (f.isFile) f.name.replaceAll('\\', '/'): f,
    };
    String oku(String yol) {
      final file = dosyalar[yol];
      if (file == null) throw FormatException('Excel bileşeni eksik: $yol');
      return utf8.decode(file.content as List<int>);
    }
    Iterable<XmlElement> elemanlar(XmlNode node, String ad) =>
        node.descendants.whereType<XmlElement>()
            .where((e) => e.name.local == ad);
    String? ozellik(XmlElement e, String ad) {
      for (final a in e.attributes) {
        if (a.name.local == ad) return a.value;
      }
      return null;
    }
    final workbook = XmlDocument.parse(oku('xl/workbook.xml'));
    final sheets = elemanlar(workbook, 'sheet')
        .where((e) => ozellik(e, 'name') == 'HaftalikSeflik').toList();
    if (sheets.length != 1) {
      throw const FormatException('HaftalikSeflik sayfası bulunamadı.');
    }
    final relId = ozellik(sheets.single, 'id');
    final rels = XmlDocument.parse(oku('xl/_rels/workbook.xml.rels'));
    final hedefler = elemanlar(rels, 'Relationship')
        .where((e) => ozellik(e, 'Id') == relId).toList();
    if (hedefler.length != 1) {
      throw const FormatException('Excel sayfa bağlantısı bulunamadı.');
    }
    final target = ozellik(hedefler.single, 'Target') ?? '';
    final path = target.startsWith('/')
        ? target.substring(1)
        : target.startsWith('xl/') ? target : 'xl/$target';
    if (!path.startsWith('xl/worksheets/') || path.contains('..')) {
      throw const FormatException('Excel sayfa yolu geçersiz.');
    }
    final ortak = <String>[];
    if (dosyalar.containsKey('xl/sharedStrings.xml')) {
      final ss = XmlDocument.parse(oku('xl/sharedStrings.xml'));
      for (final si in elemanlar(ss, 'si')) {
        ortak.add(elemanlar(si, 't').map((e) => e.innerText).join());
      }
    }
    final doc = XmlDocument.parse(oku(path));
    final sonuc = <List<String>>[];
    for (final row in elemanlar(doc, 'row')) {
      final rowNo = int.tryParse(ozellik(row, 'r') ?? '');
      if (rowNo == null || rowNo < 1 || rowNo > 10000) {
        throw const FormatException('Geçersiz Excel satır numarası.');
      }
      while (sonuc.length < rowNo) {
        sonuc.add(List.filled(5, ''));
      }
      for (final cell in row.children.whereType<XmlElement>()
          .where((e) => e.name.local == 'c')) {
        final adres = ozellik(cell, 'r') ?? '';
        final harf = RegExp(r'^[A-Z]+').stringMatch(adres);
        if (harf == null) continue;
        var col = 0;
        for (final code in harf.codeUnits) {
          col = col * 26 + code - 64;
        }
        if (col < 1 || col > 5) continue;
        final type = ozellik(cell, 't');
        final v = elemanlar(cell, 'v').firstOrNull?.innerText ?? '';
        String deger;
        if (type == 's') {
          final index = int.tryParse(v);
          if (index == null || index < 0 || index >= ortak.length) {
            throw const FormatException('Excel metin tablosu indeksi geçersiz.');
          }
          deger = ortak[index];
        } else if (type == 'inlineStr') {
          deger = elemanlar(cell, 't').map((e) => e.innerText).join();
        } else {
          deger = v;
        }
        sonuc[rowNo - 1][col - 1] = deger;
      }
    }
    return sonuc;
  }

  static Future<List<({String gun, int no, String bas, String bit})>?> onIzle({
    required String yil,
    required String ogretmen,
  }) async {
    final secim = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (secim == null || secim.files.isEmpty) return null;
    final dosya = secim.files.single;
    if (dosya.size > 10 * 1024 * 1024) {
      throw const FormatException('Şablon dosyası 10 MB sınırını aşıyor.');
    }
    final bytes = dosya.bytes ?? (dosya.path == null
      ? null : await File(dosya.path!).readAsBytes());
    if (bytes == null) throw StateError('Excel dosyası okunamadı.');
    final satirlar = _satirlariOku(bytes);
    if (satirlar.length < 6) {
      throw const FormatException('Haftalık şeflik şablonu eksik.');
    }
    if (_deger(satirlar[1], 1) != yil ||
        _deger(satirlar[2], 1).toUpperCase() != ogretmen.toUpperCase()) {
      throw StateError('Şablonun öğretmeni veya eğitim yılı aktif profille uyuşmuyor.');
    }
    final baslik = satirlar[5];
    if (_deger(baslik, 0) != 'Gün' ||
        _deger(baslik, 1) != 'Ders Saati' ||
        _deger(baslik, 4) != 'Görev') {
      throw const FormatException('Şablon sütunları değiştirilmiş.');
    }
    final secilenler = <({String gun, int no, String bas, String bit})>[];
    final gorulen = <String>{};
    for (final row in satirlar.skip(6)) {
      final gorev = _deger(row, 4);
      if (gorev.isEmpty) continue;
      if (gorev.toLowerCase() != 'şeflik') {
        throw FormatException('Görev sütununda yalnız Şeflik yazılabilir: $gorev');
      }
      final gun = _deger(row, 0);
      final no = int.tryParse(_deger(row, 1).replaceAll('.0', ''));
      final bas = _deger(row, 2);
      final bit = _deger(row, 3);
      if (!_gunler.contains(gun) || no == null || no < 1 || no > 20) {
        throw FormatException('Geçersiz gün veya ders saati: $gun / $no');
      }
      if (!gorulen.add('$gun/$no')) throw StateError('Tekrar eden şeflik saati: $gun $no');
      secilenler.add((gun: gun, no: no, bas: bas, bit: bit));
    }
    if (secilenler.isEmpty) {
      throw StateError('Şablonda Görev sütununa Şeflik yazılmış saat bulunamadı.');
    }
    return secilenler;
  }

  static Future<void> kaydet({
    required String yil,
    required int profilId,
    required List<({String gun, int no, String bas, String bit})> secimler,
  }) async {
    final profil = await BireyselProfilService.getir();
    if (profil?['OgretmenProfilId'] != profilId ||
        profil?['EgitimOgretimYili'] != yil) {
      throw StateError('Öğretmen veya eğitim yılı değişti. Tekrar önizleyin.');
    }
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final surumler = await txn.rawQuery("""
        SELECT * FROM DersProgramiSurum
        WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1
          AND (BaslangicTarihi IS NULL OR BaslangicTarihi <= date('now','localtime'))
          AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime'))
      """, [profilId, yil]);
      if (surumler.length != 1) throw StateError('Aktif tek ders programı bulunamadı.');
      final surum = surumler.single['ProgramSurumId'] as int;
      final basTarih = surumler.single['BaslangicTarihi'] as String?;
      if (basTarih == null) throw StateError('Program başlangıç tarihi bilinmiyor.');
      final ayar = await txn.query('UygulamaAyarlari',
        where: 'Anahtar = ?', whereArgs: ['MeslekPaketiAktif'], limit: 1);
      if (ayar.isEmpty || ayar.single['Deger'] != '1') {
        throw StateError('Şeflik ataması için meslek paketi etkin olmalıdır.');
      }
      final simdi = DateTime.now().toIso8601String();
      for (final secim in secimler) {
        final saat = await txn.query('DersSaati',
          where: 'SiraNo = ? AND Aktif = 1', whereArgs: [secim.no]);
        if (saat.length != 1) {
          throw StateError('${secim.no}. ders saatini önce Ders Programım ekranında tanımlayın.');
        }
        final saatId = saat.single['DersSaatiId'] as int;
        final ornek = await txn.query('DersProgrami',
          columns: ['Baslangic', 'Bitis'],
          where: 'ProgramSurumId = ? AND DersSaatiId = ? AND Aktif = 1',
          whereArgs: [surum, saatId], limit: 1);
        final bas = (saat.single['Baslangic'] ?? (ornek.isEmpty ? null : ornek.single['Baslangic']))?.toString() ?? '';
        final bit = (saat.single['Bitis'] ?? (ornek.isEmpty ? null : ornek.single['Bitis']))?.toString() ?? '';
        if (bas.isEmpty || bit.isEmpty) {
          throw StateError('${secim.no}. dersin başlangıç/bitiş saatleri tanımlı değil.');
        }
        if ((secim.bas.isNotEmpty && secim.bas != bas) ||
            (secim.bit.isNotEmpty && secim.bit != bit)) {
          throw StateError('${secim.no}. dersin Excel saatleri okul çizelgesiyle uyuşmuyor.');
        }
        final ders = await txn.query('DersProgrami',
          where: 'ProgramSurumId = ? AND Gun = ? AND DersSaatiId = ? AND Aktif = 1',
          whereArgs: [surum, secim.gun, saatId], limit: 1);
        final gorev = await txn.query('DersProgramiGorev',
          where: 'ProgramSurumId = ? AND Gun = ? AND DersSaatiNo = ?',
          whereArgs: [surum, secim.gun, secim.no], limit: 1);
        final seflik = await txn.rawQuery("""
          SELECT SeflikProgramSaatiId FROM SeflikProgramSaati
          WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ?
            AND Gun = ? AND DersSaatiNo = ? AND Aktif = 1
            AND BaslangicTarihi <= date('now','localtime')
            AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime'))
          LIMIT 1
        """, [profilId, yil, secim.gun, secim.no]);
        if (ders.isNotEmpty || gorev.isNotEmpty || seflik.isNotEmpty) {
          throw StateError('${secim.gun} ${secim.no}. saat dolu; mevcut kayıt korunuyor.');
        }
        await txn.insert('SeflikProgramSaati', {
          'OgretmenProfilId': profilId, 'EgitimOgretimYili': yil,
          'SeflikId': null, 'Gun': secim.gun, 'DersSaatiNo': secim.no,
          'Baslangic': bas, 'Bitis': bit,
          'BaslangicTarihi': basTarih, 'BitisTarihi': null,
          'Kaynak': 'Manuel', 'HamMetin': 'Şeflik',
          'Aktif': 1, 'OlusturmaTarihi': simdi,
        });
      }
    });
  }

}
