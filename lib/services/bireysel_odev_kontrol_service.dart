import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:xml/xml.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/odev_kontrol.dart';
import '../models/ders_uygulama.dart';
import '../models/performans_notu.dart';
import 'bireysel_liste_service.dart';
import 'calisma_modu_service.dart';
import 'mesajlasma_service.dart';

part 'performans_not_service.dart';
part 'ders_uygulama_service.dart';

class BireyselOdevKontrolService {
  BireyselOdevKontrolService._();

  static Future<void> _modKontrol() async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Ödev Kontrol yalnız bireysel öğretmen modunda kullanılabilir.',
      );
    }
  }

  static Future<void> _oturumKontrol(
    DatabaseExecutor db,
    BireyselListeOturumu oturum,
  ) async {
    final rows = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.first['OgretmenProfilId'] != oturum.ogretmenId ||
        rows.first['EgitimOgretimYili'] != oturum.yil) {
      throw StateError(
        'Öğretmen veya eğitim yılı değişti. Ödev Kontrol ekranını yeniden açın.',
      );
    }
    final okul = await db.query('OkulProfil', where: 'Id=1 AND AktifMi=1');
    if (okul.length != 1 ||
        okul.single['OkulAdi'] != oturum.okul ||
        okul.single['EgitimYili'] != oturum.yil ||
        (oturum.okulId != null && okul.single['OkulId'] != oturum.okulId))
      throw StateError(
        'Okul veya eğitim yılı değişti. Ödev ekranını yeniden açın.',
      );
  }

  static Future<T> _islem<T>(
    String aciklama,
    BireyselListeOturumu oturum,
    Future<T> Function(Transaction txn) yap,
  ) async {
    try {
      await _modKontrol();
      final db = await LocalDatabase.instance.database;
      return await db.transaction((txn) async {
        await _oturumKontrol(txn, oturum);
        final sonuc = await yap(txn);
        await _modKontrol();
        await _oturumKontrol(txn, oturum);
        return sonuc;
      });
    } catch (e) {
      throw Exception('$aciklama\nOrijinal hata: $e');
    }
  }

  static Future<BireyselListeOturumu> hazirla() async {
    try {
      await _modKontrol();
      final oturum = await BireyselListeService.hazirla();
      return await _islem(
        'Ödev oturumu doğrulanamadı.',
        oturum,
        (_) async => oturum,
      );
    } catch (e) {
      throw Exception('Ödev Kontrol hazırlanamadı.\nOrijinal hata: $e');
    }
  }

  static Future<List<Map<String, Object?>>> ogrenciSecenekleri(
    BireyselListeOturumu oturum,
    int sinifSubeId,
  ) async {
    try {
      final rows = await BireyselListeService.ogrenciler(oturum, sinifSubeId);
      return await _islem(
        'Öğrenci seçenekleri doğrulanamadı.',
        oturum,
        (_) async => rows,
      );
    } catch (e) {
      throw Exception('Ödev öğrencileri okunamadı.\nOrijinal hata: $e');
    }
  }

  static Future<List<OdevDersSecenegi>> dersler(
    BireyselListeOturumu oturum,
    int? sinifSubeId,
  ) => _islem('Ödev dersleri okunamadı.', oturum, (txn) async {
    final rows = await txn.rawQuery(
      '''
      SELECT DISTINCT d.DersId, d.DersAdi FROM GecerliDersProgrami dp
      INNER JOIN Ders d ON d.DersId = dp.DersId
      INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
      WHERE dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ?
        AND s.EgitimOgretimYili = ?
        ${sinifSubeId == null ? '' : 'AND s.SinifSubeId = ?'}
        AND dp.Aktif = 1 AND d.Aktif = 1 AND s.Aktif = 1
    ''',
      [
        oturum.ogretmenId,
        oturum.yil,
        oturum.yil,
        if (sinifSubeId != null) sinifSubeId,
      ],
    );
    final dersler = rows.map(OdevDersSecenegi.fromMap).toList();
    dersler.sort((a, b) {
      final sonuc = _dersSirasi(a.dersAdi).compareTo(_dersSirasi(b.dersAdi));
      return sonuc == 0 ? a.dersId.compareTo(b.dersId) : sonuc;
    });
    return dersler;
  });

  // SQLite'ın varsayılan sırası Türkçe harfleri alfabenin sonuna atar.
  static String _dersSirasi(String ad) {
    const alfabe = 'abcçdefgğhıijklmnoöprsştuüvyz';
    final kucuk = ad
        .trim()
        .replaceAll('I', 'ı')
        .replaceAll('İ', 'i')
        .toLowerCase();
    return kucuk.split('').map((harf) {
      final sira = alfabe.indexOf(harf);
      return sira < 0 ? harf : String.fromCharCode(0x100 + sira);
    }).join();
  }

  static Future<List<OdevTanim>> gorevler(
    BireyselListeOturumu oturum, {
    int? sinifSubeId,
    int? dersId,
    bool pasifleriDahilEt = false,
  }) => _islem('Ödevler okunamadı.', oturum, (txn) async {
    // Geçmiş görevler güncel ders programına veya sınıf üyeliğine bağlı okunmaz.
    final rows = await txn.query(
      'OdevTanim',
      where:
          'OgretmenProfilId = ? AND EgitimOgretimYili = ?'
          '${sinifSubeId == null ? '' : ' AND SinifSubeId = ?'}'
          '${dersId == null ? '' : ' AND DersId = ?'}'
          '${pasifleriDahilEt ? '' : ' AND Aktif = 1'}',
      whereArgs: [
        oturum.ogretmenId,
        oturum.yil,
        if (sinifSubeId != null) sinifSubeId,
        if (dersId != null) dersId,
      ],
      orderBy: 'BaslangicTarihi DESC, OdevId DESC',
    );
    return rows.map(OdevTanim.fromMap).toList(growable: false);
  });

  static Future<String?> gorevListesiExcelAktar(
    BireyselListeOturumu oturum, {
    int? sinifSubeId,
    int? dersId,
    bool pasifleriDahilEt = false,
  }) async {
    final kitap = await _islem('Ödev listesi Excel için okunamadı.', oturum, (
      txn,
    ) async {
      final rows = await txn.rawQuery(
        '''
        SELECT g.*, s.SinifKodu, d.DersAdi FROM OdevTanim g
        INNER JOIN SinifSube s ON s.SinifSubeId = g.SinifSubeId
        INNER JOIN Ders d ON d.DersId = g.DersId
        WHERE g.OgretmenProfilId = ? AND g.EgitimOgretimYili = ?
        ${sinifSubeId == null ? '' : 'AND g.SinifSubeId = ?'}
        ${dersId == null ? '' : 'AND g.DersId = ?'}
        ${pasifleriDahilEt ? '' : 'AND g.Aktif = 1'}
        ORDER BY g.BaslangicTarihi DESC, g.OdevId DESC
      ''',
        [
          oturum.ogretmenId,
          oturum.yil,
          if (sinifSubeId != null) sinifSubeId,
          if (dersId != null) dersId,
        ],
      );
      final excel = _excelOlustur('Ödevler');
      final sheet = excel['Ödevler'];
      sheet.appendRow(['Öğretmen', oturum.ogretmen, 'Eğitim yılı', oturum.yil]);
      sheet.appendRow([
        'Sınıf',
        'Ders',
        'Başlık',
        'Tür',
        'Başlangıç',
        'Teslim',
        'Dönem',
        'Durum',
        'Açıklama',
      ]);
      for (final row in rows) {
        final g = OdevTanim.fromMap(row);
        sheet.appendRow([
          row['SinifKodu'],
          row['DersAdi'],
          g.baslik,
          g.gorevTuru.baslik,
          odevTarihYaz(g.baslangicTarihi),
          g.teslimTarihi == null ? '' : odevTarihYaz(g.teslimTarihi!),
          g.donem ?? '',
          g.aktif ? 'Aktif' : 'Pasif',
          g.aciklama ?? '',
        ]);
      }
      _excelBicimle(excel, sheet, 1, 9);
      return excel;
    });
    return _excelKaydet(kitap, 'Odev_Listesi');
  }

  static Future<String?> gorevDetayExcelAktar(
    BireyselListeOturumu oturum,
    int odevId,
  ) async {
    final kitap = await _islem(
      'Görev kontrolleri Excel için okunamadı.',
      oturum,
      (txn) async {
        final gorev = await _gorev(txn, oturum, odevId);
        final bilgi = (await txn.rawQuery(
          '''
        SELECT s.SinifKodu, d.DersAdi FROM OdevTanim g
        INNER JOIN SinifSube s ON s.SinifSubeId = g.SinifSubeId
        INNER JOIN Ders d ON d.DersId = g.DersId WHERE g.OdevId = ?
      ''',
          [odevId],
        )).single;
        final kontroller = await txn.query(
          'OdevKontrol',
          where: 'OdevId = ?',
          whereArgs: [odevId],
          orderBy: 'SiraNo',
        );
        final ogrenciler = await txn.rawQuery(
          '''
        SELECT k.*, o.OkulNo, o.Ad, o.Soyad FROM OdevOgrenci k
        INNER JOIN Ogrenci o ON o.OgrenciId = k.OgrenciId
        WHERE k.OdevId = ? ORDER BY CAST(o.OkulNo AS INTEGER), o.OkulNo
      ''',
          [odevId],
        );
        final sonuclar = await txn.query(
          'OdevKontrolSonuc',
          where: 'OdevId = ?',
          whereArgs: [odevId],
        );
        final sonucHaritasi = {
          for (final row in sonuclar)
            '${row['OgrenciId']}-${row['OdevKontrolId']}':
                OdevKontrolSonuc.fromMap(row),
        };
        final excel = _excelOlustur('Kontroller');
        final sheet = excel['Kontroller'];
        sheet.appendRow(['Görev', gorev.baslik, 'Tür', gorev.gorevTuru.baslik]);
        sheet.appendRow([
          'Sınıf',
          bilgi['SinifKodu'],
          'Ders',
          bilgi['DersAdi'],
        ]);
        sheet.appendRow([
          'Öğretmen',
          oturum.ogretmen,
          'Eğitim yılı',
          oturum.yil,
        ]);
        sheet.appendRow([
          'Başlangıç',
          odevTarihYaz(gorev.baslangicTarihi),
          'Teslim',
          gorev.teslimTarihi == null ? '' : odevTarihYaz(gorev.teslimTarihi!),
        ]);
        sheet.appendRow([
          'Durum',
          gorev.aktif ? 'Aktif' : 'Pasif',
          'Açıklama',
          gorev.aciklama ?? '',
        ]);
        sheet.appendRow([
          'Okul no',
          'Ad soyad',
          'Katılım',
          for (final k in kontroller) ...[
            '${k['SiraNo']}. kontrol • ${k['KontrolTarihi']}${k['Aktif'] == 1 ? '' : ' • Pasif'}',
            '${k['SiraNo']}. kontrol açıklaması',
          ],
        ]);
        for (final o in ogrenciler) {
          final row = <dynamic>[
            o['OkulNo'],
            '${o['Ad']} ${o['Soyad']}',
            o['Aktif'] == 1 ? 'Aktif' : 'Pasif',
          ];
          for (final k in kontroller) {
            final s = sonucHaritasi['${o['OgrenciId']}-${k['OdevKontrolId']}'];
            row.addAll([s?.gosterim ?? 'Dahil değil', s?.aciklama ?? '']);
          }
          sheet.appendRow(row);
        }
        final aciklamalar = excel['Durum açıklamaları'];
        aciklamalar.appendRow(['Sembol', 'Anlam']);
        for (final d in OdevKontrolDurumu.values) {
          aciklamalar.appendRow([d.sembol, d.baslik]);
        }
        aciklamalar.appendRow([
          'Dahil değil',
          'Öğrenci bu kontrole dahil edilmemiştir.',
        ]);
        aciklamalar.appendRow(['G ve M', 'Değerlendirme dışıdır.']);
        aciklamalar.setColWidth(0, 18);
        aciklamalar.setColWidth(1, 55);
        _excelBicimle(excel, sheet, 5, 3 + kontroller.length * 2);
        return excel;
      },
    );
    return _excelKaydet(kitap, 'Odev_${odevId}_Kontroller');
  }

  static Excel _excelOlustur(String sayfaAdi) {
    // excel 2.1.0'ın delete/rename işlemi archive 3.6'nın salt okunur
    // dosya listesiyle uyumsuz. Boş şablonun sayfa adını baştan belirle.
    final sablon = Excel.createExcel().encode();
    if (sablon == null) throw StateError('Excel şablonu oluşturulamadı.');
    final arsiv = ZipDecoder().decodeBytes(sablon);
    final dosya = arsiv.findFile('xl/workbook.xml');
    if (dosya == null) throw StateError('Excel çalışma kitabı bulunamadı.');
    final belge = XmlDocument.parse(utf8.decode(dosya.content as List<int>));
    belge.findAllElements('sheet').single.setAttribute('name', sayfaAdi);
    final icerik = utf8.encode(belge.toXmlString());
    arsiv.addFile(ArchiveFile(dosya.name, icerik.length, icerik));
    final bytes = ZipEncoder().encode(arsiv);
    if (bytes == null) throw StateError('Excel şablonu paketlenemedi.');
    return Excel.decodeBytes(bytes);
  }

  static void _excelBicimle(
    Excel excel,
    Sheet sheet,
    int baslikSatiri,
    int sutun,
  ) {
    excel.setDefaultSheet(sheet.sheetName);
    for (var i = 0; i < sutun; i++) {
      sheet.setColWidth(i, i == 0 ? 16 : 30);
      sheet
          .cell(
            CellIndex.indexByColumnRow(columnIndex: i, rowIndex: baslikSatiri),
          )
          .cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: 'DCE6F1',
      );
    }
  }

  static Future<String?> _excelKaydet(Excel excel, String ad) async {
    try {
      final encoded = excel.encode();
      if (encoded == null) throw StateError('Excel dosyası oluşturulamadı.');
      final bytes = Uint8List.fromList(encoded);
      final yol = await FilePicker.platform.saveFile(
        dialogTitle: 'Excel dosyasını kaydet',
        fileName: '${ad}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: bytes,
      );
      if (yol == null) return null;
      // Mobilde seçilen konuma yazmayı dosya seçici tamamlar.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(yol).writeAsBytes(bytes, flush: true);
      }
      return yol;
    } catch (e) {
      throw Exception('Excel dosyası kaydedilemedi.\nOrijinal hata: $e');
    }
  }

  static Future<OdevTanim> _gorev(
    DatabaseExecutor db,
    BireyselListeOturumu oturum,
    int odevId, {
    bool yazma = false,
  }) async {
    final rows = await db.query(
      'OdevTanim',
      where: 'OdevId = ? AND OgretmenProfilId = ? AND EgitimOgretimYili = ?',
      whereArgs: [odevId, oturum.ogretmenId, oturum.yil],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Bu öğretmene ve eğitim yılına ait görev bulunamadı.');
    }
    final gorev = OdevTanim.fromMap(rows.single);
    if (yazma && !gorev.aktif) {
      throw StateError('Pasif görev üzerinde değişiklik yapılamaz.');
    }
    return gorev;
  }

  static Future<OdevTanim> gorevGetir(
    BireyselListeOturumu oturum,
    int odevId,
  ) => _islem('Ödev okunamadı.', oturum, (txn) => _gorev(txn, oturum, odevId));

  static String? _metin(String? metin) =>
      metin == null || metin.trim().isEmpty ? null : metin.trim();

  static Map<String, Object?> _tanim({
    required OdevGorevTuru gorevTuru,
    required String baslik,
    required DateTime baslangicTarihi,
    DateTime? teslimTarihi,
    String? aciklama,
    int? donem,
  }) {
    if (baslik.trim().isEmpty) {
      throw ArgumentError('Görev başlığı boş bırakılamaz.');
    }
    if (donem != null && donem != 1 && donem != 2) {
      throw ArgumentError('Dönem 1 veya 2 olmalıdır.');
    }
    final baslangic = odevTarihYaz(baslangicTarihi);
    final teslim = teslimTarihi == null ? null : odevTarihYaz(teslimTarihi);
    if (teslim != null && teslim.compareTo(baslangic) < 0) {
      throw ArgumentError('Teslim tarihi başlangıç tarihinden önce olamaz.');
    }
    return {
      'GorevTuru': gorevTuru.kayitDegeri,
      'Baslik': baslik.trim(),
      'Aciklama': _metin(aciklama),
      'BaslangicTarihi': baslangic,
      'TeslimTarihi': teslim,
      'Donem': donem,
    };
  }

  static Future<void> _dersKontrol(
    DatabaseExecutor db,
    BireyselListeOturumu oturum,
    int sinifId,
    int dersId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT dp.DersProgramiId FROM GecerliDersProgrami dp
      INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
      INNER JOIN Ders d ON d.DersId = dp.DersId
      WHERE dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ?
        AND s.EgitimOgretimYili = ? AND dp.SinifSubeId = ? AND dp.DersId = ?
        AND dp.Aktif = 1 AND s.Aktif = 1 AND d.Aktif = 1 LIMIT 1
    ''',
      [oturum.ogretmenId, oturum.yil, oturum.yil, sinifId, dersId],
    );
    if (rows.isEmpty) {
      throw StateError(
        'Seçilen ders/sınıf aktif öğretmen programında bulunamadı.',
      );
    }
  }

  static Future<void> _katilimcilariKaydet(
    DatabaseExecutor db,
    BireyselListeOturumu oturum,
    int odevId,
    int sinifId,
    List<int> ogrenciIdleri,
    String simdi,
  ) async {
    final secilen = ogrenciIdleri.toSet();
    if (secilen.isEmpty ||
        secilen.length != ogrenciIdleri.length ||
        secilen.any((id) => id <= 0)) {
      throw ArgumentError(
        'En az bir öğrenci seçin; öğrenci kimlikleri geçerli ve tekil olmalıdır.',
      );
    }
    final mevcut = await db.query(
      'OdevOgrenci',
      where: 'OdevId = ?',
      whereArgs: [odevId],
    );
    final mevcutIdler = mevcut.map((r) => r['OgrenciId'] as int).toSet();
    for (final id in secilen.difference(mevcutIdler)) {
      final rows = await db.rawQuery(
        '''
        SELECT o.OgrenciId FROM Ogrenci o
        INNER JOIN OgrenciSinifKayit k ON k.OgrenciId = o.OgrenciId
        INNER JOIN SinifSube s ON s.SinifSubeId = k.SinifSubeId
        WHERE o.OgrenciId = ? AND k.SinifSubeId = ?
          AND k.EgitimOgretimYili = ? AND s.EgitimOgretimYili = ?
          AND o.Aktif = 1 AND k.Aktif = 1 AND s.Aktif = 1 LIMIT 1
      ''',
        [id, sinifId, oturum.yil, oturum.yil],
      );
      if (rows.isEmpty) {
        throw StateError(
          'Öğrenci seçilen sınıfa ve eğitim yılına ait değil: $id',
        );
      }
    }
    // Yeni eklenen veya yeniden etkinleştirilen öğrencilerin mevcut
    // kontrollerde eksik olan sonuçları G (Gelmedi) olarak oluşturulur.
    // Önceden kayıtlı sonuçlar hiçbir şekilde değiştirilmez.
    final eklenecekIdler = <int>{
      ...secilen.difference(mevcutIdler),
      ...mevcut.where((r) =>
          r['Aktif'] != 1 && secilen.contains(r['OgrenciId']))
          .map((r) => r['OgrenciId'] as int),
    };
    final kontroller = eklenecekIdler.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query('OdevKontrol',
            columns: ['OdevKontrolId'],
            where: 'OdevId = ?',
            whereArgs: [odevId]);
    for (final row in mevcut) {
      await db.update(
        'OdevOgrenci',
        {
          'Aktif': secilen.contains(row['OgrenciId']) ? 1 : 0,
          'GuncellemeTarihi': simdi,
        },
        where: 'OdevOgrenciId = ?',
        whereArgs: [row['OdevOgrenciId']],
      );
    }
    for (final id in secilen.difference(mevcutIdler)) {
      await db.insert('OdevOgrenci', {
        'OdevId': odevId,
        'OgrenciId': id,
        'Aktif': 1,
        'OlusturmaTarihi': simdi,
      });
    }
    for (final id in eklenecekIdler) {
      for (final kontrol in kontroller) {
        final kontrolId = kontrol['OdevKontrolId'] as int;
        final onceki = await db.query('OdevKontrolSonuc',
          columns: ['OdevKontrolSonucId'],
          where: 'OdevKontrolId = ? AND OgrenciId = ?',
          whereArgs: [kontrolId, id],
          limit: 1);
        if (onceki.isNotEmpty) continue;
        await db.insert('OdevKontrolSonuc', {
          'OdevId': odevId,
          'OdevKontrolId': kontrolId,
          'OgrenciId': id,
          'Durum': OdevKontrolDurumu.gelmedi.kayitDegeri,
          'NotDegeri': null,
          'OlusturmaTarihi': simdi,
        });
      }
    }
  }

  static Future<int> gorevOlustur(
    BireyselListeOturumu oturum, {
    required int sinifSubeId,
    required int dersId,
    required OdevGorevTuru gorevTuru,
    required String baslik,
    required DateTime baslangicTarihi,
    required List<int> ogrenciIdleri,
    DateTime? teslimTarihi,
    String? aciklama,
    int? donem,
    bool kontrolBaslat = false,
    bool dersUygulamalari = false,
    String? ekAdi,
    Uint8List? ekVeri,
  }) {
    final idler = List<int>.of(ogrenciIdleri);
    return _islem('Ödev oluşturulamadı. İşlem geri alındı.', oturum, (
      txn,
    ) async {
      if (dersUygulamalari && gorevTuru != OdevGorevTuru.rutinKontrol) {
        throw ArgumentError('Ders uygulamaları rutin kontrol alt türüdür.');
      }
      final veri = _tanim(
        gorevTuru: gorevTuru,
        baslik: baslik,
        baslangicTarihi: baslangicTarihi,
        teslimTarihi: teslimTarihi,
        aciklama: aciklama,
        donem: donem,
      );
      await _dersKontrol(txn, oturum, sinifSubeId, dersId);
      final simdi = DateTime.now().toIso8601String();
      final id = await txn.insert('OdevTanim', {
        ...veri,
        'DersUygulamalari': dersUygulamalari ? 1 : 0,
        'OgretmenProfilId': oturum.ogretmenId,
        'EgitimOgretimYili': oturum.yil,
        'SinifSubeId': sinifSubeId,
        'DersId': dersId,
        'Aktif': 1,
        'OlusturmaTarihi': simdi,
      });
      await _katilimcilariKaydet(txn, oturum, id, sinifSubeId, idler, simdi);
      if (kontrolBaslat) {
        final k = await txn.insert('OdevKontrol', {
          'OdevId': id,
          'KontrolTarihi': odevTarihYaz(baslangicTarihi),
          'SiraNo': 1,
          'OlusturmaTarihi': simdi,
        });
        for (final oid in idler) {
          await txn.insert('OdevKontrolSonuc', {
            'OdevId': id,
            'OdevKontrolId': k,
            'OgrenciId': oid,
            'OlusturmaTarihi': simdi,
          });
        }
      }
      if (ekVeri != null) {
        if (ekAdi == null ||
            ekAdi.trim().isEmpty ||
            ekVeri.isEmpty ||
            ekVeri.length > 10485760) {
          throw ArgumentError('Ek dosya geçersiz veya 10 MB sınırını aşıyor.');
        }
        await txn.insert('OdevEk', {
          'OdevId': id,
          'DosyaAdi': ekAdi,
          'Veri': Uint8List.fromList(ekVeri),
        });
      }
      return id;
    });
  }

  /// Ders/sınıf/profil/yıl sabittir. Null öğrenci listesi katılımı korur.
  static Future<void> gorevGuncelle(
    BireyselListeOturumu oturum,
    int odevId, {
    required OdevGorevTuru gorevTuru,
    required String baslik,
    required DateTime baslangicTarihi,
    DateTime? teslimTarihi,
    String? aciklama,
    int? donem,
    List<int>? ogrenciIdleri,
  }) {
    final idler = ogrenciIdleri == null ? null : List<int>.of(ogrenciIdleri);
    return _islem('Ödev güncellenemedi. İşlem geri alındı.', oturum, (
      txn,
    ) async {
      final gorev = await _gorev(txn, oturum, odevId, yazma: true);
      if (gorev.dersUygulamalari && gorevTuru != OdevGorevTuru.rutinKontrol) {
        throw StateError('Uygulama geçmişi olan görevin türü değiştirilemez.');
      }
      final veri = _tanim(
        gorevTuru: gorevTuru,
        baslik: baslik,
        baslangicTarihi: baslangicTarihi,
        teslimTarihi: teslimTarihi,
        aciklama: aciklama,
        donem: donem,
      );
      if (donem != null &&
          (await txn.rawQuery(
            'SELECT p.Id FROM PerformansTanim p JOIN PerformansOdev x ON x.PerformansId=p.Id WHERE x.OdevId=? AND p.Donem<>?',
            [odevId, donem],
          )).isNotEmpty) {
        throw StateError(
          'Ödev farklı dönem performansına seçili. Önce ilgili P1/P2 seçiminden çıkarın.',
        );
      }
      final kontroller = await txn.query(
        'OdevKontrol',
        columns: ['KontrolTarihi'],
        where: 'OdevId = ?',
        whereArgs: [odevId],
        orderBy: 'KontrolTarihi ASC',
        limit: 1,
      );
      if (kontroller.isNotEmpty) {
        final ilkKontrol = kontroller.first['KontrolTarihi'] as String;
        final yeniBaslangic = veri['BaslangicTarihi'] as String;
        if (yeniBaslangic.compareTo(ilkKontrol) > 0) {
          throw ArgumentError(
            'Görev başlangıç tarihi mevcut en erken kontrol '
            'tarihinden ($ilkKontrol) sonra olamaz.',
          );
        }
      }
      final simdi = DateTime.now().toIso8601String();
      if (idler != null) {
        await _katilimcilariKaydet(
          txn,
          oturum,
          odevId,
          gorev.sinifSubeId,
          idler,
          simdi,
        );
      }
      await txn.update(
        'OdevTanim',
        {...veri, 'GuncellemeTarihi': simdi},
        where: 'OdevId = ?',
        whereArgs: [odevId],
      );
    });
  }

  /// Seçilen görevleri bağlı puan/sonuç kayıtlarıyla birlikte atomik siler.
  static Future<void> gorevleriSil(
    BireyselListeOturumu oturum,
    Set<int> idler, {
    bool mesajlariSil = false,
  }) {
    final secilen = Set<int>.of(idler);
    return _islem('Ödevler silinemedi. İşlem geri alındı.', oturum, (
      txn,
    ) async {
      if (secilen.isEmpty) throw ArgumentError('En az bir ödev seçin.');
      for (final id in secilen) {
        await _gorev(txn, oturum, id);
      }
      await MesajlasmaService.instance.odevBildirimleriniKaldir(
        txn,
        secilen,
        sil: mesajlariSil,
      );
      for (final id in secilen) {
        await _gorevKayitlariniSil(txn, id);
      }
    });
  }

  static Future<void> _gorevKayitlariniSil(DatabaseExecutor db, int id) async {
    await db.delete(
      'OdevDegerlendirmePuani',
      where:
          '''OlcutId IN (SELECT OlcutId FROM OdevDegerlendirmeOlcutu WHERE OdevId = ?)
         OR OdevKontrolSonucId IN (SELECT OdevKontrolSonucId FROM OdevKontrolSonuc WHERE OdevId = ?)
    ''',
      whereArgs: [id, id],
    );
    for (final tablo in [
      'OdevUygulamaSonuc',
      'OdevUygulama',
      'OdevDegerlendirmeOlcutu',
      'OdevKontrolSonuc',
      'OdevKontrol',
      'OdevOgrenci',
      'OdevTanim',
    ]) {
      await db.delete(tablo, where: 'OdevId = ?', whereArgs: [id]);
    }
  }

  /// Defter görevleri yalnız aynı sınıf/ders/tür/dönem/durum içinde birleşir.
  /// Kontroller kopyalanır; aynı tarihli farklı kontroller birbirini ezmez.
  static Future<int> defterGorevleriniBirlestir(
    BireyselListeOturumu oturum,
    Set<int> idler,
  ) {
    final secilen = idler.toList()..sort();
    return _islem('Defter ödevleri birleştirilemedi. İşlem geri alındı.', oturum, (
      txn,
    ) async {
      if (secilen.length < 2) {
        throw ArgumentError('En az iki defter ödevi seçin.');
      }
      for (final id in secilen) {
        if ((await txn.query(
          'PerformansOdev',
          where: 'OdevId=?',
          whereArgs: [id],
        )).isNotEmpty) {
          throw StateError(
            'Performans hesabına seçilmiş ödevleri birleştirmeden önce ilgili P1/P2 seçiminden çıkarın.',
          );
        }
      }
      final gorevler = <OdevTanim>[];
      for (final id in secilen) {
        gorevler.add(await _gorev(txn, oturum, id));
      }
      final temel = gorevler.first;
      if (gorevler.any((g) => g.dersUygulamalari)) {
        throw StateError('Ders uygulamaları birleştirilemez; kayıtlar korunuyor.');
      }
      if (gorevler.any(
        (g) =>
            !g.baslik.toLowerCase().contains('defter') ||
            g.sinifSubeId != temel.sinifSubeId ||
            g.dersId != temel.dersId ||
            g.gorevTuru != temel.gorevTuru ||
            g.donem != temel.donem ||
            g.aktif != temel.aktif,
      )) {
        throw StateError(
          'Aynı sınıf, ders, tür, dönem ve aktiflikteki defter ödevlerini seçin.',
        );
      }
      final marks = List.filled(secilen.length, '?').join(',');
      final azami =
          Sqflite.firstIntValue(
            await txn.rawQuery('''
        SELECT COALESCE(SUM(o.AzamiPuan), 0) FROM OdevDegerlendirmeOlcutu o
        JOIN OdevKontrol k ON k.OdevKontrolId = o.OdevKontrolId
        WHERE o.OdevId IN ($marks) AND k.Aktif = 1
      ''', secilen),
          ) ??
          0;
      if (azami > 100) {
        throw StateError(
          'Birleşen ölçütlerin toplamı 100 puanı aşıyor. Ödevler korunuyor.',
        );
      }
      final simdi = DateTime.now().toIso8601String();
      final baslangiclar =
          gorevler.map((g) => odevTarihYaz(g.baslangicTarihi)).toList()..sort();
      final teslimler =
          gorevler
              .where((g) => g.teslimTarihi != null)
              .map((g) => odevTarihYaz(g.teslimTarihi!))
              .toList()
            ..sort();
      // Yeni ana kayıt, kaynakların tarih ve açıklamalarını da saklar.
      final hedef = await txn.insert('OdevTanim', {
        'OgretmenProfilId': oturum.ogretmenId,
        'EgitimOgretimYili': oturum.yil,
        'SinifSubeId': temel.sinifSubeId,
        'DersId': temel.dersId,
        'Donem': temel.donem,
        'GorevTuru': temel.gorevTuru.kayitDegeri,
        'Baslik': 'Defter Kontrol',
        'BaslangicTarihi': baslangiclar.first,
        'TeslimTarihi': teslimler.isEmpty ? null : teslimler.last,
        'Aktif': temel.aktif ? 1 : 0,
        'OlusturmaTarihi': simdi,
        'Aciklama': gorevler
            .map(
              (g) =>
                  '${g.baslik}\nBaşlangıç: ${odevTarihYaz(g.baslangicTarihi)}'
                  '${g.teslimTarihi == null ? '' : '\nTeslim: ${odevTarihYaz(g.teslimTarihi!)}'}'
                  '${g.aciklama == null ? '' : '\n${g.aciklama}'}',
            )
            .join('\n\n'),
      });
      var sira = 0;
      for (final g in gorevler) {
        final katilim = await txn.query(
          'OdevOgrenci',
          where: 'OdevId = ?',
          whereArgs: [g.odevId],
        );
        for (final k in katilim) {
          final mevcut = await txn.query(
            'OdevOgrenci',
            where: 'OdevId = ? AND OgrenciId = ?',
            whereArgs: [hedef, k['OgrenciId']],
          );
          if (mevcut.isEmpty) {
            await txn.insert('OdevOgrenci', {
              ...k,
              'OdevOgrenciId': null,
              'OdevId': hedef,
            });
          } else if (k['Aktif'] == 1) {
            await txn.update(
              'OdevOgrenci',
              {'Aktif': 1},
              where: 'OdevOgrenciId = ?',
              whereArgs: [mevcut.single['OdevOgrenciId']],
            );
          }
        }
        final kontroller = await txn.query(
          'OdevKontrol',
          where: 'OdevId = ?',
          whereArgs: [g.odevId],
          orderBy: 'SiraNo',
        );
        for (final k in kontroller) {
          final yeniKontrol = await txn.insert('OdevKontrol', {
            ...k,
            'OdevKontrolId': null,
            'OdevId': hedef,
            'SiraNo': ++sira,
            'Aciklama':
                '${g.baslik}${k['Aciklama'] == null ? '' : '\n${k['Aciklama']}'}',
          });
          final sonucMap = <int, int>{};
          final sonuclar = await txn.query(
            'OdevKontrolSonuc',
            where: 'OdevKontrolId = ?',
            whereArgs: [k['OdevKontrolId']],
          );
          for (final sonuc in sonuclar) {
            sonucMap[sonuc['OdevKontrolSonucId'] as int] = await txn
                .insert('OdevKontrolSonuc', {
                  ...sonuc,
                  'OdevKontrolSonucId': null,
                  'OdevId': hedef,
                  'OdevKontrolId': yeniKontrol,
                });
          }
          final olcutler = await txn.query(
            'OdevDegerlendirmeOlcutu',
            where: 'OdevKontrolId = ?',
            whereArgs: [k['OdevKontrolId']],
          );
          for (final o in olcutler) {
            final yeniOlcut = await txn.insert('OdevDegerlendirmeOlcutu', {
              ...o,
              'OlcutId': null,
              'OdevId': hedef,
              'OdevKontrolId': yeniKontrol,
            });
            final puanlar = await txn.query(
              'OdevDegerlendirmePuani',
              where: 'OlcutId = ?',
              whereArgs: [o['OlcutId']],
            );
            for (final puan in puanlar) {
              final yeniSonuc = sonucMap[puan['OdevKontrolSonucId']];
              if (yeniSonuc == null) {
                throw StateError('Puanın öğrenci sonucu bulunamadı.');
              }
              await txn.insert('OdevDegerlendirmePuani', {
                ...puan,
                'OlcutId': yeniOlcut,
                'OdevKontrolSonucId': yeniSonuc,
              });
            }
          }
        }
      }
      for (final id in secilen) {
        await _gorevKayitlariniSil(txn, id);
      }
      return hedef;
    });
  }

  static Future<void> gorevPasiflestir(
    BireyselListeOturumu oturum,
    int odevId,
  ) => _islem('Ödev pasifleştirilemedi.', oturum, (txn) async {
    await _gorev(txn, oturum, odevId);
    await txn.update(
      'OdevTanim',
      {'Aktif': 0, 'GuncellemeTarihi': DateTime.now().toIso8601String()},
      where: 'OdevId = ?',
      whereArgs: [odevId],
    );
  });

  /// Katılımı pasifleştirir; öğrenci, kontrol ve not kayıtlarını silmez.
  static Future<void> katilimcilariCikar(
    BireyselListeOturumu oturum,
    int odevId,
    Set<int> ogrenciIdleri,
  ) => _islem('Öğrenciler ödevden çıkarılamadı.', oturum, (txn) async {
    if (ogrenciIdleri.isEmpty) return;
    await _gorev(txn, oturum, odevId, yazma: true);
    final simdi = DateTime.now().toIso8601String();
    for (final id in ogrenciIdleri) {
      final kayit = await txn.query('OdevOgrenci',
        columns: ['OdevOgrenciId'],
        where: 'OdevId = ? AND OgrenciId = ? AND Aktif = 1',
        whereArgs: [odevId, id], limit: 1);
      if (kayit.isEmpty) {
        throw StateError('Ödevde aktif öğrenci bulunamadı: $id');
      }
      await txn.update('OdevOgrenci',
        {'Aktif': 0, 'GuncellemeTarihi': simdi},
        where: 'OdevId = ? AND OgrenciId = ? AND Aktif = 1',
        whereArgs: [odevId, id]);
    }
  });

  static Future<List<OdevOgrenci>> katilimcilar(
    BireyselListeOturumu oturum,
    int odevId,
  ) => _islem('Görev öğrencileri okunamadı.', oturum, (txn) async {
    await _gorev(txn, oturum, odevId);
    final rows = await txn.rawQuery(
      '''
      SELECT k.*, o.OkulNo, o.Ad, o.Soyad, f.FotoVerisi, f.DosyaYolu FROM OdevOgrenci k
      INNER JOIN Ogrenci o ON o.OgrenciId = k.OgrenciId
      LEFT JOIN OgrenciFotograf f ON f.OgrenciId = o.OgrenciId AND f.Aktif = 1
      WHERE k.OdevId = ? ORDER BY CAST(o.OkulNo AS INTEGER), o.OkulNo
    ''',
      [odevId],
    );
    return rows.map(OdevOgrenci.fromMap).toList(growable: false);
  });

  static Future<List<OdevKontrol>> kontroller(
    BireyselListeOturumu oturum,
    int odevId,
  ) => _islem('Kontroller okunamadı.', oturum, (txn) async {
    await _gorev(txn, oturum, odevId);
    final rows = await txn.query(
      'OdevKontrol',
      where: 'OdevId = ?',
      whereArgs: [odevId],
      orderBy: 'SiraNo',
    );
    return rows.map(OdevKontrol.fromMap).toList(growable: false);
  });

  static Future<int> kontrolOlustur(
    BireyselListeOturumu oturum,
    int odevId, {
    required DateTime kontrolTarihi,
    String? aciklama,
  }) => _islem('Kontrol oluşturulamadı. İşlem geri alındı.', oturum, (
    txn,
  ) async {
    final gorev = await _gorev(txn, oturum, odevId, yazma: true);
    final tarih = odevTarihYaz(kontrolTarihi);
    if (tarih.compareTo(odevTarihYaz(gorev.baslangicTarihi)) < 0) {
      throw ArgumentError('Kontrol tarihi görev başlangıcından önce olamaz.');
    }
    final katilim = await txn.query(
      'OdevOgrenci',
      where: 'OdevId = ? AND Aktif = 1',
      whereArgs: [odevId],
    );
    if (katilim.isEmpty) {
      throw StateError('Kontrol için aktif görev öğrencisi bulunamadı.');
    }
    final sira = Sqflite.firstIntValue(
      await txn.rawQuery(
        'SELECT COALESCE(MAX(SiraNo), 0) + 1 FROM OdevKontrol WHERE OdevId = ?',
        [odevId],
      ),
    )!;
    final simdi = DateTime.now().toIso8601String();
    final id = await txn.insert('OdevKontrol', {
      'OdevId': odevId,
      'KontrolTarihi': tarih,
      'SiraNo': sira,
      'Aciklama': _metin(aciklama),
      'Aktif': 1,
      'OlusturmaTarihi': simdi,
    });
    for (final ogrenci in katilim) {
      await txn.insert('OdevKontrolSonuc', {
        'OdevId': odevId,
        'OdevKontrolId': id,
        'OgrenciId': ogrenci['OgrenciId'],
        'Durum': OdevKontrolDurumu.kontrolEdilmedi.kayitDegeri,
        'OlusturmaTarihi': simdi,
      });
    }
    return id;
  });

  /// Seçili kontrolü ve yalnızca ona bağlı değerlendirmeleri atomik siler.
  static Future<void> kontrolSil(
    BireyselListeOturumu oturum,
    int kontrolId,
  ) => _islem('Kontrol silinemedi. İşlem geri alındı.', oturum, (txn) async {
    final kontrol = await _kontrol(txn, oturum, kontrolId, yazma: true);
    await txn.delete('OdevUygulamaSonuc', where: 'OdevKontrolId = ?', whereArgs: [kontrolId]);
    await txn.rawDelete(
      '''
      DELETE FROM OdevDegerlendirmePuani
      WHERE OlcutId IN (
        SELECT OlcutId FROM OdevDegerlendirmeOlcutu
        WHERE OdevKontrolId = ?
      ) OR OdevKontrolSonucId IN (
        SELECT OdevKontrolSonucId FROM OdevKontrolSonuc
        WHERE OdevKontrolId = ?
      )
      ''',
      [kontrolId, kontrolId],
    );
    await txn.delete(
      'OdevDegerlendirmeOlcutu',
      where: 'OdevKontrolId = ? AND OdevId = ?',
      whereArgs: [kontrolId, kontrol.odevId],
    );
    await txn.delete(
      'OdevKontrolSonuc',
      where: 'OdevKontrolId = ? AND OdevId = ?',
      whereArgs: [kontrolId, kontrol.odevId],
    );
    final silinen = await txn.delete(
      'OdevKontrol',
      where: 'OdevKontrolId = ? AND OdevId = ?',
      whereArgs: [kontrolId, kontrol.odevId],
    );
    if (silinen != 1) {
      throw StateError('Kontrol kaydı silinemedi.');
    }
  });

  static Future<void> kontrolAciklamaKaydet(
    BireyselListeOturumu oturum,
    int kontrolId,
    String aciklama,
  ) => _islem('Kontrol açıklaması kaydedilemedi.', oturum, (txn) async {
    await _kontrol(txn, oturum, kontrolId, yazma: true);
    if (aciklama.length > 1000) {
      throw ArgumentError(
        'Kontrol açıklaması en fazla 1000 karakter olabilir.',
      );
    }
    await txn.update(
      'OdevKontrol',
      {'Aciklama': _metin(aciklama)},
      where: 'OdevKontrolId = ?',
      whereArgs: [kontrolId],
    );
  });

  static Future<OdevKontrol> _kontrol(
    DatabaseExecutor db,
    BireyselListeOturumu oturum,
    int kontrolId, {
    bool yazma = false,
  }) async {
    final rows = await db.query(
      'OdevKontrol',
      where: 'OdevKontrolId = ?',
      whereArgs: [kontrolId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Kontrol bulunamadı.');
    final kontrol = OdevKontrol.fromMap(rows.single);
    await _gorev(db, oturum, kontrol.odevId, yazma: yazma);
    if (yazma && !kontrol.aktif) {
      throw StateError('Pasif kontrol değiştirilemez.');
    }
    return kontrol;
  }

  /// Bir ara kontrolün ölçütleri. Normal ve rutin görevlerde kullanılmaz.
  static Future<List<Map<String, Object?>>> degerlendirmeOlcutleri(
    BireyselListeOturumu oturum,
    int kontrolId,
  ) => _islem('Ölçütler okunamadı.', oturum, (txn) async {
    await _kontrol(txn, oturum, kontrolId);
    return txn.query(
      'OdevDegerlendirmeOlcutu',
      where: 'OdevKontrolId = ?',
      whereArgs: [kontrolId],
      orderBy: 'Sira',
    );
  });

  /// Ölçütler yalnızca henüz puanlama başlamamış bir kontrolde değiştirilebilir.
  /// Her kontrolün azami puanları toplamı 100'ü aşamaz.
  static Future<void> degerlendirmeOlcutleriniKaydet(
    BireyselListeOturumu oturum,
    int kontrolId,
    List<Map<String, Object?>> olcutler,
  ) => _islem('Ölçütler kaydedilemedi. İşlem geri alındı.', oturum, (
    txn,
  ) async {
    final kontrol = await _kontrol(txn, oturum, kontrolId, yazma: true);
    final gorev = await _gorev(txn, oturum, kontrol.odevId, yazma: true);
    if (gorev.gorevTuru != OdevGorevTuru.proje &&
        gorev.gorevTuru != OdevGorevTuru.performans) {
      throw StateError(
        'Ölçütlü puanlama yalnız proje ve performans görevlerinde kullanılabilir.',
      );
    }
    if (olcutler.isEmpty || olcutler.length > 20) {
      throw ArgumentError('Bir kontrol için 1 ile 20 arasında ölçüt girin.');
    }
    var toplam = 0;
    final basliklar = <String>{};
    for (final olcut in olcutler) {
      final baslik = (olcut['Baslik'] as String?)?.trim() ?? '';
      final azami = olcut['AzamiPuan'];
      if (baslik.isEmpty ||
          baslik.length > 150 ||
          azami is! int ||
          azami < 1 ||
          azami > 100 ||
          !basliklar.add(baslik.toLowerCase())) {
        throw ArgumentError(
          'Ölçüt başlıkları benzersiz ve 1-150 karakter, puanları 1-100 olmalıdır.',
        );
      }
      toplam += azami;
    }
    final digerToplam =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            '''
      SELECT COALESCE(SUM(o.AzamiPuan), 0)
      FROM OdevDegerlendirmeOlcutu o
      JOIN OdevKontrol k ON k.OdevKontrolId = o.OdevKontrolId
      WHERE o.OdevId = ? AND o.OdevKontrolId <> ? AND k.Aktif = 1
    ''',
            [kontrol.odevId, kontrolId],
          ),
        ) ??
        0;
    if (toplam + digerToplam > 100) {
      throw ArgumentError(
        'Görevin tüm aktif kontrollerindeki ölçüt puanları toplamı 100\'ü aşamaz.',
      );
    }
    final mevcutPuan =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            '''
      SELECT COUNT(*) FROM OdevDegerlendirmePuani p
      JOIN OdevDegerlendirmeOlcutu o ON o.OlcutId = p.OlcutId
      WHERE o.OdevKontrolId = ?
    ''',
            [kontrolId],
          ),
        ) ??
        0;
    if (mevcutPuan > 0) {
      throw StateError(
        'Öğrenci puanları girildikten sonra ölçütler değiştirilemez.',
      );
    }
    await txn.delete(
      'OdevDegerlendirmeOlcutu',
      where: 'OdevKontrolId = ?',
      whereArgs: [kontrolId],
    );
    for (var i = 0; i < olcutler.length; i++) {
      await txn.insert('OdevDegerlendirmeOlcutu', {
        'OdevId': kontrol.odevId,
        'OdevKontrolId': kontrolId,
        'Sira': i + 1,
        'Baslik': (olcutler[i]['Baslik'] as String).trim(),
        'AzamiPuan': olcutler[i]['AzamiPuan'],
      });
    }
  });

  static Future<List<Map<String, Object?>>> degerlendirmePuanlari(
    BireyselListeOturumu oturum,
    int kontrolId,
  ) => _islem('Puanlar okunamadı.', oturum, (txn) async {
    await _kontrol(txn, oturum, kontrolId);
    return txn.rawQuery(
      '''
      SELECT p.OlcutId, p.OdevKontrolSonucId, p.Puan
      FROM OdevDegerlendirmePuani p
      JOIN OdevDegerlendirmeOlcutu o ON o.OlcutId = p.OlcutId
      WHERE o.OdevKontrolId = ?
    ''',
      [kontrolId],
    );
  });

  /// Boş puan, değerlendirilmedi anlamına gelir; sıfır puan değildir.
  static Future<void> degerlendirmePuaniKaydet(
    BireyselListeOturumu oturum,
    int kontrolId,
    int ogrenciId,
    Map<int, int?> puanlar,
  ) => _islem('Öğrenci puanları kaydedilemedi. İşlem geri alındı.', oturum, (
    txn,
  ) async {
    await _kontrol(txn, oturum, kontrolId, yazma: true);
    final sonuc = await txn.query(
      'OdevKontrolSonuc',
      columns: ['OdevKontrolSonucId'],
      where: 'OdevKontrolId = ? AND OgrenciId = ?',
      whereArgs: [kontrolId, ogrenciId],
      limit: 1,
    );
    if (sonuc.isEmpty) throw StateError('Öğrenci bu kontrole dahil değil.');
    final sonucId = sonuc.single['OdevKontrolSonucId'] as int;
    final olcutler = await txn.query(
      'OdevDegerlendirmeOlcutu',
      where: 'OdevKontrolId = ?',
      whereArgs: [kontrolId],
    );
    final izinli = {
      for (final o in olcutler) o['OlcutId'] as int: o['AzamiPuan'] as int,
    };
    if (izinli.isEmpty) {
      throw StateError('Önce değerlendirme ölçütlerini oluşturun.');
    }
    for (final entry in puanlar.entries) {
      final azami = izinli[entry.key];
      if (azami == null ||
          (entry.value != null && (entry.value! < 0 || entry.value! > azami))) {
        throw ArgumentError('Geçersiz ölçüt veya puan.');
      }
      await txn.delete(
        'OdevDegerlendirmePuani',
        where: 'OlcutId = ? AND OdevKontrolSonucId = ?',
        whereArgs: [entry.key, sonucId],
      );
      if (entry.value != null) {
        await txn.insert('OdevDegerlendirmePuani', {
          'OlcutId': entry.key,
          'OdevKontrolSonucId': sonucId,
          'Puan': entry.value,
        });
      }
    }
  });

  static Future<List<OdevKontrolSonuc>> sonuclar(
    BireyselListeOturumu oturum,
    int kontrolId,
  ) => _islem('Kontrol sonuçları okunamadı.', oturum, (txn) async {
    await _kontrol(txn, oturum, kontrolId);
    final rows = await txn.query(
      'OdevKontrolSonuc',
      where: 'OdevKontrolId = ?',
      whereArgs: [kontrolId],
      orderBy: 'OgrenciId',
    );
    return rows.map(OdevKontrolSonuc.fromMap).toList(growable: false);
  });

  /// Yalnız kontrol oluşturulurken dahil edilmiş öğrenciler güncellenir.
  /// Listede gönderilmeyen sonuçlar aynen korunur.
  static Future<void> sonuclariKaydet(
    BireyselListeOturumu oturum,
    int kontrolId,
    List<OdevSonucGirdisi> girdiler,
  ) {
    final kayitlar = List<OdevSonucGirdisi>.of(girdiler);
    return _islem(
      'Kontrol sonuçları kaydedilemedi. İşlem geri alındı.',
      oturum,
      (txn) async {
        final kontrol = await _kontrol(txn, oturum, kontrolId, yazma: true);
        if (kayitlar.isEmpty ||
            kayitlar.map((r) => r.ogrenciId).toSet().length !=
                kayitlar.length) {
          throw ArgumentError(
            'Sonuç listesi boş olamaz; aynı öğrenci tekrarlanamaz.',
          );
        }
        final simdi = DateTime.now().toIso8601String();
        for (final kayit in kayitlar) {
          final n = kayit.notDegeri ?? OdevKontrolSonuc.hizliNot(kayit.durum);
          if (n != null && (n < 0 || n > 10)) {
            throw ArgumentError('Ödev puanı 0–10 olmalıdır.');
          }
          if (kayit.durum == OdevKontrolDurumu.manuel &&
              kayit.notDegeri == null) {
            throw ArgumentError('Manuel puan girin.');
          }
          if (n != null && OdevKontrolSonuc.notDurumu(n, null) != kayit.durum) {
            throw ArgumentError('Hızlı durum ile puan çelişiyor.');
          }
          final eskiDurum = switch (kayit.durum) {
            OdevKontrolDurumu.manuel => OdevKontrolDurumu.kontrolEdilmedi,
            _ => kayit.durum,
          };
          final adet = await txn.update(
            'OdevKontrolSonuc',
            {
              'Durum': eskiDurum.kayitDegeri,
              'NotDegeri': n,
              'Aciklama': _metin(kayit.aciklama),
              'GuncellemeTarihi': simdi,
            },
            where: 'OdevKontrolId = ? AND OdevId = ? AND OgrenciId = ?',
            whereArgs: [kontrolId, kontrol.odevId, kayit.ogrenciId],
          );
          if (adet != 1) {
            throw StateError(
              'Öğrenci bu kontrole dahil değil: ${kayit.ogrenciId}',
            );
          }
        }
      },
    );
  }

  static Future<List<Map<String, Object?>>> ogrenciGecmisi(
    BireyselListeOturumu o,
    int ogrenciId,
  ) => _islem(
    'Öğrenci ödev geçmişi okunamadı.',
    o,
    (db) => db.rawQuery(
      '''SELECT g.Baslik,x.OkulNo,x.Ad,x.Soyad,c.SinifKodu,k.KontrolTarihi,s.*
      FROM OdevOgrenci a JOIN OdevTanim g ON g.OdevId=a.OdevId
      JOIN Ogrenci x ON x.OgrenciId=a.OgrenciId JOIN SinifSube c ON c.SinifSubeId=g.SinifSubeId
      LEFT JOIN OdevKontrol k ON k.OdevId=g.OdevId
      LEFT JOIN OdevKontrolSonuc s ON s.OdevKontrolId=k.OdevKontrolId AND s.OgrenciId=x.OgrenciId
      WHERE g.OgretmenProfilId=? AND g.EgitimOgretimYili=? AND a.OgrenciId=?
      ORDER BY g.BaslangicTarihi DESC,k.KontrolTarihi DESC''',
      [o.ogretmenId, o.yil, ogrenciId],
    ),
  );

  static Future<void> tamamlanmaKaydet(
    BireyselListeOturumu o,
    int id,
    bool tamam,
  ) => _islem('Ödev durumu kaydedilemedi.', o, (db) async {
    await _gorev(db, o, id, yazma: true);
    await db.update(
      'OdevTanim',
      {'Tamamlandi': tamam ? 1 : 0},
      where: 'OdevId=?',
      whereArgs: [id],
    );
  });
  static Future<Map<int, Map<String, int>>> listeOzeti(
    BireyselListeOturumu o,
  ) => _islem('Ödev özeti okunamadı.', o, (db) async {
    final rows = await db.rawQuery(
      '''SELECT a.OdevId,a.OgrenciId,s.Durum,s.NotDegeri FROM OdevOgrenci a
        JOIN OdevTanim g ON g.OdevId=a.OdevId
        LEFT JOIN OdevKontrolSonuc s ON s.OdevId=g.OdevId AND s.OgrenciId=a.OgrenciId
          AND s.OdevKontrolId=(SELECT k.OdevKontrolId FROM OdevKontrol k WHERE k.OdevId=g.OdevId AND k.Aktif=1 ORDER BY k.SiraNo DESC LIMIT 1)
        WHERE g.OgretmenProfilId=? AND g.EgitimOgretimYili=? AND a.Aktif=1''',
      [o.ogretmenId, o.yil],
    );
    final m = <int, Map<String, int>>{};
    for (final r in rows) {
      final d = m.putIfAbsent(
        r['OdevId'] as int,
        () => {'toplam': 0, 'girilen': 0},
      );
      d['toplam'] = d['toplam']! + 1;
      if (r['Durum'] != null &&
          !OdevKontrolSonuc.notDurumu(
            r['NotDegeri'] as int?,
            r['Durum'],
          ).bekliyor) {
        d['girilen'] = d['girilen']! + 1;
      }
    }
    final uygulamaRows = await db.rawQuery('''
      SELECT g.OdevId,u.UygulamaId,a.OgrenciId,
        (SELECT s.Durum FROM OdevUygulamaSonuc s
          JOIN OdevKontrol k ON k.OdevKontrolId=s.OdevKontrolId
          WHERE s.OdevId=g.OdevId AND s.UygulamaId=u.UygulamaId
            AND s.OgrenciId=a.OgrenciId AND k.Aktif=1
          ORDER BY k.KontrolTarihi DESC,k.SiraNo DESC,k.OdevKontrolId DESC LIMIT 1) AS Durum
      FROM OdevTanim g JOIN OdevOgrenci a ON a.OdevId=g.OdevId AND a.Aktif=1
      LEFT JOIN OdevUygulama u ON u.OdevId=g.OdevId AND u.Aktif=1
      WHERE g.DersUygulamalari=1 AND g.OgretmenProfilId=? AND g.EgitimOgretimYili=?
    ''', [o.ogretmenId,o.yil]);
    final uygulamaOzetleri = <int, Map<String,int>>{};
    for (final r in uygulamaRows) {
      final d = uygulamaOzetleri.putIfAbsent(r['OdevId'] as int, () => {'toplam':0,'girilen':0});
      if (r['UygulamaId'] != null) {
        d['toplam'] = d['toplam']! + 1;
        if (r['Durum'] != null && r['Durum'] != 'KontrolEdilmedi') d['girilen'] = d['girilen']! + 1;
      }
    }
    m.addAll(uygulamaOzetleri);
    return m;
  });
}
