import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../database/bilgi_toplama_semasi.dart';
import '../database/veli_iliskisi.dart';
import '../models/mesajlasma.dart';
import 'calisma_modu_service.dart';
import 'rehberlik_google_form_service.dart';
import 'bireysel_rehberlik_service.dart';

part 'bilgi_toplama_duzenleme.dart';
part 'bilgi_toplama_ogretmen_gorus_katalog.dart';
part 'bilgi_toplama_yonetim.dart';
part 'bilgi_toplama_ogrenci_tanima_katalog.dart';

class BilgiToplamaOturumu {
  const BilgiToplamaOturumu._(
    this.okulId,
    this.profilId,
    this.yil,
    this.okulAdi,
  );
  final String okulId, yil, okulAdi;
  final int profilId;
}

class BilgiToplamaSorusu {
  BilgiToplamaSorusu({
    required this.anahtar,
    required this.baslik,
    this.veriTuru = 'Metin',
    this.hedefAlan,
    this.zorunlu = false,
    List<String> secenekler = const [],
  }) : secenekler = List.unmodifiable(secenekler);
  final String anahtar, baslik, veriTuru;
  final String? hedefAlan;
  final bool zorunlu;
  final List<String> secenekler;
}

/// Yalnız servis üretebilir. İmzaya bütün güncel ön izleme verileri dahildir.
class BilgiToplamaOnizleme {
  BilgiToplamaOnizleme._({
    required this.yanitId,
    required this.ogrenci,
    required this.girilen,
    required this.degisiklikler,
    required this.serbestDegerler,
    required this.serbestOncekiDegerler,
    required this.hatalar,
    required this.uyarilar,
    required String imza,
  }) : _imza = imza;
  final int yanitId;
  final Map<String, Object?>? ogrenci;
  final Map<String, String> girilen;
  final Map<String, Map<String, String?>> degisiklikler;
  final Map<int, String> serbestDegerler;
  final Map<int, String> serbestOncekiDegerler;
  final List<String> hatalar, uyarilar;
  final String _imza;
  bool get kaydedilebilir => hatalar.isEmpty && ogrenci != null;
}

/// Bireysel SQLite: sahibi kendi ders kapsamındaki formun kontrol yetkilisidir.
/// Ham cevap kaydı ana öğrenci kaydına yazma/onay anlamına gelmez.
class BilgiToplamaSilmePlani {
  BilgiToplamaSilmePlani._(
    this.formId,
    this.googleFormId,
    this._formImza,
    Map<String, String> imzalar,
    this.kaydedilmemisSayisi,
  ) : _imzalar = Map.unmodifiable(imzalar);
  final int formId, kaydedilmemisSayisi;
  final String googleFormId, _formImza;
  final Map<String, String> _imzalar;
  List<String> get googleYanitIdleri => List.unmodifiable(_imzalar.keys);
  int get toplam => _imzalar.length;
}

class BireyselBilgiToplamaService {
  BireyselBilgiToplamaService({
    Future<Database> Function()? databaseGetir,
    Future<CalismaModu?> Function()? modGetir,
    String silmeDagitimi = '',
  }) : _db = databaseGetir ?? (() => LocalDatabase.instance.database),
       _mod = modGetir ?? CalismaModuService.getir,
       _silmeDagitimi = silmeDagitimi;
  // API dağıtım kimliği herkese açık tanımlayıcıdır; erişim Google hesabıyla doğrulanır.
  static const varsayilanSilmeDagitimi = String.fromEnvironment(
    'GOOGLE_FORMS_DELETE_DEPLOYMENT_ID',
    defaultValue:
        'AKfycbzqt5tBBAmgmHmmpPjWVxc7cNqpQF2YtcnXS9GDHSp6BJ5Rs21OUkhJsxOVNFp7jpRf',
  );
  static final instance = BireyselBilgiToplamaService(
    silmeDagitimi: varsayilanSilmeDagitimi,
  );
  final Future<Database> Function() _db;
  final Future<CalismaModu?> Function() _mod;
  final String _silmeDagitimi;
  static const kimlikler = {
    'okulNo': 'Okul numarası',
    'adSoyad': 'Ad soyad',
    'sinif': 'Sınıf',
  };
  static bool kimlikAlani(Object? key) =>
      key == 'ogrenciSecimi' || kimlikler.containsKey(key);

  Future<Map<String, Object?>> _ogrenciSecimSorusu(
    DatabaseExecutor tx,
    BilgiToplamaOturumu b,
    int id,
    Set<int> ids,
  ) async {
    final kapsam = await _kapsam(tx, b);
    final secenekler = <Map<String, Object?>>[];
    final etiketler = <String>{};
    for (final oid in ids.toList()..sort()) {
      final o = kapsam.firstWhere((o) => o['OgrenciId'] == oid);
      final ad = '${o['Ad']} ${o['Soyad']}'.trim();
      var etiket = '${o['SinifKodu']} • ${o['OkulNo']} • $ad';
      if (!etiketler.add(etiket)) {
        etiket = '$etiket (Kayıt $oid)';
        etiketler.add(etiket);
      }
      secenekler.add({
        'etiket': etiket,
        'ogrenciId': oid,
        'okulNo': o['OkulNo'].toString(),
        'adSoyad': ad,
        'sinif': o['SinifKodu'].toString(),
      });
    }
    secenekler.sort(
      (a, b) => (a['etiket'] as String).compareTo(b['etiket'] as String),
    );
    return {
      'FormId': id,
      'AlanAnahtari': 'ogrenciSecimi',
      'Baslik': 'Öğrenciyi seçin',
      'VeriTuru': 'Secenek',
      'HedefAlan': null,
      'Secenekler': jsonEncode(secenekler),
      'Zorunlu': 1,
      'Sira': 1,
    };
  }

  static Map? _secilenKimlik(List ss, Map raw) {
    final sorular = ss.where((q) => q['AlanAnahtari'] == 'ogrenciSecimi');
    if (sorular.isEmpty) return null;
    final q = sorular.single;
    final cevap = _cevap(raw, q);
    final secenekler = (jsonDecode(q['Secenekler'] as String) as List)
        .whereType<Map>();
    final eslesen = secenekler.where((o) => o['etiket'] == cevap).toList();
    return eslesen.length == 1 ? eslesen.single : null;
  }

  // Sabit soru anahtarları mevcut soru tablosunda tutulur; iletişim verisi
  // yalnız öğretmen onayında kişinin mevcut kaydına yazılır.
  static final veliSorulari = List<BilgiToplamaSorusu>.unmodifiable([
    BilgiToplamaSorusu(
      anahtar: 'veliSecimi',
      baslik: 'Veliniz kim?',
      veriTuru: 'Secenek',
      zorunlu: true,
      secenekler: ['Annem', 'Babam', 'Diğer'],
    ),
    BilgiToplamaSorusu(
      anahtar: 'digerVeliAdi',
      baslik: 'Diğer velinin adı soyadı (yalnız Diğer seçtiyseniz)',
    ),
    BilgiToplamaSorusu(
      anahtar: 'digerVeliYakinlik',
      baslik: 'Diğer velinin yakınlık derecesi (yalnız Diğer seçtiyseniz)',
    ),
    BilgiToplamaSorusu(
      anahtar: 'digerVeliTelefonu',
      veriTuru: 'Telefon',
      baslik: 'Diğer velinin telefonu (yalnız Diğer seçtiyseniz)',
    ),
  ]);
  static const veliAlanBasliklari = {
    'VeliTuru': 'Veli ilişkisi',
    'VeliAdi': 'Diğer veli adı',
    'VeliTelefonu': 'Diğer veli telefonu',
  };
  static String _simdi() => DateTime.now().toUtc().toIso8601String();
  static Object? _sirala(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: _sirala(v[k])};
    }
    if (v is List) return v.map(_sirala).toList();
    return v;
  }

  static String _ozet(Object? v) =>
      sha256.convert(utf8.encode(jsonEncode(_sirala(v)))).toString();
  Future<BilgiToplamaOturumu> _oturum(DatabaseExecutor tx) async {
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Bilgi toplama yalnız bireysel öğretmen modunda kullanılabilir.',
      );
    }
    final okullar = await tx.query('OkulProfil', where: 'Id=1 AND AktifMi=1');
    final profiller = await tx.query(
      'OgretmenProfil',
      where: 'Aktif=1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (okullar.length != 1 || profiller.length != 1) {
      throw StateError('Aktif okul ve öğretmen kurulumu gerekli.');
    }
    final o = okullar.single, p = profiller.single;
    if (o['OkulAdi'] != p['OkulAdi'] ||
        o['EgitimYili'] != p['EgitimOgretimYili'] ||
        o['OkulId'].toString().trim().isEmpty ||
        o['EgitimYili'].toString().trim().isEmpty) {
      throw StateError('Okul ve öğretmen eğitim yılı bilgileri tutarsız.');
    }
    return BilgiToplamaOturumu._(
      o['OkulId'] as String,
      p['OgretmenProfilId'] as int,
      o['EgitimYili'] as String,
      o['OkulAdi'] as String,
    );
  }

  Future<void> _kontrol(DatabaseExecutor tx, BilgiToplamaOturumu b) async {
    final g = await _oturum(tx);
    if (g.okulId != b.okulId ||
        g.profilId != b.profilId ||
        g.yil != b.yil ||
        g.okulAdi != b.okulAdi) {
      throw StateError(
        'Okul, öğretmen veya yıl değişti; bilgi toplama bölümünü yeniden açın.',
      );
    }
  }

  Future<T> _islem<T>(
    BilgiToplamaOturumu b,
    Future<T> Function(Transaction) f,
  ) async {
    // Mod kontrolü veritabanını açmadan önce de yapılır.
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError('Bireysel mod gerekli.');
    }
    return (await _db()).transaction((tx) async {
      await _kontrol(tx, b);
      final result = await f(tx);
      await _kontrol(tx, b);
      return result;
    });
  }

  Future<BilgiToplamaOturumu> hazirla() async {
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError('Bireysel mod gerekli.');
    }
    return (await _db()).transaction(_oturum);
  }

  Future<Map<String, Object?>> _form(
    DatabaseExecutor tx,
    BilgiToplamaOturumu b,
    int id,
  ) async {
    final rows = await tx.query(
      'BilgiToplamaForm',
      where: '''Id=? AND OkulId=? AND OgretmenProfilId=? AND EgitimOgretimYili=?
        AND NOT EXISTS(SELECT 1 FROM UygulamaAyarlari a
          WHERE a.Anahtar='bilgi_toplama_form_silinen:' || BilgiToplamaForm.Id)''',
      whereArgs: [id, b.okulId, b.profilId, b.yil],
    );
    if (rows.length != 1) {
      throw StateError('Form aktif okul, öğretmen ve yıl kapsamında değil.');
    }
    return rows.single;
  }

  Future<List<Map<String, Object?>>> _kapsam(
    DatabaseExecutor tx,
    BilgiToplamaOturumu b,
  ) => tx.rawQuery(
    '''
    SELECT DISTINCT o.*, s.SinifSubeId, s.SinifKodu FROM Ogrenci o
    JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
    JOIN SinifSube s ON s.SinifSubeId=k.SinifSubeId
    WHERE o.Aktif=1 AND k.Aktif=1 AND s.Aktif=1
      AND k.EgitimOgretimYili=? AND s.EgitimOgretimYili=?
      AND EXISTS(SELECT 1 FROM GecerliDersProgrami dp WHERE dp.SinifSubeId=s.SinifSubeId
        AND dp.OgretmenProfilId=? AND dp.EgitimOgretimYili=? AND dp.Aktif=1)
    ORDER BY o.OgrenciId, s.SinifSubeId''',
    [b.yil, b.yil, b.profilId, b.yil],
  );

  Future<List<Map<String, Object?>>> hedefAdaylari(BilgiToplamaOturumu b) =>
      _islem(
        b,
        (tx) async => List.unmodifiable(
          (await _kapsam(
            tx,
            b,
          )).map((r) => Map<String, Object?>.unmodifiable(r)),
        ),
      );
  Future<List<Map<String, Object?>>> formlar(BilgiToplamaOturumu b) => _islem(
    b,
    (tx) => tx.query(
      'BilgiToplamaForm',
      where: '''OkulId=? AND OgretmenProfilId=? AND EgitimOgretimYili=?
        AND NOT EXISTS(SELECT 1 FROM UygulamaAyarlari a
          WHERE a.Anahtar='bilgi_toplama_form_silinen:' || BilgiToplamaForm.Id)''',
      whereArgs: [b.okulId, b.profilId, b.yil],
      orderBy: 'Id DESC',
    ),
  );

  /// Formun kayıt bağları onaylı öğrenci ek bilgileri için korunur.
  /// Uzak temizlik başarısızsa listeden kaldırılmaz; tekrar denenebilir.
  Future<void> formuSil(
    BilgiToplamaOturumu b,
    int id, {
    required Future<void> Function(String googleFormId) googleTemizle,
  }) async {
    Future<List<Object?>> anlik(Transaction tx) async => [
      await _form(tx, b, id),
      await tx.query(
        'BilgiToplamaYanit',
        where: 'FormId=?',
        whereArgs: [id],
        orderBy: 'Id',
      ),
    ];
    final onceki = await _islem(b, (tx) async {
      final veri = await anlik(tx);
      final f = veri.first as Map;
      if (f['GoogleFormId'] == null &&
          (await tx.query(
            'UygulamaAyarlari',
            where: 'Anahtar=?',
            whereArgs: [_olusturmaAnahtari(id)],
          )).isNotEmpty) {
        throw StateError(
          'Google oluşturma işlemi yarım kalmış. Önce mevcut Google formunu bağlayın veya oluşmadığını doğrulayın.',
        );
      }
      return veri;
    });
    final gid = (onceki.first as Map)['GoogleFormId'] as String?;
    if (gid != null) await googleTemizle(gid);
    await _islem(b, (tx) async {
      if (_ozet(await anlik(tx)) != _ozet(onceki)) {
        throw StateError(
          'İşlem sırasında form veya yanıtlar değişti. Form korunuyor; yeniden deneyin.',
        );
      }
      final rows = onceki[1] as List;
      for (final googleId
          in rows.map((y) => (y as Map)['GoogleYanitId'] as String).toSet()) {
        await _hamYanitiTemizle(tx, b, id, googleId);
      }
      await tx.update(
        'BilgiToplamaForm',
        {'Durum': 'Kapali', 'GuncellemeTarihi': _simdi()},
        where: 'Id=?',
        whereArgs: [id],
      );
      await tx.insert('UygulamaAyarlari', {
        'Anahtar': 'bilgi_toplama_form_silinen:$id',
        'Deger': _simdi(),
        'GuncellemeTarihi': _simdi(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Set<int>> _formDogrula(
    Transaction tx,
    BilgiToplamaOturumu b,
    String baslik,
    List<BilgiToplamaSorusu> ss,
    String hedefTuru,
    Set<int> oo,
    Set<int> siniflar,
  ) async {
    if (baslik.trim().isEmpty ||
        baslik.trim().length > 300 ||
        ss.isEmpty ||
        ss.length > 100) {
      throw const FormatException('Form başlığı ve 1–100 soru gerekli.');
    }
    if (!{'Siniflarim', 'SinifSec', 'OgrenciSec'}.contains(hedefTuru)) {
      throw StateError(
        'Bireysel modda yalnız kendi ders kapsamınız seçilebilir.',
      );
    }
    if ((hedefTuru == 'SinifSec' && (siniflar.isEmpty || oo.isNotEmpty)) ||
        (hedefTuru == 'OgrenciSec' && (oo.isEmpty || siniflar.isNotEmpty)) ||
        (hedefTuru == 'Siniflarim' && (oo.isNotEmpty || siniflar.isNotEmpty))) {
      throw const FormatException('Hedef türü ve seçimler uyuşmuyor.');
    }
    final keys = {...kimlikler.keys, 'ogrenciSecimi'}, hedefler = <String>{};
    final veliKeys = veliSorulari.map((s) => s.anahtar).toSet();
    if (ss.any((s) => veliKeys.contains(s.anahtar))) {
      for (final beklenen in veliSorulari) {
        final eslesen = ss.where((s) => s.anahtar == beklenen.anahtar);
        if (eslesen.length != 1 ||
            eslesen.single.hedefAlan != null ||
            eslesen.single.veriTuru != beklenen.veriTuru ||
            eslesen.single.zorunlu != beklenen.zorunlu ||
            jsonEncode(eslesen.single.secenekler) !=
                jsonEncode(beklenen.secenekler)) {
          throw const FormatException(
            'Veli soruları birlikte ve tanımlı seçenekleriyle eklenmeli.',
          );
        }
      }
    }
    for (final s in ss) {
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,99}$').hasMatch(s.anahtar) ||
          !keys.add(s.anahtar) ||
          s.baslik.trim().isEmpty ||
          s.baslik.trim().length > 300 ||
          !{
            'Metin',
            'Sayi',
            'Tarih',
            'EvetHayir',
            'Secenek',
            'Telefon',
          }.contains(s.veriTuru)) {
        throw const FormatException(
          'Soru anahtarı, başlığı veya veri türü geçersiz.',
        );
      }
      if (s.hedefAlan != null &&
          (!BilgiToplamaSemasi.ogrenciAlanlari.contains(s.hedefAlan) ||
              !hedefler.add(s.hedefAlan!) ||
              s.veriTuru !=
                  (s.hedefAlan!.contains('Telefon') ? 'Telefon' : 'Metin'))) {
        throw const FormatException(
          'Hazır alan eşleştirmesi geçersiz veya tekrarlanıyor.',
        );
      }
      if ((s.veriTuru == 'Secenek' &&
              (s.secenekler.isEmpty ||
                  s.secenekler.length > 100 ||
                  s.secenekler.any(
                    (v) => v.trim().isEmpty || v != v.trim() || v.length > 300,
                  ) ||
                  s.secenekler.toSet().length != s.secenekler.length)) ||
          (s.veriTuru != 'Secenek' && s.secenekler.isNotEmpty)) {
        throw const FormatException('Soru seçeneklerini kontrol edin.');
      }
    }
    final kapsam = await _kapsam(tx, b);
    final izinli = kapsam.map((r) => r['OgrenciId'] as int).toSet();
    final izinliSinif = kapsam.map((r) => r['SinifSubeId'] as int).toSet();
    if (!izinli.containsAll(oo) || !izinliSinif.containsAll(siniflar)) {
      throw StateError('Seçim ders kapsamınızın dışında.');
    }
    final secilen = kapsam
        .where(
          (r) =>
              hedefTuru == 'Siniflarim' ||
              (hedefTuru == 'SinifSec'
                  ? siniflar.contains(r['SinifSubeId'])
                  : oo.contains(r['OgrenciId'])),
        )
        .map((r) => r['OgrenciId'] as int)
        .toSet();
    if (secilen.isEmpty) throw StateError('Hedef öğrenci bulunamadı.');
    return secilen;
  }

  Future<int> formOlustur(
    BilgiToplamaOturumu b, {
    required String baslik,
    required List<BilgiToplamaSorusu> sorular,
    String hedefTuru = 'Siniflarim',
    String? istekKimligi,
    bool ogrenciListesi = false,
    Set<int> ogrenciIdleri = const {},
    Set<int> sinifIdleri = const {},
  }) {
    // Çağıranın işlem devam ederken listeleri değiştirmesine izin verme.
    final ss = List<BilgiToplamaSorusu>.of(sorular);
    final oo = Set<int>.of(ogrenciIdleri), siniflar = Set<int>.of(sinifIdleri);
    return _islem(b, (tx) async {
      final secilen = await _formDogrula(
        tx,
        b,
        baslik,
        ss,
        hedefTuru,
        oo,
        siniflar,
      );
      final istekKey = istekKimligi == null
          ? null
          : 'bilgi_form_taslak_istegi:${jsonEncode([b.okulId, b.profilId, b.yil, istekKimligi])}';
      final istekOzeti = _ozet([
        baslik.trim(),
        if (ogrenciListesi) 'ogrenci-listesi/v1',
        hedefTuru,
        oo.toList()..sort(),
        siniflar.toList()..sort(),
        ss
            .map(
              (q) => [
                q.anahtar,
                q.baslik,
                q.veriTuru,
                q.hedefAlan,
                q.zorunlu,
                q.secenekler,
              ],
            )
            .toList(),
      ]);
      if (istekKey != null) {
        if (!RegExp(r'^[a-zA-Z0-9_-]{16,100}$').hasMatch(istekKimligi!)) {
          throw const FormatException('Taslak istek kimliği geçersiz.');
        }
        final onceki = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [istekKey],
        );
        if (onceki.isNotEmpty) {
          final v = jsonDecode(onceki.single['Deger'] as String) as Map;
          if (v['ozet'] != istekOzeti) {
            throw StateError(
              'Bu taslak önceden kaydedildi. Listeden açarak düzenleyin.',
            );
          }
          final f = await _form(tx, b, v['formId'] as int);
          return f['Id'] as int;
        }
      }
      final id = await tx.insert('BilgiToplamaForm', {
        'OkulId': b.okulId,
        'OgretmenProfilId': b.profilId,
        'EgitimOgretimYili': b.yil,
        'Baslik': baslik.trim(),
        'HedefTuru': hedefTuru,
        'OlusturmaTarihi': _simdi(),
      });
      final tum = [
        if (!ogrenciListesi)
          for (final k in kimlikler.entries)
            BilgiToplamaSorusu(anahtar: k.key, baslik: k.value, zorunlu: true),
        ...ss,
      ];
      if (ogrenciListesi) {
        await tx.insert(
          'BilgiToplamaSoru',
          await _ogrenciSecimSorusu(tx, b, id, secilen),
        );
      }
      for (var i = 0; i < tum.length; i++) {
        final s = tum[i];
        await tx.insert('BilgiToplamaSoru', {
          'FormId': id,
          'AlanAnahtari': s.anahtar,
          'Baslik': s.baslik.trim(),
          'VeriTuru': s.veriTuru,
          'HedefAlan': s.hedefAlan,
          'Secenekler': jsonEncode(s.secenekler),
          'Zorunlu': s.zorunlu ? 1 : 0,
          'Sira': i + (ogrenciListesi ? 2 : 1),
        });
      }
      for (final o in secilen) {
        await tx.insert('BilgiToplamaHedef', {'FormId': id, 'OgrenciId': o});
      }
      if (istekKey != null) {
        await tx.insert('UygulamaAyarlari', {
          'Anahtar': istekKey,
          'Deger': jsonEncode({'formId': id, 'ozet': istekOzeti}),
          'GuncellemeTarihi': _simdi(),
        });
      }
      return id;
    });
  }

  Future<List<Map<String, Object?>>> sorular(
    BilgiToplamaOturumu b,
    int formId,
  ) => _islem(b, (tx) async {
    await _form(tx, b, formId);
    return tx.query(
      'BilgiToplamaSoru',
      where: 'FormId=?',
      whereArgs: [formId],
      orderBy: 'Sira',
    );
  });

  Future<Map<String, Object?>> formGetir(BilgiToplamaOturumu b, int id) =>
      _islem(b, (tx) => _form(tx, b, id));

  Future<List<Map<String, Object?>>> hedefOgrenciler(
    BilgiToplamaOturumu b,
    int id,
  ) => _islem(b, (tx) async {
    await _form(tx, b, id);
    final hedef = await tx.query(
      'BilgiToplamaHedef',
      where: 'FormId=?',
      whereArgs: [id],
    );
    final ids = hedef.map((r) => r['OgrenciId']).toSet();
    return (await _kapsam(
      tx,
      b,
    )).where((r) => ids.contains(r['OgrenciId'])).toList();
  });

  String _olusturmaAnahtari(int id) => 'bilgi_toplama_google_olusturma:$id';

  /// Ağ isteğinden önce kalıcı işaret; belirsiz POST otomatik tekrarlanmaz.
  Future<void> googleOlusturmayiBaslat(
    BilgiToplamaOturumu b,
    int id,
  ) => _islem(b, (tx) async {
    final f = await _form(tx, b, id);
    if (f['GoogleFormId'] != null || f['Durum'] != 'Taslak') {
      throw StateError('Mevcut form üzerinden devam edin.');
    }
    if ((await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: [_olusturmaAnahtari(id)],
    )).isNotEmpty) {
      throw StateError(
        'Önceki oluşturma işleminin sonucu belirsiz. Google Forms hesabınızdaki formu bağlayın veya oluşmadığını kontrol ederek yeniden denemeyi seçin.',
      );
    }
    await tx.insert('UygulamaAyarlari', {
      'Anahtar': _olusturmaAnahtari(id),
      'Deger': 'Bekliyor',
      'GuncellemeTarihi': _simdi(),
    });
  });

  Future<void> googleTekrarDenemeyeIzinVer(BilgiToplamaOturumu b, int id) =>
      _islem(b, (tx) async {
        final f = await _form(tx, b, id);
        if (f['GoogleFormId'] != null || f['Durum'] != 'Taslak') {
          throw StateError('Mevcut form üzerinden devam edin.');
        }
        await tx.delete(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [_olusturmaAnahtari(id)],
        );
      });

  Future<void> googleTaslakKimliginiKaydet(
    BilgiToplamaOturumu b,
    int id,
    String googleId,
  ) => _islem(b, (tx) async {
    final f = await _form(tx, b, id);
    if (f['Durum'] != 'Taslak' ||
        googleId.trim().isEmpty ||
        (f['GoogleFormId'] != null && f['GoogleFormId'] != googleId)) {
      throw StateError('Taslak form kimliği uyuşmuyor.');
    }
    await tx.update(
      'BilgiToplamaForm',
      {'GoogleFormId': googleId, 'GuncellemeTarihi': _simdi()},
      where: 'Id=?',
      whereArgs: [id],
    );
  });

  /// Google soruları oluşturulduktan sonra gerçek questionId değerleri bağlanır.
  Future<void> googleBagla(
    BilgiToplamaOturumu b,
    int formId,
    String googleFormId,
    Map<String, String> soruKimlikleri,
  ) {
    final ids = Map<String, String>.of(soruKimlikleri);
    return _islem(b, (tx) async {
      final f = await _form(tx, b, formId);
      if (f['Durum'] != 'Taslak' || googleFormId.trim().isEmpty) {
        throw StateError('Yalnız taslak form bağlanabilir.');
      }
      if (f['GoogleFormId'] != null &&
          f['GoogleFormId'] != googleFormId.trim()) {
        throw StateError('Kayıtlı Google formu değiştirilemez.');
      }
      final ss = await tx.query(
        'BilgiToplamaSoru',
        where: 'FormId=?',
        whereArgs: [formId],
      );
      if (ids.length != ss.length ||
          ids.values.any((v) => v.trim().isEmpty) ||
          ids.values.toSet().length != ids.length ||
          ss.any((s) => !ids.containsKey(s['AlanAnahtari']))) {
        throw const FormatException(
          'Google soru kimlikleri eksik veya tekrarlı.',
        );
      }
      for (final s in ss) {
        await tx.update(
          'BilgiToplamaSoru',
          {'GoogleSoruId': ids[s['AlanAnahtari']]},
          where: 'Id=?',
          whereArgs: [s['Id']],
        );
      }
      await tx.update(
        'BilgiToplamaForm',
        {
          'GoogleFormId': googleFormId.trim(),
          'Durum': 'Aktif',
          'GuncellemeTarihi': _simdi(),
        },
        where: 'Id=?',
        whereArgs: [formId],
      );
    });
  }

  /// Ağ isteği transaction dışında; kayıt sırasında sahiplik/mod yeniden denetlenir.
  Future<List<int>> googleYanitlariniAl(
    BilgiToplamaOturumu b,
    int formId, {
    required String erisimBelirteci,
    RehberlikGoogleFormService? google,
  }) async {
    final f = await _islem(b, (tx) => _form(tx, b, formId));
    if (f['Durum'] != 'Aktif' || f['GoogleFormId'] == null) {
      throw StateError('Aktif Google bağlantısı yok.');
    }
    final istemci = google ?? RehberlikGoogleFormService();
    try {
      final cevaplar = await istemci.yanitlariGetir(
        erisimBelirteci: erisimBelirteci,
        googleFormId: f['GoogleFormId'] as String,
      );
      return await yanitlariKaydet(b, formId, cevaplar);
    } finally {
      if (google == null) istemci.dispose();
    }
  }

  Future<List<int>> yanitlariKaydet(
    BilgiToplamaOturumu b,
    int formId,
    List<Map<String, dynamic>> yanitlar,
  ) {
    final kopya = jsonDecode(jsonEncode(yanitlar)) as List;
    return _islem(b, (tx) async {
      final f = await _form(tx, b, formId);
      final bekleyen = await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar=?',
        whereArgs: ['bilgi_toplama_duzenleme:$formId'],
      );
      if (bekleyen.isNotEmpty &&
          (jsonDecode(bekleyen.single['Deger'] as String)
                  as Map)['yerelKaydedildi'] !=
              true) {
        throw StateError(
          'Önce bekleyen form düzenlemesini tamamlayın; ardından yanıtları yeniden getirin.',
        );
      }
      if (f['Durum'] == 'Taslak') throw StateError('Form henüz hazır değil.');
      final ss = await tx.query(
        'BilgiToplamaSoru',
        where: 'FormId=?',
        whereArgs: [formId],
        orderBy: 'Sira',
      );
      final sonuc = <int>[];
      for (final raw in kopya) {
        final r = Map<String, dynamic>.from(raw as Map);
        final id = r['responseId'];
        if (id is! String ||
            id.trim().isEmpty ||
            id.length > 200 ||
            jsonEncode(r).length > 1000000 ||
            (r['formId'] != null && r['formId'] != f['GoogleFormId'])) {
          throw const FormatException(
            'Google yanıt kimliği veya boyutu geçersiz.',
          );
        }
        final surum = _ozet(r);
        if (await _silinmis(tx, formId, id)) continue;
        final eski = await tx.query(
          'BilgiToplamaYanit',
          where: 'FormId=? AND GoogleYanitId=? AND KaynakSurum=?',
          whereArgs: [formId, id, surum],
        );
        if (eski.isNotEmpty) {
          sonuc.add(eski.single['Id'] as int);
          continue;
        }
        // Gecikmiş bir ağ isteği daha eski Google sürümünü güncel yapmasın.
        final gelenZaman = DateTime.tryParse(
          r['lastSubmittedTime']?.toString() ?? '',
        );
        if (gelenZaman != null) {
          final oncekiler = await tx.query(
            'BilgiToplamaYanit',
            where: 'FormId=? AND GoogleYanitId=?',
            whereArgs: [formId, id],
            orderBy: 'Id DESC',
          );
          final dahaYeni = oncekiler.where((y) {
            final ham = jsonDecode(y['HamYanit'] as String) as Map;
            final zaman = DateTime.tryParse(
              ham['lastSubmittedTime']?.toString() ?? '',
            );
            return zaman != null && zaman.isAfter(gelenZaman);
          });
          if (dahaYeni.isNotEmpty) {
            sonuc.add(dahaYeni.first['Id'] as int);
            continue;
          }
        }
        String kimlik(String k) {
          if (ss.any((q) => q['AlanAnahtari'] == 'ogrenciSecimi')) {
            return _secilenKimlik(ss, r)?[k]?.toString() ?? '';
          }
          final s = ss.singleWhere((s) => s['AlanAnahtari'] == k);
          try {
            return _cevap(r, s);
          } on FormatException {
            return '';
          }
        }

        sonuc.add(
          await tx.insert('BilgiToplamaYanit', {
            'FormId': formId,
            'GoogleYanitId': id,
            'KaynakSurum': surum,
            'FormSurum': f['Surum'],
            'GirilenOkulNo': kimlik('okulNo'),
            'GirilenAdSoyad': kimlik('adSoyad'),
            'GirilenSinif': kimlik('sinif'),
            'HamYanit': jsonEncode(r),
            'SoruAnlikGoruntusu': jsonEncode(ss),
            'OlusturmaTarihi': _simdi(),
          }),
        );
      }
      return List.unmodifiable(sonuc);
    });
  }

  static String _cevap(Map r, Map s) {
    final duzeltme = r['_yerelDuzeltme'];
    if (duzeltme is Map && duzeltme['cevaplar'] is Map) {
      final v = duzeltme['cevaplar'][s['AlanAnahtari']];
      if (v is String) return v;
    }
    final answers = r['answers'];
    if (answers is! Map) {
      throw const FormatException('Yanıt alanları geçersiz.');
    }
    final a = answers[s['GoogleSoruId']];
    if (a == null) return '';
    if (a is! Map || a['textAnswers'] is! Map) {
      throw const FormatException('Desteklenmeyen cevap türü.');
    }
    final values = a['textAnswers']['answers'];
    if (values is! List ||
        values.length != 1 ||
        values.single is! Map ||
        values.single['value'] is! String) {
      throw const FormatException('Her soruya tek cevap gerekli.');
    }
    return values.single['value'] as String;
  }

  static String _deger(Map s, String ham) {
    final v = ham.trim();
    if (v.isEmpty) {
      if (s['Zorunlu'] == 1) {
        throw const FormatException('Zorunlu cevap eksik.');
      }
      return '';
    }
    if (v.length > 10000) throw const FormatException('Cevap çok uzun.');
    switch (s['VeriTuru']) {
      case 'Telefon':
        if (v.length > 50 || mesajTelefonNormalize(v) == null) {
          throw const FormatException('Telefon biçimi geçersiz.');
        }
        // Mevcut iletişim servisi gibi görüntülenen biçimi koru.
        break;
      case 'Sayi':
        if (!RegExp(r'^-?\d+(?:[.,]\d+)?$').hasMatch(v)) {
          throw const FormatException('Geçerli bir sayı gerekli.');
        }
        break;
      case 'Tarih':
        final t = DateTime.tryParse(v);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
            t == null ||
            t.toIso8601String().substring(0, 10) != v) {
          throw const FormatException('Geçerli tarih gerekli (YYYY-AA-GG).');
        }
        break;
      case 'EvetHayir':
        if (!{'Evet', 'Hayır'}.contains(v)) {
          throw const FormatException('Evet veya Hayır seçilmeli.');
        }
        break;
      case 'Secenek':
        if (!(jsonDecode(s['Secenekler'] as String) as List)
            .map((o) => o is Map ? o['etiket'] : o)
            .contains(v)) {
          throw const FormatException('Tanımlı seçeneklerden biri gerekli.');
        }
        break;
      case 'Metin':
        break;
      default:
        throw const FormatException('Bilinmeyen veri türü.');
    }
    if (s['HedefAlan'] != null && v.length > 300) {
      throw const FormatException('Hazır alan en fazla 300 karakter olabilir.');
    }
    return v;
  }

  Future<Map<String, Object?>> _yanit(
    DatabaseExecutor tx,
    BilgiToplamaOturumu b,
    int id,
  ) async {
    final rows = await tx.query(
      'BilgiToplamaYanit',
      where: 'Id=?',
      whereArgs: [id],
    );
    if (rows.length != 1) throw StateError('Yanıt bulunamadı.');
    await _form(tx, b, rows.single['FormId'] as int);
    return rows.single;
  }

  Future<List<Map<String, Object?>>> yanitlar(
    BilgiToplamaOturumu b,
    int formId,
  ) => _islem(b, (tx) async {
    await _form(tx, b, formId);
    return _gorunenYanitlar(tx, formId);
  });

  String _silmeAnahtari(int formId, String googleId) =>
      'bilgi_toplama_silinen:$formId:${_ozet(googleId)}';

  Future<bool> formPaylasildiMi(BilgiToplamaOturumu b, int id) => _islem(b, (
    tx,
  ) async {
    final f = await _form(tx, b, id);
    if (f['GoogleFormId'] == null) return false;
    final rows = await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: ['bilgi_toplama_paylasildi:$id'],
    );
    if (rows.isNotEmpty && rows.single['Deger'] == f['GoogleFormId']) {
      return true;
    }
    // Önceki uygulama sürümlerinde paylaşılmış, yanıt alınmış formları koru.
    return (await tx.query(
      'BilgiToplamaYanit',
      columns: ['Id'],
      where: 'FormId=?',
      whereArgs: [id],
      limit: 1,
    )).isNotEmpty;
  });

  Future<void> formPaylasildiIsaretle(
    BilgiToplamaOturumu b,
    int id,
    String googleId,
  ) => _islem(b, (tx) async {
    final f = await _form(tx, b, id);
    if (googleId.isEmpty ||
        f['GoogleFormId'] != googleId ||
        f['Durum'] != 'Aktif') {
      throw StateError('Paylaşılan Google formu güncel kayıtla uyuşmuyor.');
    }
    await tx.insert('UygulamaAyarlari', {
      'Anahtar': 'bilgi_toplama_paylasildi:$id',
      'Deger': googleId,
      'GuncellemeTarihi': _simdi(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  String _scriptAnahtari(BilgiToplamaOturumu b) =>
      'bilgi_toplama_silme_script:${_ozet([b.okulId, b.profilId])}';

  Future<String> silmeBaglantisi(BilgiToplamaOturumu b) =>
      _islem(b, (tx) async {
        final rows = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [_scriptAnahtari(b)],
        );
        return rows.isEmpty ? _silmeDagitimi : rows.single['Deger'] as String;
      });

  Future<void> silmeBaglantisiniKaydet(
    BilgiToplamaOturumu b,
    String deploymentId,
  ) => _islem(b, (tx) async {
    final id = deploymentId.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{10,300}$').hasMatch(id)) {
      throw const FormatException(
        'Apps Script API yürütülebilir dağıtım kimliğini girin; URL veya betik kimliği girmeyin.',
      );
    }
    await tx.insert('UygulamaAyarlari', {
      'Anahtar': _scriptAnahtari(b),
      'Deger': id,
      'GuncellemeTarihi': _simdi(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  /// Ağ isteği SQLite işlemi dışında; iki tarafta da sahiplik/yıl doğrulanır.
  Future<void> yanitiGoogleIleSil(
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p, {
    required Future<void> Function(String formId, String responseId) googleSil,
  }) async {
    final hedef = await _islem(b, (tx) async {
      await _guncel(tx, b, p);
      final y = await _yanit(tx, b, p.yanitId);
      final f = await _form(tx, b, y['FormId'] as int);
      final gid = f['GoogleFormId'] as String?;
      if (gid == null || gid.isEmpty) {
        throw StateError('Google form bağlantısı eksik.');
      }
      return [gid, y['GoogleYanitId'] as String];
    });
    await googleSil(hedef[0], hedef[1]);
    try {
      await yanitiSil(b, p);
    } catch (_) {
      throw StateError(
        'Google tarafında yanıtın silindiği doğrulandı; uygulama kaydı güncellenemedi. '
        'Form ekranını yeniden açıp aynı yanıt için silmeyi tekrar deneyin.',
      );
    }
  }

  Future<bool> _silinmis(
    DatabaseExecutor tx,
    int formId,
    String googleId,
  ) async => (await tx.query(
    'UygulamaAyarlari',
    where: 'Anahtar=?',
    whereArgs: [_silmeAnahtari(formId, googleId)],
  )).isNotEmpty;

  Future<BilgiToplamaSilmePlani> topluSilmePlani(
    BilgiToplamaOturumu b,
    int formId, {
    required bool sadeceKaydedilenler,
    Set<int>? seciliYanitIdleri,
  }) => _islem(b, (tx) async {
    final f = await _form(tx, b, formId);
    final gid = f['GoogleFormId'] as String?;
    if (gid == null || gid.isEmpty) {
      throw StateError('Google form bağlantısı eksik.');
    }
    final rows = await tx.query(
      'BilgiToplamaYanit',
      where: 'FormId=?',
      whereArgs: [formId],
      orderBy: 'Id',
    );
    final gruplar = <String, List<Map<String, Object?>>>{};
    for (final y in rows) {
      (gruplar[y['GoogleYanitId'] as String] ??= []).add(y);
    }
    final imzalar = <String, String>{};
    var kaydedilmemis = 0;
    for (final e in gruplar.entries) {
      // Zaten temizlenen kayıtlar tekrar işlenmez; eski yerel silmeler temizlenebilir.
      if (e.value.every(
        (y) =>
            (jsonDecode(y['HamYanit'] as String) as Map)['_yerelTemizlendi'] ==
            true,
      )) {
        continue;
      }
      if (seciliYanitIdleri != null &&
          !e.value.any((y) => seciliYanitIdleri.contains(y['Id']))) {
        continue;
      }
      final kayitli = e.value.last['Durum'] == 'Onaylandi';
      if (sadeceKaydedilenler && !kayitli) continue;
      if (!kayitli) kaydedilmemis++;
      imzalar[e.key] = _ozet(e.value);
    }
    return BilgiToplamaSilmePlani._(
      formId,
      gid,
      _ozet(f),
      imzalar,
      kaydedilmemis,
    );
  });

  Future<void> topluSilmeYanitiSil(
    BilgiToplamaOturumu b,
    BilgiToplamaSilmePlani plan,
    String googleId, {
    required Future<void> Function(String formId, String responseId) googleSil,
  }) async {
    Future<void> kontrol(Transaction tx) async {
      final f = await _form(tx, b, plan.formId);
      final rows = await tx.query(
        'BilgiToplamaYanit',
        where: 'FormId=? AND GoogleYanitId=?',
        whereArgs: [plan.formId, googleId],
        orderBy: 'Id',
      );
      if (!plan._imzalar.containsKey(googleId) ||
          _ozet(f) != plan._formImza ||
          _ozet(rows) != plan._imzalar[googleId]) {
        throw StateError(
          'Silme onayından sonra kayıt değişti; yeniden kontrol edin.',
        );
      }
    }

    await _islem(b, kontrol);
    await googleSil(plan.googleFormId, googleId);
    try {
      await _islem(b, (tx) async {
        await kontrol(tx);
        await _hamYanitiTemizle(tx, b, plan.formId, googleId);
      });
    } catch (_) {
      throw StateError(
        'Google’dan silindi; yerel temizlik tamamlanamadı. Toplu silmeyi yeniden deneyin.',
      );
    }
  }

  Future<List<Map<String, Object?>>> _gorunenYanitlar(
    DatabaseExecutor tx,
    int formId,
  ) async {
    final rows = await tx.query(
      'BilgiToplamaYanit',
      where: 'FormId=?',
      whereArgs: [formId],
      orderBy: 'Id DESC',
    );
    final eskiSurumler = <int>{};
    final byId = {for (final y in rows) y['Id']: y};
    for (final y in rows) {
      final raw = jsonDecode(y['HamYanit'] as String) as Map;
      final duzeltme = raw['_yerelDuzeltme'];
      if (duzeltme is! Map) continue;
      final eski = byId[duzeltme['oncekiYanitId']];
      if (eski != null && eski['GoogleYanitId'] == y['GoogleYanitId']) {
        eskiSurumler.add(eski['Id'] as int);
      }
    }
    final silinenler = (await tx.query(
      'UygulamaAyarlari',
      columns: ['Anahtar'],
      where: 'Anahtar LIKE ?',
      whereArgs: ['bilgi_toplama_silinen:$formId:%'],
    )).map((r) => r['Anahtar']).toSet();
    final gosterilenGoogleYanitlari = <String>{};
    return rows
        .where(
          (y) =>
              !eskiSurumler.contains(y['Id']) &&
              !silinenler.contains(
                _silmeAnahtari(formId, y['GoogleYanitId'] as String),
              ) &&
              gosterilenGoogleYanitlari.add(y['GoogleYanitId'] as String),
        )
        .toList();
  }

  /// Listeden kaldırır; onaylı öğrenci bilgileri ve kayıt geçmişi korunur.
  Future<void> yanitiSil(BilgiToplamaOturumu b, BilgiToplamaOnizleme p) =>
      _islem(b, (tx) async {
        await _guncel(tx, b, p);
        final y = await _yanit(tx, b, p.yanitId);
        await _hamYanitiTemizle(
          tx,
          b,
          y['FormId'] as int,
          y['GoogleYanitId'] as String,
        );
      });

  Future<void> _hamYanitiTemizle(
    DatabaseExecutor tx,
    BilgiToplamaOturumu b,
    int formId,
    String googleId,
  ) async {
    final rows = await tx.query(
      'BilgiToplamaYanit',
      columns: ['Id'],
      where: 'FormId=? AND GoogleYanitId=?',
      whereArgs: [formId, googleId],
    );
    for (final y in rows) {
      await tx.update(
        'BilgiToplamaEsleme',
        {'Aciklama': 'Yanıtın ham verileri temizlendi.'},
        where: 'YanitId=?',
        whereArgs: [y['Id']],
      );
    }
    await tx.update(
      'BilgiToplamaYanit',
      {
        'HamYanit': '{"_yerelTemizlendi":true}',
        'SoruAnlikGoruntusu': '[]',
        'GirilenOkulNo': '',
        'GirilenAdSoyad': '',
        'GirilenSinif': '',
      },
      where: 'FormId=? AND GoogleYanitId=?',
      whereArgs: [formId, googleId],
    );
    await tx.insert('UygulamaAyarlari', {
      'Anahtar': _silmeAnahtari(formId, googleId),
      'Deger': jsonEncode({'profilId': b.profilId, 'tarih': _simdi()}),
      'GuncellemeTarihi': _simdi(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<BilgiToplamaOnizleme> onizle(BilgiToplamaOturumu b, int yanitId) =>
      _islem(b, (tx) => _onizle(tx, b, yanitId));

  Future<Map<String, Object?>> duzeltmeHedefi(
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p,
  ) => _islem(b, (tx) async {
    await _guncel(tx, b, p);
    final y = await _yanit(tx, b, p.yanitId);
    final f = await _form(tx, b, y['FormId'] as int);
    if (f['Durum'] != 'Aktif' ||
        f['GoogleFormId'] == null ||
        p.ogrenci == null ||
        p.hatalar.any((e) => e.contains('eşleş') || e.contains('kapsam'))) {
      throw StateError(
        'Önce yanıtın doğru öğrenciyle eşleştiğini kontrol edin.',
      );
    }
    final elle = await tx.query(
      'BilgiToplamaEsleme',
      where: 'YanitId=?',
      whereArgs: [p.yanitId],
    );
    String norm(String v) =>
        v.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (elle.isEmpty &&
        (norm(p.girilen['okulNo']!) != norm(p.ogrenci!['OkulNo'].toString()) ||
            norm(p.girilen['adSoyad']!) !=
                norm('${p.ogrenci!['Ad']} ${p.ogrenci!['Soyad']}') ||
            !(await _kapsam(tx, b)).any(
              (o) =>
                  o['OgrenciId'] == p.ogrenci!['OgrenciId'] &&
                  norm(o['SinifKodu'].toString()) == norm(p.girilen['sinif']!),
            ))) {
      throw StateError(
        'Kimlik bilgileri uyuşmuyor. Önce “Doğru öğrenciyi seç” ile eşleştirmeyi doğrulayın.',
      );
    }
    return {
      'formId': f['Id'],
      'googleFormId': f['GoogleFormId'],
      'responseId': y['GoogleYanitId'],
      'ogrenciId': p.ogrenci!['OgrenciId'],
      'baslik': f['Baslik'],
    };
  });

  Future<Map<String, String>> duzenlenecekCevaplar(
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p,
  ) => _islem(b, (tx) async {
    await _guncel(tx, b, p);
    final y = await _yanit(tx, b, p.yanitId);
    final raw = jsonDecode(y['HamYanit'] as String) as Map;
    final ss = jsonDecode(y['SoruAnlikGoruntusu'] as String) as List;
    return {for (final q in ss) q['AlanAnahtari'] as String: _cevap(raw, q)};
  });

  /// Düzeltme yeni bir onay adayıdır; özgün yanıt ve eski onay korunur.
  Future<int> yanitiDuzenle(
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p,
    Map<String, String> cevaplar,
  ) {
    final kopya = Map<String, String>.of(cevaplar);
    return _islem(b, (tx) async {
      await _guncel(tx, b, p);
      final y = await _yanit(tx, b, p.yanitId);
      final f = await _form(tx, b, y['FormId'] as int);
      // Yanıt alımı kapalı olması, önceden gelen yanıtın öğretmen
      // tarafından yeniden değerlendirilmesini engellemez.
      // Reddedilmiş yanıtın kendisi korunur; yapılan düzeltme yeni
      // bir Kontrol kaydı olarak açılır.
      final ss = jsonDecode(y['SoruAnlikGoruntusu'] as String) as List;
      final guncelSorular = await tx.query(
        'BilgiToplamaSoru',
        where: 'FormId=?',
        whereArgs: [f['Id']],
        orderBy: 'Sira',
      );
      if (y['FormSurum'] != f['Surum'] || _ozet(ss) != _ozet(guncelSorular)) {
        throw StateError('Form soruları değişmiş; yeniden kontrol gerekli.');
      }
      if (kopya.length != ss.length ||
          ss.any((q) => !kopya.containsKey(q['AlanAnahtari']))) {
        throw const FormatException(
          'Cevap alanları form sorularıyla uyuşmuyor.',
        );
      }
      final raw = jsonDecode(y['HamYanit'] as String) as Map<String, dynamic>;
      final degerler = <String, String>{};
      for (final q in ss) {
        try {
          degerler[q['AlanAnahtari'] as String] =
              veliSorulari.skip(1).any((s) => s.anahtar == q['AlanAnahtari']) &&
                  kopya['veliSecimi'] != 'Diğer'
              ? ''
              : _deger(q as Map, kopya[q['AlanAnahtari']]!);
        } on FormatException catch (e) {
          throw FormatException('${q['Baslik']}: ${e.message}');
        }
      }
      _veliCevabiniDogrula(degerler);
      if (ss.every((q) => _cevap(raw, q) == degerler[q['AlanAnahtari']])) {
        if (y['Durum'] == 'Reddedildi') {
          throw StateError(
            'Reddedilmiş yanıtı yeniden değerlendirmek için en az bir cevabı değiştirin.',
          );
        }
        return p.yanitId;
      }
      final kimlikSecimi = ss.where(
        (q) => q['AlanAnahtari'] == 'ogrenciSecimi',
      );
      final ayniKimlik = kimlikSecimi.isNotEmpty
          ? _cevap(raw, kimlikSecimi.single) == degerler['ogrenciSecimi']
          : kimlikler.keys.every((k) => degerler[k] == p.girilen[k]);
      raw['_yerelDuzeltme'] = {
        'oncekiYanitId': p.yanitId,
        'profilId': b.profilId,
        'tarih': _simdi(),
        'cevaplar': degerler,
      };
      final id = await tx.insert('BilgiToplamaYanit', {
        'FormId': y['FormId'],
        'GoogleYanitId': y['GoogleYanitId'],
        'KaynakSurum': _ozet(raw),
        'FormSurum': y['FormSurum'],
        'GirilenOkulNo':
            _secilenKimlik(ss, raw)?['okulNo'] ?? degerler['okulNo'] ?? '',
        'GirilenAdSoyad':
            _secilenKimlik(ss, raw)?['adSoyad'] ?? degerler['adSoyad'] ?? '',
        'GirilenSinif':
            _secilenKimlik(ss, raw)?['sinif'] ?? degerler['sinif'] ?? '',
        'HamYanit': jsonEncode(raw),
        'SoruAnlikGoruntusu': y['SoruAnlikGoruntusu'],
        'Durum': 'Kontrol',
        'OlusturmaTarihi': _simdi(),
      });
      // Önceki bekleyen sürümün yanlışlıkla toplu onaylanmasını önle.
      if (y['Durum'] != 'Onaylandi') {
        await tx.update(
          'BilgiToplamaYanit',
          {'Durum': 'Reddedildi'},
          where: 'Id=?',
          whereArgs: [p.yanitId],
        );
      }
      final eslemeler = await tx.query(
        'BilgiToplamaEsleme',
        where: 'YanitId=?',
        whereArgs: [p.yanitId],
      );
      if (eslemeler.isNotEmpty && ayniKimlik) {
        await _eslemeyiDuzeltTx(tx, b, id, y);
      }
      return id;
    });
  }

  Future<void> _eslemeyiDuzeltTx(
    Transaction tx,
    BilgiToplamaOturumu b,
    int id,
    Map<String, Object?> onceki,
  ) async {
    await tx.insert('BilgiToplamaEsleme', {
      'YanitId': id,
      'FormId': onceki['FormId'],
      'OncekiOgrenciId': onceki['OgrenciId'],
      'YeniOgrenciId': onceki['OgrenciId'],
      'KontrolEdenProfilId': b.profilId,
      'Aciklama':
          'Kimlik bilgileri değişmedi; önceki öğretmen eşleştirmesi korundu.',
      'Tarih': _simdi(),
    });
    await tx.update(
      'BilgiToplamaYanit',
      {'OgrenciId': onceki['OgrenciId']},
      where: 'Id=?',
      whereArgs: [id],
    );
  }

  static void _veliCevabiniDogrula(Map<String, String> degerler) {
    if (!degerler.containsKey('veliSecimi')) return; // Eski formlar korunur.
    if (!{'Annem', 'Babam', 'Diğer'}.contains(degerler['veliSecimi'])) {
      throw const FormatException('Veliniz kim? sorusunu cevaplayın.');
    }
    if (degerler['veliSecimi'] != 'Diğer') return;
    final ad = degerler['digerVeliAdi'] ?? '';
    final yakinlik = degerler['digerVeliYakinlik'] ?? '';
    final tel = degerler['digerVeliTelefonu'] ?? '';
    if (ad.trim().isEmpty ||
        ad.length > 200 ||
        yakinlik.trim().isEmpty ||
        yakinlik.length > 200 ||
        tel.length > 50 ||
        mesajTelefonNormalize(tel) == null) {
      throw const FormatException(
        'Diğer veli için ad soyad, yakınlık derecesi ve geçerli telefon gerekli.',
      );
    }
  }

  Future<BilgiToplamaOnizleme> _onizle(
    DatabaseExecutor tx,
    BilgiToplamaOturumu b,
    int id,
  ) async {
    final y = await _yanit(tx, b, id),
        hatalar = <String>[],
        uyarilar = <String>[];
    final f = await _form(tx, b, y['FormId'] as int);
    final gorunen = await _gorunenYanitlar(tx, f['Id'] as int);
    if (!gorunen.any((r) => r['Id'] == id)) {
      hatalar.add(
        'Yanıt silinmiş veya daha yeni bir düzeltmeyle değiştirilmiş.',
      );
    }
    if (f['Durum'] == 'Taslak' ||
        y['Durum'] == 'Onaylandi' ||
        y['Durum'] == 'Reddedildi') {
      hatalar.add('Form/yanıt kayıt için açık değil.');
    }
    final ss = (jsonDecode(y['SoruAnlikGoruntusu'] as String) as List)
        .cast<Map>();
    final guncelSorular = await tx.query(
      'BilgiToplamaSoru',
      where: 'FormId=?',
      whereArgs: [f['Id']],
      orderBy: 'Sira',
    );
    if (y['FormSurum'] != f['Surum'] || _ozet(ss) != _ozet(guncelSorular)) {
      hatalar.add('Form soruları değişmiş; yeniden kontrol gerekli.');
    }
    final raw = jsonDecode(y['HamYanit'] as String) as Map;
    final bilinenSorular = ss.map((s) => s['GoogleSoruId']).toSet();
    if (raw['answers'] is Map &&
        (raw['answers'] as Map).keys.any((k) => !bilinenSorular.contains(k))) {
      hatalar.add('Formda eşleştirilmemiş soru var; cevaplar kaydedilmedi.');
    }
    final degerler = <String, String>{};
    final veliSorusu = ss.where((s) => s['AlanAnahtari'] == 'veliSecimi');
    final digerVeli =
        veliSorusu.isNotEmpty && _cevap(raw, veliSorusu.single) == 'Diğer';
    for (final s in ss) {
      try {
        degerler[s['AlanAnahtari'] as String] =
            veliSorulari.skip(1).any((q) => q.anahtar == s['AlanAnahtari']) &&
                !digerVeli
            ? ''
            : _deger(s, _cevap(raw, s));
      } on FormatException catch (e) {
        hatalar.add('${s['Baslik']}: ${e.message}');
      }
    }
    try {
      _veliCevabiniDogrula(degerler);
    } on FormatException catch (e) {
      hatalar.add(e.message);
    }
    final kapsam = await _kapsam(tx, b);
    final hedefler = await tx.query(
      'BilgiToplamaHedef',
      where: 'FormId=?',
      whereArgs: [f['Id']],
    );
    final hedefIds = hedefler.map((r) => r['OgrenciId']).toSet();
    final duzeltmeler = await tx.query(
      'BilgiToplamaEsleme',
      where: 'YanitId=?',
      whereArgs: [id],
      orderBy: 'Id',
    );
    final no = (y['GirilenOkulNo'] as String).trim();
    final adaylar = kapsam
        .where((o) => (o['OkulNo'] as String).trim() == no)
        .toList();
    final adayIds = adaylar.map((o) => o['OgrenciId']).toSet();
    int? ogrenciId;
    if (duzeltmeler.isNotEmpty) {
      ogrenciId = y['OgrenciId'] as int?;
    } else if (ss.any((q) => q['AlanAnahtari'] == 'ogrenciSecimi')) {
      ogrenciId = _secilenKimlik(ss, raw)?['ogrenciId'] as int?;
      if (ogrenciId == null) {
        hatalar.add('Geçerli bir öğrenci seçimi bulunamadı.');
      }
    } else if (no.isNotEmpty && adayIds.length == 1) {
      ogrenciId = adayIds.single as int;
    } else {
      hatalar.add(
        adayIds.length > 1
            ? 'Okul numarası birden fazla öğrenciyle eşleşti.'
            : 'Okul numarası bulunamadı.',
      );
    }
    final ogrenciler = kapsam
        .where((o) => o['OgrenciId'] == ogrenciId)
        .toList();
    Map<String, Object?>? ogrenci;
    if (ogrenciId != null &&
        hedefIds.contains(ogrenciId) &&
        ogrenciler.isNotEmpty) {
      ogrenci = Map<String, Object?>.of(ogrenciler.first);
      ogrenci['SinifKodu'] =
          (ogrenciler.map((o) => o['SinifKodu'].toString()).toSet().toList()
                ..sort())
              .join(', ');
    } else if (ogrenciId != null) {
      hatalar.add('Öğrenci hedef liste veya güncel ders kapsamı dışında.');
    }
    final diger = ogrenciId == null
        ? <Map<String, Object?>>[]
        : await tx.query(
            'BilgiToplamaYanit',
            where:
                'FormId=? AND Id!=? AND (OgrenciId=? OR GoogleYanitId=? OR trim(GirilenOkulNo)=?)',
            whereArgs: [f['Id'], id, ogrenciId, y['GoogleYanitId'], no],
            orderBy: 'Id',
          );
    final gorunenIds = gorunen.map((r) => r['Id']).toSet();
    if (diger.any((r) => r['GoogleYanitId'] == y['GoogleYanitId'])) {
      uyarilar.add(
        'Bu cevabın önceki sürümü var. Güncel düzeltmeleri kontrol ederek yeniden onaylayın.',
      );
    }
    if (diger.any((r) => gorunenIds.contains(r['Id']))) {
      uyarilar.add(
        'Aynı öğrenci veya Google yanıtı için başka cevaplar var; seçtiğiniz cevap ayrıca onaylanmalı.',
      );
    }
    if (ogrenci != null) {
      String norm(String v) =>
          v.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (norm(y['GirilenAdSoyad'] as String) !=
              norm('${ogrenci['Ad']} ${ogrenci['Soyad']}') ||
          !ogrenciler.any(
            (o) =>
                norm(o['SinifKodu'].toString()) ==
                norm(y['GirilenSinif'] as String),
          ) ||
          no != (ogrenci['OkulNo'] as String).trim()) {
        uyarilar.add(
          'Formdaki kimlik bilgileri mevcut öğrenciyle farklı; kontrol edin.',
        );
      }
    }
    final degisiklikler = <String, Map<String, String?>>{},
        serbest = <int, String>{};
    if (ogrenci != null) {
      for (final s in ss.where((s) => !kimlikAlani(s['AlanAnahtari']))) {
        final v = degerler[s['AlanAnahtari']];
        if (v == null || v.isEmpty) continue;
        if (veliSorulari.any((q) => q.anahtar == s['AlanAnahtari']) &&
            s['AlanAnahtari'] != 'digerVeliYakinlik') {
          continue;
        }
        final hedef = s['HedefAlan'] as String?;
        if (hedef != null) {
          if (!BilgiToplamaSemasi.ogrenciAlanlari.contains(hedef)) {
            hatalar.add('İzin verilmeyen alan eşleştirmesi.');
            continue;
          }
          degisiklikler[hedef] = Map.unmodifiable({
            'eski': ogrenci[hedef]?.toString(),
            'yeni': v,
          });
        } else {
          serbest[s['Id'] as int] = v;
        }
      }
      final tur = {
        'Annem': 'Anne',
        'Babam': 'Baba',
        'Diğer': 'Diger',
      }[degerler['veliSecimi']];
      if (tur != null) {
        degisiklikler['VeliTuru'] = Map.unmodifiable({
          'eski': VeliIliskisi.tur(ogrenci),
          'yeni': tur,
        });
        if (tur == 'Diger') {
          for (final e in {
            'VeliAdi': 'digerVeliAdi',
            'VeliTelefonu': 'digerVeliTelefonu',
          }.entries) {
            degisiklikler[e.key] = Map.unmodifiable({
              'eski': ogrenci[e.key]?.toString(),
              'yeni': degerler[e.value],
            });
          }
        }
      }
    }
    final mevcutEk = ogrenciId == null
        ? []
        : await tx.rawQuery(
            '''SELECT e.* FROM OgrenciEkBilgiDeger e
            JOIN BilgiToplamaYanit y ON y.Id=e.YanitId
            WHERE e.OgrenciId=? AND y.Durum='Onaylandi'
            ORDER BY y.OnayTarihi, y.Id, e.SoruId''',
            [ogrenciId],
          );
    final imza = _ozet({
      'yanit': y,
      'form': f,
      'sorular': guncelSorular,
      'ogrenciler': ogrenciler,
      'hedef': hedefler,
      'duzeltmeler': duzeltmeler,
      'diger': diger,
      'ek': mevcutEk,
      'hata': hatalar,
      'uyari': uyarilar,
    });
    return BilgiToplamaOnizleme._(
      yanitId: id,
      ogrenci: ogrenci == null ? null : Map.unmodifiable(ogrenci),
      girilen: Map.unmodifiable({
        'okulNo': y['GirilenOkulNo'] as String,
        'adSoyad': y['GirilenAdSoyad'] as String,
        'sinif': y['GirilenSinif'] as String,
      }),
      degisiklikler: Map.unmodifiable(degisiklikler),
      serbestDegerler: Map.unmodifiable(serbest),
      serbestOncekiDegerler: Map.unmodifiable({
        for (final e in mevcutEk)
          if (serbest.containsKey(e['SoruId']))
            e['SoruId'] as int: e['Deger'] as String,
      }),
      hatalar: List.unmodifiable(hatalar),
      uyarilar: List.unmodifiable(uyarilar),
      imza: imza,
    );
  }

  Future<void> eslemeyiDuzelt(
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p, {
    required int ogrenciId,
    required String aciklama,
  }) => _islem(b, (tx) async {
    await _guncel(tx, b, p);
    final y = await _yanit(tx, b, p.yanitId);
    if (y['Durum'] == 'Onaylandi' || y['Durum'] == 'Reddedildi') {
      throw StateError('Kapalı yanıt düzeltilemez.');
    }
    final f = await _form(tx, b, y['FormId'] as int);
    if (f['Durum'] != 'Aktif') throw StateError('Form aktif değil.');
    if (aciklama.trim().isEmpty || aciklama.length > 1000) {
      throw const FormatException(
        'Düzeltme açıklaması gerekli (en fazla 1000 karakter).',
      );
    }
    final kapsam = await _kapsam(tx, b);
    final hedef = await tx.query(
      'BilgiToplamaHedef',
      where: 'FormId=? AND OgrenciId=?',
      whereArgs: [y['FormId'], ogrenciId],
    );
    if (!kapsam.any((o) => o['OgrenciId'] == ogrenciId) || hedef.isEmpty) {
      throw StateError('Öğrenci yetkili hedef kapsamında değil.');
    }
    await tx.insert('BilgiToplamaEsleme', {
      'YanitId': p.yanitId,
      'FormId': y['FormId'],
      'OncekiOgrenciId': p.ogrenci?['OgrenciId'],
      'YeniOgrenciId': ogrenciId,
      'KontrolEdenProfilId': b.profilId,
      'Aciklama': aciklama.trim(),
      'Tarih': _simdi(),
    });
    await tx.update(
      'BilgiToplamaYanit',
      {'OgrenciId': ogrenciId, 'Durum': 'Kontrol'},
      where: 'Id=?',
      whereArgs: [p.yanitId],
    );
  });
  Future<BilgiToplamaOnizleme> _guncel(
    DatabaseExecutor tx,
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p,
  ) async {
    final y = await _yanit(tx, b, p.yanitId);
    if (!(await _gorunenYanitlar(
      tx,
      y['FormId'] as int,
    )).any((r) => r['Id'] == p.yanitId)) {
      throw StateError(
        'Yanıt silinmiş veya daha yeni bir düzeltmeyle değiştirilmiş.',
      );
    }
    final yeni = await _onizle(tx, b, p.yanitId);
    if (yeni._imza != p._imza) {
      throw StateError(
        'Ön izleme sonrasında veriler değişti; yeniden kontrol edin.',
      );
    }
    return yeni;
  }

  Future<void> onayla(
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p, {
    bool uyarilariKabulEt = false,
  }) => _islem(b, (tx) async {
    final yeni = await _guncel(tx, b, p);
    if (!yeni.kaydedilebilir) {
      throw StateError('Hataları düzeltmeden kaydedilemez.');
    }
    if (yeni.uyarilar.isNotEmpty && !uyarilariKabulEt) {
      throw StateError('Kimlik/tekrar yanıt uyarıları için açık onay gerekli.');
    }
    final y = await _yanit(tx, b, p.yanitId), simdi = _simdi();
    final oid = yeni.ogrenci!['OgrenciId'] as int;
    await tx.update(
      'BilgiToplamaYanit',
      {
        'OgrenciId': oid,
        'Durum': 'Onaylandi',
        'OnaylayanProfilId': b.profilId,
        'OnayTarihi': simdi,
      },
      where: 'Id=?',
      whereArgs: [p.yanitId],
    );
    if (yeni.degisiklikler.isNotEmpty) {
      await tx.update(
        'Ogrenci',
        {
          for (final e in yeni.degisiklikler.entries) e.key: e.value['yeni'],
          'GuncellemeTarihi': simdi,
        },
        where: 'OgrenciId=?',
        whereArgs: [oid],
      );
    }
    for (final e in yeni.serbestDegerler.entries) {
      await tx.insert('OgrenciEkBilgiDeger', {
        'YanitId': p.yanitId,
        'FormId': y['FormId'],
        'SoruId': e.key,
        'OgrenciId': oid,
        'Deger': e.value,
      });
    }
  });
  Future<void> reddet(BilgiToplamaOturumu b, BilgiToplamaOnizleme p) =>
      _islem(b, (tx) async {
        await _guncel(tx, b, p);
        final y = await _yanit(tx, b, p.yanitId);
        if (y['Durum'] == 'Onaylandi' || y['Durum'] == 'Reddedildi') {
          throw StateError('Kapalı yanıt değiştirilemez.');
        }
        await tx.update(
          'BilgiToplamaYanit',
          {'Durum': 'Reddedildi'},
          where: 'Id=?',
          whereArgs: [p.yanitId],
        );
      });
}

extension BilgiFormAliciSecimi on BireyselBilgiToplamaService {
  Future<Set<String>> formAliciBaglari(BilgiToplamaOturumu b, int id) =>
      _islem(b, (tx) async {
        await _form(tx, b, id);
        final r = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: ['bilgi_form_alicilari:$id'],
        );
        return r.isEmpty
            ? <String>{}
            : (jsonDecode(r.single['Deger'] as String) as List)
                  .cast<String>()
                  .toSet();
      });
  Future<void> formAlicilariniKaydet(
    BilgiToplamaOturumu b,
    int id,
    Set<String> baglar,
  ) => _islem(b, (tx) async {
    await _form(tx, b, id);
    if (baglar.isEmpty || baglar.length > 2000) {
      throw StateError('En az bir alıcı seçin.');
    }
    final kapsam = await _kapsam(tx, b);
    for (final bag in baglar) {
      final p = bag.split(':');
      if (p.length != 3) throw StateError('Alıcı bağı geçersiz.');
      final sinif = int.tryParse(p[2]);
      if (!kapsam.any((o) => o['SinifSubeId'] == sinif)) {
        throw StateError('Alıcı sınıfı kapsam dışında.');
      }
      if (p[0] == 'Ogretmen') {
        final rows = await tx.rawQuery(
          'SELECT k.KisiId FROM MesajOgretmenKisi k JOIN MesajOgretmenSinif i ON i.KisiId=k.KisiId WHERE k.KisiId=? AND k.OkulId=? AND k.SahipProfilId=? AND k.Aktif=1 AND i.SinifSubeId=? AND i.EgitimOgretimYili=?',
          [p[1], b.okulId, b.profilId, sinif, b.yil],
        );
        if (rows.isEmpty) throw StateError('Öğretmen bu sınıfta değil.');
      } else if (!{'Ogrenci', 'Veli'}.contains(p[0]) ||
          !kapsam.any(
            (o) => '${o['OgrenciId']}' == p[1] && o['SinifSubeId'] == sinif,
          )) {
        throw StateError('Öğrenci veya veli kapsam dışında.');
      }
    }
    await tx.insert('UygulamaAyarlari', {
      'Anahtar': 'bilgi_form_alicilari:$id',
      'Deger': jsonEncode(baglar.toList()),
      'GuncellemeTarihi': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
}
