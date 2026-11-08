import 'dart:async';
import 'dart:convert';
import 'dart:io' hide ZLibDecoder;
import 'dart:io' as io show ZLibDecoder;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../database/odev_not_semasi.dart';
import '../database/ders_uygulama_semasi.dart';
import '../database/odev_durum_temizligi.dart';
import '../database/mesajlasma_semasi.dart';
import '../database/rehberlik_semasi.dart';
import '../database/gunluk_plan_semasi.dart';
import '../database/kaldirilan_moduller.dart';
import '../database/bilgi_toplama_semasi.dart';
import '../database/veli_iliskisi.dart';
import '../database/mesaj_alici_semasi.dart';
import 'bireysel_belge_service.dart';
import 'calisma_modu_service.dart';

part 'bireysel_sifirlama_service.dart';

class BakimYedegi {
  const BakimYedegi(this.dosya, this.tarih, this.ogretmen, this.sayilar);
  final File dosya;
  final String tarih, ogretmen;
  final Map<String, int> sayilar;
}

/// Yalnız bireysel SQLite verileri; SQL ve hedef yollar yedekten çalıştırılmaz.
class BireyselBakimService {
  BireyselBakimService({
    Future<Database> Function()? databaseGetir,
    Future<Directory> Function()? alanGetir,
    Future<CalismaModu?> Function()? modGetir,
  }) : _db = databaseGetir ?? (() => LocalDatabase.instance.database),
       _alan = alanGetir ?? getApplicationSupportDirectory,
       _mod = modGetir ?? CalismaModuService.getir;
  static final instance = BireyselBakimService();
  static const azamiBoyut = 512 * 1024 * 1024;
  final Future<Database> Function() _db;
  final Future<Directory> Function() _alan;
  final Future<CalismaModu?> Function() _mod;
  static Future<void> _sira = Future.value();
  Future<T> _sirali<T>(Future<T> Function() f) {
    final r = _sira.then((_) => BireyselBelgeService.instance.bakimIslemi(f));
    _sira = r.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return r;
  }

  Future<void> _yetki() async {
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError('Bakım yalnız bireysel öğretmen modunda yapılabilir.');
    }
  }

  static String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<Directory> _klasor(String ad) async {
    final d = Directory(p.join((await _alan()).path, ad));
    final type = await FileSystemEntity.type(d.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw StateError('Bakım dosya alanı güvenli değil.');
    }
    return d.create(recursive: true);
  }

  static String _belgeYolu(Map<String, Object?> r) {
    final a = r['ArsivId'].toString(),
        b = r['BelgeId'].toString(),
        e = r['Uzanti'].toString();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(a) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(b) ||
        !BireyselBelgeService.uzantilar.contains(e) ||
        r['GoreliYol'] != '$a/$b.$e') {
      throw const FormatException('Yedekte geçersiz belge yolu var.');
    }
    return '$a/$b.$e';
  }

  static Future<void> _guvenliDosya(File f) async {
    if (await FileSystemEntity.type(f.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.type(f.parent.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw StateError('Belge dosyası eksik veya güvenli değil.');
    }
  }

  static Future<String> _ozet(File f) async {
    var crc = 0;
    await for (final bytes in f.openRead()) {
      crc = getCrc32(bytes, crc);
    }
    return 'crc32:${crc.toRadixString(16).padLeft(8, '0')}';
  }

  static Object? _kodla(Object? v) =>
      v is Uint8List ? {'blob': base64Encode(v)} : v;
  static Object? _coz(Object? v) {
    if (v is Map && v.keys.length == 1 && v['blob'] is String) {
      return base64Decode(v['blob'] as String);
    }
    if (v == null || v is String || v is int || v is double) return v;
    throw const FormatException('Yedekte geçersiz hücre değeri var.');
  }

  Future<List<Map<String, Object?>>> _sema(DatabaseExecutor db) => db.rawQuery(
    "SELECT name, sql FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' AND lower(name) != 'android_metadata' "
    "ORDER BY name",
  );
  Future<List<String>> _siraGetir(
    DatabaseExecutor db,
    List<String> tables,
  ) async {
    final kalan = tables.toSet(), sonuc = <String>[];
    final parents = <String, Set<String>>{};
    for (final t in tables) {
      parents[t] = (await db.rawQuery(
        'PRAGMA foreign_key_list("$t")',
      )).map((r) => r['table'].toString()).where((p) => p != t).toSet();
    }
    while (kalan.isNotEmpty) {
      final uygun = kalan
          .where((t) => parents[t]!.intersection(kalan).isEmpty)
          .toList();
      if (uygun.isEmpty) throw StateError('Veri ilişkileri sıralanamadı.');
      sonuc.addAll(uygun);
      kalan.removeAll(uygun);
    }
    return sonuc;
  }

  Future<BakimYedegi> yedekle() => _sirali(() async {
    await _yetki();
    return _yedekle();
  });
  Future<BakimYedegi> _yedekle() async {
    final db = await _db(), belgeler = await _klasor('bireysel_belgeler');
    final hedef = File(
      p.join(
        (await _klasor('bakim_yedekleri')).path,
        'OkulYonetim_${DateTime.now().millisecondsSinceEpoch}_${_id().substring(0, 8)}.zip',
      ),
    );
    final entries = <Map<String, String>>[];
    late Map<String, Object?> m;
    try {
      await db.transaction((tx) async {
        await DersUygulamaSemasi.hazirla(tx);
        if ((await tx.query('BelgeSilmeBekleyen')).isNotEmpty) {
          throw StateError(
            'Bekleyen belge işlemleri var. Önce Belgelerim ekranını açıp yeniden deneyin.',
          );
        }
        final tables = <String, Object?>{}, columns = <String, Object?>{};
        var total = 0;
        for (final schema in await _sema(tx)) {
          final t = schema['name'] as String;
          columns[t] = (await tx.rawQuery(
            'PRAGMA table_info("$t")',
          )).map((r) => r['name']).toList();
          final rows = <Map<String, Object?>>[];
          for (final raw in await tx.query(t)) {
            final r = Map<String, Object?>.from(raw);
            if (t == 'OgrenciFotograf' &&
                r['FotoVerisi'] == null &&
                (r['DosyaYolu'] ?? '').toString().isNotEmpty) {
              final f = File(r['DosyaYolu'] as String);
              await _guvenliDosya(f);
              if (await f.length() > BireyselBelgeService.azamiBoyut) {
                throw StateError('Öğrenci fotoğrafı boyut sınırını aşıyor.');
              }
              r['FotoVerisi'] = await f.readAsBytes();
            }
            if (t == 'OgrenciFotograf') r['DosyaYolu'] = '';
            if (t == 'BireyselBelge') {
              final rel = _belgeYolu(r),
                  f = File(p.join(belgeler.path, _belgeYolu(r)));
              await _guvenliDosya(f);
              if (r['Durum'] != 'Hazir' ||
                  await f.length() != r['Boyut'] ||
                  await _ozet(f) != r['IcerikOzeti']) {
                throw StateError(
                  'Belge eksik/bozuk: ${r['DosyaAdi']}. Kısmi yedek oluşturulmadı.',
                );
              }
              total += await f.length();
              if (total > azamiBoyut) {
                throw StateError('Yedek 512 MB sınırını aşıyor.');
              }
              entries.add({'yol': f.path, 'ad': 'belgeler/$rel'});
            }
            rows.add(r.map((k, v) => MapEntry(k, _kodla(v))));
          }
          tables[t] = rows;
        }
        m = {
          'bicim': 'OkulYonetimBireyselYedek',
          'surum': 1,
          'sema': 31,
          'tarih': DateTime.now().toIso8601String(),
          'kolonlar': columns,
          'tablolar': tables,
        };
        final bytes = utf8.encode(jsonEncode(m));
        if (bytes.length > 64 * 1024 * 1024 ||
            total + bytes.length > azamiBoyut) {
          throw StateError('Yedek veri boyutu sınırı aşıyor.');
        }
        await _zipYaz(hedef.path, bytes, entries);
      });
      if (await hedef.length() > azamiBoyut) {
        throw StateError('Yedek paketi 512 MB sınırını aşıyor.');
      }
      return _bilgi(hedef, m);
    } catch (_) {
      if (await hedef.exists()) await hedef.delete();
      rethrow;
    }
  }

  static Future<void> _zipYaz(
    String target,
    List<int> meta,
    List<Map<String, String>> files,
  ) => Isolate.run(() {
    final encoder = ZipFileEncoder()..create(target);
    try {
      encoder.addArchiveFile(ArchiveFile('yedek.json', meta.length, meta));
      for (final f in files) {
        final input = InputFileStream(f['yol']!);
        try {
          encoder.addArchiveFile(
            ArchiveFile.stream(f['ad']!, input.length, input),
          );
        } finally {
          input.closeSync();
        }
      }
    } finally {
      encoder.closeSync();
    }
  });
  static BakimYedegi _bilgi(File f, Map<String, Object?> m) {
    final tables = m['tablolar'] as Map,
        profiles = (m['tablolar'] as Map)['OgretmenProfil'] as List;
    final ad = profiles.isEmpty
        ? 'Kurulum yapılmamış'
        : (profiles.last as Map)['AdSoyad'].toString();
    return BakimYedegi(
      f,
      m['tarih'].toString(),
      ad,
      tables.map((k, v) => MapEntry(k.toString(), (v as List).length)),
    );
  }

  // Başlık boyutları ve yollar içerik açılmadan önce kontrol edilir.
  static ZipDirectory _zipAc(InputFileStream input) {
    final dir = ZipDirectory.read(input), names = <String>{};
    var total = 0;
    for (final h in dir.fileHeaders) {
      final size = h.uncompressedSize ?? -1;
      total += size;
      final name = h.filename;
      final mode = (h.externalFileAttributes ?? 0) >> 16;
      if (h.compressionMethod != 0 && h.compressionMethod != 8 ||
          (h.generalPurposeBitFlag & 1) != 0 ||
          (h.compressedSize ?? azamiBoyut) > 64 * 1024 * 1024 ||
          h.file?.uncompressedSize != h.uncompressedSize ||
          size < 0 ||
          total > azamiBoyut ||
          !names.add(name) ||
          names.length > 20000 ||
          (mode & 0xf000) == 0xa000 ||
          h.file?.filename != name ||
          (name == 'yedek.json'
              ? size > 64 * 1024 * 1024
              : size > BireyselBelgeService.azamiBoyut ||
                    !RegExp(
                      r'^belgeler/[a-f0-9]{32}/[a-f0-9]{32}\.[a-z]+$',
                    ).hasMatch(name))) {
        throw const FormatException('Yedek dosya başlıkları geçersiz.');
      }
    }
    return dir;
  }

  Future<List<File>> yerelYedekler() => _sirali(() async {
    await _yetki();
    final d = await _klasor('bakim_yedekleri');
    final files = (await d.list(followLinks: false).toList())
        .whereType<File>()
        .where(
          (f) => RegExp(
            r'^OkulYonetim_[0-9]+_[a-f0-9]{8}\.zip$',
          ).hasMatch(p.basename(f.path)),
        )
        .toList();
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files.take(100).toList();
  });
  Future<void> yerelYedegiSil(File file, {required String onay}) =>
      _sirali(() async {
        await _yetki();
        if (onay != 'SİL') {
          throw StateError('Yerel yedek silme onayı gereklidir.');
        }
        final root = await _klasor('bakim_yedekleri');
        if (p.normalize(p.absolute(file.parent.path)) !=
                p.normalize(p.absolute(root.path)) ||
            !RegExp(
              r'^OkulYonetim_[0-9]+_[a-f0-9]{8}\.zip$',
            ).hasMatch(p.basename(file.path))) {
          throw StateError(
            'Yalnız uygulamanın oluşturduğu yerel yedek silinebilir.',
          );
        }
        await _guvenliDosya(file);
        await file.delete();
      });
  static List<int> _icerik(ZipFileHeader h) {
    if ((h.generalPurposeBitFlag & 1) != 0 ||
        !const {0, 8}.contains(h.compressionMethod)) {
      throw const FormatException('Şifreli/desteklenmeyen ZIP girdisi.');
    }
    final limit = h.filename == 'yedek.json'
        ? 64 * 1024 * 1024
        : BireyselBelgeService.azamiBoyut;
    final raw = h.file!.rawContent!;
    if (raw.length > limit + 65536) {
      throw const FormatException('Sıkıştırılmış girdi çok büyük.');
    }
    final sink = _SinirliYedekCikti(h.uncompressedSize!);
    if (h.compressionMethod == 8) {
      final converter = io.ZLibDecoder(raw: true).startChunkedConversion(sink);
      while (!raw.isEOS) {
        converter.add(raw.readBytes(65536).toUint8List());
      }
      converter.close();
    } else {
      while (!raw.isEOS) {
        sink.add(raw.readBytes(65536).toUint8List());
      }
      sink.close();
    }
    final bytes = sink.bytes.takeBytes();
    if (bytes.length != h.uncompressedSize || getCrc32(bytes) != h.crc32) {
      throw const FormatException('Yedek içeriği veya boyutu bozuk.');
    }
    return bytes;
  }

  static Future<Map<String, Object?>> _paketiOku(String path) =>
      Isolate.run(() {
        final input = InputFileStream(path);
        try {
          if (input.length > azamiBoyut) {
            throw const FormatException('Yedek 512 MB sınırını aşıyor.');
          }
          final dir = _zipAc(input);
          final headers = {for (final h in dir.fileHeaders) h.filename: h};
          final meta = headers['yedek.json'];
          if (meta == null) {
            throw const FormatException('Yedek bilgisi bulunamadı.');
          }
          final m = Map<String, Object?>.from(
            jsonDecode(utf8.decode(_icerik(meta))) as Map,
          );
          if (m['bicim'] != 'OkulYonetimBireyselYedek' ||
              m['surum'] != 1 ||
              !const {
                12,
                13,
                14,
                15,
                16,
                17,
                18,
                19,
                20,
                21,
                22,
                23,
                24,
                25,
                26,
                27,
                28,
                29,
                30,
                31,
              }.contains(m['sema']) ||
              DateTime.tryParse(m['tarih'].toString()) == null) {
            throw const FormatException(
              'Bu dosya desteklenen bir bireysel yedek değil.',
            );
          }
          final needed = <String>{'yedek.json'};
          for (final raw in (m['tablolar'] as Map)['BireyselBelge'] as List) {
            final r = Map<String, Object?>.from(raw as Map),
                rel = _belgeYolu(Map<String, Object?>.from(raw));
            final h = headers['belgeler/$rel'];
            if (h == null ||
                r['Durum'] != 'Hazir' ||
                h.uncompressedSize != r['Boyut']) {
              throw const FormatException(
                'Yedekte belge eksik veya boyutu uyuşmuyor.',
              );
            }
            final bytes = _icerik(h);
            if ('crc32:${getCrc32(bytes).toRadixString(16).padLeft(8, '0')}' !=
                r['IcerikOzeti']) {
              throw const FormatException('Belge içeriği bozuk.');
            }
            needed.add(h.filename);
          }
          if (needed.length != headers.length) {
            throw const FormatException('Yedekte ilişkisiz dosya var.');
          }
          return m;
        } finally {
          input.closeSync();
        }
      });
  Future<void> _dogrula(Database db, Map<String, Object?> m) async {
    await db.transaction(DersUygulamaSemasi.hazirla);
    // Android bu sistem tablosunu her veritabanında kendisi oluşturur.
    // Eski Android yedeklerinde de uygulama verisi olarak geri yüklenmez.
    for (final entries in [m['tablolar'] as Map, m['kolonlar'] as Map]) {
      entries.removeWhere(
        (key, _) => key is String && key.toLowerCase() == 'android_metadata',
      );
    }
    await _eskiYedegiUyarla(db, m);
    final schema = await _sema(db),
        tables = m['tablolar'] as Map,
        cols = m['kolonlar'] as Map;
    final names = schema.map((r) => r['name'] as String).toSet();
    if (tables.keys.toSet().difference(names).isNotEmpty ||
        names.difference(tables.keys.toSet()).isNotEmpty ||
        cols.length != names.length ||
        (tables['BelgeSilmeBekleyen'] as List).isNotEmpty) {
      throw const FormatException(
        'Yedek tabloları mevcut uygulama ile uyuşmuyor.',
      );
    }
    for (final t in names) {
      final fields = (await db.rawQuery(
        'PRAGMA table_info("$t")',
      )).map((r) => r['name']).toSet();
      if (fields.length != (cols[t] as List).length ||
          fields.difference((cols[t] as List).toSet()).isNotEmpty) {
        throw const FormatException('Yedek sütunları uyuşmuyor.');
      }
      for (final r in tables[t] as List) {
        final row = r as Map;
        if (row.keys.toSet().difference(fields).isNotEmpty ||
            row.length != fields.length) {
          throw const FormatException('Yedek kayıt yapısı geçersiz.');
        }
      }
    }
    for (final photo in tables['OgrenciFotograf'] as List) {
      final bytes = _coz(photo['FotoVerisi']);
      if (photo['DosyaYolu'] != '' ||
          (bytes != null &&
              (bytes is! Uint8List ||
                  bytes.length > BireyselBelgeService.azamiBoyut))) {
        throw const FormatException(
          'Yedekte taşınabilir olmayan fotoğraf kaydı var.',
        );
      }
    }
    final indexes = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL",
    );
    final triggers = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='trigger' AND sql IS NOT NULL");
    final temp = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          for (final s in schema) {
            await d.execute(s['sql'] as String);
          }
          for (final s in indexes) {
            await d.execute(s['sql'] as String);
          }
          for (final s in triggers) {
            await d.execute(s['sql'] as String);
          }
        },
      ),
    );
    try {
      final order = await _siraGetir(db, names.toList());
      await temp.transaction((tx) async {
        await _ekle(tx, tables, order);
        if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw const FormatException('Yedekte kopuk veri ilişkileri var.');
        }
      });
      final school = await temp.query('OkulProfil'),
          teacher = await temp.query('OgretmenProfil', where: 'Aktif = 1');
      if (teacher.isNotEmpty &&
          (school.length != 1 ||
              teacher.any(
                (t) =>
                    t['OkulAdi'] != school.single['OkulAdi'] ||
                    t['EgitimOgretimYili'] != school.single['EgitimYili'],
              ))) {
        throw const FormatException(
          'Yedekte okul ve öğretmen bilgileri uyuşmuyor.',
        );
      }
      for (final b in tables['BireyselBelge'] as List) {
        if (b['KlasorId'] != null &&
            !(tables['BelgeKlasoru'] as List).any(
              (c) =>
                  c['KlasorId'] == b['KlasorId'] &&
                  c['ArsivId'] == b['ArsivId'],
            )) {
          throw const FormatException('Belge klasörü farklı arşive ait.');
        }
      }
    } finally {
      await temp.close();
    }
  }

  // Yalnız bilinen v12 -> v20 farklarını tamamla. Diğer eksik/fazla alanlar
  // mevcut sıkı doğrulamadan geçmek zorundadır; yedekten SQL çalıştırılmaz.
  Future<void> _eskiYedegiUyarla(Database db, Map<String, Object?> m) async {
    final eskiSurum = m['sema'] as int;
    final tablolar = m['tablolar'] as Map, kolonlar = m['kolonlar'] as Map;
    if (eskiSurum < 26) {
      for (final t in KaldirilanModuller.tablolar) {
        tablolar.remove(t);
        kolonlar.remove(t);
      }
    }
    const dersTablosu = 'MesajOgretmenSinifDers';
    if (eskiSurum < 25 &&
        (tablolar.containsKey(dersTablosu) ||
            kolonlar.containsKey(dersTablosu))) {
      throw const FormatException(
        'Eski yedekte beklenmeyen öğretmen ders ilişkisi var.',
      );
    }
    if (eskiSurum < 22 &&
        (tablolar.containsKey('OgrenciIletisim') ||
            kolonlar.containsKey('OgrenciIletisim'))) {
      throw const FormatException(
        'Eski yedekte beklenmeyen iletişim tablosu var.',
      );
    }
    if (eskiSurum < 23 &&
        MesajAliciSemasi.tablolar.any(
          (t) => tablolar.containsKey(t) || kolonlar.containsKey(t),
        )) {
      throw const FormatException(
        'Eski yedekte beklenmeyen alıcı kimliği tablosu var.',
      );
    }
    if (eskiSurum < 22 &&
        ((kolonlar['Ogrenci'] as List).contains('VeliTuru') ||
            (tablolar['Ogrenci'] as List).any(
              (r) => (r as Map).containsKey('VeliTuru'),
            ))) {
      throw const FormatException(
        'Eski yedekte beklenmeyen veli ilişkisi var.',
      );
    }
    if (eskiSurum < 20 &&
        (BilgiToplamaSemasi.tablolar.any(
              (t) => tablolar.containsKey(t) || kolonlar.containsKey(t),
            ) ||
            BilgiToplamaSemasi.ogrenciAlanlari.any(
              (f) =>
                  (kolonlar['Ogrenci'] as List).contains(f) ||
                  (tablolar['Ogrenci'] as List).any(
                    (r) => (r as Map).containsKey(f),
                  ),
            ))) {
      throw const FormatException(
        'Eski yedekte beklenmeyen bilgi toplama alanı var.',
      );
    }
    // Yeni tabloları taşıdığını iddia eden eski paketlerin sessizce üzerine yazma.
    if (eskiSurum < 18 &&
        (tablolar.containsKey('MesajSms') ||
            kolonlar.containsKey('MesajSms'))) {
      throw const FormatException('Eski yedekte beklenmeyen SMS tablosu var.');
    }
    if (eskiSurum < 19 &&
        RehberlikSemasi.googleTablolari.any(
          (t) => tablolar.containsKey(t) || kolonlar.containsKey(t),
        )) {
      throw const FormatException(
        'Eski yedekte beklenmeyen Google Forms tablosu var.',
      );
    }
    if ((m['sema'] as int) < 16) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      if (tables.containsKey(GunlukPlanSemasi.tablo) ||
          cols.containsKey(GunlukPlanSemasi.tablo)) {
        throw const FormatException(
          'Eski yedekte beklenmeyen günlük plan tablosu var.',
        );
      }
    }
    if ((m['sema'] as int) < 15) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      for (final t in RehberlikSemasi.modulTablolari) {
        if (tables.containsKey(t) || cols.containsKey(t)) {
          throw const FormatException(
            'Eski yedekte beklenmeyen modül tablosu var.',
          );
        }
      }
    }
    if (m['sema'] == 12 || m['sema'] == 13) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      if (tables.containsKey(RehberlikSemasi.atamaTablosu) ||
          cols.containsKey(RehberlikSemasi.atamaTablosu)) {
        throw const FormatException(
          'Eski yedekte beklenmeyen rehberlik tablosu var.',
        );
      }
    }
    await _mesajlasmaYedeginiUyarla(db, m);
    if (m['sema'] == 13) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      tables[RehberlikSemasi.atamaTablosu] = <Object?>[];
      cols[RehberlikSemasi.atamaTablosu] = (await db.rawQuery(
        'PRAGMA table_info("${RehberlikSemasi.atamaTablosu}")',
      )).map((r) => r['name']).toList();
      m['sema'] = 14;
    }
    if (m['sema'] == 14) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      for (final t in RehberlikSemasi.modulTablolari) {
        tables[t] = <Object?>[];
        cols[t] = (await db.rawQuery(
          'PRAGMA table_info("$t")',
        )).map((r) => r['name']).toList();
      }
      m['sema'] = 15;
    }
    if (m['sema'] == 15) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      tables[GunlukPlanSemasi.tablo] = <Object?>[];
      cols[GunlukPlanSemasi.tablo] = (await db.rawQuery(
        'PRAGMA table_info("${GunlukPlanSemasi.tablo}")',
      )).map((r) => r['name']).toList();
      m['sema'] = 16;
    }
    if (m['sema'] == 16) m['sema'] = 17;
    if (m['sema'] == 17) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      const t = 'MesajSms';
      tables[t] = <Object?>[];
      cols[t] = (await db.rawQuery(
        'PRAGMA table_info("$t")',
      )).map((r) => r['name']).toList();
      m['sema'] = 18;
    }
    if (m['sema'] == 18) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      for (final t in RehberlikSemasi.googleTablolari) {
        tables[t] = <Object?>[];
        cols[t] = (await db.rawQuery(
          'PRAGMA table_info("$t")',
        )).map((r) => r['name']).toList();
      }
      m['sema'] = 19;
    }
    if (m['sema'] == 19) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      for (final t in BilgiToplamaSemasi.tablolar) {
        tables[t] = <Object?>[];
        cols[t] = (await db.rawQuery(
          'PRAGMA table_info("$t")',
        )).map((r) => r['name']).toList();
      }
      (cols['Ogrenci'] as List).addAll(BilgiToplamaSemasi.ogrenciAlanlari);
      for (final r in tables['Ogrenci'] as List) {
        for (final alan in BilgiToplamaSemasi.ogrenciAlanlari) {
          (r as Map)[alan] = null;
        }
      }
      m['sema'] = 20;
    }
    if (m['sema'] == 20) {
      final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
      for (final t in ['OdevDegerlendirmeOlcutu', 'OdevDegerlendirmePuani']) {
        tables[t] = <Object?>[];
        cols[t] = (await db.rawQuery(
          'PRAGMA table_info("$t")',
        )).map((r) => r['name']).toList();
      }
      m['sema'] = 21;
    }
    if ((m['sema'] as int) < 24 &&
        !(kolonlar['Ogrenci'] as List).contains('VeliTuru')) {
      (kolonlar['Ogrenci'] as List).add('VeliTuru');
      for (final o in tablolar['Ogrenci'] as List) {
        (o as Map)['VeliTuru'] = VeliIliskisi.eskiTur(o);
      }
    }
    if ((m['sema'] as int) < 23) {
      for (final t in MesajAliciSemasi.tablolar) {
        tablolar[t] = <Object?>[];
        kolonlar[t] = (await db.rawQuery(
          'PRAGMA table_info("$t")',
        )).map((r) => r['name']).toList();
      }
      tablolar['MesajAliciBag'] = MesajAliciSemasi.eskiBaglar(
        (tablolar['MesajKuyrugu'] as List)
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList(),
        (tablolar['MesajAlici'] as List)
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList(),
      );
    }
    if ((m['sema'] as int) < 24) {
      // GitHub v22'nin iletişim satırları varsa aynen korunur. Yerel v22/v23
      // yedeğinde tablo yoktur; boş uyumluluk tablosu eklenir, telefon kopyalanmaz.
      if (!tablolar.containsKey('OgrenciIletisim') &&
          !kolonlar.containsKey('OgrenciIletisim')) {
        tablolar['OgrenciIletisim'] = <Object?>[];
        kolonlar['OgrenciIletisim'] = (await db.rawQuery(
          'PRAGMA table_info(OgrenciIletisim)',
        )).map((r) => r['name']).toList();
      }
      m['sema'] = 24;
    }
    if ((m['sema'] as int) < 25) {
      tablolar[dersTablosu] = <Object?>[];
      kolonlar[dersTablosu] = (await db.rawQuery(
        'PRAGMA table_info($dersTablosu)',
      )).map((r) => r['name']).toList();
      m['sema'] = 25;
    }
    const tekli = MesajlasmaSemasi.tekliGecmisTablosu;
    if (eskiSurum < 27) {
      if (tablolar.containsKey(tekli) || kolonlar.containsKey(tekli)) {
        throw const FormatException(
          'Eski yedekte beklenmeyen tekli gönderim geçmişi var.',
        );
      }
      tablolar[tekli] = <Object?>[];
      kolonlar[tekli] = (await db.rawQuery(
        'PRAGMA table_info($tekli)',
      )).map((r) => r['name']).toList();
    }
    if (eskiSurum < 28) {
      for(final t in OdevNotSemasi.tablolar){
        if(tablolar.containsKey(t) || kolonlar.containsKey(t))throw const FormatException('Eski yedekte beklenmeyen performans tablosu var.');
        tablolar[t]=<Object?>[];
        kolonlar[t]=(await db.rawQuery('PRAGMA table_info("$t")')).map((r)=>r['name']).toList();
      }
      for(final (t,alan,deger) in [('OdevKontrolSonuc','NotDegeri',null),('OdevTanim','Tamamlandi',0)]){
        if((kolonlar[t] as List).contains(alan) || (tablolar[t] as List).any((r)=>(r as Map).containsKey(alan)))throw const FormatException('Eski yedekte beklenmeyen ödev puan alanı var.');
        (kolonlar[t] as List).add(alan);
        for(final r in tablolar[t] as List){(r as Map)[alan]=deger;}
      }
    }
    if (eskiSurum < 30) {
      for (final t in DersUygulamaSemasi.tablolar) {
        if (tablolar.containsKey(t) || kolonlar.containsKey(t)) {
          throw const FormatException('Eski yedekte beklenmeyen uygulama tablosu var.');
        }
        tablolar[t] = <Object?>[];
        kolonlar[t] = (await db.rawQuery('PRAGMA table_info("$t")')).map((r) => r['name']).toList();
      }
      const alan = 'DersUygulamalari';
      if ((kolonlar['OdevTanim'] as List).contains(alan) ||
          (tablolar['OdevTanim'] as List).any((r) => (r as Map).containsKey(alan))) {
        throw const FormatException('Eski yedekte beklenmeyen uygulama türü var.');
      }
      (kolonlar['OdevTanim'] as List).add(alan);
      for (final r in tablolar['OdevTanim'] as List) { (r as Map)[alan] = 0; }
    }
    // v30 yedekleri adet alanlarından önce de üretildi. Yalnız bilinen
    // eksik alanları tamamla; kısmi/çelişkili kayıtları sıkı doğrulamaya bırak.
    for (final (table, field, value) in [
      ('OdevUygulama', 'Adet', 1),
      ('OdevUygulamaSonuc', 'Adet', null),
      ('OdevUygulamaSonuc', 'Yapilan', null),
    ]) {
      final fields = kolonlar[table] as List;
      if (!fields.contains(field)) {
        if ((tablolar[table] as List).any((r) => (r as Map).containsKey(field))) {
          throw const FormatException('Yedekte uygulama adet alanları uyuşmuyor.');
        }
        fields.add(field);
        for (final row in tablolar[table] as List) {
          (row as Map)[field] = value;
        }
      }
    }
    if (eskiSurum < 31) OdevDurumTemizligi.yedegiUyarla(tablolar);
    m['sema'] = 31;
  }

  Future<void> _mesajlasmaYedeginiUyarla(
    Database db,
    Map<String, Object?> m,
  ) async {
    if (m['sema'] != 12) return;
    final tables = m['tablolar'] as Map, cols = m['kolonlar'] as Map;
    for (final t in MesajlasmaSemasi.tablolar) {
      if (tables.containsKey(t) || cols.containsKey(t)) {
        throw const FormatException(
          'Eski yedekte beklenmeyen mesajlaşma tablosu var.',
        );
      }
    }
    final fields = cols['Ogrenci'] as List;
    if (MesajlasmaSemasi.iletisimAlanlari.any(fields.contains)) {
      throw const FormatException(
        'Eski yedekte beklenmeyen iletişim alanı var.',
      );
    }
    for (final r in tables['Ogrenci'] as List) {
      if (MesajlasmaSemasi.iletisimAlanlari.any((r as Map).containsKey)) {
        throw const FormatException(
          'Eski yedekte beklenmeyen iletişim kaydı var.',
        );
      }
      for (final f in MesajlasmaSemasi.iletisimAlanlari) {
        r[f] = null;
      }
    }
    fields.addAll(MesajlasmaSemasi.iletisimAlanlari);
    for (final t in MesajlasmaSemasi.tablolar) {
      tables[t] = <Object?>[];
      cols[t] = (await db.rawQuery(
        'PRAGMA table_info("$t")',
      )).map((r) => r['name']).toList();
    }
    m['sema'] = 13;
  }

  static Future<void> _ekle(
    DatabaseExecutor db,
    Map tables,
    List<String> order,
  ) async {
    for (final t in order) {
      for (final r in tables[t] as List) {
        await db.insert(
          t,
          (r as Map).map((k, v) => MapEntry(k.toString(), _coz(v))),
        );
      }
    }
  }

  Future<BakimYedegi> incele(File kaynak) => _sirali(() async {
    await _yetki();
    if (await kaynak.length() > azamiBoyut) {
      throw StateError('Yedek 512 MB sınırını aşıyor.');
    }
    final copy = await kaynak.copy(
      p.join((await _klasor('bakim_onizleme')).path, '${_id()}.zip'),
    );
    try {
      final m = await _paketiOku(copy.path);
      await _dogrula(await _db(), m);
      return _bilgi(copy, m);
    } catch (_) {
      await copy.delete();
      rethrow;
    }
  });
  Future<String> geriYukle(
    BakimYedegi yedek, {
    required String onayMetni,
  }) => _sirali(() async {
    await _yetki();
    if (onayMetni != 'GERİ YÜKLE') {
      throw StateError('GERİ YÜKLE onayı gereklidir.');
    }
    final m = await _paketiOku(yedek.dosya.path), db = await _db();
    await _dogrula(db, m);
    final eskiBelgeler = await db.query('BireyselBelge');
    final koruma = await _yedekle(), root = await _klasor('bireysel_belgeler');
    final tables = m['tablolar'] as Map,
        dirs = <Directory>[],
        map = <String, String>{};
    var veriYuklendi = false;
    try {
      for (final r in tables['BelgeArsivi'] as List) {
        final old = r['ArsivId'] as String, fresh = _id();
        map[old] = fresh;
        final d = Directory(p.join(root.path, fresh));
        if (await d.exists()) {
          throw StateError('Yeni arşiv alanı oluşturulamadı.');
        }
        await d.create();
        dirs.add(d);
        r['ArsivId'] = fresh;
      }
      final targets = <String, String>{};
      for (final r in tables['BireyselBelge'] as List) {
        final oldRel = _belgeYolu(Map<String, Object?>.from(r));
        r['ArsivId'] = map[r['ArsivId']]!;
        r['GoreliYol'] = '${r['ArsivId']}/${r['BelgeId']}.${r['Uzanti']}';
        targets['belgeler/$oldRel'] = p.join(
          root.path,
          r['GoreliYol'] as String,
        );
      }
      for (final r in tables['BelgeKlasoru'] as List) {
        r['ArsivId'] = map[r['ArsivId']]!;
      }
      await _dosyalariYaz(yedek.dosya.path, targets);
      final order = await _siraGetir(db, tables.keys.cast<String>().toList());
      await _yetki();
      await db.transaction((tx) async {
        for (final t in order.reversed) {
          await tx.delete(t);
        }
        await _ekle(tx, tables, order);
        if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw StateError('Geri yükleme ilişkileri doğrulanamadı.');
        }
      });
      veriYuklendi = true;
      // Commit sonrası yalnız doğrulanmış eski özel kopyalar temizlenir.
      // Koruma ZIP'i bütün eski verileri içerir; kaynak cihaz dosyaları silinmez.
      for (final old in eskiBelgeler) {
        try {
          final f = File(p.join(root.path, _belgeYolu(old)));
          await _guvenliDosya(f);
          if (await _ozet(f) == old['IcerikOzeti']) await f.delete();
          if (await f.parent.list(followLinks: false).isEmpty) {
            await f.parent.delete();
          }
        } on FileSystemException catch (_) {
          // Temizlik hatası başarılı DB commit'ini başarısız gibi göstermez.
        } on FormatException catch (_) {
          // Geçersiz eski yola dokunulmaz.
        } on StateError catch (_) {
          // Değişmiş dosyaya veya sembolik bağa dokunulmaz.
        }
      }
      // Uzak daldaki geri yükleme sonrası doğrulama korunur.
      try {
        final yeniYedek = await _yedekle();
        await _dogrula(db, await _paketiOku(yeniYedek.dosya.path));
      } catch (e) {
        throw StateError(
          'Geri yükleme veritabanına uygulandı ancak yeni yedek doğrulanamadı. '
          'Koruma yedeği: ${koruma.dosya.path}. Orijinal yedek korunuyor. Orijinal hata: $e',
        );
      }
      return koruma.dosya.path;
    } catch (_) {
      if (!veriYuklendi) {
        for (final d in dirs) {
          if (await d.exists()) await d.delete(recursive: true);
        }
      }
      rethrow;
    }
  });
  static Future<void> _dosyalariYaz(String zip, Map<String, String> targets) =>
      Isolate.run(() {
        final input = InputFileStream(zip);
        try {
          final dir = _zipAc(input);
          for (final h in dir.fileHeaders) {
            final target = targets[h.filename];
            if (target == null) continue;
            final out = OutputFileStream(target);
            try {
              out.writeBytes(_icerik(h));
            } finally {
              out.closeSync();
            }
          }
        } finally {
          input.closeSync();
        }
      });
}

/// İlan edilen boyutu aşan deflate içeriği belleğe alınmadan durdurulur.
class _SinirliYedekCikti implements Sink<List<int>> {
  _SinirliYedekCikti(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  int _length = 0;
  @override
  void add(List<int> chunk) {
    _length += chunk.length;
    if (_length > limit) {
      throw const FormatException('Açılmış ZIP içeriği boyut sınırını aşıyor.');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
