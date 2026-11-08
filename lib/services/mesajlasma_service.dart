import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../database/veli_iliskisi.dart';
import '../models/mesajlasma.dart';
import '../models/mesaj_sablonu.dart';
import '../models/ortak_import.dart';
import 'calisma_modu_service.dart';

part 'mesaj_form_service.dart';
part 'mesaj_sablon_service.dart';
part 'mesaj_alici_service.dart';
part 'mesaj_ogretmen_import_service.dart';

/// Modüller kaynakModul/kaynakKayit, metin ve öğrenci kimlikleri sağlar.
/// Alıcı kapsamını ve kalıcı gönderim akışını yalnız bu servis yönetir.
class MesajlasmaService {
  MesajlasmaService({
    Future<Database> Function()? databaseGetir,
    Future<CalismaModu?> Function()? modGetir,
    Future<void> Function(String telefon, String metin)? whatsappAc,
    Future<bool> Function()? smsIzni,
    Future<int> Function(String telefon, String metin)? smsGonder,
    this.ogrenciTelefonu = false,
  }) : _db = databaseGetir ?? (() => LocalDatabase.instance.database),
       _mod = modGetir ?? CalismaModuService.getir,
       _whatsapp = whatsappAc ?? _whatsappAc,
       _smsIzin = smsIzni ?? _smsIzni,
       _sms = smsGonder ?? _smsGonder;
  static final instance = MesajlasmaService();
  final Future<Database> Function() _db;
  final Future<CalismaModu?> Function() _mod;
  final Future<void> Function(String, String) _whatsapp;
  final Future<bool> Function() _smsIzin;
  final Future<int> Function(String, String) _sms;
  final bool ogrenciTelefonu;
  static const formDuzeltmeOgrenciModulu = 'BilgiFormDuzeltmeOgrenci';
  static const formPaylasimOgrenciModulu = 'BilgiFormPaylasimOgrenci';
  static const formPaylasimVeliModulu = 'BilgiFormPaylasimVeli';
  static bool _islemSuruyor = false;
  static final _bekleyenIslemler = <void Function()>[];

  Future<T> _sirali<T>(Future<T> Function() f) {
    final sonuc = Completer<T>();
    final zone = Zone.current;
    // Bitmiş bir Future'ın oluşturulduğu yaşam döngüsüne bağlanma. İşlemler
    // servis örnekleri arasında sıralı kalır, her çağrı kendi Zone'unda yürür.
    void baslat() async {
      try {
        sonuc.complete(await f());
      } catch (e, st) {
        sonuc.completeError(e, st);
      } finally {
        if (_bekleyenIslemler.isEmpty) {
          _islemSuruyor = false;
        } else {
          _bekleyenIslemler.removeAt(0)();
        }
      }
    }

    if (_islemSuruyor) {
      _bekleyenIslemler.add(() => zone.run(baslat));
    } else {
      _islemSuruyor = true;
      zone.run(baslat);
    }
    return sonuc.future;
  }

  static Future<void> _whatsappAc(String telefon, String metin) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'WhatsApp açma bu sürümde yalnız Android üzerinde destekleniyor.',
      );
    }
    await const MethodChannel(
      'elpi_okul_yonetim/mesajlasma',
    ).invokeMethod<void>('whatsappAc', {'telefon': telefon, 'metin': metin});
  }

  static Future<bool> _smsIzni() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'SIM üzerinden SMS yalnız Android cihazda desteklenir.',
      );
    }
    return await const MethodChannel(
          'elpi_okul_yonetim/mesajlasma',
        ).invokeMethod<bool>('smsIzni') ==
        true;
  }

  static Future<int> _smsGonder(String telefon, String metin) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'SIM üzerinden SMS yalnız Android cihazda desteklenir.',
      );
    }
    final sonuc = await const MethodChannel('elpi_okul_yonetim/mesajlasma')
        .invokeMapMethod<String, dynamic>('smsGonder', {
          'telefon': telefon,
          'metin': metin,
        });
    final parca = sonuc?['parca'];
    if (parca is! int || parca <= 0)
      throw StateError('SMS gönderim sonucu doğrulanamadı.');
    return parca;
  }

  Future<void> _modKontrol() async {
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Mesajlaşma yalnız bireysel öğretmen modunda kullanılabilir.',
      );
    }
  }

  Future<MesajBaglami> _baglam(DatabaseExecutor db) async {
    await _modKontrol();
    final okul = await db.query('OkulProfil', where: 'Id = 1 AND AktifMi = 1');
    final profil = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (okul.length != 1 ||
        profil.isEmpty ||
        okul.single['EgitimYili'] != profil.single['EgitimOgretimYili'] ||
        okul.single['OkulAdi'] != profil.single['OkulAdi']) {
      throw StateError('Önce bireysel öğretmen ve okul kurulumunu tamamlayın.');
    }
    final p = profil.single, s = okul.single;
    return MesajBaglami(
      s['OkulId'] as String,
      p['OgretmenProfilId'] as int,
      p['AdSoyad'] as String,
      s['OkulAdi'] as String,
      s['EgitimYili'] as String,
    );
  }

  Future<void> _kontrol(DatabaseExecutor db, MesajBaglami b) async {
    if (!b.ayni(await _baglam(db))) {
      throw StateError(
        'Öğretmen, okul veya eğitim yılı değişti. Mesajlaşmayı yeniden açın.',
      );
    }
  }

  Future<MesajBaglami> hazirla() async => _baglam(await _db());

  Future<List<MesajOgrencisi>> _ogrenciler(
    DatabaseExecutor db,
    MesajBaglami b, {
    bool? ogrenciAlici,
  }) async {
    final ogrenci = ogrenciAlici ?? ogrenciTelefonu;
    final rows = await db.rawQuery(
      '''SELECT DISTINCT o.OgrenciId, o.OkulNo,
      o.Ad, o.Soyad, ${ogrenci ? "o.Ad || ' ' || o.Soyad" : VeliIliskisi.adSql('o')} AS VeliAdi,
      ${ogrenci ? 'o.Telefon' : VeliIliskisi.telefonSql('o')} AS VeliTelefonu,
      ${VeliIliskisi.turSql('o')} AS SeciliVeliTuru, o.VeliTuru AS KayitliVeliTuru,
      o.AnneAdi, o.AnneTelefon, o.BabaAdi, o.BabaTelefon,
      s.SinifSubeId, s.SinifKodu
      FROM Ogrenci o JOIN OgrenciSinifKayit k ON k.OgrenciId = o.OgrenciId
      JOIN SinifSube s ON s.SinifSubeId = k.SinifSubeId
      WHERE o.Aktif = 1 AND k.Aktif = 1 AND s.Aktif = 1
        AND k.EgitimOgretimYili = ? AND s.EgitimOgretimYili = ?
        AND EXISTS (SELECT 1 FROM GecerliDersProgrami dp
          WHERE dp.SinifSubeId = s.SinifSubeId AND dp.OgretmenProfilId = ?
          AND dp.EgitimOgretimYili = ? AND dp.Aktif = 1)
      ORDER BY s.SinifKodu, CAST(o.OkulNo AS INTEGER), o.OkulNo, o.Ad''',
      [b.yil, b.yil, b.ogretmenId, b.yil],
    );
    return rows.map((r) {
      var ad = (r['VeliAdi'] ?? '').toString();
      var telefon = (r['VeliTelefonu'] ?? '').toString();
      var tur = r['SeciliVeliTuru'] as String?;
      String? telefonAciklamasi;
      if (!ogrenci &&
          r['KayitliVeliTuru'] != null &&
          (tur == 'Anne' || tur == 'Baba') &&
          mesajTelefonNormalize(telefon) == null) {
        final diger = tur == 'Anne' ? 'Baba' : 'Anne';
        final digerTelefon = (r['${diger}Telefon'] ?? '').toString();
        if (mesajTelefonNormalize(digerTelefon) != null) {
          telefonAciklamasi =
              'Kayıtlı veli: $tur. $tur telefonu eksik veya geçersiz olduğu için $diger telefonu kullanılıyor.';
          tur = diger;
          telefon = digerTelefon;
          ad = (r['${diger}Adi'] ?? '').toString().trim();
          if (ad.isEmpty) ad = diger == 'Anne' ? 'Annesi' : 'Babası';
        }
      }
      return MesajOgrencisi(
        r['OgrenciId'] as int,
        r['OkulNo'] as String,
        '${r['Ad']} ${r['Soyad']}',
        r['SinifSubeId'] as int,
        r['SinifKodu'] as String,
        ad,
        telefon,
        veliTuru: tur,
        veliIliskisiTanimli: r['KayitliVeliTuru'] != null,
        telefonAciklamasi: telefonAciklamasi,
      );
    }).toList();
  }

  Future<List<MesajOgrencisi>> ogrenciler(MesajBaglami b) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _kontrol(tx, b);
      return _ogrenciler(tx, b);
    });
  }

  Future<Map<String, Object?>> veliBilgileri(MesajBaglami b, int id) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _kontrol(tx, b);
      if (!(await _ogrenciler(tx, b)).any((o) => o.id == id)) {
        throw StateError('Öğrenci ders kapsamınızda değil.');
      }
      return VeliIliskisi.gorunum(
        (await tx.query(
          'Ogrenci',
          where: 'OgrenciId=?',
          whereArgs: [id],
        )).single,
      );
    });
  }

  Future<List<Map<String, Object?>>> telefonDuzenlemeBilgileri(
    MesajBaglami b,
    Set<int> ids,
  ) async {
    final secilen = Set<int>.of(ids), db = await _db();
    return db.transaction((tx) async {
      await _kontrol(tx, b);
      final uygun = await _ogrenciler(tx, b);
      if (secilen.any((id) => !uygun.any((o) => o.id == id))) {
        throw StateError(
          'Telefonu düzenlenecek öğrenci ders kapsamınızda değil.',
        );
      }
      final rows = <Map<String, Object?>>[];
      for (final id in secilen) {
        final o = (await tx.query(
          'Ogrenci',
          where: 'OgrenciId=?',
          whereArgs: [id],
        )).single;
        final tur = ogrenciTelefonu ? 'Ogrenci' : VeliIliskisi.tur(o);
        final alan = tur == 'Ogrenci'
            ? 'Telefon'
            : tur == 'Diger'
            ? 'VeliTelefonu'
            : '${tur}Telefon';
        rows.add({
          'id': id,
          'tur': tur,
          'telefon': o[alan]?.toString() ?? '',
          'aciklama': uygun.firstWhere((o) => o.id == id).aciklama,
        });
      }
      return rows;
    });
  }

  Future<void> telefonlariKaydet(
    MesajBaglami b,
    Map<int, String> telefonlar, {
    required List<Map<String, Object?>> beklenen,
  }) {
    final degerler = Map<int, String>.of(telefonlar);
    final eski = [for (final r in beklenen) Map<String, Object?>.of(r)];
    return _sirali(() async {
      final db = await _db();
      await db.transaction((tx) async {
        await _kontrol(tx, b);
        final uygun = await _ogrenciler(tx, b);
        for (final e in degerler.entries) {
          if (e.value.trim().length > 50 ||
              mesajTelefonNormalize(e.value) == null) {
            throw const FormatException('Geçerli tek telefon numarası girin.');
          }
          if (!uygun.any((o) => o.id == e.key))
            throw StateError('Öğrenci ders kapsamınızda değil.');
          final onceki = eski.where((o) => o['id'] == e.key).toList();
          final o = (await tx.query(
            'Ogrenci',
            where: 'OgrenciId=?',
            whereArgs: [e.key],
          )).single;
          final tur = ogrenciTelefonu ? 'Ogrenci' : VeliIliskisi.tur(o);
          final alan = tur == 'Ogrenci'
              ? 'Telefon'
              : tur == 'Diger'
              ? 'VeliTelefonu'
              : '${tur}Telefon';
          if (onceki.length != 1 ||
              onceki.single['tur'] != tur ||
              onceki.single['telefon'] != (o[alan]?.toString() ?? '')) {
            throw StateError(
              'Telefon veya veli ilişkisi değişti. Ekranı yenileyip yeniden deneyin.',
            );
          }
          await tx.update(
            'Ogrenci',
            {
              alan: e.value.trim(),
              'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'OgrenciId=?',
            whereArgs: [e.key],
          );
        }
        await _kontrol(tx, b);
      });
    });
  }

  Future<void> _formPaylasimKapsami(
    DatabaseExecutor db,
    MesajBaglami b,
    String kaynak,
    String? kayit,
    Iterable<int> ids,
  ) async {
    if (kaynak != formPaylasimOgrenciModulu && kaynak != formPaylasimVeliModulu)
      return;
    final id = int.tryParse(kayit ?? '');
    final form = await db.query(
      'BilgiToplamaForm',
      where:
          "Id=? AND OkulId=? AND OgretmenProfilId=? AND EgitimOgretimYili=? AND Durum='Aktif' AND GoogleFormId IS NOT NULL",
      whereArgs: [id, b.okulId, b.ogretmenId, b.yil],
    );
    final hedef = await db.query(
      'BilgiToplamaHedef',
      where: 'FormId=?',
      whereArgs: [id],
    );
    final izinli = hedef.map((o) => o['OgrenciId']).toSet();
    if (form.length != 1 || ids.any((id) => !izinli.contains(id))) {
      throw StateError(
        'Form kapatılmış veya alıcılar formun hedef kapsamı dışında.',
      );
    }
  }

  Future<void> iletisimKaydet(
    MesajBaglami b,
    int ogrenciId,
    String veliAdi,
    String telefon, {
    String veliTuru = 'Diger',
    Map<String, Object?>? onceki,
  }) => _sirali(() async {
    if (veliTuru == 'Diger' &&
        (veliAdi.trim().length > 200 ||
            telefon.trim().length > 50 ||
            (telefon.trim().isNotEmpty &&
                mesajTelefonNormalize(telefon) == null))) {
      throw const FormatException(
        'Telefonu kontrol edin. Türkiye için 05xx…; diğer ülkeler için +ülke kodu kullanın.',
      );
    }
    final db = await _db();
    await db.transaction((tx) async {
      await _kontrol(tx, b);
      if (!(await _ogrenciler(tx, b)).any((o) => o.id == ogrenciId)) {
        throw StateError('Öğrenci ders verdiğiniz sınıflarda bulunmuyor.');
      }
      await VeliIliskisi.kaydet(
        tx,
        ogrenciId,
        veliTuru,
        ad: veliAdi,
        telefon: telefon,
        onceki: onceki,
      );
      await _kontrol(tx, b);
    });
  });

  /// Tek kişilik gönderim kuyruk oluşturmaz; öğrenci bağlantılı geçmişi ayrıca tutar.
  Future<void> tekliGonder(
    MesajBaglami b,
    String metin, {
    MesajOnIzleme? ogrenciler,
    MesajKisiOnIzleme? kisiler,
    required bool sms,
    required String kaynakModul,
    String? kaynakKayit,
    Map<int, String>? ogrenciMesajlari,
    Set<int>? izinliOgrenciIdleri,
  }) => _sirali(() async {
    final text = metin.trim();
    if ((ogrenciler == null) == (kisiler == null) ||
        text.isEmpty ||
        text.length > 4000 ||
        kaynakModul.trim().isEmpty ||
        kaynakModul.length > 100 ||
        (kaynakKayit?.length ?? 0) > 200) {
      throw StateError('Tek alıcı ve 1–4000 karakterlik mesaj gerekli.');
    }
    final db = await _db();
    late String telefon, mesaj;
    var baglar = <Map<String, Object?>>[];
    Future<void> dogrula() => db.transaction((tx) async {
      await _kontrol(tx, b);
      baglar = [];
      if (kisiler != null) {
        if (kisiler.kisiSayisi != 1 ||
            kisiler.telefonGruplari.length != 1 ||
            kisiler.gecersizler.isNotEmpty) {
          throw StateError(
            'Tek kişilik gönderim için bir geçerli alıcı seçin.',
          );
        }
        final adaylar = await _kisiler(tx, b);
        for (final k in kisiler.secilenler) {
          if (izinliOgrenciIdleri != null &&
              (k.tur == MesajKisiTuru.ogretmen ||
                  !izinliOgrenciIdleri.contains(int.tryParse(k.kisiId)))) {
            throw StateError('Alıcı kaynak işlemin kapsamı dışında.');
          }
          if (!adaylar.any(
            (a) =>
                a.bagAnahtari == k.bagAnahtari &&
                jsonEncode(a.anlikGoruntu) == jsonEncode(k.anlikGoruntu),
          )) {
            throw StateError('Alıcı bilgileri değişti. Ön izlemeyi yenileyin.');
          }
        }
        await _kaynakKisiKontrol(
          tx,
          b,
          kaynakModul,
          kaynakKayit,
          kisiler.secilenler,
        );
        for (final k in kisiler.secilenler) {
          final oid = k.tur == MesajKisiTuru.ogretmen
              ? null
              : int.parse(k.kisiId);
          final ogrenci = oid == null
              ? null
              : (await tx.query(
                  'Ogrenci',
                  where: 'OgrenciId=?',
                  whereArgs: [oid],
                )).single;
          baglar.add({
            'OgrenciId': oid,
            'OgrenciKimligi': ogrenci?['OlusturmaTarihi'],
            'Tur': k.tur.kod,
            'KisiId': k.kisiId,
            'AliciAdi': k.ad,
            'Aciklama': k.aciklama,
          });
        }
        telefon = kisiler.telefonGruplari.keys.single;
        mesaj = text;
      } else {
        final p = ogrenciler!;
        if (p.secilenler.length != 1 ||
            p.alicilar.length != 1 ||
            p.gecersizler.isNotEmpty) {
          throw StateError(
            'Tek kişilik gönderim için bir geçerli alıcı seçin.',
          );
        }
        final o = p.secilenler.single;
        if (izinliOgrenciIdleri != null &&
            !izinliOgrenciIdleri.contains(o.id)) {
          throw StateError('Alıcı kaynak işlemin kapsamı dışında.');
        }
        final adaylar = await _ogrenciler(tx, b);
        if (!adaylar.any(
          (a) =>
              a.id == o.id &&
              a.sinifId == o.sinifId &&
              a.okulNo == o.okulNo &&
              a.ad == o.ad &&
              a.veliAdi == o.veliAdi &&
              a.veliTuru == o.veliTuru &&
              a.telefonAciklamasi == o.telefonAciklamasi &&
              a.telefon == o.telefon,
        )) {
          throw StateError('Alıcı bilgileri değişti. Ön izlemeyi yenileyin.');
        }
        await _formPaylasimKapsami(tx, b, kaynakModul, kaynakKayit, [o.id]);
        final ogrenci = (await tx.query(
          'Ogrenci',
          where: 'OgrenciId=?',
          whereArgs: [o.id],
        )).single;
        baglar.add({
          'OgrenciId': o.id,
          'OgrenciKimligi': ogrenci['OlusturmaTarihi'],
          'Tur': ogrenciTelefonu ? 'Ogrenci' : 'Veli',
          'KisiId': '${o.id}',
          'AliciAdi': o.veliAdi,
          'Aciklama': o.aciklama,
        });
        telefon = p.alicilar.single.telefon;
        mesaj = ogrenciMesajlari == null
            ? text
            : (ogrenciMesajlari[o.id] ?? '').trim();
      }
      if (mesaj.isEmpty || mesaj.length > 4000) {
        throw StateError('Alıcıya özel mesaj 1–4000 karakter olmalıdır.');
      }
      await _kontrol(tx, b);
    });
    await dogrula();
    if (sms) {
      if (!await _smsIzin()) throw StateError('SMS gönderme izni verilmedi.');
      await dogrula();
    }
    final islem = MesajFormIslemleri._id();
    await db.transaction((tx) async {
      await _kontrol(tx, b);
      for (final bag in baglar) {
        await tx.insert('MesajTekliGecmis', {
          'KayitId': MesajFormIslemleri._id(),
          'IslemId': islem,
          'OkulId': b.okulId,
          'OgretmenProfilId': b.ogretmenId,
          'OgretmenAdi': b.ogretmenAdi,
          'EgitimOgretimYili': b.yil,
          'KaynakModul': kaynakModul,
          'KaynakKayit': kaynakKayit,
          ...bag,
          'Telefon': telefon,
          'Metin': mesaj,
          'Kanal': sms ? 'SMS' : 'WhatsApp',
          'Durum': 'Belirsiz',
          'Tarih': DateTime.now().toIso8601String(),
        });
      }
    });
    try {
      // Geçmiş yazılırken değişen telefon/kapsam da dış çağrıdan önce yakalanır.
      await dogrula();
      if (sms) {
        await _sms(telefon, mesaj);
      } else {
        await _whatsapp(telefon, mesaj);
      }
      await db.update(
        'MesajTekliGecmis',
        {'Durum': sms ? 'Istendi' : 'Acildi'},
        where: 'IslemId=?',
        whereArgs: [islem],
      );
    } catch (e) {
      await db.update(
        'MesajTekliGecmis',
        {'Durum': sms ? 'Belirsiz' : 'Acilamadi', 'Hata': '$e'},
        where: 'IslemId=?',
        whereArgs: [islem],
      );
      if (sms) {
        throw StateError(
          'SMS sonucu belirsiz. Yeniden göndermeden önce telefonunuzdan kontrol edin. Orijinal hata: $e',
        );
      }
      rethrow;
    }
  });

  Future<List<Map<String, Object?>>> tekliGecmis(MesajBaglami b) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _kontrol(tx, b);
      return tx.query(
        'MesajTekliGecmis',
        where:
            'OkulId=? AND OgretmenProfilId=? AND OgretmenAdi=? AND EgitimOgretimYili=?',
        whereArgs: [b.okulId, b.ogretmenId, b.ogretmenAdi, b.yil],
        orderBy: 'Tarih DESC, KayitId DESC',
      );
    });
  }

  /// Kullanıcının açık gönderim beyanı; yeni SMS/WhatsApp çağrısı yapmaz.
  Future<void> gecmisiOnayla(
    MesajBaglami b, {
    required Map<String, Set<int>> kuyrukAlicilari,
    required Set<String> tekliKayitlar,
  }) {
    final kuyruklar = {
      for (final e in kuyrukAlicilari.entries) e.key: Set<int>.of(e.value),
    };
    final tekliler = Set<String>.of(tekliKayitlar);
    return _sirali(() async {
      if (kuyruklar.values.every((s) => s.isEmpty) && tekliler.isEmpty) {
        throw StateError('Onaylanacak mesaj seçin.');
      }
      final db = await _db();
      await db.transaction((tx) async {
        await _kontrol(tx, b);
        final alicilar = <int>[];
        for (final e in kuyruklar.entries) {
          final q = await _kuyruk(tx, b, e.key);
          for (final id in e.value) {
            final uygun = q.alicilar.where((a) => a.id == id).toList();
            if (uygun.length != 1 ||
                uygun.single.smsDurumu != null ||
                !{'Acildi', 'Onaylandi'}.contains(uygun.single.durum)) {
              throw StateError(
                'Seçili mesajın durumu değişti. Geçmişi yenileyin.',
              );
            }
            if (uygun.single.durum == 'Acildi') alicilar.add(id);
          }
        }
        for (final id in tekliler) {
          final rows = await tx.query(
            'MesajTekliGecmis',
            where:
                'KayitId=? AND OkulId=? AND OgretmenProfilId=? AND OgretmenAdi=? AND EgitimOgretimYili=?',
            whereArgs: [id, b.okulId, b.ogretmenId, b.ogretmenAdi, b.yil],
          );
          if (rows.length != 1 ||
              rows.single['Kanal'] != 'WhatsApp' ||
              !{'Acildi', 'Istendi'}.contains(rows.single['Durum'])) {
            throw StateError('Seçili mesaj onaylanamaz. Geçmişi yenileyin.');
          }
        }
        final tarih = DateTime.now().toIso8601String();
        for (final id in alicilar) {
          await tx.update(
            'MesajAlici',
            {'Durum': 'Onaylandi', 'OnayTarihi': tarih},
            where: 'AliciId=?',
            whereArgs: [id],
          );
        }
        for (final id in tekliler) {
          // Istendi: SMS'te native istek, WhatsApp'ta kullanıcının gönderim beyanı.
          // Her iki kanalda da teslim/okundu bilgisi değildir.
          await tx.update(
            'MesajTekliGecmis',
            {'Durum': 'Istendi'},
            where: "KayitId=? AND Durum='Acildi'",
            whereArgs: [id],
          );
        }
        await _kontrol(tx, b);
      });
    });
  }

  /// Ödev silme işlemiyle aynı transaction içinde yalnız ilgili kaynak
  /// kayıtlarını işler. Arşiv, ayrı kaynak sınıfında tutulur; gerçek gönderim
  /// durumları ve tarihleri değiştirilmez, şema/yedek biçimi korunur.
  Future<void> odevBildirimleriniKaldir(
    DatabaseExecutor tx,
    Set<int> idler, {
    required bool sil,
  }) async {
    final b = await _baglam(tx);
    await _kontrol(tx, b);
    for (final id in idler) {
      const kosul =
          "KaynakModul IN ('OdevBildirim','OdevBildirimArsiv') AND KaynakKayit=? AND OkulId=? AND OgretmenProfilId=? AND OgretmenAdi=? AND EgitimOgretimYili=?";
      final args = ['$id', b.okulId, b.ogretmenId, b.ogretmenAdi, b.yil];
      if (!sil) {
        for (final tablo in ['MesajKuyrugu', 'MesajTekliGecmis']) {
          await tx.update(
            tablo,
            {'KaynakModul': odevBildirimArsivModulu},
            where: kosul,
            whereArgs: args,
          );
        }
        continue;
      }
      final queues = await tx.query(
        'MesajKuyrugu',
        columns: ['KuyrukId'],
        where: kosul,
        whereArgs: args,
      );
      for (final q in queues) {
        final alicilar = await tx.query(
          'MesajAlici',
          columns: ['AliciId'],
          where: 'KuyrukId=?',
          whereArgs: [q['KuyrukId']],
        );
        for (final a in alicilar) {
          for (final tablo in ['MesajSms', 'MesajAliciBag', 'MesajAlici']) {
            await tx.delete(
              tablo,
              where: 'AliciId=?',
              whereArgs: [a['AliciId']],
            );
          }
        }
        await tx.delete(
          'MesajKuyrugu',
          where: 'KuyrukId=?',
          whereArgs: [q['KuyrukId']],
        );
      }
      await tx.delete('MesajTekliGecmis', where: kosul, whereArgs: args);
    }
    await _kontrol(tx, b);
  }

  Future<void> gecmisiSil(
    MesajBaglami b, {
    required Map<String, Set<int>> kuyrukAlicilari,
    required Set<String> tekliKayitlar,
    required String onayMetni,
  }) {
    final kuyruklar = {
      for (final e in kuyrukAlicilari.entries) e.key: Set<int>.of(e.value),
    };
    final tekliler = Set<String>.of(tekliKayitlar);
    return _sirali(() async {
      if (onayMetni != 'SİL' ||
          (tekliler.isEmpty && kuyruklar.values.every((s) => s.isEmpty))) {
        throw StateError('Geçmiş kaydı seçimi ve silme onayı gerekli.');
      }
      final db = await _db();
      await db.transaction((tx) async {
        await _kontrol(tx, b);
        // Bütün sahiplikler silmeden önce doğrulanır; işlem bütünüyle uygulanır.
        for (final e in kuyruklar.entries) {
          final q = await _kuyruk(tx, b, e.key);
          if (!q.alicilar.map((a) => a.id).toSet().containsAll(e.value)) {
            throw StateError('Geçmiş kaydı değişti. Listeyi yenileyin.');
          }
        }
        for (final id in tekliler) {
          final rows = await tx.query(
            'MesajTekliGecmis',
            where:
                'KayitId=? AND OkulId=? AND OgretmenProfilId=? AND OgretmenAdi=? AND EgitimOgretimYili=?',
            whereArgs: [id, b.okulId, b.ogretmenId, b.ogretmenAdi, b.yil],
          );
          if (rows.length != 1) {
            throw StateError('Geçmiş kaydı değişti veya kapsamınızda değil.');
          }
        }
        for (final e in kuyruklar.entries) {
          for (final id in e.value) {
            await tx.delete('MesajSms', where: 'AliciId=?', whereArgs: [id]);
            await tx.delete(
              'MesajAliciBag',
              where: 'AliciId=?',
              whereArgs: [id],
            );
            await tx.delete('MesajAlici', where: 'AliciId=?', whereArgs: [id]);
          }
          final kalan = await tx.query(
            'MesajAlici',
            where: 'KuyrukId=?',
            whereArgs: [e.key],
            orderBy: 'Sira',
          );
          if (kalan.isEmpty) {
            await tx.delete(
              'MesajKuyrugu',
              where: 'KuyrukId=?',
              whereArgs: [e.key],
            );
          } else {
            for (var i = 0; i < kalan.length; i++) {
              await tx.update(
                'MesajAlici',
                {'Sira': i + 1},
                where: 'AliciId=?',
                whereArgs: [kalan[i]['AliciId']],
              );
            }
          }
        }
        for (final id in tekliler) {
          await tx.delete(
            'MesajTekliGecmis',
            where: 'KayitId=?',
            whereArgs: [id],
          );
        }
        await _kontrol(tx, b);
      });
    });
  }

  Future<MesajKuyrugu> kuyrukOlustur(
    MesajBaglami b,
    MesajOnIzleme preview,
    String metin, {
    required String kaynakModul,
    String? kaynakKayit,
    Map<int, String>? ogrenciMesajlari,
  }) => _sirali(() async {
    final text = metin.trim();
    if (text.isEmpty ||
        text.length > 4000 ||
        kaynakModul.trim().isEmpty ||
        kaynakModul.length > 100 ||
        (kaynakKayit?.length ?? 0) > 200 ||
        preview.alicilar.isEmpty) {
      throw StateError('Geçerli alıcı seçin; mesaj 1–4000 karakter olmalıdır.');
    }
    final db = await _db();
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await db.transaction((tx) async {
      await _kontrol(tx, b);
      final current = await _ogrenciler(tx, b);
      await _formPaylasimKapsami(
        tx,
        b,
        kaynakModul,
        kaynakKayit,
        preview.secilenler.map((o) => o.id),
      );
      if (ogrenciMesajlari != null) {
        final eskiler = await tx.rawQuery(
          '''SELECT a.Ogrenciler
          FROM MesajAlici a JOIN MesajKuyrugu q ON q.KuyrukId=a.KuyrukId
          WHERE q.OkulId=? AND q.OgretmenProfilId=? AND q.EgitimOgretimYili=?
          AND q.KaynakModul=? AND q.KaynakKayit=?''',
          [b.okulId, b.ogretmenId, b.yil, kaynakModul, kaynakKayit],
        );
        final ids = preview.secilenler.map((o) => o.id).toSet();
        if (eskiler.any(
          (r) => (jsonDecode(r['Ogrenciler'] as String) as List).any(
            (o) => ids.contains(o['id']),
          ),
        )) {
          throw StateError(
            'Bu öğrencilerin daveti kuyrukta bulunuyor. Mevcut kuyruktan devam edin.',
          );
        }
        for (final a in preview.alicilar) {
          if (a.ogrenciler
                  .map((o) => ogrenciMesajlari[o.id] ?? '')
                  .join('\n\n')
                  .length >
              4000) {
            throw StateError(
              'Aynı veliye ait birleşik mesaj çok uzun. Öğrencileri ayrı seçin.',
            );
          }
        }
      }
      if (ogrenciMesajlari != null &&
          preview.secilenler.any(
            (o) =>
                (ogrenciMesajlari[o.id] ?? '').trim().isEmpty ||
                ogrenciMesajlari[o.id]!.length > 4000,
          )) {
        throw StateError('Öğrenciye özel mesaj eksik veya fazla uzun.');
      }
      // Ön izleme ile kayıt arasında iletişim veya sınıf değiştiyse onayı yenile.
      for (final o in preview.secilenler) {
        if (!current.any(
          (c) =>
              c.id == o.id &&
              c.sinifId == o.sinifId &&
              c.okulNo == o.okulNo &&
              c.ad == o.ad &&
              c.veliAdi == o.veliAdi &&
              c.veliTuru == o.veliTuru &&
              c.telefonAciklamasi == o.telefonAciklamasi &&
              c.telefon == o.telefon,
        )) {
          throw StateError(
            'Alıcı bilgileri değişti. Ön izlemeyi yeniden hazırlayın.',
          );
        }
      }
      await tx.insert('MesajKuyrugu', {
        'KuyrukId': id,
        'OkulId': b.okulId,
        'OgretmenProfilId': b.ogretmenId,
        'OgretmenAdi': b.ogretmenAdi,
        'OkulAdi': b.okulAdi,
        'EgitimOgretimYili': b.yil,
        'KaynakModul': kaynakModul.trim(),
        'KaynakKayit': kaynakKayit,
        'Metin': text,
        'OlusturmaTarihi': DateTime.now().toIso8601String(),
      });
      var order = 0;
      for (final a in preview.alicilar) {
        final aliciId = await tx.insert('MesajAlici', {
          'KuyrukId': id,
          'Sira': ++order,
          'Telefon': a.telefon,
          'AliciAdi': a.ad,
          'Ogrenciler': jsonEncode(
            a.ogrenciler
                .map(
                  (o) => {
                    'id': o.id,
                    'sinifId': o.sinifId,
                    'aciklama': o.aciklama,
                    if (ogrenciMesajlari != null)
                      'mesaj': ogrenciMesajlari[o.id],
                  },
                )
                .toList(),
          ),
        });
        for (final o in a.ogrenciler) {
          final kisi = MesajKisi(
            tur: ogrenciTelefonu ? MesajKisiTuru.ogrenci : MesajKisiTuru.veli,
            kisiId: '${o.id}',
            sinifId: o.sinifId,
            ad: o.veliAdi,
            telefon: o.telefon,
            aciklama: o.aciklama,
            veliTuru: ogrenciTelefonu ? null : o.veliTuru,
            telefonAciklamasi: o.telefonAciklamasi,
          );
          await _aliciBaginiYaz(
            tx,
            aliciId,
            kisi,
            eskiKayit: !ogrenciTelefonu && !o.veliIliskisiTanimli,
          );
        }
      }
      await _kontrol(tx, b);
    });
    return kuyrukGetir(b, id);
  });

  Future<MesajKuyrugu> _kuyruk(
    DatabaseExecutor db,
    MesajBaglami b,
    String id,
  ) async {
    await _kontrol(db, b);
    // Okul adı tarihsel görüntüdür; sahiplik kalıcı okul kimliğiyle doğrulanır.
    final rows = await db.query(
      'MesajKuyrugu',
      where: '''KuyrukId = ? AND OkulId = ?
      AND OgretmenProfilId = ? AND EgitimOgretimYili = ? AND OgretmenAdi = ?''',
      whereArgs: [id, b.okulId, b.ogretmenId, b.yil, b.ogretmenAdi],
    );
    if (rows.length != 1) {
      throw StateError(
        'Bu kuyruk aktif öğretmen, okul ve eğitim yılına ait değil.',
      );
    }
    final recipients = await db.rawQuery(
      '''SELECT a.*, s.Durum AS SmsDurumu FROM MesajAlici a
      LEFT JOIN MesajSms s ON s.AliciId=a.AliciId
      WHERE a.KuyrukId=? ORDER BY a.Sira''',
      [id],
    );
    final baglar = await db.rawQuery(
      '''SELECT b.* FROM MesajAliciBag b
      JOIN MesajAlici a ON a.AliciId=b.AliciId WHERE a.KuyrukId=?''',
      [id],
    );
    return MesajKuyrugu(
      rows.single,
      recipients
          .map(
            (r) => MesajAlicisi(
              r,
              baglar: baglar
                  .where((b) => b['AliciId'] == r['AliciId'])
                  .toList(),
            ),
          )
          .toList(),
    );
  }

  Future<MesajKuyrugu> kuyrukGetir(MesajBaglami b, String id) async {
    final db = await _db();
    return db.transaction((tx) => _kuyruk(tx, b, id));
  }

  Future<List<MesajKuyrugu>> kuyruklar(MesajBaglami b) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _kontrol(tx, b);
      final rows = await tx.query(
        'MesajKuyrugu',
        where: '''OkulId = ? AND
        OgretmenProfilId = ? AND EgitimOgretimYili = ? AND OgretmenAdi = ?''',
        whereArgs: [b.okulId, b.ogretmenId, b.yil, b.ogretmenAdi],
        orderBy: 'OlusturmaTarihi DESC, KuyrukId DESC',
      );
      final result = <MesajKuyrugu>[];
      for (final r in rows) {
        result.add(await _kuyruk(tx, b, r['KuyrukId'] as String));
      }
      return result;
    });
  }

  /// Android SMS uygulamasını açmadan, tekil numaralara gönderim isteği verir.
  /// Belirsiz/başlatılmış kayıtlar otomatik yeniden gönderilmez.
  Future<Map<String, int>> smsTopluGonder(
    MesajBaglami b,
    String kuyrukId,
  ) => _sirali(() async {
    await _modKontrol();
    final db = await _db();
    final q = await _kuyruk(db, b, kuyrukId);
    // İzin istemeden önce bütün henüz işlenmemiş alıcılar doğrulanır.
    var bekleyen = 0;
    for (final a in q.alicilar) {
      if ((await db.query(
        'MesajSms',
        where: 'AliciId=?',
        whereArgs: [a.id],
      )).isEmpty) {
        await _aliciKontrol(db, b, q, a);
        bekleyen++;
      }
    }
    if (bekleyen == 0)
      return {'istenen': 0, 'belirsiz': 0, 'atlanan': q.alicilar.length};
    if (!await _smsIzin()) throw StateError('SMS gönderme izni verilmedi.');
    var istenen = 0, basarisiz = 0, atlanan = 0;
    for (final a in q.alicilar) {
      final kayit = await db.query(
        'MesajSms',
        where: 'AliciId = ?',
        whereArgs: [a.id],
        limit: 1,
      );
      if (kayit.isNotEmpty) {
        atlanan++;
        continue;
      }
      // Uzun toplu gönderimde değişen profil/yıl/telefon sonraki kişiye gitmez.
      await _aliciKontrol(db, b, q, a);
      // Dış yan etkiden önce kayıt: süreç kesilirse otomatik tekrar yok.
      final eklendi = await db.insert('MesajSms', {
        'AliciId': a.id,
        'Durum': 'Belirsiz',
        'IstekTarihi': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (eklendi == 0) {
        atlanan++;
        continue;
      }
      try {
        await _kontrol(db, b);
        final parca = await _sms(a.telefon, aliciMetni(q, a));
        await db.update(
          'MesajSms',
          {
            'Durum': 'Istendi',
            'ParcaSayisi': parca,
            'SonucTarihi': DateTime.now().toIso8601String(),
          },
          where: "AliciId = ? AND Durum = 'Belirsiz'",
          whereArgs: [a.id],
        );
        istenen++;
      } catch (e) {
        // Native çağrı başarısız olabilir; gönderim kesinlikle gerçekleşmedi
        // denemediğinden belirsiz durum korunur.
        await db.update(
          'MesajSms',
          {'Hata': '$e'},
          where: "AliciId = ? AND Durum = 'Belirsiz'",
          whereArgs: [a.id],
        );
        basarisiz++;
      }
    }
    return {'istenen': istenen, 'belirsiz': basarisiz, 'atlanan': atlanan};
  });

  Future<void> aliciyiAc(
    MesajBaglami b,
    String kuyrukId,
    int aliciId, {
    bool tekrar = false,
  }) => _sirali(() async {
    final db = await _db();
    late MesajKuyrugu queue;
    late MesajAlicisi recipient;
    await db.transaction((tx) async {
      queue = await _kuyruk(tx, b, kuyrukId);
      final next = queue.siradaki;
      if (next == null ||
          next.id != aliciId ||
          (next.durum == 'Acildi' && !tekrar)) {
        throw StateError(
          'Sıra değişti veya alıcı zaten açıldı. Kuyruğu yenileyin.',
        );
      }
      recipient = next;
      await _aliciKontrol(tx, b, queue, next);
      // Dış uygulamadan önce kalıcı kayıt: kapanma halinde onaysız alıcı korunur.
      await tx.update(
        'MesajAlici',
        {
          'Durum': 'Acildi',
          'Hata': null,
          'AcilmaTarihi': DateTime.now().toIso8601String(),
        },
        where: 'AliciId = ?',
        whereArgs: [aliciId],
      );
    });
    try {
      await _kontrol(db, b);
      await _whatsapp(recipient.telefon, aliciMetni(queue, recipient));
    } catch (e) {
      await db.update(
        'MesajAlici',
        {'Durum': 'Acilamadi', 'Hata': '$e'},
        where: "AliciId = ? AND Durum = 'Acildi'",
        whereArgs: [aliciId],
      );
      throw StateError(
        'WhatsApp açılamadı; alıcı kuyrukta korunuyor. Orijinal hata: $e',
      );
    }
  });
  Future<void> aliciyiSonuclandir(
    MesajBaglami b,
    String kuyrukId,
    int aliciId, {
    required bool gonderdim,
  }) => _sirali(() async {
    final db = await _db();
    await db.transaction((tx) async {
      final q = await _kuyruk(tx, b, kuyrukId), next = q.siradaki;
      if (next == null ||
          next.id != aliciId ||
          (gonderdim && next.durum != 'Acildi')) {
        throw StateError(
          'Yalnız açılan sıradaki alıcının gönderimi onaylanabilir.',
        );
      }
      await tx.update(
        'MesajAlici',
        {
          'Durum': gonderdim ? 'Onaylandi' : 'Atlandi',
          'OnayTarihi': gonderdim ? DateTime.now().toIso8601String() : null,
        },
        where: 'AliciId = ?',
        whereArgs: [aliciId],
      );
      await _kontrol(tx, b);
    });
  });

  /// Aynı telefondaki kardeşlerin bağlantıları tek mesajda birlikte korunur.
  static String aliciMetni(MesajKuyrugu q, MesajAlicisi a) {
    final rows = jsonDecode(a.ogrenciler) as List;
    final metinler = rows
        .whereType<Map>()
        .map((r) => r['mesaj'])
        .whereType<String>()
        .toSet()
        .toList();
    return metinler.isEmpty ? q.metin : metinler.join('\n\n');
  }
}
