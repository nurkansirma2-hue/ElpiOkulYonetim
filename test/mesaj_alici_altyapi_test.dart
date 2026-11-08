import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/mesaj_alici_semasi.dart';
import 'package:elpi_okul_yonetim/database/mesajlasma_semasi.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  late MesajBaglami b;
  late Directory alan;
  late BireyselBakimService bakim;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;
  var whatsapp = 0, sms = 0, izin = 0;
  var smsHata = false, smsSonrasiModDegistir = false;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    alan = await Directory.systemTemp.createTemp('mesaj_alici_altyapi_');
    mod = CalismaModu.bireyselOgretmen;
    whatsapp = 0;
    sms = 0;
    izin = 0;
    smsHata = false;
    smsSonrasiModDegistir = false;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
      whatsappAc: (_, _) async {
        whatsapp++;
      },
      smsIzni: () async {
        izin++;
        return true;
      },
      smsGonder: (_, _) async {
        sms++;
        if (smsHata) throw StateError('Sahte platform kesintisi');
        if (smsSonrasiModDegistir) mod = null;
        return 1;
      },
    );
    bakim = BireyselBakimService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
      alanGetir: () async => alan,
    );
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
      'EgitimYili': '2026-2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Profil',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    for (var i = 1; i <= 3; i++) {
      await db.insert('SinifSube', {
        'SinifSubeId': i,
        'SinifKodu': '9/$i',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      if (i < 3) {
        await db.insert('DersProgrami', {
          'SinifSubeId': i,
          'DersId': 1,
          'DersSaatiId': 1,
          'Gun': i == 1 ? 'Pazartesi' : 'Salı',
          'OgretmenProfilId': 1,
          'EgitimOgretimYili': '2026-2027',
          'OlusturmaTarihi': 'test',
        });
      }
      await db.insert('Ogrenci', {
        'OgrenciId': i,
        'OkulNo': '00$i',
        'Ad': 'Ad$i',
        'Soyad': 'Soyad',
        'Telefon': '0532111223$i',
        'AnneAdi': 'Anne$i',
        'AnneTelefon': '0532444556$i',
        'BabaAdi': 'Baba$i',
        'BabaTelefon': '0532777889$i',
        'VeliTuru': 'Anne',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': i,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    b = await service.hazirla();
  });
  tearDown(() async {
    await LocalDatabase.instance.close();
    await alan.delete(recursive: true);
  });
  Future<List<MesajKisi>> adaylar([MesajKisiTuru? tur]) =>
      service.aliciAdaylari(b, tur: tur);
  Future<MesajKuyrugu> kuyruk(
    List<MesajKisi> ks, {
    Map<String, String>? ozel,
  }) => service.kisilerleKuyrukOlustur(
    b,
    MesajKisiOnIzleme(ks),
    'Mesaj',
    kaynakModul: 'Mesajlasma',
    kisiMesajlari: ozel,
  );
  Future<String> ogretmen({
    String tel = '05329990011',
    Set<int> siniflar = const {1, 2},
  }) => service.ogretmenIletisimKaydet(
    b,
    ad: 'Ders öğretmeni',
    telefon: tel,
    sinifIdleri: siniflar,
    sinifIliskileriniDogruladim: true,
  );

  test(
    'yeni alıcı modelinde tanımsız veli seçilmez; eski kuyruk uyumluluğu korunur',
    () async {
      await db.update('Ogrenci', {'VeliTuru': null}, where: 'OgrenciId=1');
      final k = (await adaylar(MesajKisiTuru.veli)).first;
      expect(k.veliTuru, isNull);
      expect(k.ad, 'Veli ilişkisi seçilmemiş');
      expect(k.normalizeTelefon, isNull);
      await expectLater(kuyruk([k]), throwsFormatException);
      await expectLater(
        service.kisiTelefonlariniKaydet(
          b,
          {k.secimAnahtari: '05320000000'},
          beklenen: [k],
        ),
        throwsStateError,
      );
      final eski = (await service.ogrenciler(b)).first;
      final q = await service.kuyrukOlustur(
        b,
        MesajOnIzleme([eski]),
        'Eski akış',
        kaynakModul: 'Test',
      );
      await service.aliciyiAc(b, q.id, q.siradaki!.id);
      expect(whatsapp, 1);
    },
  );
  test(
    'sınıflar ders kapsamındadır; öğretmen rehberi oturum profilinden ayrıdır',
    () async {
      expect((await service.mesajSiniflari(b)).map((s) => s['SinifSubeId']), [
        1,
        2,
      ]);
      expect(await adaylar(MesajKisiTuru.ogretmen), isEmpty);
      final id = await ogretmen();
      final ks = await adaylar(MesajKisiTuru.ogretmen);
      expect(ks.map((k) => k.kisiId).toSet(), {id});
      expect(ks.map((k) => k.sinifId), [1, 2]);
      expect(MesajKisiOnIzleme(ks).kisiSayisi, 1);
      expect(await db.query('OgretmenProfil'), hasLength(1));
      expect(
        await service.aliciAdaylari(
          b,
          tur: MesajKisiTuru.ogretmen,
          izinliOgrenciIdleri: {1},
        ),
        isEmpty,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'öğretmen ilişkisi onaysız veya kapsam dışı kaydedilemez; eski düzenleme reddedilir',
    () async {
      await expectLater(
        service.ogretmenIletisimKaydet(
          b,
          ad: 'X',
          sinifIdleri: {1},
          sinifIliskileriniDogruladim: false,
        ),
        throwsFormatException,
      );
      await expectLater(ogretmen(siniflar: {3}), throwsStateError);
      expect(await db.query('MesajOgretmenKisi'), isEmpty);
      final id = await ogretmen();
      final eski = await service.ogretmenIletisimBilgisi(b, id);
      await service.ogretmenIletisimKaydet(
        b,
        id: id,
        ad: 'Yeni',
        telefon: '05329990011',
        sinifIdleri: {1},
        sinifIliskileriniDogruladim: true,
        onceki: eski,
      );
      await expectLater(
        service.ogretmenIletisimKaydet(
          b,
          id: id,
          ad: 'Eski',
          sinifIdleri: {2},
          sinifIliskileriniDogruladim: true,
          onceki: eski,
        ),
        throwsStateError,
      );
      expect((await adaylar(MesajKisiTuru.ogretmen)).single.ad, 'Yeni');
    },
  );
  test(
    'öğrenci ve veli ayrı kimliktir; aynı telefonda kayıtlar açık türleriyle korunur',
    () async {
      await db.update('Ogrenci', {
        'Telefon': '05324445561',
      }, where: 'OgrenciId=1');
      final ks = (await adaylar()).where((k) => k.kisiId == '1').toList();
      expect(ks.map((k) => k.secimAnahtari).toSet(), {'Ogrenci:1', 'Veli:1'});
      final q = await kuyruk(ks);
      expect(q.alicilar, hasLength(1));
      expect(q.alicilar.single.baglar.map((r) => r['Tur']).toSet(), {
        'Ogrenci',
        'Veli',
      });
      expect(whatsapp, 0);
      expect(sms, 0);
    },
  );
  test(
    'ana geçmişten açılan öğrenci kuyruğu modül adından bağımsız doğru telefona gider',
    () async {
      final k = (await adaylar(MesajKisiTuru.ogrenci)).first;
      final q = await kuyruk([k]);
      final genel = MesajlasmaService(
        databaseGetir: () => Future.value(db),
        modGetir: () => Future.value(mod),
        whatsappAc: (tel, _) async {
          expect(tel, k.normalizeTelefon);
          whatsapp++;
        },
      );
      await genel.aliciyiAc(b, q.id, q.siradaki!.id);
      expect(whatsapp, 1);
      expect((await genel.kuyrukGetir(b, q.id)).siradaki!.durum, 'Acildi');
    },
  );
  test(
    'öğretmen kuyruğu aynı motorla açılır; ilişki kaldırılınca eski alıcıya gönderilmez',
    () async {
      final id = await ogretmen();
      final ks = await adaylar(MesajKisiTuru.ogretmen);
      final q = await kuyruk([ks.first]);
      final eski = await service.ogretmenIletisimBilgisi(b, id);
      await service.ogretmenIletisimKaydet(
        b,
        id: id,
        ad: 'Ders öğretmeni',
        telefon: '05329990011',
        sinifIdleri: {2},
        sinifIliskileriniDogruladim: true,
        onceki: eski,
      );
      await expectLater(
        service.aliciyiAc(b, q.id, q.siradaki!.id),
        throwsStateError,
      );
      expect(whatsapp, 0);
    },
  );
  test(
    'telefonlar gerçek kişi alanına yazılır; anne baba ve veli kopyası oluşturulmaz',
    () async {
      final id = await ogretmen();
      final ks = (await adaylar())
          .where((k) => k.kisiId == '1' || k.kisiId == id)
          .toList();
      await service.kisiTelefonlariniKaydet(b, {
        'Ogrenci:1': '05321110000',
        'Veli:1': '05324440000',
        'Ogretmen:$id': '05329990000',
      }, beklenen: ks);
      final o = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
      expect(o['Telefon'], '05321110000');
      expect(o['AnneTelefon'], '05324440000');
      expect(o['BabaTelefon'], '05327778891');
      expect(o['VeliTelefonu'], isNull);
      expect(
        (await db.query('MesajOgretmenKisi')).single['Telefon'],
        '05329990000',
      );
      await expectLater(
        service.kisiTelefonlariniKaydet(b, {
          'Veli:1': '05320000000',
        }, beklenen: ks),
        throwsStateError,
      );
    },
  );
  test(
    'telefon ön izlemesi değişirse çoklu güncellemenin tümü geri alınır',
    () async {
      final ks = await adaylar(MesajKisiTuru.veli);
      await db.update('Ogrenci', {'VeliTuru': 'Baba'}, where: 'OgrenciId=2');
      await expectLater(
        service.kisiTelefonlariniKaydet(b, {
          'Veli:1': '05320000001',
          'Veli:2': '05320000002',
        }, beklenen: ks),
        throwsStateError,
      );
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneTelefon'],
        '05324445561',
      );
    },
  );
  test(
    'geçersiz alıcı, boş kaynak kapsamı ve kaynağa aykırı tür kuyruk oluşturmaz',
    () async {
      await db.update('Ogrenci', {'Telefon': ''}, where: 'OgrenciId=1');
      final ks = await adaylar(MesajKisiTuru.ogrenci);
      await expectLater(kuyruk([ks.first]), throwsFormatException);
      await expectLater(
        service.kisilerleKuyrukOlustur(
          b,
          MesajKisiOnIzleme([ks.last]),
          'Mesaj',
          kaynakModul: 'Test',
          izinliOgrenciIdleri: {},
        ),
        throwsStateError,
      );
      final veli = (await adaylar(MesajKisiTuru.veli)).first;
      await expectLater(
        service.kisilerleKuyrukOlustur(
          b,
          MesajKisiOnIzleme([veli]),
          'Mesaj',
          kaynakModul: MesajlasmaService.formDuzeltmeOgrenciModulu,
        ),
        throwsStateError,
      );
      expect(await db.query('MesajKuyrugu'), isEmpty);
    },
  );
  test(
    'kardeşlerin özel bağlantıları korunur; farklı türün özel içeriği karıştırılmaz',
    () async {
      await db.update('Ogrenci', {
        'AnneTelefon': '05324445561',
      }, where: 'OgrenciId=2');
      final ks = await adaylar(MesajKisiTuru.veli);
      final q = await kuyruk(
        ks,
        ozel: {'Veli:1': 'Bağlantı1', 'Veli:2': 'Bağlantı2'},
      );
      expect(
        MesajlasmaService.aliciMetni(q, q.alicilar.single),
        'Bağlantı1\n\nBağlantı2',
      );
      await db.update('Ogrenci', {
        'Telefon': '05324445561',
      }, where: 'OgrenciId=1');
      final karisik = (await adaylar()).where((k) => k.kisiId == '1').toList();
      await expectLater(
        kuyruk(
          karisik,
          ozel: {'Veli:1': 'Veliye özel', 'Ogrenci:1': 'Öğrenciye özel'},
        ),
        throwsStateError,
      );
      expect(await db.query('MesajKuyrugu'), hasLength(1));
    },
  );
  test(
    'SMS her kaynakta güncel telefonu kontrol eder; izin ve gönderim başlamaz',
    () async {
      final q = await kuyruk([(await adaylar(MesajKisiTuru.veli)).first]);
      await db.update('Ogrenci', {
        'AnneTelefon': '05320000000',
      }, where: 'OgrenciId=1');
      await expectLater(service.smsTopluGonder(b, q.id), throwsStateError);
      expect(izin, 0);
      expect(sms, 0);
      expect(await db.query('MesajSms'), isEmpty);
    },
  );
  test(
    'SMS sırasında mod değişirse sonraki alıcı durur; dönüşte önceki tekrar edilmez',
    () async {
      final q = await kuyruk(await adaylar(MesajKisiTuru.veli));
      smsSonrasiModDegistir = true;
      await expectLater(service.smsTopluGonder(b, q.id), throwsStateError);
      expect(sms, 1);
      expect(await db.query('MesajSms'), hasLength(1));
      mod = CalismaModu.bireyselOgretmen;
      smsSonrasiModDegistir = false;
      final sonuc = await service.smsTopluGonder(b, q.id);
      expect(sonuc, {'istenen': 1, 'belirsiz': 0, 'atlanan': 1});
      expect(sms, 2);
      expect(await service.smsTopluGonder(b, q.id), {
        'istenen': 0,
        'belirsiz': 0,
        'atlanan': 2,
      });
      expect(sms, 2);
      expect((await service.kuyrukGetir(b, q.id)).onaylanan, 0);
    },
  );
  test(
    'SMS hatası belirsiz kalır; yeniden çağrı otomatik tekrar göndermez',
    () async {
      final q = await kuyruk([(await adaylar(MesajKisiTuru.ogrenci)).first]);
      smsHata = true;
      expect((await service.smsTopluGonder(b, q.id))['belirsiz'], 1);
      expect((await db.query('MesajSms')).single['Durum'], 'Belirsiz');
      await service.smsTopluGonder(b, q.id);
      expect(sms, 1);
    },
  );
  test(
    'telefon aynı kalsa da veli ilişkisi değişince gönderim engellenir',
    () async {
      await db.update('Ogrenci', {
        'BabaTelefon': '05324445561',
      }, where: 'OgrenciId=1');
      final q = await kuyruk([(await adaylar(MesajKisiTuru.veli)).first]);
      await db.update('Ogrenci', {'VeliTuru': 'Baba'}, where: 'OgrenciId=1');
      await expectLater(
        service.aliciyiAc(b, q.id, q.siradaki!.id),
        throwsStateError,
      );
      await expectLater(service.smsTopluGonder(b, q.id), throwsStateError);
      expect(sms, 0);
      expect(whatsapp, 0);
    },
  );
  test(
    'v24 yedek öğretmen ve kuyruk bağlarını korur; sıfırlama geçmişi silmez',
    () async {
      await ogretmen();
      final q = await kuyruk(await adaylar(MesajKisiTuru.ogretmen));
      final onceki = await db.query('MesajAliciBag');
      final y = await bakim.yedekle();
      await LocalDatabase.instance.bireyselVerileriSifirla(
        onayMetni: 'SIFIRLA',
      );
      expect(await db.query('MesajOgretmenKisi'), isEmpty);
      expect(await db.query('MesajAliciBag'), onceki);
      await bakim.geriYukle(
        await bakim.incele(y.dosya),
        onayMetni: 'GERİ YÜKLE',
      );
      expect(await db.query('MesajAliciBag'), onceki);
      await service.aliciyiAc(b, q.id, q.siradaki!.id);
      expect(whatsapp, 1);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'v22 yedek bağları tarihsel kuralla tamamlar; metin ve SMS geçmişi değişmez',
    () async {
      final ks = await service.ogrenciler(b);
      final q = await service.kuyrukOlustur(
        b,
        MesajOnIzleme(ks),
        'Eski mesaj',
        kaynakModul: 'Test',
      );
      await service.smsTopluGonder(b, q.id);
      final smsOnceki = await db.query('MesajSms');
      final y = await bakim.yedekle();
      final archive = ZipDecoder().decodeBytes(await y.dosya.readAsBytes());
      final m =
          jsonDecode(
                utf8.decode(
                  archive.findFile('yedek.json')!.content as List<int>,
                ),
              )
              as Map;
      m['sema'] = 22;
      for (final t in [...MesajAliciSemasi.tablolar,'MesajOgretmenSinifDers','MesajTekliGecmis']) {
        (m['tablolar'] as Map).remove(t);
        (m['kolonlar'] as Map).remove(t);
      }
      final bytes = utf8.encode(jsonEncode(m)),
          a = Archive()
            ..addFile(ArchiveFile('yedek.json', bytes.length, bytes));
      final f = await File(
        '${alan.path}/v22.zip',
      ).writeAsBytes(ZipEncoder().encode(a)!);
      await bakim.geriYukle(await bakim.incele(f), onayMetni: 'GERİ YÜKLE');
      final restored = await service.kuyrukGetir(b, q.id);
      expect(restored.metin, 'Eski mesaj');
      expect(await db.query('MesajSms'), smsOnceki);
      expect(
        restored.alicilar
            .expand((a) => a.baglar)
            .every((r) => r['EskiKayit'] == 1),
        true,
      );
      await service.aliciyiAc(b, q.id, restored.siradaki!.id);
      expect(whatsapp, 1);
    },
  );
  test(
    'başka profil veya kurumsal mod adaylara ve öğretmen rehberine erişemez',
    () async {
      final id = await ogretmen();
      mod = null;
      await expectLater(adaylar(), throwsStateError);
      mod = CalismaModu.bireyselOgretmen;
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Başka',
        'OkulAdi': 'Okul',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await expectLater(
        service.ogretmenIletisimBilgisi(b, id),
        throwsStateError,
      );
      final yeni = await service.hazirla();
      expect(await service.aliciAdaylari(yeni), isEmpty);
      await expectLater(
        service.ogretmenIletisimBilgisi(yeni, id),
        throwsStateError,
      );
    },
  );
  test(
    'v22 veritabanına eklenen şema mevcut kuyruk ve durumlara dokunmaz',
    () async {
      final eski = WindowsMemoryDatabase();
      try {
        await eski.execute(
          'CREATE TABLE Ogrenci(OgrenciId INTEGER PRIMARY KEY)',
        );
        await MesajlasmaSemasi.hazirla(eski);
        await eski.insert('MesajKuyrugu', {
          'KuyrukId': 'eski',
          'OkulId': 'okul',
          'OgretmenProfilId': 1,
          'OgretmenAdi': 'Profil',
          'OkulAdi': 'Okul',
          'EgitimOgretimYili': '2026-2027',
          'KaynakModul': 'BilgiFormPaylasimOgrenci',
          'Metin': 'Korunacak',
          'OlusturmaTarihi': 'test',
        });
        await eski.insert('MesajAlici', {
          'KuyrukId': 'eski',
          'Sira': 1,
          'Telefon': '905321112231',
          'AliciAdi': 'Ad1',
          'Ogrenciler': jsonEncode([
            {'id': 1, 'sinifId': 1, 'aciklama': '1 • Ad1'},
          ]),
        });
        final onceki = await eski.query('MesajAlici');
        await MesajAliciSemasi.hazirla(eski);
        expect(await eski.query('MesajAlici'), onceki);
        expect((await eski.query('MesajAliciBag')).single['Tur'], 'Ogrenci');
        expect((await eski.query('MesajAliciBag')).single['EskiKayit'], 1);
      } finally {
        await eski.close();
      }
    },
  );
  for (final kaynak in ['yerel22', 'github22', 'yerel23', 'yerel24']) {
    test(
      'LocalDatabase $kaynak verisini kaybetmeden v25 sürümüne geçirir',
      () async {
        final q = await service.kuyrukOlustur(
          b,
          MesajOnIzleme(await service.ogrenciler(b)),
          'Eski kuyruk',
          kaynakModul: 'Test',
        );
        final onceki = await db.query('MesajAlici');
        final eski = WindowsMemoryDatabase();
        final haric = {
          'MesajOgretmenSinifDers',
          'MesajTekliGecmis',
          if (kaynak != 'yerel23' && kaynak != 'yerel24') ...MesajAliciSemasi.tablolar,
          if (kaynak != 'github22' && kaynak != 'yerel24') 'OgrenciIletisim',
        };
        final sema = await db.rawQuery(
          "SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY rowid",
        );
        for (final t in sema.where((t) => !haric.contains(t['name']))) {
          await eski.execute(t['sql'] as String);
          for (final row in await db.query(t['name'] as String)) {
            await eski.insert(t['name'] as String, row);
          }
        }
        for (final v in await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='view'",
        )) {
          await eski.execute(v['sql'] as String);
        }
        for (final index in await db.rawQuery(
          "SELECT tbl_name,sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL",
        )) {
          if (!haric.contains(index['tbl_name'])) {
            await eski.execute(index['sql'] as String);
          }
        }
        if (kaynak == 'github22') {
          await eski.execute('ALTER TABLE Ogrenci DROP COLUMN VeliTuru');
          await eski.insert('OgrenciIletisim', {
            'OgrenciId': 1,
            'Tur': 'Baba',
            'Ad': 'Eski baba',
            'Telefon': '05329990000',
            'Varsayilan': 1,
          });
        }
        final arsiv = kaynak == 'github22'
            ? await eski.query('OgrenciIletisim')
            : [];
        final baglar = kaynak == 'yerel23'
            ? await eski.query('MesajAliciBag')
            : [];
        await LocalDatabase.instance.close();
        final factory = _V22Factory(eski, kaynak == 'yerel24' ? 24 : kaynak == 'yerel23' ? 23 : 22);
        databaseFactory = factory;
        db = await LocalDatabase.instance.database;
        expect(factory.yukseltildi, true);
        expect(await db.query('MesajAlici'), onceki);
        expect(await db.query('OgrenciIletisim'), arsiv);
        if (kaynak == 'yerel23') {
          expect(await db.query('MesajAliciBag'), baglar);
        }
        expect(
          (await db.rawQuery(
            'PRAGMA table_info(Ogrenci)',
          )).any((r) => r['name'] == 'VeliTuru'),
          true,
        );
        expect(
          (await service.kuyrukGetir(
            b,
            q.id,
          )).alicilar.every((a) => a.baglar.isNotEmpty),
          true,
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }

  for (final kaynak in ['yerel22', 'github22', 'yerel23', 'yerel24']) {
    test(
      '$kaynak yedeği v25 olarak geri yüklenir; eski iletişim kayıtları korunur',
      () async {
        await db.insert('OgrenciIletisim', {
          'OgrenciId': 1,
          'Tur': 'Baba',
          'Ad': 'Arşiv baba',
          'Telefon': '05329990000',
          'Varsayilan': 1,
        });
        final arsiv = await db.query('OgrenciIletisim');
        final y = await bakim.yedekle();
        final archive = ZipDecoder().decodeBytes(await y.dosya.readAsBytes());
        final m =
            jsonDecode(
                  utf8.decode(
                    archive.findFile('yedek.json')!.content as List<int>,
                  ),
                )
                as Map;
        m['sema'] = kaynak == 'yerel24' ? 24 : kaynak == 'yerel23' ? 23 : 22;
        final tablolar = m['tablolar'] as Map, kolonlar = m['kolonlar'] as Map;
        tablolar.remove('MesajTekliGecmis'); kolonlar.remove('MesajTekliGecmis');
        tablolar.remove('MesajOgretmenSinifDers'); kolonlar.remove('MesajOgretmenSinifDers');
        if (kaynak != 'github22' && kaynak != 'yerel24') {
          tablolar.remove('OgrenciIletisim');
          kolonlar.remove('OgrenciIletisim');
        } else if (kaynak == 'github22') {
          (kolonlar['Ogrenci'] as List).remove('VeliTuru');
          for (final o in tablolar['Ogrenci'] as List) {
            (o as Map).remove('VeliTuru');
          }
        }
        if (kaynak != 'yerel23' && kaynak != 'yerel24') {
          for (final t in MesajAliciSemasi.tablolar) {
            tablolar.remove(t);
            kolonlar.remove(t);
          }
        }
        final bytes = utf8.encode(jsonEncode(m));
        final a = Archive()
          ..addFile(ArchiveFile('yedek.json', bytes.length, bytes));
        final f = await File(
          '${alan.path}/$kaynak.zip',
        ).writeAsBytes(ZipEncoder().encode(a)!);
        await bakim.geriYukle(await bakim.incele(f), onayMetni: 'GERİ YÜKLE');
        expect(
          await db.query('OgrenciIletisim'),
          kaynak == 'github22' || kaynak == 'yerel24' ? arsiv : isEmpty,
        );
        expect(
          (await adaylar(MesajKisiTuru.veli)).first.telefon,
          '05324445561',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }
}

class _V22Factory extends WindowsMemoryFactory {
  _V22Factory(this.eskiDb, this.eskiSurum);
  final Database eskiDb;
  final int eskiSurum;
  bool yukseltildi = false;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    await options?.onConfigure?.call(eskiDb);
    expect(options?.version, 27);
    await options?.onUpgrade?.call(eskiDb, eskiSurum, options.version!);
    await options?.onOpen?.call(eskiDb);
    yukseltildi = true;
    return eskiDb;
  }
}
