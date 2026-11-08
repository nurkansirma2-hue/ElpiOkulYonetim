import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  late MesajBaglami b;
  late List<String> gonderilen;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    gonderilen = [];
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
      whatsappAc: (tel, _) async {
        gonderilen.add(tel);
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
      'AdSoyad': 'Profil',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-C',
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
      'OgrenciId': 1,
      'OkulNo': '001',
      'Ad': 'Ali',
      'Soyad': 'Test',
      'Telefon': '',
      'AnneAdi': 'Anne Adı',
      'AnneTelefon': '05324445566',
      'BabaAdi': 'Baba Adı',
      'BabaTelefon': '05327778899',
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

  Future<MesajKisi> veli() async =>
      (await service.aliciAdaylari(b, tur: MesajKisiTuru.veli)).single;

  test(
    'veli adı ve telefonu aynı işlemde yazılır; eski görüntü ve veli dışı ad reddedilir',
    () async {
      final k = await veli();
      await service.kisiTelefonlariniKaydet(
        b,
        {k.secimAnahtari: '05321110000'},
        beklenen: [k],
        adlar: {k.secimAnahtari: 'Yeni Anne'},
      );
      var row = (await db.query('Ogrenci')).single;
      expect(row['AnneAdi'], 'Yeni Anne');
      expect(row['AnneTelefon'], '05321110000');
      expect(row['BabaAdi'], 'Baba Adı');
      await expectLater(
        service.kisiTelefonlariniKaydet(
          b,
          {k.secimAnahtari: '05320000000'},
          beklenen: [k],
          adlar: {k.secimAnahtari: 'Eski ekran'},
        ),
        throwsStateError,
      );
      final ogrenci = (await service.aliciAdaylari(
        b,
        tur: MesajKisiTuru.ogrenci,
      )).single;
      await expectLater(
        service.kisiTelefonlariniKaydet(
          b,
          {ogrenci.secimAnahtari: '05320000000'},
          beklenen: [ogrenci],
          adlar: {ogrenci.secimAnahtari: 'Değişmesin'},
        ),
        throwsFormatException,
      );
      row = (await db.query('Ogrenci')).single;
      expect(row['AnneAdi'], 'Yeni Anne');
      expect(row['AnneTelefon'], '05321110000');
      expect(row['Ad'], 'Ali');
      expect(row['Telefon'], '');
    },
  );

  for (final eksik in ['', 'abc']) {
    test(
      'anne telefonu "$eksik" ise baba seçilir; kaynak kayıt korunur',
      () async {
        await db.update('Ogrenci', {
          'AnneTelefon': eksik,
        }, where: 'OgrenciId=1');
        final onceki = (await db.query('Ogrenci')).single;
        final k = await veli();
        expect(k.veliTuru, 'Baba');
        expect(k.ad, 'Baba Adı');
        expect(k.normalizeTelefon, '905327778899');
        expect(k.telefonAciklamasi, contains('Kayıtlı veli: Anne'));
        expect(k.telefonAciklamasi, contains('Baba telefonu kullanılıyor'));
        expect(
          (await service.ogrenciler(b)).single.telefonAciklamasi,
          k.telefonAciklamasi,
        );
        final ogrenci = (await service.aliciAdaylari(
          b,
          tur: MesajKisiTuru.ogrenci,
        )).single;
        expect(ogrenci.normalizeTelefon, isNull);
        expect(ogrenci.telefonAciklamasi, isNull);
        await service.tekliGonder(
          b,
          'Bilgi',
          kisiler: MesajKisiOnIzleme([k]),
          sms: false,
          kaynakModul: 'Mesajlasma',
        );
        expect(gonderilen, ['905327778899']);
        final log = (await service.tekliGecmis(b)).single;
        expect(log['AliciAdi'], 'Baba Adı');
        expect(log['Telefon'], '905327778899');
        expect(await db.query('Ogrenci'), [onceki]);
        expect(await db.query('MesajKuyrugu'), isEmpty);
      },
    );
  }
  test(
    'baba eksikse anne kullanılır; geçerli seçili veli önceliklidir',
    () async {
      expect((await veli()).telefonAciklamasi, isNull);
      expect((await veli()).normalizeTelefon, '905324445566');
      await db.update('Ogrenci', {
        'VeliTuru': 'Baba',
        'BabaTelefon': '',
      }, where: 'OgrenciId=1');
      final k = await veli();
      expect(k.veliTuru, 'Anne');
      expect(k.ad, 'Anne Adı');
      expect(k.telefonAciklamasi, contains('Anne telefonu kullanılıyor'));
    },
  );
  test(
    'iki telefon da geçersizse, ilişki belirsizse ve diğer veli seçiliyse varsayım yapılmaz',
    () async {
      await db.update('Ogrenci', {
        'AnneTelefon': '',
        'BabaTelefon': 'abc',
      }, where: 'OgrenciId=1');
      expect((await veli()).normalizeTelefon, isNull);
      expect((await veli()).telefonAciklamasi, isNull);
      await db.update('Ogrenci', {
        'VeliTuru': null,
        'BabaTelefon': '05327778899',
      }, where: 'OgrenciId=1');
      expect((await veli()).normalizeTelefon, isNull);
      expect((await veli()).veliTuru, isNull);
      await db.update('Ogrenci', {'VeliTuru': 'Diger'}, where: 'OgrenciId=1');
      expect((await veli()).normalizeTelefon, isNull);
      expect((await veli()).veliTuru, 'Diger');
    },
  );
  test(
    'ön izlemeden sonra anne telefonu tamamlanırsa eski baba onayıyla gönderilmez',
    () async {
      await db.update('Ogrenci', {'AnneTelefon': ''}, where: 'OgrenciId=1');
      final k = await veli();
      final q = await service.kisilerleKuyrukOlustur(
        b,
        MesajKisiOnIzleme([k]),
        'Bilgi',
        kaynakModul: 'Mesajlasma',
      );
      await db.update('Ogrenci', {
        'AnneTelefon': '05324445566',
      }, where: 'OgrenciId=1');
      await expectLater(
        service.aliciyiAc(b, q.id, q.alicilar.single.id),
        throwsStateError,
      );
      await expectLater(
        service.tekliGonder(
          b,
          'Bilgi',
          kisiler: MesajKisiOnIzleme([k]),
          sms: false,
          kaynakModul: 'Mesajlasma',
        ),
        throwsStateError,
      );
      expect(gonderilen, isEmpty);
    },
  );

  Future<void> tikla(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      final scroll = find.byType(Scrollable).first;
      t.state<ScrollableState>(scroll).position.jumpTo(0);
      await t.pumpAndSettle();
      if (f.evaluate().isEmpty) {
        await t.scrollUntilVisible(f, 160, scrollable: scroll);
      }
    }
    await t.ensureVisible(f.last);
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(f.last);
    await t.pump(const Duration(milliseconds: 350));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
    if (find.byType(AlertDialog).evaluate().isEmpty &&
        find.byType(SimpleDialog).evaluate().isEmpty) {
      await t.pumpAndSettle();
    }
  }

  for (final kaynak in [false, true]) {
    testWidgets(
      'ön izleme baba numarasını ve kullanım gerekçesini gösterir (kaynak=$kaynak)',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await db.update('Ogrenci', {'AnneTelefon': ''}, where: 'OgrenciId=1');
        await t.pumpWidget(
          MaterialApp(
            home: MesajlasmaScreen(
              service: service,
              kaynakModul: kaynak ? 'Test' : 'Mesajlasma',
              baslangicOgrenciIdleri: kaynak ? const {1} : const {},
              baslangicMetni: 'Bilgi',
            ),
          ),
        );
        await t.pumpAndSettle();
        if (!kaynak) {
          await tikla(t, find.byType(DropdownButton<int>));
          await tikla(t, find.text('9-C').last);
          await tikla(t, find.text('Alıcı grubu'));
          await tikla(t, find.text('Sınıf öğrencileri'));
          await tikla(t, find.text('Velisi'));
          await tikla(t, find.text('Öğrenci listesi (0/1 seçili)'));
          await tikla(t, find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')));
        }
        await tikla(t, find.text('Ön İzle ve Onayla'));
        expect(find.text('1 / 1 kişi'), findsNothing);
        expect(find.text('Mesajı gönder'), findsOneWidget);
        expect(
          find.textContaining('Baba telefonu kullanılıyor'),
          findsOneWidget,
        );
        expect(find.textContaining('+905327778899'), findsOneWidget);
        expect(find.textContaining('Baba Adı'), findsWidgets);
        expect(find.textContaining('Veli (Baba)'), findsOneWidget);
        expect(gonderilen, isEmpty);
        expect((await db.query('Ogrenci')).single['VeliTuru'], 'Anne');
        await tikla(t, find.byTooltip('Telefonu düzenle'));
        await t.enterText(
          find.byKey(const ValueKey('mesaj-kisi-ad')),
          'Yeni Baba',
        );
        await t.enterText(
          find.byKey(const ValueKey('mesaj-kisi-telefon')),
          '05321110000',
        );
        await tikla(t, find.text('Kaydet'));
        expect(find.text('Mesajı gönder'), findsOneWidget);
        expect(find.textContaining('+905321110000'), findsOneWidget);
        expect(
          find.textContaining('Baba telefonu kullanılıyor'),
          findsOneWidget,
        );
        final kayit = (await db.query('Ogrenci')).single;
        expect(kayit['BabaTelefon'], '05321110000');
        expect(kayit['BabaAdi'], 'Yeni Baba');
        expect(find.textContaining('Veli (Baba) • Yeni Baba'), findsOneWidget);
        expect(kayit['AnneTelefon'], '');
        expect(kayit['Telefon'], '');
        expect(kayit['VeliTuru'], 'Anne');
        await tikla(t, find.text('Düzelt'));
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final tur in ['Anne', 'Baba', 'Diger']) {
    for (final kaynak in [false, true]) {
      testWidgets('ön izlemede veli türü açık yazılır: $tur (kaynak=$kaynak)', (
        t,
      ) async {
        await db.update('Ogrenci', {
          'VeliTuru': tur,
          'BabaAdi': tur == 'Baba' ? '' : 'Baba Adı',
          'VeliAdi': 'Diğer Kişi',
          'VeliTelefonu': '05320000000',
        }, where: 'OgrenciId=1');
        await t.pumpWidget(
          MaterialApp(
            home: MesajlasmaScreen(
              service: service,
              kaynakModul: kaynak ? 'Test' : 'Mesajlasma',
              baslangicOgrenciIdleri: kaynak ? const {1} : const {},
              baslangicMetni: 'Bilgi',
            ),
          ),
        );
        await t.pumpAndSettle();
        if (!kaynak) {
          await tikla(t, find.byType(DropdownButton<int>));
          await tikla(t, find.text('9-C').last);
          await tikla(t, find.text('Alıcı grubu'));
          await tikla(t, find.text('Sınıf öğrencileri'));
          await tikla(t, find.text('Velisi'));
          await tikla(t, find.text('Öğrenci listesi (0/1 seçili)'));
          await tikla(t, find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')));
        }
        await tikla(t, find.text('Ön İzle ve Onayla'));
        expect(
          find.textContaining('Veli (${tur == 'Diger' ? 'Diğer veli' : tur})'),
          findsOneWidget,
        );
        if (!kaynak) {
          expect(find.text('1 alıcı • 1 telefon numarası'), findsOneWidget);
          expect(find.textContaining('0 tekrar'), findsNothing);
          expect(find.textContaining('0 kişi atlandı'), findsNothing);
        }
        expect(gonderilen, isEmpty);
        final onceki = (await db.query('Ogrenci')).single;
        await tikla(t, find.byTooltip('Telefonu düzenle'));
        final isim = find.byKey(const ValueKey('mesaj-kisi-ad'));
        expect(
          t.widget<TextField>(isim).controller!.text,
          tur == 'Baba'
              ? ''
              : tur == 'Anne'
              ? 'Anne Adı'
              : 'Diğer Kişi',
        );
        await t.enterText(isim, 'Yeni $tur');
        final alan = find.byKey(const ValueKey('mesaj-kisi-telefon'));
        await t.enterText(alan, 'abc');
        await tikla(t, find.text('Kaydet'));
        expect(
          find.text('Geçerli tek telefon numarası girin.'),
          findsOneWidget,
        );
        expect((await db.query('Ogrenci')).single, onceki);
        await t.enterText(alan, '05321110000');
        await tikla(t, find.text('Kaydet'));
        expect(find.text('Mesajı gönder'), findsOneWidget);
        expect(find.textContaining('+905321110000'), findsOneWidget);
        final alanAdi = tur == 'Diger' ? 'VeliTelefonu' : '${tur}Telefon';
        final sonraki = (await db.query('Ogrenci')).single;
        expect(sonraki[alanAdi], '05321110000');
        expect(sonraki[tur == 'Diger' ? 'VeliAdi' : '${tur}Adi'], 'Yeni $tur');
        expect(
          find.textContaining(
            'Veli (${tur == 'Diger' ? 'Diğer veli' : tur}) • Yeni $tur',
          ),
          findsOneWidget,
        );
        for (final key in [
          'Telefon',
          'AnneTelefon',
          'BabaTelefon',
          'VeliTelefonu',
          'VeliTuru',
        ]) {
          if (key != alanAdi) expect(sonraki[key], onceki[key]);
        }
        await tikla(t, find.byTooltip('Telefonu düzenle'));
        await t.enterText(
          find.byKey(const ValueKey('mesaj-kisi-telefon')),
          '05329990000',
        );
        await tikla(t, find.text('Vazgeç'));
        expect(find.textContaining('+905321110000'), findsOneWidget);
        expect((await db.query('Ogrenci')).single[alanAdi], '05321110000');
        await tikla(t, find.text('Düzelt'));
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final kaynak in [false, true]) {
    testWidgets(
      'ön izlemede öğrencinin kendi telefonu güncellenir (kaynak=$kaynak)',
      (t) async {
        await db.update('Ogrenci', {
          'Telefon': '05321112233',
        }, where: 'OgrenciId=1');
        final ogrenciService = kaynak
            ? MesajlasmaService(
                databaseGetir: () async => db,
                modGetir: () async => CalismaModu.bireyselOgretmen,
                ogrenciTelefonu: true,
              )
            : service;
        await t.pumpWidget(
          MaterialApp(
            home: MesajlasmaScreen(
              service: ogrenciService,
              kaynakModul: kaynak ? 'Test' : 'Mesajlasma',
              ogrenciTelefonu: kaynak,
              baslangicOgrenciIdleri: kaynak ? const {1} : const {},
              baslangicMetni: 'Bilgi',
            ),
          ),
        );
        await t.pumpAndSettle();
        if (!kaynak) {
          await tikla(t, find.byType(DropdownButton<int>));
          await tikla(t, find.text('9-C').last);
          await tikla(t, find.text('Alıcı grubu'));
          await tikla(t, find.text('Sınıf öğrencileri'));
          await tikla(t, find.text('Kendisi'));
          await tikla(t, find.text('Öğrenci listesi (0/1 seçili)'));
          await tikla(t, find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')));
        }
        await tikla(t, find.text('Ön İzle ve Onayla'));
        await tikla(t, find.byTooltip('Telefonu düzenle'));
        await t.enterText(
          find.byKey(const ValueKey('mesaj-kisi-telefon')),
          '05321110000',
        );
        await tikla(t, find.text('Kaydet'));
        expect(find.text('Mesajı gönder'), findsOneWidget);
        expect(find.textContaining('+905321110000'), findsOneWidget);
        final kayit = (await db.query('Ogrenci')).single;
        expect(kayit['Telefon'], '05321110000');
        expect(kayit['AnneTelefon'], '05324445566');
        expect(kayit['BabaTelefon'], '05327778899');
        await tikla(t, find.text('Düzelt'));
        expect(t.takeException(), isNull);
      },
    );
  }
}
