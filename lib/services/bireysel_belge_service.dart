import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/bireysel_belge.dart';
import '../models/ortak_import.dart';
import 'calisma_modu_service.dart';
import 'bireysel_yillik_plan_service.dart';

class BireyselBelgeService {
  BireyselBelgeService({
    Future<Database> Function()? databaseGetir,
    Future<Directory> Function()? alanGetir,
    Future<Directory> Function()? geciciAlanGetir,
    Future<CalismaModu?> Function()? modGetir,
  }) : _databaseGetir =
           databaseGetir ?? (() => LocalDatabase.instance.database),
       _alanGetir = alanGetir ?? getApplicationSupportDirectory,
       _geciciAlanGetir = geciciAlanGetir ?? getTemporaryDirectory,
       _modGetir = modGetir ?? CalismaModuService.getir;

  static final instance = BireyselBelgeService();
  static const azamiBoyut = 50 * 1024 * 1024;
  static const uzantilar = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'csv',
    'txt',
    'rtf',
    'odt',
    'ods',
    'ppt',
    'pptx',
    'jpg',
    'jpeg',
    'png',
  };
  final Future<Database> Function() _databaseGetir;
  final Future<Directory> Function() _alanGetir;
  final Future<Directory> Function() _geciciAlanGetir;
  final Future<CalismaModu?> Function() _modGetir;
  static Future<void> _sira = Future.value();

  // Uzlaştırma, ekleme ve açma aynı özel dosyayı eşzamanlı değiştirmez.
  Future<T> _sirali<T>(Future<T> Function() action) {
    final result = _sira.then((_) => action());
    _sira = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Bakım, belge ekleme/silme ile aynı dosya kilidini kullanır.
  Future<T> bakimIslemi<T>(Future<T> Function() action) => _sirali(action);

  Future<void> _moduDogrula() async {
    if (await _modGetir() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Belgelerim yalnız bireysel öğretmen modunda açılabilir.',
      );
    }
  }

  Future<Map<String, Object?>> _profil(DatabaseExecutor db) async {
    final okul = await db.query('OkulProfil', where: 'Id = 1 AND AktifMi = 1');
    final profil = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (okul.length != 1 ||
        profil.isEmpty ||
        (okul.single['OkulId'] as String).trim().isEmpty ||
        okul.single['EgitimYili'] != profil.single['EgitimOgretimYili'] ||
        okul.single['OkulAdi'] != profil.single['OkulAdi']) {
      throw StateError('Önce bireysel öğretmen ve okul kurulumunu tamamlayın.');
    }
    return {...profil.single, 'OkulId': okul.single['OkulId']};
  }

  static String _kimlik() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Directory> _kok() async {
    final alan = await _alanGetir();
    final kok = Directory(p.join(alan.path, 'bireysel_belgeler'));
    final type = await FileSystemEntity.type(kok.path, followLinks: false);
    if (type != FileSystemEntityType.directory &&
        type != FileSystemEntityType.notFound) {
      throw StateError('Belge dosya alanı güvenli biçimde açılamadı.');
    }
    await kok.create(recursive: true);
    return kok;
  }

  File _dosya(Directory kok, BireyselBelge belge) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(belge.arsivId) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(belge.id) ||
        !uzantilar.contains(belge.uzanti) ||
        belge.goreliYol != '${belge.arsivId}/${belge.id}.${belge.uzanti}') {
      throw StateError('Belgenin kayıtlı dosya yolu geçersiz.');
    }
    return File(p.join(kok.path, belge.arsivId, '${belge.id}.${belge.uzanti}'));
  }

  Future<void> _normalDosya(File file) async {
    final parentType = await FileSystemEntity.type(
      file.parent.path,
      followLinks: false,
    );
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if ((parentType != FileSystemEntityType.directory &&
            parentType != FileSystemEntityType.notFound) ||
        (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.notFound)) {
      throw StateError('Belge dosya alanı güvenli biçimde okunamadı.');
    }
  }

  Future<BelgeArsivListesi> arsivleriGetir() => _sirali(() async {
    await _moduDogrula();
    final db = await _databaseGetir();
    return db.transaction((txn) async {
      final profil = await _profil(txn);
      final mevcut = await txn.query(
        'BelgeArsivi',
        where: 'OkulId = ? AND OgretmenProfilId = ?',
        whereArgs: [profil['OkulId'], profil['OgretmenProfilId']],
      );
      if (mevcut.isEmpty) {
        await txn.insert('BelgeArsivi', {
          'ArsivId': _kimlik(),
          'OkulId': profil['OkulId'],
          'OgretmenProfilId': profil['OgretmenProfilId'],
          'OkulAdi': profil['OkulAdi'],
          'OgretmenAdi': profil['AdSoyad'],
          'OlusturmaTarihi': DateTime.now().toIso8601String(),
        });
      }
      final rows = await txn.query(
        'BelgeArsivi',
        orderBy: 'OlusturmaTarihi DESC',
      );
      final arsivler = rows.map(BelgeArsivi.fromMap).toList();
      final aktif = arsivler.singleWhere(
        (a) =>
            a.okulId == profil['OkulId'] &&
            a.ogretmenProfilId == profil['OgretmenProfilId'],
      );
      return BelgeArsivListesi(
        aktif,
        List.unmodifiable([aktif, ...arsivler.where((a) => a.id != aktif.id)]),
      );
    });
  });

  Future<void> _arsiviDogrula(DatabaseExecutor db, String id) async {
    await _profil(db);
    if ((await db.query(
      'BelgeArsivi',
      where: 'ArsivId = ?',
      whereArgs: [id],
    )).isEmpty) {
      throw StateError('Belge arşivi bulunamadı. Ekranı yeniden açın.');
    }
  }

  Future<void> _eklemeKapsaminiDogrula(
    DatabaseExecutor db,
    String id,
    String yil,
  ) async {
    final profil = await _profil(db);
    final rows = await db.query(
      'BelgeArsivi',
      where: 'ArsivId = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty ||
        rows.single['OkulId'] != profil['OkulId'] ||
        rows.single['OgretmenProfilId'] != profil['OgretmenProfilId'] ||
        profil['EgitimOgretimYili'] != yil) {
      throw StateError(
        'Okul, öğretmen veya eğitim yılı değişti. Belgeyi yeniden seçin.',
      );
    }
  }

  Future<List<BireyselBelge>> listele({
    required String arsivId,
    String arama = '',
    int offset = 0,
    int limit = 50,
    String? klasorId,
    bool tumKlasorler = true,
    String? tur,
    String? yil,
    bool copKutusu = false,
  }) => _sirali(() async {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError('Geçersiz sayfa.');
    }
    await _moduDogrula();
    final db = await _databaseGetir();
    await _arsiviDogrula(db, arsivId);
    final kok = await _kok();
    await _uzlastir(db, kok, arsivId);
    final rows = await db.query(
      'BireyselBelge',
      columns: [
        '*',
        '(SELECT MAX(Tarih) FROM BelgeImportGecmisi g WHERE g.BelgeId = BireyselBelge.BelgeId) AS SonImport',
      ],
      where:
          "ArsivId = ? AND Durum != 'Hazirlaniyor' AND instr(AramaAdi, ?) > 0 "
          'AND SilinmeTarihi IS ${copKutusu ? 'NOT ' : ''}NULL '
          '${tumKlasorler ? '' : 'AND KlasorId IS ? '}'
          '${tur == null ? '' : 'AND BelgeTuru = ? '}'
          '${yil == null ? '' : 'AND EgitimOgretimYili = ? '}',
      whereArgs: [
        arsivId,
        importNormalize(arama),
        if (!tumKlasorler) klasorId,
        if (tur != null) tur,
        if (yil != null) yil,
      ],
      orderBy: 'EklenmeTarihi DESC, BelgeId DESC',
      limit: limit,
      offset: offset,
    );
    final result = <BireyselBelge>[];
    for (final row in rows) {
      var belge = BireyselBelge.fromMap(row);
      final file = _dosya(kok, belge);
      await _normalDosya(file);
      final mevcut = await file.exists() && await file.length() == belge.boyut;
      if (!mevcut && belge.acilabilir) {
        await db.update(
          'BireyselBelge',
          {'Durum': 'Eksik'},
          where: 'BelgeId = ?',
          whereArgs: [belge.id],
        );
        belge = BireyselBelge.fromMap({...row, 'Durum': 'Eksik'});
      }
      result.add(belge);
    }
    await _moduDogrula();
    await _arsiviDogrula(db, arsivId);
    return result;
  });

  Future<BelgeEklemeSonucu> ekle({
    required String arsivId,
    required PlatformFile dosya,
    void Function(int, int)? ilerleme,
    String? klasorId,
  }) => _sirali(() => _ekle(
    arsivId: arsivId,
    dosya: dosya,
    ilerleme: ilerleme,
    klasorId: klasorId,
  ));

  Future<BelgeEklemeSonucu> _ekle({
    required String arsivId,
    required PlatformFile dosya,
    void Function(int, int)? ilerleme,
    String? klasorId,
    bool ayniIcerigiKullan = true,
    Future<void> Function(Transaction, String)? kaydiBagla,
  }) async {
    await _moduDogrula();
    final ad = dosya.name.replaceAll('\\', '/').split('/').last.trim();
    final uzanti = p.extension(ad).replaceFirst('.', '').toLowerCase();
    if (ad.isEmpty ||
        ad.length > 240 ||
        RegExp(r'[\x00-\x1f]').hasMatch(ad) ||
        !uzantilar.contains(uzanti)) {
      throw const FormatException(
        'Desteklenen bir Word, Excel, PDF, metin veya görsel dosyası seçin.',
      );
    }
    if (dosya.size <= 0 || dosya.size > azamiBoyut) {
      throw const FormatException('Dosya boş veya 50 MB sınırından büyük.');
    }
    final Stream<List<int>> kaynak;
    if (dosya.readStream != null) {
      kaynak = dosya.readStream!;
    } else if (dosya.path != null) {
      kaynak = File(dosya.path!).openRead();
    } else if (dosya.bytes != null) {
      kaynak = Stream.value(dosya.bytes!);
    } else {
      throw StateError('Dosya okunamadı; cihazdan yeniden seçin.');
    }
    final db = await _databaseGetir();
    final profil = await _profil(db);
    final yil = profil['EgitimOgretimYili'] as String;
    final id = _kimlik();
    final row = <String, Object?>{
      'BelgeId': id,
      'ArsivId': arsivId,
      'DosyaAdi': ad,
      'AramaAdi': importNormalize(ad),
      'GoreliYol': '$arsivId/$id.$uzanti',
      'Uzanti': uzanti,
      'Boyut': dosya.size,
      'IcerikOzeti': null,
      'EgitimOgretimYili': yil,
      'EklenmeTarihi': DateTime.now().toIso8601String(),
      'Durum': 'Hazirlaniyor',
      'KlasorId': klasorId,
    };
    final kok = await _kok();
    final hedef = _dosya(kok, BireyselBelge.fromMap(row));
    await hedef.parent.create(recursive: true);
    await _normalDosya(hedef);
    final gecici = File('${hedef.path}.tmp');
    await _normalDosya(gecici);
    await db.transaction((txn) async {
      await _eklemeKapsaminiDogrula(txn, arsivId, yil);
      await _klasoruDogrula(txn, arsivId, klasorId);
      await txn.insert('BireyselBelge', row);
      await kaydiBagla?.call(txn, id);
    });
    var tamamlandi = false;
    var geriKazanilabilir = false;
    try {
      final sink = gecici.openWrite();
      var boyut = 0;
      try {
        await for (final bytes in kaynak) {
          boyut += bytes.length;
          if (boyut > azamiBoyut || boyut > dosya.size) {
            throw const FormatException(
              'Dosyanın boyutu seçim bilgisiyle uyuşmuyor veya 50 MB sınırını aşıyor.',
            );
          }
          sink.add(bytes);
          await sink.flush();
          ilerleme?.call(boyut, dosya.size);
        }
      } finally {
        await sink.close();
      }
      if (boyut != dosya.size) {
        throw const FormatException('Dosya tam okunamadı; yeniden seçin.');
      }
      final ozet = await _ozet(gecici);
      await _moduDogrula();
      await _eklemeKapsaminiDogrula(db, arsivId, yil);
      final adaylar = !ayniIcerigiKullan ? <Map<String, Object?>>[] : await db.query(
        'BireyselBelge',
        where:
            "ArsivId = ? AND Boyut = ? AND IcerikOzeti = ? AND Durum = 'Hazir'",
        whereArgs: [arsivId, boyut, ozet],
      );
      for (final aday in adaylar) {
        final belge = BireyselBelge.fromMap(aday);
        final file = _dosya(kok, belge);
        await _normalDosya(file);
        // CRC32 yalnız aday süzer. Çakışmalar tam içerik karşılaştırmasıyla ayrılır.
        if (await file.exists() && await _ayni(gecici, file)) {
          await _moduDogrula();
          await db.transaction((txn) async {
            await _eklemeKapsaminiDogrula(txn, arsivId, yil);
            // Çöp kutusundaki aynı dosya yeniden eklendiğinde geri alınır.
            await txn.update(
              'BireyselBelge',
              {'SilinmeTarihi': null},
              where: 'BelgeId = ?',
              whereArgs: [belge.id],
            );
            await txn.delete(
              'BireyselBelge',
              where: 'BelgeId = ?',
              whereArgs: [id],
            );
          });
          await gecici.delete();
          tamamlandi = true;
          return BelgeEklemeSonucu(
            BireyselBelge.fromMap({...aday, 'SilinmeTarihi': null}),
            zatenVar: true,
          );
        }
      }
      row['IcerikOzeti'] = ozet;
      await db.update(
        'BireyselBelge',
        {'IcerikOzeti': ozet},
        where: 'BelgeId = ?',
        whereArgs: [id],
      );
      geriKazanilabilir = true;
      await gecici.rename(hedef.path);
      await _moduDogrula();
      await db.transaction((txn) async {
        await _eklemeKapsaminiDogrula(txn, arsivId, yil);
        await kaydiBagla?.call(txn, id);
        await txn.update(
          'BireyselBelge',
          {'Durum': 'Hazir'},
          where: 'BelgeId = ?',
          whereArgs: [id],
        );
      });
      tamamlandi = true;
      return BelgeEklemeSonucu(
        BireyselBelge.fromMap({...row, 'Durum': 'Hazir'}),
        zatenVar: false,
      );
    } finally {
      if (!tamamlandi && !geriKazanilabilir) {
        // Yalnız bu işlemin oluşturduğu geçici kopya temizlenir; kaynak korunur.
        if (await gecici.exists()) await gecici.delete();
        await db.delete('BireyselBelge', where: 'BelgeId = ?', whereArgs: [id]);
      }
    }
  }

  Future<Map<String, Object?>> _gunlukPlaniDogrula(
    DatabaseExecutor db, int id, int surum,
  ) async {
    await _moduDogrula();
    final profil = await _profil(db);
    final rows = await db.query('BireyselGunlukPlan',
      where: 'GunlukPlanId = ?', whereArgs: [id]);
    if (rows.length != 1 || rows.single['Surum'] != surum ||
        rows.single['OkulId'] != profil['OkulId'] ||
        rows.single['OgretmenProfilId'] != profil['OgretmenProfilId'] ||
        BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
          rows.single['EgitimOgretimYili'].toString()) !=
        BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
          profil['EgitimOgretimYili'].toString())) {
      throw StateError('Günlük plan, öğretmen veya eğitim yılı değişti. Planı yeniden açın.');
    }
    return rows.single;
  }

  /// Aynı günlük planın PDF'i aynı belge kimliği ve dosya yolunda güncellenir.
  Future<BireyselBelge> gunlukPlanPdfKaydet({
    required int gunlukPlanId,
    required int surum,
    required Uint8List bytes,
  }) => _sirali(() async {
    if (gunlukPlanId <= 0 || surum <= 0 || bytes.length < 5 ||
        bytes.length > azamiBoyut ||
        bytes[0] != 0x25 || bytes[1] != 0x50 || bytes[2] != 0x44 ||
        bytes[3] != 0x46 || bytes[4] != 0x2d) {
      throw const FormatException('Kaydedilmiş bir günlük plan ve geçerli PDF içeriği gerekli.');
    }
    final db = await _databaseGetir();
    final plan = await _gunlukPlaniDogrula(db, gunlukPlanId, surum);
    final profil = await _profil(db);
    final hamYil = profil['EgitimOgretimYili'] as String;
    final arsivId = await db.transaction((txn) async {
      await _gunlukPlaniDogrula(txn, gunlukPlanId, surum);
      final arsivler = await txn.query('BelgeArsivi',
        where: 'OkulId = ? AND OgretmenProfilId = ?',
        whereArgs: [plan['OkulId'], plan['OgretmenProfilId']]);
      if (arsivler.isNotEmpty) return arsivler.single['ArsivId'] as String;
      final id = _kimlik();
      await txn.insert('BelgeArsivi', {
        'ArsivId': id, 'OkulId': profil['OkulId'],
        'OgretmenProfilId': profil['OgretmenProfilId'],
        'OkulAdi': profil['OkulAdi'], 'OgretmenAdi': profil['AdSoyad'],
        'OlusturmaTarihi': DateTime.now().toIso8601String(),
      });
      return id;
    });
    final kok = await _kok();
    await _uzlastir(db, kok, arsivId);
    final guncelPlan = await _gunlukPlaniDogrula(db, gunlukPlanId, surum);
    final eskiId = guncelPlan['BelgeId'] as String?;

    Future<void> bagla(Transaction txn, String belgeId) async {
      final asil = await _gunlukPlaniDogrula(txn, gunlukPlanId, surum);
      if (asil['BelgeId'] != eskiId && asil['BelgeId'] != belgeId) {
        throw StateError('Günlük planın belge bağlantısı değişti. Yeniden deneyin.');
      }
      await _eklemeKapsaminiDogrula(txn, arsivId, hamYil);
      final count = await txn.update('BireyselGunlukPlan', {'BelgeId': belgeId},
        where: 'GunlukPlanId = ? AND Surum = ? AND BelgeId IS ?',
        whereArgs: [gunlukPlanId, surum, asil['BelgeId']]);
      if (count != 1) throw StateError('Günlük plan değişti. Yeniden açın.');
    }

    if (eskiId == null) {
      final sonuc = await _ekle(
        arsivId: arsivId,
        dosya: PlatformFile(name: 'Gunluk_Plan_$gunlukPlanId.pdf',
          size: bytes.length, bytes: bytes),
        ayniIcerigiKullan: false,
        kaydiBagla: bagla,
      );
      return sonuc.belge;
    }

    final rows = await db.query('BireyselBelge',
      where: 'BelgeId = ? AND ArsivId = ?', whereArgs: [eskiId, arsivId]);
    final paylasilan = await db.query('BireyselGunlukPlan',
      columns: ['GunlukPlanId'], where: 'BelgeId = ? AND GunlukPlanId != ?',
      whereArgs: [eskiId, gunlukPlanId]);
    if (rows.length != 1 || rows.single['Uzanti'] != 'pdf' ||
        BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
          rows.single['EgitimOgretimYili'].toString()) !=
        BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(hamYil) ||
        paylasilan.isNotEmpty) {
      throw StateError('Günlük planın PDF bağlantısı bu arşive ait değil.');
    }
    final belge = BireyselBelge.fromMap(rows.single);
    final hedef = _dosya(kok, belge);
    await hedef.parent.create(recursive: true);
    await _normalDosya(hedef);
    final gecici = File('${hedef.path}.tmp');
    await _normalDosya(gecici);
    var bekleyenKayit = false;
    try {
      await gecici.writeAsBytes(bytes, flush: true);
      final ozet = await _ozet(gecici);
      await db.transaction((txn) async {
        await bagla(txn, eskiId);
        final count = await txn.update('BireyselBelge', {
          'Boyut': bytes.length, 'IcerikOzeti': ozet,
          'Durum': 'Hazirlaniyor', 'SilinmeTarihi': null, 'Analiz': null,
        }, where: 'BelgeId = ? AND ArsivId = ?',
          whereArgs: [eskiId, arsivId]);
        if (count != 1) throw StateError('Günlük planın PDF kaydı bulunamadı.');
      });
      bekleyenKayit = true;
      await gecici.rename(hedef.path);
      await db.transaction((txn) async {
        await bagla(txn, eskiId);
        await txn.update('BireyselBelge', {'Durum': 'Hazir'},
          where: 'BelgeId = ? AND ArsivId = ?', whereArgs: [eskiId, arsivId]);
      });
      return BireyselBelge.fromMap({
        ...rows.single, 'Boyut': bytes.length, 'IcerikOzeti': ozet,
        'Durum': 'Hazir', 'SilinmeTarihi': null, 'Analiz': null,
      });
    } finally {
      // Hazırlanıyor kaydı varsa sonraki açılış sağlam .tmp dosyasını tamamlar.
      if (!bekleyenKayit && await gecici.exists()) await gecici.delete();
    }
  });

  /// Uygulama içi salt okuma için doğrulanmış arşiv yolu.
  Future<String> dosyaYolunuGetir({
    required String arsivId,
    required String belgeId,
  }) => _sirali(() async {
    await _moduDogrula();
    final db = await _databaseGetir();
    await _arsiviDogrula(db, arsivId);
    final rows = await db.query(
      'BireyselBelge',
      where: 'BelgeId = ? AND ArsivId = ?',
      whereArgs: [belgeId, arsivId],
    );
    if (rows.isEmpty) throw StateError('Belge bu arşivde bulunamadı.');
    final belge = BireyselBelge.fromMap(rows.single);
    final file = _dosya(await _kok(), belge);
    await _normalDosya(file);
    if (!await _butunluk(file, belge)) {
      await db.update(
        'BireyselBelge',
        {'Durum': 'Eksik'},
        where: 'BelgeId = ?',
        whereArgs: [belgeId],
      );
      throw StateError(
        'Belgenin dosyası eksik veya değişmiş. Orijinal dosyayı yeniden ekleyin.',
      );
    }
    if (!belge.acilabilir) {
      await db.update(
        'BireyselBelge',
        {'Durum': 'Hazir'},
        where: 'BelgeId = ?',
        whereArgs: [belgeId],
      );
    }
    await _moduDogrula();
    await _arsiviDogrula(db, arsivId);
    return file.path;
  });

  /// open_file dış uygulamaya yazma izni de verir; arşiv orijinali paylaşılmaz.
  Future<String> acmaYolunuGetir({
    required String arsivId,
    required String belgeId,
  }) async {
    final kaynakYolu = await dosyaYolunuGetir(
      arsivId: arsivId,
      belgeId: belgeId,
    );
    return _sirali(() async {
      await _moduDogrula();
      final db = await _databaseGetir();
      await _arsiviDogrula(db, arsivId);
      final alan = await _geciciAlanGetir();
      final klasor = Directory(p.join(alan.path, 'belge_goruntuleme'));
      final type = await FileSystemEntity.type(klasor.path, followLinks: false);
      if (type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.notFound) {
        throw StateError('Geçici görüntüleme alanı açılamadı.');
      }
      await klasor.create(recursive: true);
      // Yalnız kendi oluşturduğumuz görüntüleme dosyalarını temizleriz.
      // En son açılan dosyanın kopyası tutulur; arşiv iki kat büyümez.
      await for (final entity in klasor.list(followLinks: false)) {
        if (entity is File &&
            RegExp(
              r'^[a-f0-9]{32}\.[a-z0-9]+$',
            ).hasMatch(p.basename(entity.path))) {
          await entity.delete();
        }
      }
      final kopya = File(p.join(klasor.path, p.basename(kaynakYolu)));
      await _normalDosya(kopya);
      final kaynak = File(kaynakYolu);
      await _normalDosya(kaynak);
      try {
        await kaynak.copy(kopya.path);
        if (!await _ayni(kaynak, kopya)) {
          throw StateError('Görüntüleme kopyası tam hazırlanamadı.');
        }
        await _moduDogrula();
        await _arsiviDogrula(db, arsivId);
        return kopya.path;
      } catch (_) {
        if (await kopya.exists()) await kopya.delete();
        rethrow;
      }
    });
  }

  static const belgeTurleri = [
    'Genel belge',
    'Öğrenci listesi',
    'Öğretmen listesi',
    'Ders listesi',
    'Ders programı',
    'Yıllık plan',
    'Günlük plan',
    'Ders bilgi formu',
    'BEP belgesi',
  ];

  Future<void> _klasoruDogrula(
    DatabaseExecutor db,
    String arsivId,
    String? id,
  ) async {
    if (id == null) return;
    if ((await db.query(
      'BelgeKlasoru',
      where: 'KlasorId = ? AND ArsivId = ?',
      whereArgs: [id, arsivId],
    )).isEmpty) {
      throw StateError('Klasör bu arşivde bulunamadı.');
    }
  }

  Future<String> _aktifYil(DatabaseExecutor db, String arsivId) async {
    final yil = (await _profil(db))['EgitimOgretimYili'] as String;
    await _eklemeKapsaminiDogrula(db, arsivId, yil);
    return yil;
  }

  Future<List<BelgeKlasoru>> klasorleriGetir(String arsivId) => _sirali(
    () async {
      await _moduDogrula();
      final db = await _databaseGetir();
      await _arsiviDogrula(db, arsivId);
      final rows = await db.query(
        'BelgeKlasoru',
        where: 'ArsivId = ?',
        whereArgs: [arsivId],
        orderBy: 'AramaAdi',
      );
      return rows
          .map((r) => BelgeKlasoru(r['KlasorId'] as String, r['Ad'] as String))
          .toList();
    },
  );

  static String _adiDogrula(String ad) {
    ad = ad.trim();
    if (ad.isEmpty ||
        ad.length > 240 ||
        RegExp(r'[\\/\x00-\x1f]').hasMatch(ad) ||
        ad == '.' ||
        ad == '..' ||
        importNormalize(ad).isEmpty) {
      throw const FormatException(
        '1–240 karakterlik geçerli bir ad girin; yol veya kontrol karakteri kullanmayın.',
      );
    }
    return ad;
  }

  Future<void> klasorKaydet(String arsivId, String ad, {String? id}) =>
      _sirali(() async {
        ad = _adiDogrula(ad);
        await _moduDogrula();
        final db = await _databaseGetir();
        await db.transaction((txn) async {
          await _aktifYil(txn, arsivId);
          await _klasoruDogrula(txn, arsivId, id);
          final veri = {'Ad': ad, 'AramaAdi': importNormalize(ad)};
          final tekrar = await txn.query(
            'BelgeKlasoru',
            where: 'ArsivId = ? AND AramaAdi = ? AND KlasorId != ?',
            whereArgs: [arsivId, importNormalize(ad), id ?? ''],
          );
          if (tekrar.isNotEmpty) {
            throw StateError('Bu adla bir klasör zaten var.');
          }
          if (id == null) {
            await txn.insert('BelgeKlasoru', {
              ...veri,
              'KlasorId': _kimlik(),
              'ArsivId': arsivId,
            });
          } else {
            await txn.update(
              'BelgeKlasoru',
              veri,
              where: 'KlasorId = ?',
              whereArgs: [id],
            );
          }
        });
      });

  Future<void> klasorSil(String arsivId, String id) => _sirali(() async {
    await _moduDogrula();
    final db = await _databaseGetir();
    await db.transaction((txn) async {
      await _aktifYil(txn, arsivId);
      await _klasoruDogrula(txn, arsivId, id);
      await txn.update(
        'BireyselBelge',
        {'KlasorId': null},
        where: 'ArsivId = ? AND KlasorId = ?',
        whereArgs: [arsivId, id],
      );
      await txn.delete(
        'BelgeKlasoru',
        where: 'KlasorId = ? AND ArsivId = ?',
        whereArgs: [id, arsivId],
      );
    });
  });

  Future<void> belgeyiDuzenle(
    BireyselBelge belge, {
    String? ad,
    String? tur,
    String? klasorId,
    bool tasi = false,
    bool? sil,
  }) => _sirali(() async {
    if (ad != null) {
      ad = _adiDogrula(ad!);
      if (p.extension(ad!).replaceFirst('.', '').toLowerCase() !=
          belge.uzanti) {
        throw const FormatException('Dosya uzantısını değiştirmeyin.');
      }
    }
    if (tur != null && !belgeTurleri.contains(tur)) {
      throw ArgumentError('Geçersiz belge türü.');
    }
    await _moduDogrula();
    final db = await _databaseGetir();
    await db.transaction((txn) async {
      await _aktifYil(txn, belge.arsivId);
      if (tasi) await _klasoruDogrula(txn, belge.arsivId, klasorId);
      final count = await txn.update(
        'BireyselBelge',
        {
          if (ad != null) 'DosyaAdi': ad,
          if (ad != null) 'AramaAdi': importNormalize(ad!),
          if (tur != null) 'BelgeTuru': tur,
          if (tur != null) 'TurElleSecildi': 1,
          if (tasi) 'KlasorId': klasorId,
          if (sil != null)
            'SilinmeTarihi': sil ? DateTime.now().toIso8601String() : null,
        },
        where: 'BelgeId = ? AND ArsivId = ?',
        whereArgs: [belge.id, belge.arsivId],
      );
      if (count != 1) throw StateError('Belge bulunamadı.');
    });
  });

  Future<void> analizKaydet(
    BireyselBelge belge,
    String analiz,
    String tur,
  ) => _sirali(() async {
    if (!belgeTurleri.contains(tur)) {
      throw ArgumentError('Geçersiz belge türü.');
    }
    await _moduDogrula();
    final db = await _databaseGetir();
    await db.transaction((txn) async {
      await _aktifYil(txn, belge.arsivId);
      await txn.update(
        'BireyselBelge',
        {
          'Analiz': analiz,
          if (belge.belgeTuru == 'Genel belge' && !belge.turElleSecildi)
            'BelgeTuru': tur,
        },
        where:
            'BelgeId = ? AND ArsivId = ? AND IcerikOzeti = ? AND BelgeTuru = ? AND TurElleSecildi = ?',
        whereArgs: [
          belge.id,
          belge.arsivId,
          belge.icerikOzeti,
          belge.belgeTuru,
          belge.turElleSecildi ? 1 : 0,
        ],
      );
    });
  });

  Future<List<BelgeImportKaydi>> gecmis(BireyselBelge belge) =>
      _sirali(() async {
        await _moduDogrula();
        final db = await _databaseGetir();
        await _arsiviDogrula(db, belge.arsivId);
        final rows = await db.rawQuery(
          '''SELECT g.* FROM BelgeImportGecmisi g
      JOIN BireyselBelge b ON b.BelgeId = g.BelgeId
      WHERE b.BelgeId = ? AND b.ArsivId = ? ORDER BY g.Tarih DESC LIMIT 100''',
          [belge.id, belge.arsivId],
        );
        return rows
            .map(
              (r) => BelgeImportKaydi(
                r['Modul'] as String,
                r['EgitimOgretimYili'] as String,
                DateTime.parse(r['Tarih'] as String),
                r['Eklenen'] as int,
                r['Guncellenen'] as int,
                r['Mesaj'] as String,
              ),
            )
            .toList();
      });

  Future<BireyselBelge> belgeGetir(String arsivId, String belgeId) =>
      _sirali(() async {
        await _moduDogrula();
        final db = await _databaseGetir();
        await _arsiviDogrula(db, arsivId);
        final rows = await db.query(
          'BireyselBelge',
          where: 'ArsivId = ? AND BelgeId = ?',
          whereArgs: [arsivId, belgeId],
        );
        if (rows.isEmpty) throw StateError('Belge bulunamadı.');
        return BireyselBelge.fromMap(rows.single);
      });

  Future<BelgeImportKaynagi> importKaynaginiGetir(BireyselBelge belge) =>
      _sirali(() async {
        await _moduDogrula();
        final db = await _databaseGetir();
        final yil = await _aktifYil(db, belge.arsivId);
        final rows = await db.query(
          'BireyselBelge',
          where: 'BelgeId = ? AND ArsivId = ? AND SilinmeTarihi IS NULL',
          whereArgs: [belge.id, belge.arsivId],
        );
        if (rows.isEmpty) {
          throw StateError('Silinen belge import için kullanılamaz.');
        }
        return BelgeImportKaynagi(belge.arsivId, belge.id, yil);
      });

  Future<void> importKapsaminiDogrula(BelgeImportKaynagi kaynak) => _sirali(
    () async {
      await _moduDogrula();
      final db = await _databaseGetir();
      await _eklemeKapsaminiDogrula(db, kaynak.arsivId, kaynak.yil);
      if ((await db.query(
        'BireyselBelge',
        where: 'BelgeId = ? AND ArsivId = ? AND SilinmeTarihi IS NULL',
        whereArgs: [kaynak.belgeId, kaynak.arsivId],
      )).isEmpty) {
        throw StateError('Belge artık arşivde kullanılamıyor. Yeniden seçin.');
      }
    },
  );

  Future<void> importSonucunuKaydet(
    BelgeImportKaynagi kaynak,
    String modul,
    ImportOzet sonuc,
  ) => _sirali(() async {
    await _moduDogrula();
    final db = await _databaseGetir();
    await db.transaction((txn) async {
      await _eklemeKapsaminiDogrula(txn, kaynak.arsivId, kaynak.yil);
      await txn.insert('BelgeImportGecmisi', {
        'IslemId': _kimlik(),
        'BelgeId': kaynak.belgeId,
        'Modul': modul,
        'EgitimOgretimYili': kaynak.yil,
        'Tarih': DateTime.now().toIso8601String(),
        'Eklenen': sonuc.eklenen,
        'Guncellenen': sonuc.guncellenen,
        'Mesaj': sonuc.mesaj,
      });
    });
  });

  Future<List<String>> yillariGetir(String arsivId) => _sirali(() async {
    await _moduDogrula();
    final db = await _databaseGetir();
    await _arsiviDogrula(db, arsivId);
    final rows = await db.rawQuery(
      'SELECT DISTINCT EgitimOgretimYili FROM BireyselBelge WHERE ArsivId = ? ORDER BY EgitimOgretimYili DESC',
      [arsivId],
    );
    return rows.map((r) => r['EgitimOgretimYili'] as String).toList();
  });

  /// SQLite ve bu listedeki gerçek dosyalar aynı yedeğe dahil edilmelidir.
  Future<List<Map<String, Object?>>> yedekDosyaListesi(String arsivId) =>
      _sirali(() async {
        await _moduDogrula();
        final db = await _databaseGetir();
        await _arsiviDogrula(db, arsivId);
        final kok = await _kok();
        await _uzlastir(db, kok, arsivId);
        final rows = await db.query(
          'BireyselBelge',
          where: 'ArsivId = ?',
          whereArgs: [arsivId],
        );
        for (final r in rows) {
          final b = BireyselBelge.fromMap(r),
              file = _dosya(kok, BireyselBelge.fromMap(r));
          await _normalDosya(file);
          if (!await _butunluk(file, b)) {
            throw StateError('Yedek için belge dosyası eksik: ${b.dosyaAdi}');
          }
        }
        return List.unmodifiable(rows);
      });

  Future<void> _uzlastir(Database db, Directory kok, String arsivId) async {
    await _bekleyenSilmeleriTamamla(db, kok, arsivId);
    final rows = await db.query(
      'BireyselBelge',
      where: "ArsivId = ? AND Durum = 'Hazirlaniyor'",
      whereArgs: [arsivId],
    );
    for (final row in rows) {
      final belge = BireyselBelge.fromMap(row);
      final hedef = _dosya(kok, belge);
      final gecici = File('${hedef.path}.tmp');
      // Klasör daha oluşturulmadan kapanma halinde işlem kaydı kaldırılır.
      if (!await hedef.parent.exists()) {
        await db.delete(
          'BireyselBelge',
          where: 'BelgeId = ?',
          whereArgs: [belge.id],
        );
        continue;
      }
      await _normalDosya(hedef);
      await _normalDosya(gecici);
      if (await _butunluk(hedef, belge)) {
        await db.update(
          'BireyselBelge',
          {'Durum': 'Hazir'},
          where: 'BelgeId = ?',
          whereArgs: [belge.id],
        );
      } else if (await _butunluk(gecici, belge)) {
        await gecici.rename(hedef.path);
        await db.update(
          'BireyselBelge',
          {'Durum': 'Hazir'},
          where: 'BelgeId = ?',
          whereArgs: [belge.id],
        );
      } else if (await hedef.exists()) {
        // Kalıcı dosyayı doğrulayamıyorsak silmeyiz.
        await db.update(
          'BireyselBelge',
          {'Durum': 'Eksik'},
          where: 'BelgeId = ?',
          whereArgs: [belge.id],
        );
      } else {
        if (await gecici.exists()) await gecici.delete();
        await db.delete(
          'BireyselBelge',
          where: 'BelgeId = ?',
          whereArgs: [belge.id],
        );
      }
    }
  }

  Future<void> kaliciSil(
    BireyselBelge belge, {
    required String onay,
  }) => _sirali(() async {
    if (onay != 'SİL') throw StateError('Kalıcı silme için SİL onayı gerekir.');
    await _moduDogrula();
    final db = await _databaseGetir();
    await db.transaction((txn) async {
      await _aktifYil(txn, belge.arsivId);
      final rows = await txn.query(
        'BireyselBelge',
        where: 'BelgeId = ? AND ArsivId = ? AND SilinmeTarihi IS NOT NULL',
        whereArgs: [belge.id, belge.arsivId],
      );
      if (rows.isEmpty) throw StateError('Önce belgeyi çöp kutusuna taşıyın.');
      final guncel = BireyselBelge.fromMap(rows.single);
      _dosya(await _kok(), guncel); // Yol doğrulanmadan kayıt kaldırılmaz.
      await txn.insert('BelgeSilmeBekleyen', {
        'BelgeId': guncel.id,
        'ArsivId': guncel.arsivId,
        'Uzanti': guncel.uzanti,
      });
      await txn.delete(
        'BelgeImportGecmisi',
        where: 'BelgeId = ?',
        whereArgs: [guncel.id],
      );
      await txn.delete(
        'BireyselBelge',
        where: 'BelgeId = ?',
        whereArgs: [guncel.id],
      );
    });
    // Kapanma veya dosya sistemi hatası olursa listeleme aynı işi tamamlar.
    await _bekleyenSilmeleriTamamla(db, await _kok(), belge.arsivId);
  });

  Future<void> _bekleyenSilmeleriTamamla(
    Database db,
    Directory kok,
    String arsivId,
  ) async {
    final rows = await db.query(
      'BelgeSilmeBekleyen',
      where: 'ArsivId = ?',
      whereArgs: [arsivId],
    );
    for (final r in rows) {
      final id = r['BelgeId'] as String,
          ar = r['ArsivId'] as String,
          ext = r['Uzanti'] as String;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(ar) ||
          !uzantilar.contains(ext)) {
        throw StateError('Bekleyen silmenin dosya yolu geçersiz.');
      }
      final file = File(p.join(kok.path, ar, '$id.$ext'));
      await _normalDosya(file);
      if (await file.exists()) await file.delete();
      final tmp = File('${file.path}.tmp');
      await _normalDosya(tmp);
      if (await tmp.exists()) await tmp.delete();
      await db.delete(
        'BelgeSilmeBekleyen',
        where: 'BelgeId = ?',
        whereArgs: [id],
      );
    }
  }

  static Future<bool> _butunluk(File file, BireyselBelge belge) async =>
      belge.icerikOzeti != null &&
      await file.exists() &&
      await file.length() == belge.boyut &&
      await _ozet(file) == belge.icerikOzeti;

  static Future<String> _ozet(File file) => Isolate.run(() async {
    var crc = 0;
    await for (final bytes in file.openRead()) {
      crc = getCrc32(bytes, crc);
    }
    return 'crc32:${crc.toRadixString(16).padLeft(8, '0')}';
  });

  static Future<bool> _ayni(File a, File b) => Isolate.run(() async {
    if (await a.length() != await b.length()) return false;
    final left = await a.open();
    try {
      final right = await b.open();
      try {
        while (true) {
          final x = await left.read(65536), y = await right.read(65536);
          if (x.length != y.length) return false;
          if (x.isEmpty) return true;
          for (var i = 0; i < x.length; i++) {
            if (x[i] != y[i]) return false;
          }
        }
      } finally {
        await right.close();
      }
    } finally {
      await left.close();
    }
  });
}
