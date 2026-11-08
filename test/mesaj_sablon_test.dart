import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/screens/mesaj_sablon_ayarlar_screen.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  var gonderim = 0;
  Completer<void>? whatsappBekle;
  var whatsappHata = false;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    gonderim = 0;
    whatsappBekle = null;
    whatsappHata = false;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
      whatsappAc: (_, _) async {
        gonderim++;
        if (whatsappHata) throw StateError('WhatsApp açılamadı');
        await whatsappBekle?.future;
      },
      smsIzni: () async => true,
      smsGonder: (_, _) async {
        gonderim++;
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
        'SinifKodu': i == 1
            ? '9/A'
            : i == 2
            ? '9/B'
            : '9/C',
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
    }
    for (var i = 1; i <= 4; i++) {
      await db.insert('Ogrenci', {
        'OgrenciId': i,
        'OkulNo': '00$i',
        'Ad': 'Öğrenci$i',
        'Soyad': 'Test',
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
        'SinifSubeId': i <= 2
            ? 1
            : i == 3
            ? 2
            : 3,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
  });
  tearDown(LocalDatabase.instance.close);

  test(
    'gruplar ayrı; ekleme düzenleme silme yeniden okumada kalıcıdır',
    () async {
      final b = await service.hazirla();
      var p = await service.hazirMesajlariGetir(b);
      expect(
        p.sablonlar.map((s) => s.tur).toSet(),
        MesajKisiTuru.values.toSet(),
      );
      final veli = p.sablonlar
          .where((s) => s.tur == MesajKisiTuru.veli)
          .toList();
      p = await service.hazirMesajKaydet(
        b,
        beklenen: p,
        tur: MesajKisiTuru.ogretmen,
        baslik: 'Özel duyuru',
        metin: 'Duyuru {Tarih}',
      );
      final yeni = p.sablonlar.singleWhere((s) => s.baslik == 'Özel duyuru');
      p = await service.hazirMesajKaydet(
        b,
        beklenen: p,
        eski: yeni,
        tur: MesajKisiTuru.ogrenci,
        baslik: 'Öğrenci özel',
        metin: 'Yeni içerik',
      );
      final duzenlenen = p.sablonlar.singleWhere((s) => s.id == yeni.id);
      expect(duzenlenen.tur, MesajKisiTuru.ogrenci);
      expect(
        p.sablonlar
            .where((s) => s.tur == MesajKisiTuru.veli)
            .map((s) => s.json),
        veli.map((s) => s.json),
      );
      final eski = p.sablonlar.first;
      p = await service.hazirMesajSil(b, beklenen: p, eski: eski);
      final yeniden = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final okunan = await yeniden.hazirMesajlariGetir(b);
      expect(okunan.sablonlar.any((s) => s.id == eski.id), false);
      expect(
        okunan.sablonlar.singleWhere((s) => s.id == yeni.id).metin,
        'Yeni içerik',
      );
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(gonderim, 0);
    },
  );

  test('silinen son mesaj yeniden varsayılan olarak eklenmez', () async {
    final b = await service.hazirla();
    var p = await service.hazirMesajlariGetir(b);
    for (final s in p.sablonlar.toList()) {
      p = await service.hazirMesajSil(b, beklenen: p, eski: s);
    }
    expect((await service.hazirMesajlariGetir(b)).sablonlar, isEmpty);
  });

  test('boş uzun tekrar başlık ve yanlış değişken yazılmaz', () async {
    final b = await service.hazirla(),
        p = await service.hazirMesajlariGetir(await service.hazirla());
    for (final mesaj in [
      '',
      'x' * 4001,
      '{Bilinmeyen}',
      '{Tarih',
      '{OgrenciAdi}',
    ]) {
      await expectLater(
        service.hazirMesajKaydet(
          b,
          beklenen: p,
          tur: MesajKisiTuru.ogretmen,
          baslik: 'Başlık',
          metin: mesaj,
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      service.hazirMesajKaydet(
        b,
        beklenen: p,
        tur: MesajKisiTuru.veli,
        baslik: 'Veli toplantısı',
        metin: 'Yeni',
      ),
      throwsStateError,
    );
    expect(
      await db.query(
        'UygulamaAyarlari',
        where: 'Anahtar LIKE ?',
        whereArgs: ['mesaj_sablonlari:%'],
      ),
      isEmpty,
    );
  });

  test(
    'eski düzenleme kaybı ve yanlış okul profil erişimi engellenir',
    () async {
      final b = await service.hazirla(),
          p = await service.hazirMesajlariGetir(await service.hazirla());
      await service.hazirMesajKaydet(
        b,
        beklenen: p,
        tur: MesajKisiTuru.veli,
        baslik: 'Yeni',
        metin: 'İçerik',
      );
      await expectLater(
        service.hazirMesajSil(b, beklenen: p, eski: p.sablonlar.first),
        throwsStateError,
      );
      await db.update('OkulProfil', {'OkulId': 'diger'});
      await expectLater(service.hazirMesajlariGetir(b), throwsStateError);
      final diger = await service.hazirla();
      expect(
        (await service.hazirMesajlariGetir(
          diger,
        )).sablonlar.any((s) => s.baslik == 'Yeni'),
        false,
      );
      await expectLater(
        service.hazirMesajKaydet(
          diger,
          beklenen: p,
          tur: MesajKisiTuru.veli,
          baslik: 'Yeni2',
          metin: 'İçerik',
        ),
        throwsStateError,
      );
    },
  );

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
    await t.tap(f.last);
    await t.pumpAndSettle();
  }

  Future<void> kaydet(WidgetTester t) async {
    await t.runAsync(() async {
      await t.ensureVisible(find.text('Kaydet').last);
      await t.tap(find.text('Kaydet').last);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await t.pumpAndSettle();
  }

  testWidgets('ayarlar: dar ekranda ekle oku düzenle sil ve iptal', (t) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final b = await service.hazirla();
    await t.pumpWidget(
      MaterialApp(
        home: MesajSablonAyarlarScreen(service: service, baglam: b),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, find.byTooltip('Yeni hazır mesaj'));
    await t.enterText(
      find.byKey(const ValueKey('sablon-baslik')),
      'Yeni veli mesajı',
    );
    await t.enterText(
      find.byKey(const ValueKey('sablon-metin')),
      'Özel mesaj {Tarih}',
    );
    await kaydet(t);
    var p = await service.hazirMesajlariGetir(b);
    final s = p.sablonlar.singleWhere((s) => s.baslik == 'Yeni veli mesajı');
    final row = find.byKey(ValueKey('sablon-${s.id}'));
    await t.scrollUntilVisible(
      row,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(t, row);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('sablon-metin')))
          .controller!
          .text,
      'Özel mesaj {Tarih}',
    );
    await t.enterText(find.byKey(const ValueKey('sablon-metin')), 'Düzenlendi');
    await kaydet(t);
    expect(
      (await service.hazirMesajlariGetir(
        b,
      )).sablonlar.singleWhere((x) => x.id == s.id).metin,
      'Düzenlendi',
    );
    await tap(t, row);
    await t.enterText(
      find.byKey(const ValueKey('sablon-metin')),
      'İptal edilecek',
    );
    await tap(t, find.text('Vazgeç'));
    final sil = find.descendant(
      of: row,
      matching: find.byTooltip('Hazır mesajı sil'),
    );
    await tap(t, sil);
    await tap(t, find.text('Vazgeç'));
    expect(
      (await service.hazirMesajlariGetir(
        b,
      )).sablonlar.singleWhere((x) => x.id == s.id).metin,
      'Düzenlendi',
    );
    await tap(t, sil);
    await t.runAsync(() async {
      await t.tap(find.text('Sil').last);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await t.pumpAndSettle();
    expect(
      (await service.hazirMesajlariGetir(b)).sablonlar.any((x) => x.id == s.id),
      false,
    );
    expect(t.takeException(), isNull);
    expect(gonderim, 0);
  });

  testWidgets('mesaj ekranında ayarlar ve alıcı grubuna uygun hazır mesajlar', (
    t,
  ) async {
    await t.pumpWidget(MaterialApp(home: MesajlasmaScreen(service: service)));
    await t.pumpAndSettle();
    expect(find.byTooltip('Hazır mesaj ayarları'), findsOneWidget);
    await tap(t, find.byType(DropdownButton<int>));
    await tap(t, find.text('9/A').last);
    await tap(t, find.text('Alıcı grubu'));
    await tap(t, find.text('Sınıf öğrencileri'));
    await tap(t, find.text('Kendisi'));
    Future<void> hazir() async {
      final f = find.byType(DropdownButton<String>);
      final scroll = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(f, 180, scrollable: scroll);
      await tap(t, f);
    }

    await hazir();
    expect(find.text('Öğrenci ödev hatırlatması'), findsOneWidget);
    expect(find.text('Veli toplantısı'), findsNothing);
    await tap(t, find.text('Öğrenci ödev hatırlatması'));
    final metin = find.byKey(const ValueKey('mesaj-metni'));
    await t.scrollUntilVisible(
      metin,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      t.widget<TextField>(metin).controller!.text,
      contains('Sevgili öğrencimiz'),
    );
    await tap(t, find.byTooltip('Hazır mesaj ayarları'));
    expect(find.text('Hazır mesaj ayarları'), findsOneWidget);
    expect(find.text('Öğrenci ödev hatırlatması'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    Future<void> basaDon() async {
      final scroll = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      t.state<ScrollableState>(scroll).position.jumpTo(0);
      await t.pumpAndSettle();
    }

    await basaDon();
    await tap(t, find.byKey(const ValueKey('mesaj-ogrenci-hedef-basligi')));
    await tap(t, find.text('Velisi'));
    await hazir();
    expect(find.text('Veli toplantısı'), findsOneWidget);
    expect(find.text('Öğrenci ödev hatırlatması'), findsNothing);
    await tap(t, find.text('Hazır mesaj seçin').last);
    await t.scrollUntilVisible(
      metin,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      t.widget<TextField>(metin).controller!.text,
      contains('Sevgili öğrencimiz'),
    );
    await t.runAsync(() async {
      await service.ogretmenIletisimKaydet(
        await service.hazirla(),
        ad: 'Ders öğretmeni',
        sinifIdleri: {1},
        sinifIliskileriniDogruladim: true,
      );
    });
    await tap(t, find.byTooltip('Yenile'));
    await basaDon();
    await tap(t, find.text('Alıcı grubu'));
    await tap(t, find.text('Sınıfta derse giren öğretmenler'));
    await hazir();
    expect(find.text('Öğretmen toplantısı'), findsOneWidget);
    expect(find.text('Veli toplantısı'), findsNothing);
    await tap(t, find.text('Öğretmen toplantısı'));
    await t.scrollUntilVisible(
      metin,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      t.widget<TextField>(metin).controller!.text,
      contains('Değerli öğretmenim'),
    );

    expect(t.takeException(), isNull);
  });
}
