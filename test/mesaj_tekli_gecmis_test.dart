import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/mesajlasma_semasi.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'support/windows_memory_database.dart';

class _V26Factory extends WindowsMemoryFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final memory = db = WindowsMemoryDatabase();
    await options?.onConfigure?.call(memory);
    await memory.execute(
      'CREATE TABLE Ogrenci (OgrenciId INTEGER PRIMARY KEY, Ad TEXT)',
    );
    await memory.insert('Ogrenci', {'OgrenciId': 1, 'Ad': 'Korunan öğrenci'});
    await memory.execute('CREATE TABLE MesajKuyrugu (Metin TEXT)');
    await memory.insert('MesajKuyrugu', {'Metin': 'Korunan geçmiş'});
    expect(options!.version, 27);
    await options.onUpgrade!(memory, 26, options.version!);
    return memory;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  late MesajBaglami b;
  var gonderim = 0, izin = true, hata = false, izinSirasindaDegistir = false;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    gonderim = 0;
    izin = true;
    hata = false;
    izinSirasindaDegistir = false;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
      whatsappAc: (_, _) async {
        gonderim++;
        if (hata) throw StateError('Native hata');
      },
      smsIzni: () async {
        if (izinSirasindaDegistir)
          await db.update('Ogrenci', {
            'AnneTelefon': '05320000000',
          }, where: 'OgrenciId=1');
        return izin;
      },
      smsGonder: (_, _) async {
        gonderim++;
        if (hata) throw StateError('Native hata');
        return 1;
      },
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
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifKodu': '9-A',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OkulNo': '001',
      'Ad': 'Öğrenci',
      'Soyad': 'Test',
      'AnneAdi': 'Anne',
      'AnneTelefon': '05321112233',
      'VeliTuru': 'Anne',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    b = await service.hazirla();
  });
  tearDown(LocalDatabase.instance.close);
  test('26→27 gerçek yükseltme öğrenci ve mevcut geçmişi korur', () async {
    await LocalDatabase.instance.close();
    databaseFactory = _V26Factory();
    final memory = await LocalDatabase.instance.database;
    expect((await memory.query('Ogrenci')).single['Ad'], 'Korunan öğrenci');
    expect(
      (await memory.query('MesajKuyrugu')).single['Metin'],
      'Korunan geçmiş',
    );
    expect(await memory.query('MesajTekliGecmis'), isEmpty);
  });
  Future<MesajKisiOnIzleme> kisi() async => MesajKisiOnIzleme(
    await service.aliciAdaylari(b, tur: MesajKisiTuru.veli),
  );
  Future<void> gonder({bool sms = false}) async => service.tekliGonder(
    b,
    'Bilgi',
    kisiler: await kisi(),
    sms: sms,
    kaynakModul: 'Test',
  );
  test('tek veli gönderimi öğrenci geçmişidir; kuyruk yazılmaz', () async {
    await gonder();
    expect(gonderim, 1);
    for (final t in [
      'MesajKuyrugu',
      'MesajAlici',
      'MesajSms',
      'MesajAliciBag',
    ]) {
      expect(await db.query(t), isEmpty);
    }
    final r = (await service.tekliGecmis(b)).single;
    expect(r['OgrenciId'], 1);
    expect(r['Tur'], 'Veli');
    expect(r['AliciAdi'], 'Anne');
    expect(r['Durum'], 'Acildi');
    expect(r['Aciklama'], contains('001'));
  });
  test(
    'geçmiş silme seçili SMS/tekli kayıtlarını kaldırır; öğrenciler ve diğer geçmiş korunur',
    () async {
      await gonder();
      await gonder(sms: true);
      final rows = await service.tekliGecmis(b);
      final sms =
          rows.firstWhere((r) => r['Kanal'] == 'SMS')['KayitId'] as String;
      final kalan = rows.firstWhere((r) => r['Kanal'] == 'WhatsApp')['KayitId'];
      final q = await service.kisilerleKuyrukOlustur(
        b,
        await kisi(),
        'Eski SMS',
        kaynakModul: 'Test',
      );
      await service.smsTopluGonder(b, q.id);
      final once = gonderim;
      await service.gecmisiSil(
        b,
        kuyrukAlicilari: {
          q.id: {q.alicilar.single.id},
        },
        tekliKayitlar: {sms},
        onayMetni: 'SİL',
      );
      expect((await service.tekliGecmis(b)).single['KayitId'], kalan);
      for (final t in [
        'MesajKuyrugu',
        'MesajAlici',
        'MesajAliciBag',
        'MesajSms',
      ]) {
        expect(await db.query(t), isEmpty);
      }
      expect(await db.query('Ogrenci'), hasLength(1));
      expect(gonderim, once);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'silme onayı/sahipliği yanlışsa veya işlem hata verirse hiçbir geçmiş kısmen silinmez',
    () async {
      await gonder();
      final id = (await service.tekliGecmis(b)).single['KayitId'] as String;
      final q = await service.kisilerleKuyrukOlustur(
        b,
        await kisi(),
        'Korunan',
        kaynakModul: 'Test',
      );
      await service.smsTopluGonder(b, q.id);
      await expectLater(
        service.gecmisiSil(
          b,
          kuyrukAlicilari: {},
          tekliKayitlar: {id},
          onayMetni: 'evet',
        ),
        throwsStateError,
      );
      await db.update('MesajTekliGecmis', {'OgretmenProfilId': 999});
      await expectLater(
        service.gecmisiSil(
          b,
          kuyrukAlicilari: {
            q.id: {q.alicilar.single.id},
          },
          tekliKayitlar: {id},
          onayMetni: 'SİL',
        ),
        throwsStateError,
      );
      await db.update('MesajTekliGecmis', {'OgretmenProfilId': 1});
      await db.execute(
        "CREATE TRIGGER gecmis_silme_hata BEFORE DELETE ON MesajTekliGecmis BEGIN SELECT RAISE(ABORT, 'Test'); END",
      );
      await expectLater(
        service.gecmisiSil(
          b,
          kuyrukAlicilari: {
            q.id: {q.alicilar.single.id},
          },
          tekliKayitlar: {id},
          onayMetni: 'SİL',
        ),
        throwsA(anything),
      );
      for (final t in [
        'MesajKuyrugu',
        'MesajAlici',
        'MesajAliciBag',
        'MesajSms',
        'MesajTekliGecmis',
      ]) {
        expect(await db.query(t), hasLength(1));
      }
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test('kuyruktan bir alıcı silinince kalan SMS ve sıralama korunur', () async {
    final eski = (await db.query('Ogrenci')).single;
    await db.insert('Ogrenci', {
      ...eski,
      'OgrenciId': 2,
      'OkulNo': '002',
      'AnneTelefon': '05324445566',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 2,
      'SinifSubeId': 1,
      'EgitimOgretimYili': b.yil,
      'OlusturmaTarihi': 'test',
    });
    final q = await service.kisilerleKuyrukOlustur(
      b,
      await kisi(),
      'Toplu',
      kaynakModul: 'Test',
    );
    await service.smsTopluGonder(b, q.id);
    await service.gecmisiSil(
      b,
      kuyrukAlicilari: {
        q.id: {q.alicilar.first.id},
      },
      tekliKayitlar: {},
      onayMetni: 'SİL',
    );
    final kalan = await service.kuyrukGetir(b, q.id);
    expect(kalan.alicilar.single.id, q.alicilar.last.id);
    expect(kalan.alicilar.single.sira, 1);
    expect(kalan.alicilar.single.smsDurumu, 'Istendi');
    expect(await db.query('MesajSms'), hasLength(1));
    expect(await db.query('Ogrenci'), hasLength(2));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
    'geçmiş onayı tekli ve eski kuyruk kayıtlarını yeniden göndermeden onaylar',
    () async {
      await gonder();
      final tekli = (await service.tekliGecmis(b)).single['KayitId'] as String;
      final q = await service.kisilerleKuyrukOlustur(
        b,
        await kisi(),
        'Eski mesaj',
        kaynakModul: 'Test',
      );
      await service.aliciyiAc(b, q.id, q.alicilar.single.id);
      final onceki = gonderim;
      for (var i = 0; i < 2; i++) {
        await service.gecmisiOnayla(
          b,
          kuyrukAlicilari: {
            q.id: {q.alicilar.single.id},
          },
          tekliKayitlar: {tekli},
        );
      }
      expect((await service.tekliGecmis(b)).single['Durum'], 'Istendi');
      expect((await service.kuyrukGetir(b, q.id)).onaylanan, 1);
      expect(gonderim, onceki);
    },
  );
  test(
    'SMS veya açılmamış kayıt seçilirse bütün onay işlemi geri alınır',
    () async {
      await gonder();
      final tekli = (await service.tekliGecmis(b)).single['KayitId'] as String;
      await gonder(sms: true);
      final sms =
          (await service.tekliGecmis(
                b,
              )).firstWhere((r) => r['Kanal'] == 'SMS')['KayitId']
              as String;
      await expectLater(
        service.gecmisiOnayla(
          b,
          kuyrukAlicilari: {},
          tekliKayitlar: {tekli, sms},
        ),
        throwsStateError,
      );
      final q = await service.kisilerleKuyrukOlustur(
        b,
        await kisi(),
        'Açılmadı',
        kaynakModul: 'Test',
      );
      await expectLater(
        service.gecmisiOnayla(
          b,
          kuyrukAlicilari: {
            q.id: {q.alicilar.single.id},
          },
          tekliKayitlar: {tekli},
        ),
        throwsStateError,
      );
      expect(
        (await service.tekliGecmis(
          b,
        )).firstWhere((r) => r['KayitId'] == tekli)['Durum'],
        'Acildi',
      );
      expect((await service.kuyrukGetir(b, q.id)).onaylanan, 0);
      expect(gonderim, 2);
    },
  );
  test('başka sahip ve eski yıl kayıtları onaylanamaz', () async {
    await gonder();
    final id = (await service.tekliGecmis(b)).single['KayitId'] as String;
    await db.update('MesajTekliGecmis', {'OgretmenProfilId': 999});
    await expectLater(
      service.gecmisiOnayla(b, kuyrukAlicilari: {}, tekliKayitlar: {id}),
      throwsStateError,
    );
    await db.update('MesajTekliGecmis', {'OgretmenProfilId': 1});
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
    await expectLater(
      service.gecmisiOnayla(b, kuyrukAlicilari: {}, tekliKayitlar: {id}),
      throwsStateError,
    );
    expect((await db.query('MesajTekliGecmis')).single['Durum'], 'Acildi');
    expect(gonderim, 1);
  });
  test(
    'değişen telefon ve boş mesaj hiçbir gönderim kaydı oluşturmaz',
    () async {
      final p = await kisi();
      await db.update('Ogrenci', {
        'AnneTelefon': '05320000000',
      }, where: 'OgrenciId=1');
      await expectLater(
        service.tekliGonder(
          b,
          'Bilgi',
          kisiler: p,
          sms: false,
          kaynakModul: 'Test',
        ),
        throwsStateError,
      );
      await expectLater(
        service.tekliGonder(
          b,
          '',
          kisiler: await kisi(),
          sms: false,
          kaynakModul: 'Test',
        ),
        throwsStateError,
      );
      expect(gonderim, 0);
      expect(await service.tekliGecmis(b), isEmpty);
    },
  );
  test(
    'SMS izin reddi ve izin sırasında değişen telefon gönderimi engeller',
    () async {
      izin = false;
      await expectLater(gonder(sms: true), throwsStateError);
      izin = true;
      izinSirasindaDegistir = true;
      await expectLater(gonder(sms: true), throwsStateError);
      expect(gonderim, 0);
      expect(await service.tekliGecmis(b), isEmpty);
    },
  );
  test('SMS belirsiz sonucu geçmiş okunduğunda yeniden gönderilmez', () async {
    hata = true;
    await expectLater(gonder(sms: true), throwsStateError);
    expect((await service.tekliGecmis(b)).single['Durum'], 'Belirsiz');
    await service.tekliGecmis(b);
    expect(gonderim, 1);
    expect(await db.query('MesajKuyrugu'), isEmpty);
  });
  test('geçmiş yedeklenir ve geri yüklenir; v26 yedeği uyarlanır', () async {
    final temp = await Directory.systemTemp.createTemp('mesaj_gecmis_test_');
    addTearDown(() => temp.delete(recursive: true));
    await gonder();
    final bakim = BireyselBakimService(
      databaseGetir: () async => db,
      alanGetir: () async => temp,
      modGetir: () async => CalismaModu.bireyselOgretmen,
    );
    final y = await bakim.yedekle();
    expect(y.sayilar['MesajTekliGecmis'], 1);
    await bakim.geriYukle(await bakim.incele(y.dosya), onayMetni: 'GERİ YÜKLE');
    expect((await service.tekliGecmis(b)).single['Metin'], 'Bilgi');
    final a = ZipDecoder().decodeBytes(await y.dosya.readAsBytes());
    final m =
        jsonDecode(utf8.decode(a.findFile('yedek.json')!.content as List<int>))
            as Map;
    m['sema'] = 26;
    (m['tablolar'] as Map).remove('MesajTekliGecmis');
    (m['kolonlar'] as Map).remove('MesajTekliGecmis');
    final bytes = utf8.encode(jsonEncode(m)), f = File('${temp.path}/v26.zip');
    await f.writeAsBytes(
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('yedek.json', bytes.length, bytes)),
      )!,
    );
    expect((await bakim.incele(f)).sayilar['MesajTekliGecmis'], 0);
    expect(await service.tekliGecmis(b), hasLength(1));
  });
  test('geçmiş mesaj sıfırlamasına dahildir; öğrenciler korunur', () async {
    await gonder();
    final bakim = BireyselBakimService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
    );
    final p = (await bakim.sifirlamaEnvanteri()).planla({'mesajlar'});
    expect(p.tablolar, contains('MesajTekliGecmis'));
    await bakim.seciliModulleriSifirla(p, onayMetni: 'SIFIRLA');
    expect(await service.tekliGecmis(b), isEmpty);
    expect(await db.query('Ogrenci'), hasLength(1));
  });
  test(
    'şema tekrar hazırlanınca kayıt korunur; eski yıl bağlamı reddedilir',
    () async {
      await gonder();
      await MesajlasmaSemasi.tekliGecmisHazirla(db);
      expect(await service.tekliGecmis(b), hasLength(1));
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
      await expectLater(service.tekliGecmis(b), throwsStateError);
      expect(await db.query('MesajTekliGecmis'), hasLength(1));
    },
  );
}
