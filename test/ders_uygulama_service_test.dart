import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/ders_uygulama_semasi.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/models/odev_kontrol.dart';
import 'package:elpi_okul_yonetim/models/ders_uygulama.dart';
import 'package:elpi_okul_yonetim/services/bireysel_odev_kontrol_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselListeOturumu o;
  late int gid, k1, u1, u2;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    await BireyselProfilService.kaydet(
      adSoyad: 'Öğretmen',
      brans: 'Ders',
      okulAdi: 'Okul',
      okulKisaAdi: 'O',
      egitimOgretimYili: '2026-2027',
      donem: 1,
      meslekPaketiAktif: false,
    );
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Ders',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '10-D',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    for (final id in [1, 2]) {
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '$id',
        'Ad': 'Öğrenci',
        'Soyad': '$id',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    o = await BireyselOdevKontrolService.hazirla();
    gid = await BireyselOdevKontrolService.gorevOlustur(
      o,
      sinifSubeId: 1,
      dersId: 1,
      gorevTuru: OdevGorevTuru.rutinKontrol,
      dersUygulamalari: true,
      baslik: 'Ders Uygulamaları',
      baslangicTarihi: DateTime(2026, 9, 1),
      ogrenciIdleri: [1, 2],
      kontrolBaslat: true,
    );
    k1 = (await BireyselOdevKontrolService.kontroller(
      o,
      gid,
    )).single.odevKontrolId;
    u1 = await DersUygulamaIslemleri.uygulamaKaydet(o, gid, 'Değişkenler');
    u2 = await DersUygulamaIslemleri.uygulamaKaydet(o, gid, 'Veri Girişi');
  });
  tearDown(LocalDatabase.instance.close);
  test(
    'adet ve yapılan kalıcıdır, kesirli puan ve eski payda korunur',
    () async {
      await DersUygulamaIslemleri.adetKaydet(o, gid, u1, 7);
      expect((await DersUygulamaIslemleri.uygulamalar(o, gid)).first.adet, 7);
      await DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
        UygulamaSonucGirdisi(
          1,
          u1,
          OdevKontrolDurumu.manuel,
          notDegeri: 9,
          yapilan: 6,
          adet: 7,
        ),
      ]);
      final sonuc = (await DersUygulamaIslemleri.gecmis(o, gid)).single;
      expect(sonuc.yapilan, 6);
      expect(sonuc.puan! * 10, closeTo(85.7142857, .00001));
      await DersUygulamaIslemleri.adetKaydet(o, gid, u1, 3);
      expect((await DersUygulamaIslemleri.gecmis(o, gid)).single.adet, 7);
      await expectLater(
        DersUygulamaIslemleri.adetKaydet(o, gid, u1, 0),
        throwsException,
      );
      await expectLater(
        DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
          UygulamaSonucGirdisi(
            1,
            u1,
            OdevKontrolDurumu.manuel,
            notDegeri: 9,
            yapilan: 8,
            adet: 7,
          ),
        ]),
        throwsException,
      );
      expect((await DersUygulamaIslemleri.gecmis(o, gid)).single.yapilan, 6);
    },
  );
  Future<List<UygulamaSonucu>> son({int? kontrol}) =>
      DersUygulamaIslemleri.gecmis(o, gid, guncel: true, kontrolId: kontrol);
  Future<UygulamaIlerleme> ilerleme(int oid) async => UygulamaIlerleme(
    await DersUygulamaIslemleri.uygulamalar(o, gid),
    (await son()).where((s) => s.ogrenciId == oid),
  );
  test(
    'ortak liste, boş sonuç, farklı ilerleme ve eşit ağırlıklı ortalama',
    () async {
      expect(
        (await BireyselOdevKontrolService.gorevGetir(o, gid)).dersUygulamalari,
        isTrue,
      );
      expect((await ilerleme(1)).toplam, 2);
      expect((await ilerleme(2)).ortalama, isNull);
      await DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
        UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.yapti),
        UygulamaSonucGirdisi(1, u2, OdevKontrolDurumu.kismen),
        UygulamaSonucGirdisi(2, u1, OdevKontrolDurumu.yapmadi),
      ]);
      expect((await ilerleme(1)).ortalama, 7.5);
      expect((await ilerleme(1)).degerlendirilen, 2);
      expect((await ilerleme(2)).bekleyen, 1);
      expect((await ilerleme(2)).ortalama, 0);
      await DersUygulamaIslemleri.uygulamaKaydet(o, gid, 'If-Else');
      expect((await ilerleme(1)).bekleyen, 1);
      expect((await ilerleme(1)).ortalama, 7.5);
      expect((await ilerleme(2)).toplam, 3);
    },
  );
  test('G/M hesap dışı, manuel puan ve boş değerlendirme', () async {
    await DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
      UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.gelmedi),
      UygulamaSonucGirdisi(1, u2, OdevKontrolDurumu.mazeretli),
    ]);
    expect((await ilerleme(1)).ortalama, isNull);
    expect((await ilerleme(1)).hesapDisi, 2);
    await DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
      UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.manuel, notDegeri: 8),
      UygulamaSonucGirdisi(1, u2, OdevKontrolDurumu.kontrolEdilmedi),
    ]);
    expect((await ilerleme(1)).ortalama, 8);
    expect((await ilerleme(1)).bekleyen, 1);
  });
  test(
    'tarihli sonuç, aynı gün çoklu uygulama, güncelleme ve kontrol silme',
    () async {
      await DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
        UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.kismen),
      ]);
      final k2 = await BireyselOdevKontrolService.kontrolOlustur(
        o,
        gid,
        kontrolTarihi: DateTime(2026, 11, 5),
      );
      await DersUygulamaIslemleri.sonuclariKaydet(o, k2, [
        UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.yapti),
        UygulamaSonucGirdisi(1, u2, OdevKontrolDurumu.yapti),
      ]);
      await DersUygulamaIslemleri.sonuclariKaydet(o, k2, [
        UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.manuel, notDegeri: 9),
      ]);
      expect((await son(kontrol: k1)).single.puan, 5);
      expect((await ilerleme(1)).ortalama, 9.5);
      expect(await DersUygulamaIslemleri.gecmis(o, gid), hasLength(3));
      await BireyselOdevKontrolService.kontrolSil(o, k2);
      expect((await son()).single.puan, 5);
      expect(await DersUygulamaIslemleri.uygulamalar(o, gid), hasLength(2));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'mükerrer sonuç reddi atomiktir, yanlış uygulama/öğrenci engellenir',
    () async {
      final s = UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.yapti);
      await expectLater(
        DersUygulamaIslemleri.sonuclariKaydet(o, k1, [s, s]),
        throwsException,
      );
      expect(await son(), isEmpty);
      await expectLater(
        DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
          s,
          UygulamaSonucGirdisi(999, u2, OdevKontrolDurumu.yapti),
        ]),
        throwsException,
      );
      expect(await son(), isEmpty);
      await expectLater(
        DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
          UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.yapti, notDegeri: 11),
        ]),
        throwsException,
      );
    },
  );
  test(
    'ad değişimi ortaktır, boş/tekrar ad reddedilir, pasif geçmiş korunur',
    () async {
      await expectLater(
        DersUygulamaIslemleri.uygulamaKaydet(o, gid, '  '),
        throwsException,
      );
      await expectLater(
        DersUygulamaIslemleri.uygulamaKaydet(o, gid, ' VERİ   GİRİŞİ '),
        throwsException,
      );
      await DersUygulamaIslemleri.uygulamaKaydet(
        o,
        gid,
        'Yeni ad',
        uygulamaId: u1,
      );
      expect(
        (await DersUygulamaIslemleri.uygulamalar(o, gid)).first.ad,
        'Yeni ad',
      );
      await DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
        UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.yapti),
      ]);
      await DersUygulamaIslemleri.uygulamaAktifligi(o, gid, u1, false);
      expect((await ilerleme(1)).toplam, 1);
      expect(await DersUygulamaIslemleri.gecmis(o, gid), hasLength(1));
      await expectLater(
        DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
          UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.yapmadi),
        ]),
        throwsException,
      );
      await DersUygulamaIslemleri.uygulamaAktifligi(o, gid, u1, true);
      expect((await ilerleme(1)).ortalama, 10);
    },
  );
  test('normal ödev ve yetki kapsamı korunur', () async {
    final normal = await BireyselOdevKontrolService.gorevOlustur(
      o,
      sinifSubeId: 1,
      dersId: 1,
      gorevTuru: OdevGorevTuru.normalOdev,
      baslik: 'Normal',
      baslangicTarihi: DateTime(2026, 9, 1),
      ogrenciIdleri: [1],
      kontrolBaslat: true,
    );
    await expectLater(
      DersUygulamaIslemleri.uygulamaKaydet(o, normal, 'X'),
      throwsException,
    );
    final k = (await BireyselOdevKontrolService.kontroller(o, normal)).single;
    await BireyselOdevKontrolService.sonuclariKaydet(o, k.odevKontrolId, [
      const OdevSonucGirdisi(ogrenciId: 1, durum: OdevKontrolDurumu.yapti),
    ]);
    expect(
      (await BireyselOdevKontrolService.sonuclar(
        o,
        k.odevKontrolId,
      )).single.puan,
      10,
    );
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
    await expectLater(
      DersUygulamaIslemleri.uygulamalar(o, gid),
      throwsException,
    );
  });
  test(
    'migration tekrar çalışır, eski kayıtlar ve ilişkiler korunur',
    () async {
      final once = await db.query('OdevTanim');
      await db.transaction(DersUygulamaSemasi.hazirla);
      await db.transaction(DersUygulamaSemasi.hazirla);
      expect(await db.query('OdevTanim'), once);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test('v29 şemasına alan ekleme mevcut ödevi ve alt kayıtları korur', () async {
    final eski = WindowsMemoryDatabase();
    addTearDown(eski.close);
    await eski.execute('PRAGMA foreign_keys=ON');
    await eski.execute(
      "CREATE TABLE OdevTanim(OdevId INTEGER PRIMARY KEY, GorevTuru TEXT NOT NULL CHECK(GorevTuru IN ('NormalOdev','RutinKontrol','Proje','Performans')))",
    );
    await eski.execute(
      'CREATE TABLE OdevOgrenci(OdevId INTEGER,OgrenciId INTEGER,UNIQUE(OdevId,OgrenciId),FOREIGN KEY(OdevId) REFERENCES OdevTanim(OdevId))',
    );
    await eski.execute(
      'CREATE TABLE OdevKontrol(OdevKontrolId INTEGER PRIMARY KEY,OdevId INTEGER,UNIQUE(OdevKontrolId,OdevId),FOREIGN KEY(OdevId) REFERENCES OdevTanim(OdevId))',
    );
    await eski.execute("INSERT INTO OdevTanim VALUES(42,'NormalOdev')");
    await eski.execute('INSERT INTO OdevOgrenci VALUES(42,7)');
    await eski.execute('INSERT INTO OdevKontrol VALUES(99,42)');
    await eski.transaction(DersUygulamaSemasi.hazirla);
    expect((await eski.query('OdevTanim')).single, {
      'OdevId': 42,
      'GorevTuru': 'NormalOdev',
      'DersUygulamalari': 0,
    });
    expect((await eski.query('OdevKontrol')).single['OdevKontrolId'], 99);
    expect(await eski.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test('aynı gün sıra, geriye tarihli kontrol ve bekleyene çevirme', () async {
    final k2 = await BireyselOdevKontrolService.kontrolOlustur(
      o,
      gid,
      kontrolTarihi: DateTime(2026, 11, 5),
    );
    final k3 = await BireyselOdevKontrolService.kontrolOlustur(
      o,
      gid,
      kontrolTarihi: DateTime(2026, 11, 5),
    );
    final eski = await BireyselOdevKontrolService.kontrolOlustur(
      o,
      gid,
      kontrolTarihi: DateTime(2026, 10, 1),
    );
    for (final (k, d) in [
      (k2, OdevKontrolDurumu.yapti),
      (k3, OdevKontrolDurumu.kismen),
      (eski, OdevKontrolDurumu.yapmadi),
    ]) {
      await DersUygulamaIslemleri.sonuclariKaydet(o, k, [
        UygulamaSonucGirdisi(1, u1, d),
      ]);
    }
    expect((await son()).single.puan, 5);
    expect((await son(kontrol: k2)).single.puan, 10);
    await DersUygulamaIslemleri.sonuclariKaydet(o, k3, [
      UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.kontrolEdilmedi),
    ]);
    expect((await ilerleme(1)).bekleyen, 2);
    expect((await ilerleme(1)).ortalama, isNull);
    await BireyselOdevKontrolService.kontrolSil(o, k3);
    expect((await son()).single.puan, 10);
  });
  test(
    'yanlış ödev kontrolü ve kurumsal mod engellenir; P1/P2 sessiz yanlış hesap yapmaz',
    () async {
      final normal = await BireyselOdevKontrolService.gorevOlustur(
        o,
        sinifSubeId: 1,
        dersId: 1,
        gorevTuru: OdevGorevTuru.proje,
        baslik: 'Proje',
        baslangicTarihi: DateTime(2026, 9, 1),
        ogrenciIdleri: [1],
        kontrolBaslat: true,
      );
      final k = (await BireyselOdevKontrolService.kontroller(o, normal)).single;
      await expectLater(
        DersUygulamaIslemleri.gecmis(o, gid, kontrolId: k.odevKontrolId),
        throwsException,
      );
      final p = await PerformansNotService.oku(o, 1, 1, 1, 1);
      await expectLater(
        PerformansNotService.odevleriSec(o, p, {gid}),
        throwsException,
      );
      SharedPreferences.setMockInitialValues({'calisma_modu': 'kurumsal'});
      await expectLater(
        DersUygulamaIslemleri.uygulamalar(o, gid),
        throwsException,
      );
    },
  );
  for (final tur in ['guncel', 'v29', 'v30', 'v30-eski-durum']) {
    final eski = tur == 'v29';
    test('yedek geri yükleme: $tur', () async {
      final alan = await Directory.systemTemp.createTemp('uygulama_test_');
      addTearDown(() => alan.delete(recursive: true));
      final bakim = BireyselBakimService(
        databaseGetir: () async => db,
        alanGetir: () async => alan,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      await DersUygulamaIslemleri.sonuclariKaydet(o, k1, [
        UygulamaSonucGirdisi(1, u1, OdevKontrolDurumu.yapti),
      ]);
      final y = await bakim.yedekle();
      var dosya = y.dosya;
      if (eski || tur.startsWith('v30')) {
        final archive = ZipDecoder().decodeBytes(await dosya.readAsBytes());
        final m =
            jsonDecode(
                  utf8.decode(
                    archive.findFile('yedek.json')!.content as List<int>,
                  ),
                )
                as Map;
        if (tur.startsWith('v30')) {
          m['sema'] = 30;
          if (tur == 'v30-eski-durum') {
            for (final r in m['tablolar']['OdevUygulamaSonuc'] as List) {
              r['Durum'] = 'Geldi'; r['NotDegeri'] = -1;
            }
            for (final r in m['tablolar']['OdevKontrolSonuc'] as List) {
              r['Durum'] = 'Yapmadi'; r['NotDegeri'] = -3;
            }
          }
          for (final (table, field) in [
            ('OdevUygulama', 'Adet'),
            ('OdevUygulamaSonuc', 'Adet'),
            ('OdevUygulamaSonuc', 'Yapilan'),
          ]) {
            (m['kolonlar'][table] as List).remove(field);
            for (final row in m['tablolar'][table] as List) {
              (row as Map).remove(field);
            }
          }
        } else {
          m['sema'] = 29;
          for (final t in DersUygulamaSemasi.tablolar) {
            (m['tablolar'] as Map).remove(t);
            (m['kolonlar'] as Map).remove(t);
          }
          (m['kolonlar']['OdevTanim'] as List).remove('DersUygulamalari');
          for (final r in m['tablolar']['OdevTanim'] as List) {
            (r as Map).remove('DersUygulamalari');
          }
        }
        final bytes = utf8.encode(jsonEncode(m));
        dosya = await File('${alan.path}/eski.zip').writeAsBytes(
          ZipEncoder().encode(
            Archive()..addFile(ArchiveFile('yedek.json', bytes.length, bytes)),
          )!,
        );
      }
      await bakim.geriYukle(await bakim.incele(dosya), onayMetni: 'GERİ YÜKLE');
      if (eski) {
        expect(
          (await BireyselOdevKontrolService.gorevGetir(
            o,
            gid,
          )).dersUygulamalari,
          isFalse,
        );
        expect(await db.query('OdevUygulama'), isEmpty);
      } else if (tur == 'v30-eski-durum') {
        expect((await ilerleme(1)).ortalama, isNull);
        expect((await ilerleme(1)).degerlendirilen, 0);
        for (final t in ['OdevUygulamaSonuc','OdevKontrolSonuc']) {
          expect((await db.query(t)).every((r) => r['Durum']=='KontrolEdilmedi' && r['NotDegeri']==null),isTrue);
        }
      } else {
        expect((await ilerleme(1)).ortalama, 10);
      }
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }
}
