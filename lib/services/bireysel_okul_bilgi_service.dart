import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/okul_bilgi_model.dart';
import 'calisma_modu_service.dart';

class BireyselOkulBilgiOturumu {
  const BireyselOkulBilgiOturumu({
    required this.okulId,
    required this.yil,
    required this.ogretmenId,
    required this.okul,
  });

  final String okulId, yil;
  final int ogretmenId;
  final OkulBilgiModel okul;
}

/// Okul kimliği profilde, öğretmenin temel okul bilgileri mevcut ayarlarda kalır.
class BireyselOkulBilgiService {
  BireyselOkulBilgiService._();

  static String _anahtar(String okulId, int ogretmenId) =>
      'okul_bilgileri:${Uri.encodeComponent(okulId)}:$ogretmenId';

  static String _okulAdiNormalizeEt(String okul) =>
      okul.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String _eskiMudurAnahtari(int ogretmenId, String okulAdi) =>
      'liste_muduru:$ogretmenId:${Uri.encodeComponent(_okulAdiNormalizeEt(okulAdi))}';

  static Future<void> _modKontrol() async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Okul bilgileri yalnız bireysel öğretmen modunda düzenlenebilir.',
      );
    }
  }

  static Future<Map<String, String>?> _ekBilgiler(
    DatabaseExecutor db,
    String okulId,
    int ogretmenId,
  ) async {
    final rows = await db.query(
      'UygulamaAyarlari',
      columns: ['Deger'],
      where: 'Anahtar = ?',
      whereArgs: [_anahtar(okulId, ogretmenId)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.single['Deger'];
    if (raw is! String) {
      throw const FormatException('Kayıtlı okul bilgileri geçersiz.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.values.any((value) => value is! String)) {
      throw const FormatException('Kayıtlı okul bilgileri geçersiz.');
    }
    return decoded.cast<String, String>();
  }

  static Future<String> _eskiMudurGetir(
    DatabaseExecutor db,
    int ogretmenId,
    String okulAdi,
  ) async {
    final rows = await db.query(
      'UygulamaAyarlari',
      columns: ['Deger'],
      where: 'Anahtar = ?',
      whereArgs: [_eskiMudurAnahtari(ogretmenId, okulAdi)],
      limit: 1,
    );
    return rows.isEmpty ? '' : (rows.single['Deger'] ?? '').toString();
  }

  static Future<BireyselOkulBilgiOturumu> _getir(DatabaseExecutor db) async {
    final schools = await db.query(
      'OkulProfil',
      where: 'Id = 1 AND AktifMi = 1',
    );
    final teachers = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (schools.length != 1 || teachers.isEmpty) {
      throw StateError('Önce bireysel öğretmen ve okul kurulumunu tamamlayın.');
    }
    final school = schools.single, teacher = teachers.single;
    final okulId = (school['OkulId'] ?? '').toString();
    final yil = (school['EgitimYili'] ?? '').toString();
    final okulAdi = (school['OkulAdi'] ?? '').toString();
    final ogretmenId = teacher['OgretmenProfilId'];
    if (okulId.trim().isEmpty ||
        yil.trim().isEmpty ||
        okulAdi.trim().isEmpty ||
        ogretmenId is! int ||
        ogretmenId <= 0 ||
        (school['OkulKisaAdi'] ?? '').toString().trim().isEmpty ||
        (school['Donem'] != 1 && school['Donem'] != 2) ||
        okulAdi != teacher['OkulAdi'] ||
        yil != teacher['EgitimOgretimYili']) {
      throw StateError(
        'Aktif okul, öğretmen ve eğitim yılı bilgileri tutarsız.',
      );
    }
    final extra = await _ekBilgiler(db, okulId, ogretmenId);
    final mudur = extra == null
        ? await _eskiMudurGetir(db, ogretmenId, okulAdi)
        : extra['mudurAdi'] ?? '';
    final okul = OkulBilgiModel.bos().copyWith(
      okulAdi: okulAdi,
      kisaAd: school['OkulKisaAdi'].toString(),
      aktifEgitimYili: yil,
      aktifDonem: school['Donem'].toString(),
      mudurAdi: mudur,
      mudurYardimcilari: extra?['mudurYardimcilari'] ?? '',
      telefon: extra?['telefon'] ?? '',
      email: extra?['email'] ?? '',
      webSitesi: extra?['webSitesi'] ?? '',
      adres: extra?['adres'] ?? '',
      konum: extra?['konum'] ?? '',
    );
    return BireyselOkulBilgiOturumu(
      okulId: okulId,
      yil: yil,
      ogretmenId: ogretmenId,
      okul: okul,
    );
  }

  static Future<BireyselOkulBilgiOturumu> getir() async {
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    return db.transaction((txn) async {
      final result = await _getir(txn);
      await _modKontrol();
      return result;
    });
  }

  static Map<String, String> _temelAlanlar(OkulBilgiModel okul) => {
    'mudurAdi': okul.mudurAdi.trim(),
    'mudurYardimcilari': okul.mudurYardimcilari.trim(),
    'telefon': okul.telefon.trim(),
    'email': okul.email.trim(),
    'webSitesi': okul.webSitesi.trim(),
    'adres': okul.adres.trim(),
    'konum': okul.konum.trim(),
  };

  static bool _webAdresiGecerli(String value) {
    if (value.isEmpty) return true;
    if (RegExp(r'\s').hasMatch(value)) return false;
    final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.contains('.') &&
        !uri.host.startsWith('.') &&
        !uri.host.endsWith('.') &&
        !uri.host.contains('..') &&
        uri.userInfo.isEmpty;
  }

  static void _dogrula(String okulAdi, Map<String, String> fields) {
    if (okulAdi.isEmpty || okulAdi.length > 200) {
      throw const FormatException('Okul adı 1–200 karakter olmalıdır.');
    }
    const limits = {
      'mudurAdi': 160,
      'mudurYardimcilari': 1000,
      'telefon': 50,
      'email': 254,
      'webSitesi': 2048,
      'adres': 2000,
      'konum': 2048,
    };
    for (final field in limits.entries) {
      if (fields[field.key]!.length > field.value) {
        throw FormatException(
          'Okul bilgileri alan sınırını aşıyor: ${field.key} (${field.value}).',
        );
      }
    }
    if (fields['email']!.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(fields['email']!)) {
      throw const FormatException('Geçerli bir e-posta adresi girin.');
    }
    if (!_webAdresiGecerli(fields['webSitesi']!) ||
        !_webAdresiGecerli(fields['konum']!)) {
      throw const FormatException(
        'Web sitesi ve konum için geçerli bir http/https adresi girin.',
      );
    }
  }

  static Future<void> _ekBilgileriYaz(
    DatabaseExecutor db,
    String okulId,
    int ogretmenId,
    Map<String, String> fields,
  ) async {
    await db.insert('UygulamaAyarlari', {
      'Anahtar': _anahtar(okulId, ogretmenId),
      'Deger': jsonEncode(fields),
      'GuncellemeTarihi': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> kaydet(
    BireyselOkulBilgiOturumu oturum,
    OkulBilgiModel okul,
  ) async {
    await _modKontrol();
    final okulAdi = okul.okulAdi.trim(), fields = _temelAlanlar(okul);
    _dogrula(okulAdi, fields);
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final current = await _getir(txn);
      if (current.okulId != oturum.okulId ||
          current.ogretmenId != oturum.ogretmenId ||
          current.yil != oturum.yil ||
          current.okul.okulAdi != oturum.okul.okulAdi ||
          current.okul.kisaAd != oturum.okul.kisaAd ||
          current.okul.aktifDonem != oturum.okul.aktifDonem ||
          jsonEncode(_temelAlanlar(current.okul)) !=
              jsonEncode(_temelAlanlar(oturum.okul))) {
        throw StateError(
          'Okul bilgileri veya oturum değişti. Okul Bilgileri bölümünü yeniden açın.',
        );
      }
      final schoolRows = await txn.update(
        'OkulProfil',
        {'OkulAdi': okulAdi},
        where: 'Id = 1 AND OkulId = ?',
        whereArgs: [oturum.okulId],
      );
      final teacherRows = await txn.update(
        'OgretmenProfil',
        {
          'OkulAdi': okulAdi,
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        },
        where: 'OgretmenProfilId = ? AND Aktif = 1',
        whereArgs: [oturum.ogretmenId],
      );
      if (schoolRows != 1 || teacherRows != 1) {
        throw StateError('Okul ve öğretmen bilgileri güncellenemedi.');
      }
      await _ekBilgileriYaz(txn, oturum.okulId, oturum.ogretmenId, fields);
      await _modKontrol();
    });
  }

  /// Eski kurulumlarda raporlar okul profili olmadan da müdür tutabiliyordu.
  static Future<({String? okulId, String mudur})> raporMuduruGetir(
    DatabaseExecutor db,
    int ogretmenId,
    String okulAdi,
  ) async {
    final schools = await db.query(
      'OkulProfil',
      where: 'Id = 1 AND AktifMi = 1',
    );
    if (schools.isNotEmpty &&
        _okulAdiNormalizeEt(schools.single['OkulAdi'].toString()) ==
            _okulAdiNormalizeEt(okulAdi)) {
      final okulId = schools.single['OkulId'].toString();
      final fields = await _ekBilgiler(db, okulId, ogretmenId);
      return (
        okulId: okulId,
        mudur: fields == null
            ? await _eskiMudurGetir(db, ogretmenId, okulAdi)
            : fields['mudurAdi'] ?? '',
      );
    }
    return (
      okulId: null,
      mudur: await _eskiMudurGetir(db, ogretmenId, okulAdi),
    );
  }

  static Future<void> raporMuduruKaydet(
    DatabaseExecutor db, {
    required String? okulId,
    required int ogretmenId,
    required String okulAdi,
    required String mudur,
  }) async {
    await _modKontrol();
    final current = await raporMuduruGetir(db, ogretmenId, okulAdi);
    if (current.okulId != okulId) {
      throw StateError(
        'Okul kimliği değişti. Öğrencilerim ekranını yeniden açın.',
      );
    }
    if (mudur.trim().length > 160) {
      throw const FormatException(
        'Okul müdürü adı en fazla 160 karakter olmalı.',
      );
    }
    if (okulId == null) {
      await db.insert('UygulamaAyarlari', {
        'Anahtar': _eskiMudurAnahtari(ogretmenId, okulAdi),
        'Deger': mudur.trim(),
        'GuncellemeTarihi': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      final fields =
          await _ekBilgiler(db, okulId, ogretmenId) ?? <String, String>{};
      await _ekBilgileriYaz(db, okulId, ogretmenId, {
        ...fields,
        'mudurAdi': mudur.trim(),
      });
    }
    await _modKontrol();
  }
}
