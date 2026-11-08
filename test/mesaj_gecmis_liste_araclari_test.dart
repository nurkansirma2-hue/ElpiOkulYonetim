import 'dart:convert';
import 'package:elpi_okul_yonetim/widgets/ortak_ui.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'package:elpi_okul_yonetim/widgets/ortak_liste_arac_cubugu.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'package:elpi_okul_yonetim/widgets/modul_ust_bar.dart';
import 'package:elpi_okul_yonetim/widgets/mesajlasma_gorunumu.dart';
import 'support/windows_memory_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  var gonderim = 0;
  setUpAll(() async {
    // Yerleşimi Flutter testinin Ahem bloklarıyla değil, uygulamanın gerçek
    // yazı tipiyle doğrula; görsel kaydetme bayrağı geometriyi değiştirmesin.
    for (final family in ['NotoSans', 'Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    await BireyselProfilService.kaydet(
      adSoyad: 'Deniz Öğretmen',
      brans: 'Matematik',
      okulAdi: 'Test Okulu',
      okulKisaAdi: 'TO',
      egitimOgretimYili: '2026-2027',
      donem: 1,
      meslekPaketiAktif: false,
    );
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    for (final id in [1, 2]) {
      await db.insert('SinifSube', {
        'SinifSubeId': id,
        'SinifKodu': id == 1 ? '9-C' : '10-D',
        'SinifSeviyesi': id == 1 ? 9 : 10,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': id,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    for (var i = 1; i <= 3; i++) {
      await db.insert('Ogrenci', {
        'OgrenciId': i,
        'OkulNo': '$i',
        'Ad': ['Ada', 'Çağla', 'Zeynep'][i - 1],
        'Soyad': 'Yılmaz',
        'Telefon': '0532000${i.toString().padLeft(4, '0')}',
        'AnneAdi': 'Anne $i',
        'AnneTelefon': i == 1 ? '' : '0532000${i.toString().padLeft(4, '0')}',
        'BabaAdi': 'Baba $i',
        'BabaTelefon': '05321112233',
        'VeliTuru': 'Anne',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': i == 3 ? 2 : 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    gonderim = 0;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
      whatsappAc: (_, _) async {
        gonderim++;
      },
      smsIzni: () async => true,
      smsGonder: (_, _) async {
        gonderim++;
        return 1;
      },
    );
    ModulUstBarBaglantisi.aktif = ModulUstBarBaglantisi(
      sahip: service,
      ayarlar: () async {},
      profil: () async {},
      bildirimler: () async {},
    );
  });
  tearDown(() async {
    ModulUstBarBaglantisi.aktif = null;
    await LocalDatabase.instance.close();
  });
  Finder getScroll() => find
      .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
      .first;
  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      t.state<ScrollableState>(getScroll()).position.jumpTo(0);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        f,
        150,
        scrollable: getScroll(),
        maxScrolls: 80,
      );
    }
    await t.ensureVisible(f.last);
    await t.pump(const Duration(milliseconds: 300));
    final checked = find.ancestor(
      of: f.last,
      matching: find.byType(CheckedPopupMenuItem<int>),
    );
    await t.tap(checked.evaluate().isNotEmpty ? checked.last : f.last);
    await t.pump(const Duration(milliseconds: 350));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump();
    for (
      var i = 0;
      i < 40 &&
          find.byType(AlertDialog).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    if (find.byType(AlertDialog).evaluate().isEmpty &&
        find.byType(SimpleDialog).evaluate().isEmpty) {
      await t.pumpAndSettle();
    }
  }

  Future<void> ac(
    WidgetTester t, {
    double width = 390,
    double yazi = 1,
    Brightness brightness = Brightness.light,
  }) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('mesaj-gorsel'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AnaSayfaTemasi.mavi.olustur(brightness),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(yazi)),
            child: child!,
          ),
          home: MesajlasmaScreen(service: service),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> gorsel(WidgetTester t, String name) async {
    if (!const bool.fromEnvironment('MESAJ_GORSEL')) return;
    await t.runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('mesaj-gorsel')),
      );
      final img = await boundary.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File('build/mesaj_arayuz/$name.png');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(data!.buffer.asUint8List());
      img.dispose();
    });
  }

  Future<void> gecmisHazirla() async {
    final b = await service.hazirla();
    final adaylar = await service.aliciAdaylari(b, tur: MesajKisiTuru.ogrenci);
    for (final id in [1, 2]) {
      await service.tekliGonder(
        b,
        'Örnek mesaj $id',
        kisiler: MesajKisiOnIzleme(adaylar.where((k) => k.kisiId == '$id')),
        sms: id == 2,
        kaynakModul: 'Mesajlasma',
      );
      await db.update(
        'MesajTekliGecmis',
        {'Tarih': id == 1 ? '2026-10-02T12:00:00' : '2026-10-01T12:00:00'},
        where: 'OgrenciId = ?',
        whereArgs: [id],
      );
    }
    final q = await service.kisilerleKuyrukOlustur(
      b,
      MesajKisiOnIzleme(adaylar.where((k) => k.kisiId == '3')),
      'Toplu mesaj',
      kaynakModul: 'Mesajlasma',
    );
    await db.update(
      'MesajKuyrugu',
      {'OlusturmaTarihi': '2026-10-03T12:00:00'},
      where: 'KuyrukId = ?',
      whereArgs: [q.id],
    );
  }

  List<String> basliklar(WidgetTester t) => t
      .widgetList<ListTile>(
        find.descendant(
          of: find.byType(MesajGecmisKarti),
          matching: find.byType(ListTile),
        ),
      )
      .map((w) => (w.title! as Text).data!)
      .toList();
  Future<void> gecmisAc(
    WidgetTester t, {
    double width = 390,
    double yazi = 1,
  }) async {
    await gecmisHazirla();
    await ac(t, width: width, yazi: yazi);
    await tap(t, find.text('Gönderim Geçmişi'));
  }

  Future<void> sirala(WidgetTester t, String ad) async {
    await tap(t, find.byTooltip('Sırala'));
    await tap(t, find.text(ad));
  }

  test('Türkçe arama ve sıralama ortak yardımcıları', () {
    expect(listeAramaMetni('IŞIK İĞDE ÇAĞLA'), 'isik igde cagla');
    expect(listeTurkceKarsilastir('Cem', 'Çağla'), lessThan(0));
    expect(listeTurkceKarsilastir('Işık', 'İpek'), lessThan(0));
  });
  testWidgets(
    'tekli ve toplu geçmiş birlikte sıralanır; arama kapanınca korunur',
    (t) async {
      await gecmisAc(t);
      expect(basliklar(t).map((s) => s.split(' • ').last), [
        'Zeynep Yılmaz',
        'Ada Yılmaz',
        'Çağla Yılmaz',
      ]);
      expect(find.byTooltip('Yenile'), findsNothing);
      expect(find.byTooltip('Hazır mesaj ayarları'), findsNothing);
      expect(find.byTooltip('Geçmiş işlemleri'), findsOneWidget);
      expect(find.byType(OrtakIslemCubugu), findsOneWidget);
      await gorsel(t, 'gecmis-yeni');
      await sirala(t, 'Tarih: eskiden yeniye');
      expect(basliklar(t).first, contains('Çağla'));
      await sirala(t, 'Öğrenci / alıcı adı (A–Z)');
      expect(basliklar(t).map((s) => s.split(' • ').last), [
        'Ada Yılmaz',
        'Çağla Yılmaz',
        'Zeynep Yılmaz',
      ]);
      await sirala(t, 'Öğrenci / alıcı adı (Z–A)');
      expect(basliklar(t).first, contains('Zeynep'));
      await tap(t, find.text('Ara'));
      await t.enterText(
        find.byKey(const ValueKey('gonderim-gecmisi-arama')),
        'CAGLA',
      );
      await t.pumpAndSettle();
      expect(basliklar(t).single, contains('Çağla'));
      await tap(t, find.text('Ara'));
      expect(basliklar(t), hasLength(1));
      await tap(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      expect(find.text('1 seçili'), findsOneWidget);
      await tap(t, find.text('Ara'));
      await tap(t, find.byTooltip('Aramayı temizle'));
      expect(basliklar(t), hasLength(3));
      expect(find.text('0 seçili'), findsOneWidget);
      expect(gonderim, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'kanal ve durum filtreleri görünür seçim ile onay kapsamını korur',
    (t) async {
      await gecmisAc(t);
      await tap(t, find.text('Filtrele'));
      await tap(t, find.byKey(const ValueKey('gecmis-kanal-null')));
      await tap(t, find.text('SMS').last);
      expect(basliklar(t).single, contains('Çağla'));
      await tap(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      expect(find.text('1 seçili'), findsOneWidget);
      expect(
        t
            .widget<IconButton>(find.byKey(const ValueKey('gecmisi-onayla')))
            .onPressed,
        isNull,
      );
      await tap(t, find.byKey(const ValueKey('gecmis-kanal-SMS')));
      await tap(t, find.text('WhatsApp').last);
      expect(find.text('0 seçili'), findsOneWidget);
      expect(basliklar(t), hasLength(2));
      await tap(t, find.byKey(const ValueKey('gecmis-durum-null')));
      await tap(t, find.text('Onay bekliyor').last);
      expect(basliklar(t).single, contains('Ada'));
      await gorsel(t, 'gecmis-filtreler');
      await tap(t, find.text('Filtrele'));
      expect(basliklar(t), hasLength(1));
      await tap(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      await tap(t, find.byKey(const ValueKey('gecmisi-onayla')));
      expect(
        (await db.query(
          'MesajTekliGecmis',
          where: 'OgrenciId=1',
        )).single['Durum'],
        'Istendi',
      );
      expect(basliklar(t), isEmpty);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Filtrele'));
      await tap(t, find.text('Filtreleri temizle'));
      expect(find.text('3 kayıt'), findsOneWidget);
      expect(gonderim, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('320 px büyük yazıda araç çubuğu, arama ve filtreler taşmaz', (
    t,
  ) async {
    await gecmisAc(t, width: 320, yazi: 1.7);
    await tap(t, find.text('Ara'));
    await tap(t, find.text('Filtrele'));
    await gorsel(t, 'gecmis-dar-ekran');
    expect(t.takeException(), isNull);
    await t.enterText(
      find.byKey(const ValueKey('gonderim-gecmisi-arama')),
      'bulunmayan',
    );
    await t.pumpAndSettle();
    await tap(t, find.text('Filtrele'));
    expect(find.text('Gönderim kaydı bulunamadı.'), findsOneWidget);
    expect(
      t
          .widget<TextButton>(find.byKey(const ValueKey('gecmis-tumunu-sec')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'tarih aralığı başlangıç ve bitiş gününü kapsar, temizlenebilir',
    (t) async {
      await gecmisAc(t);
      await tap(t, find.text('Filtrele'));
      await tap(t, find.byKey(const ValueKey('gecmis-tarih')));
      await tap(t, find.byTooltip('Switch to input'));
      final alanlar = find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byType(TextField),
      );
      await t.enterText(alanlar.at(0), '10/02/2026');
      await t.enterText(alanlar.at(1), '10/02/2026');
      await tap(t, find.text('Uygula'));
      expect(basliklar(t).single, contains('Ada'));
      await tap(t, find.text('Filtreleri temizle'));
      expect(find.text('3 kayıt'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'uzun öğretmen ve ders kartları kayar; son kayıt tek çubuğun üstünde kalır',
    (t) async {
      await gecmisHazirla();
      const uzunAd =
          'AYSUN TAŞDEMİR / BİLAL KUNDAKÇI / DERYA KAĞIT / ENGİN ÖĞRETMEN';
      await db.update('MesajAlici', {
        'AliciAdi': uzunAd,
        'Ogrenciler': jsonEncode([
          {'id': 3, 'aciklama': '9-C • DİN KÜLTÜRÜ VE AHLAK BİLGİSİ 9'},
        ]),
      });
      await ac(t);
      await tap(t, find.text('Gönderim Geçmişi'));
      expect(find.byType(OrtakIslemCubugu), findsOneWidget);
      await tap(t, find.text('Filtrele'));
      await gorsel(t, 'gecmis-ui-filtreler');
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('gonderim-gecmisi-liste')),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('gecmis-tumunu-sec')),
        150,
        scrollable: scroll,
      );
      final position = t.state<ScrollableState>(scroll).position;
      position.jumpTo(position.maxScrollExtent);
      await t.pumpAndSettle();
      await gorsel(t, 'gecmis-ui-liste');
      final footer = t.getTopLeft(find.byType(OrtakListeAracCubugu<int>)).dy;
      final last = t.getBottomRight(find.byType(MesajGecmisKarti).last).dy;
      expect(last, lessThanOrEqualTo(footer));
      expect(t.takeException(), isNull);
    },
  );

  for (final width in [320.0, 800.0]) {
    testWidgets('geçmiş koyu temada $width px genişlikte tek çubukla açılır', (
      t,
    ) async {
      await gecmisHazirla();
      await ac(t, width: width, brightness: Brightness.dark);
      await tap(t, find.text('Gönderim Geçmişi'));
      await tap(t, find.text('Filtrele'));
      expect(find.byType(OrtakIslemCubugu), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('genel geçmiş yalnız bu sayfanın tekli ve toplu kayıtlarını gösterir', (t) async {
    await gecmisHazirla();
    final b = await service.hazirla();
    final kisi = (await service.aliciAdaylari(b, tur: MesajKisiTuru.ogrenci)).first;
    await service.tekliGonder(b, 'Dış modülün tekli mesajı',
      kisiler: MesajKisiOnIzleme([kisi]), sms:false, kaynakModul:'DigerModul');
    final q = await service.kisilerleKuyrukOlustur(b,
      MesajKisiOnIzleme([kisi]), 'Dış modülün toplu mesajı', kaynakModul:'DigerModul');
    await ac(t);
    await tap(t, find.text('Gönderim Geçmişi'));
    expect(find.text('3 kayıt'), findsOneWidget);
    expect(find.textContaining('Dış modülün'), findsNothing);
    await tap(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
    expect(find.text('3 seçili'), findsOneWidget);
    expect(await db.query('MesajTekliGecmis',where:'KaynakModul=?',whereArgs:['DigerModul']),hasLength(1));
    expect((await service.kuyrukGetir(b,q.id)).kaynakModul,'DigerModul');
    await tap(t, find.byTooltip('Geçmiş işlemleri'));
    expect(find.textContaining('Devam et: Dış modülün'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
