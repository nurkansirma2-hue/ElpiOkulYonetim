import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/odev_kontrol.dart';
import 'package:elpi_okul_yonetim/models/ders_uygulama.dart';
import 'package:elpi_okul_yonetim/services/bireysel_odev_kontrol_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_detay_screen.dart';
import 'package:elpi_okul_yonetim/screens/odev_tanim_screen.dart';
import 'package:elpi_okul_yonetim/screens/ders_uygulama_screen.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselListeOturumu o;
  late int gid, kid;
  late List<int> uygulamalar;
  setUpAll(() async {
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
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    await BireyselProfilService.kaydet(
      adSoyad: 'Öğretmen',
      brans: 'Bilişim',
      okulAdi: 'Okul',
      okulKisaAdi: 'O',
      egitimOgretimYili: '2026-2027',
      donem: 1,
      meslekPaketiAktif: false,
    );
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Programlama',
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
    for (final (id, ad, soyad) in [
      (1, 'Merve', 'Akyüz'),
      (2, 'Melike', 'Akyüz'),
      (3, 'İbrahim Alperen', 'Öztürk'),
    ]) {
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '${1831 + id}',
        'Ad': ad,
        'Soyad': soyad,
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
      baslik: '10 D Ders Uygulamaları',
      baslangicTarihi: DateTime(2026, 11, 5),
      ogrenciIdleri: [1, 2, 3],
      kontrolBaslat: true,
    );
    kid = (await BireyselOdevKontrolService.kontroller(
      o,
      gid,
    )).single.odevKontrolId;
    uygulamalar = [];
    for (final ad in [
      'Değişkenler',
      'Veri Girişi',
      'If-Else',
      'Not Hesaplama',
      'Döngüler',
    ]) {
      uygulamalar.add(await DersUygulamaIslemleri.uygulamaKaydet(o, gid, ad));
    }
    await DersUygulamaIslemleri.sonuclariKaydet(o, kid, [
      for (final i in [0, 1, 2])
        UygulamaSonucGirdisi(
          1,
          uygulamalar[i],
          i == 2 ? OdevKontrolDurumu.kismen : OdevKontrolDurumu.yapti,
        ),
      for (var i = 0; i < 5; i++)
        UygulamaSonucGirdisi(
          2,
          uygulamalar[i],
          i == 1
              ? OdevKontrolDurumu.yapmadi
              : i == 4
              ? OdevKontrolDurumu.kismen
              : OdevKontrolDurumu.yapti,
        ),
    ]);
  });
  tearDown(LocalDatabase.instance.close);
  Future<void> ac(
    WidgetTester t, {
    double width = 390,
    double height = 900,
    double scale = 1,
    Brightness brightness = Brightness.light,
    Widget? home,
    bool detaylar = true,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('gorsel'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AnaSayfaTemasi.mavi.olustur(brightness),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home ?? OdevKontrolDetayScreen(oturum: o, odevId: gid),
        ),
      ),
    );
    await t.pumpAndSettle();
    if (detaylar && find.text('Tümünü Aç').evaluate().isNotEmpty) {
      await t.ensureVisible(find.text('Tümünü Aç'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tümünü Aç'));
      await t.pumpAndSettle();
    }
  }

  Future<void> tikla(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        150,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 500,
      );
    }
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> yukari(WidgetTester t) async {
    await t.drag(find.byType(CustomScrollView), const Offset(0, 4000));
    await t.pumpAndSettle();
  }

  Future<void> foto(WidgetTester t, String ad) async {
    if (!const bool.fromEnvironment('UYGULAMA_GORSEL')) return;
    await t.runAsync(() async {
      final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('gorsel')),
      );
      final im = await b.toImage(pixelRatio: 2);
      final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/ders_uygulama_gorsel');
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$ad.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      im.dispose();
    });
  }

  testWidgets('referans görünüm ve telefon yerleşimi', (t) async {
    expect((await BireyselOdevKontrolService.listeOzeti(o))[gid], {
      'toplam': 15,
      'girilen': 8,
    });
    await ac(t, width: 1000, detaylar: false);
    expect(find.byType(DersUygulamaScreen), findsOneWidget);
    expect(find.text('Uygulama Listesi'), findsOneWidget);
    await foto(t, 'genis');
    await ac(
      t,
      home: DersUygulamaScreen(key: UniqueKey(), oturum: o, odevId: gid),
      detaylar: false,
    );
    await foto(t, 'telefon');
    expect(t.takeException(), isNull);
  });
  testWidgets('uygulama ayarları ana sayfa başlığıyla daralır ve seçimi korur', (t) async {
    await ac(t);
    final panel=find.byKey(const ValueKey('uygulama-ayarlari'));
    await tikla(t,find.byType(DropdownButtonFormField<int>));
    await tikla(t,find.text('2. Veri Girişi').last);
    await tikla(t,find.descendant(of:panel,matching:find.byTooltip('Daralt')));
    expect(find.text('Uygulama Ekle'),findsNothing);
    expect(find.text('Adet (Katsayı)'),findsNothing);
    expect(find.text('Öğrenciler (3)'),findsOneWidget);
    await foto(t,'daraltilmis-ayarlar');
    await tikla(t,find.descendant(of:panel,matching:find.byTooltip('Genişlet')));
    await foto(t,'genisletilmis-ayarlar');
    expect(find.text('Uygulama Ekle'),findsOneWidget);
    expect(t.widget<DropdownButtonFormField<int>>(find.byType(DropdownButtonFormField<int>)).initialValue,uygulamalar[1]);
    expect(t.takeException(),isNull);
  });
  testWidgets('beş satırlı referans, yedi adet ve sabit kayıt alanı', (
    t,
  ) async {
    for (final id in [4, 5]) {
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '${1831 + id}',
        'Ad': id == 4 ? 'Kerem' : 'Elif',
        'Soyad': id == 4 ? 'Demir' : 'Yılmaz',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    await BireyselOdevKontrolService.gorevGuncelle(
      o,
      gid,
      gorevTuru: OdevGorevTuru.rutinKontrol,
      baslik: 'Ders Uygulamaları',
      baslangicTarihi: DateTime(2026, 11, 5),
      ogrenciIdleri: [1, 2, 3, 4, 5],
    );
    await DersUygulamaIslemleri.adetKaydet(o, gid, uygulamalar[2], 7);
    await DersUygulamaIslemleri.sonuclariKaydet(o, kid, [
      for (final (id, sayi, durum) in [
        (1, 6, OdevKontrolDurumu.yapti),
        (2, 5, OdevKontrolDurumu.yapti),
        (3, 4, OdevKontrolDurumu.kismen),
        (4, 2, OdevKontrolDurumu.yapmadi),
        (5, 0, OdevKontrolDurumu.gelmedi),
      ])
        UygulamaSonucGirdisi(id, uygulamalar[2], durum, yapilan: sayi, adet: 7),
    ]);
    await ac(t, width: 472, height: 833, detaylar: false);
    await tikla(t, find.byType(DropdownButtonFormField<int>));
    await tikla(t, find.text('3. If-Else').last);
    for (final ad in [
      'Merve Akyüz',
      'Melike Akyüz',
      'İbrahim Alperen Öztürk',
      'Kerem Demir',
    ]) {
      await tikla(t, find.byTooltip('$ad: yapılan artır'));
    }
    await yukari(t);
    await tikla(t,find.descendant(of:find.byKey(const ValueKey('uygulama-ayarlari')),matching:find.byTooltip('Daralt')));
    expect(find.text('Değişiklik var (4)'), findsOneWidget);
    expect(find.text('85,7'), findsOneWidget);
    expect(find.text('42,9'), findsOneWidget);
    expect(
      t.getRect(find.byKey(const ValueKey('uygulama-satir-5'))).bottom,
      lessThanOrEqualTo(
        t.getRect(find.byKey(const ValueKey('uygulama-icerik'))).bottom,
      ),
    );
    await foto(t, 'referans-472');
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'sayaç puanı, sonuç değişimi ve yeniden açmada altı bölü yedi korunur',
    (t) async {
      await DersUygulamaIslemleri.adetKaydet(o, gid, uygulamalar.first, 7);
      await ac(t, detaylar: false);
      await tikla(t, find.byTooltip('Merve Akyüz: yapılan azalt'));
      expect(find.text('6 / 7'), findsOneWidget);
      expect(find.text('85,7'), findsOneWidget);
      final satir = find.byKey(const ValueKey('uygulama-satir-1'));
      await tikla(
        t,
        find.descendant(of: satir, matching: find.byType(OutlinedButton)),
      );
      await tikla(t, find.text('Yarı'));
      expect(find.text('6 / 7'), findsOneWidget);
      expect(find.text('85,7'), findsOneWidget);
      await tikla(t, find.byKey(const ValueKey('uygulama-kaydet')));
      final sonuc = (await DersUygulamaIslemleri.gecmis(
        o,
        gid,
        guncel: true,
        ogrenciId: 1,
      )).firstWhere((s) => s.uygulamaId == uygulamalar.first);
      expect(sonuc.yapilan, 6);
      expect(sonuc.adet, 7);
      expect(sonuc.durum, OdevKontrolDurumu.kismen);
      await ac(
        t,
        detaylar: false,
        home: DersUygulamaScreen(key: UniqueKey(), oturum: o, odevId: gid),
      );
      expect(find.text('6 / 7'), findsOneWidget);
      expect(find.text('85,7'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  for (final boyut in [
    const Size(360, 800),
    const Size(420, 900),
    const Size(900, 450),
  ]) {
    testWidgets('sıkı düzen ve klavye $boyut boyutunda erişilebilir', (
      t,
    ) async {
      await ac(
        t,
        width: boyut.width,
        height: boyut.height,
        detaylar: false,
        home: DersUygulamaScreen(key: UniqueKey(), oturum: o, odevId: gid),
      );
      expect(t.takeException(), isNull);
      await tikla(t, find.text('Ara'));
      t.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await tikla(t, find.byKey(const ValueKey('uygulama-kaydet')));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('programdan kaldırılmış dersin ödev düzenleme kartı açılır', (
    t,
  ) async {
    final g = await BireyselOdevKontrolService.gorevGetir(o, gid);
    await db.insert('Ders', {
      'DersId': 2,
      'DersAdi': 'Başka ders',
      'OlusturmaTarihi': 'test',
    });
    await db.update('DersProgrami', {'DersId': 2});
    await ac(
      t,
      home: OdevTanimScreen(oturum: o, gorev: g),
    );
    expect(find.widgetWithText(TextFormField, 'Başlık'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('yeni ödev kartları 320 px $scale yazıda ve klavyede taşmaz', (
      t,
    ) async {
      await db.update('Ders', {'DersAdi': 'BİLGİSAYARLI TASARIM UYGULAMALARI'});
      await ac(
        t,
        width: 320,
        scale: scale,
        brightness: Brightness.dark,
        home: OdevTanimScreen(oturum: o),
      );
      expect(find.byKey(const ValueKey('odev-gorev-turu')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ogrenci-1')).hitTestable(),
        findsNothing,
      );
      await tikla(t, find.byKey(const ValueKey('odev-gorev-turu')));
      await tikla(t, find.text('Ders Uygulamaları').last);
      await tikla(t, find.widgetWithText(TextFormField, 'Başlık'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Başlık'),
        'Ders Uygulamaları',
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('odev-kaydet')).hitTestable(),
        findsOneWidget,
      );
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await tikla(t, find.byKey(const ValueKey('odev-ogrenci-secimi')));
      await tikla(t, find.byKey(const ValueKey('ogrenci-1')));
      expect(find.text('2/3 seçili'), findsOneWidget);
      await tikla(t, find.byKey(const ValueKey('odev-donem')));
      await tikla(t, find.text('1. dönem').last);
      await foto(t, 'yeni-odev-dar-$scale');
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('yeni ödev görünümü ve normal tür kaydı', (t) async {
    await db.update('Ders', {'DersAdi': 'BİLGİSAYARLI TASARIM UYGULAMALARI'});
    await ac(
      t,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => OdevTanimScreen(oturum: o)),
            ),
            child: const Text('Yeni Form'),
          ),
        ),
      ),
    );
    await tikla(t, find.text('Yeni Form'));
    await foto(t, 'yeni-odev-ust');
    await tikla(t, find.widgetWithText(TextFormField, 'Başlık'));
    await t.enterText(
      find.widgetWithText(TextFormField, 'Başlık'),
      'Kart düzeninde normal ödev',
    );
    await tikla(t, find.byKey(const ValueKey('odev-donem')));
    await tikla(t, find.text('1. dönem').last);
    await foto(t, 'yeni-odev-alt');
    await tikla(t, find.byKey(const ValueKey('odev-kaydet')));
    final kayit = (await db.query(
      'OdevTanim',
      where: 'Baslik=?',
      whereArgs: ['Kart düzeninde normal ödev'],
    )).single;
    expect(kayit['GorevTuru'], 'NormalOdev');
    expect(kayit['Donem'], 1);
    expect(kayit['DersUygulamalari'], 0);
    expect(
      await BireyselOdevKontrolService.katilimcilar(o, kayit['OdevId'] as int),
      hasLength(3),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('özel puan sınırı ve son öğrenci sabit çubuğun altında kalmaz', (
    t,
  ) async {
    for (var id = 4; id <= 40; id++) {
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '${2000 + id}',
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
    await BireyselOdevKontrolService.gorevGuncelle(
      o,
      gid,
      gorevTuru: OdevGorevTuru.rutinKontrol,
      baslik: '10 D Ders Uygulamaları',
      baslangicTarihi: DateTime(2026, 11, 5),
      ogrenciIdleri: List.generate(40, (i) => i + 1),
    );
    await ac(t);
    await tikla(
      t,
      find.byKey(ValueKey('uygulama-sonuc-1-${uygulamalar.first}')),
    );
    await tikla(t, find.text('Manuel puan'));
    await t.enterText(find.byKey(const ValueKey('uygulama-ozel-puan')), '11');
    await tikla(t, find.text('Uygula'));
    expect(find.text('0–10 arasında tam sayı girin.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('uygulama-ozel-puan')), '8');
    await tikla(t, find.text('Uygula'));
    await tikla(t, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(
      (await DersUygulamaIslemleri.gecmis(
        o,
        gid,
        ogrenciId: 1,
        guncel: true,
      )).first.notDegeri,
      8,
    );
    final son = find.byKey(const ValueKey('uygulama-ogrenci-40'));
    await tikla(t, son);
    expect(
      t.getRect(son).bottom,
      lessThanOrEqualTo(
        t.getRect(find.widgetWithText(FilledButton, 'Kaydet').last).top,
      ),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('sonuç değişimi kaydedilir; yeniden açma, arama ve aç/kapat', (
    t,
  ) async {
    await ac(t);
    final sonuc = find.byKey(ValueKey('uygulama-sonuc-1-${uygulamalar.first}'));
    await tikla(t, sonuc);
    await tikla(t, find.text('Eksik'));
    expect(find.widgetWithText(FilledButton, 'Kaydet').last, findsOneWidget);
    await tikla(t, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(
      (await DersUygulamaIslemleri.gecmis(
        o,
        gid,
        guncel: true,
        ogrenciId: 1,
      )).first.durum,
      OdevKontrolDurumu.yapmadi,
    );
    await ac(
      t,
      home: DersUygulamaScreen(key: UniqueKey(), oturum: o, odevId: gid),
    );
    await tikla(t, find.text('Ara'));
    await tikla(t, find.byKey(const ValueKey('uygulama-arama')));
    await t.enterText(find.byKey(const ValueKey('uygulama-arama')), '1833');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('uygulama-ogrenci-1')), findsNothing);
    expect(find.byKey(const ValueKey('uygulama-ogrenci-2')), findsOneWidget);
    await tikla(t, find.text('Ara'));
    await yukari(t);
    await tikla(t, find.text('Tümünü Kapat'));
    expect(sonuc, findsNothing);
    await tikla(t, find.text('Tümünü Aç'));
    await tikla(t, sonuc);
    expect(t.takeException(), isNull);
  });
  testWidgets('uygulama ekle ve ad düzenle, tekrar adı engelle', (t) async {
    await ac(t);
    await tikla(t, find.text('Uygulama Ekle'));
    await t.enterText(
      find.byKey(const ValueKey('uygulama-adi')),
      'Fonksiyonlar',
    );
    await tikla(t, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(await DersUygulamaIslemleri.uygulamalar(o, gid), hasLength(6));
    await yukari(t);
    await tikla(t, find.text('Tüm Uygulamalar'));
    await tikla(t, find.byTooltip('Değişkenler düzenle'));
    await t.enterText(
      find.byKey(const ValueKey('uygulama-adi')),
      'Veri Girişi',
    );
    await tikla(t, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(find.byKey(const ValueKey('uygulama-adi')), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('uygulama-adi')),
      'Yeni Değişkenler',
    );
    await tikla(t, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(
      (await DersUygulamaIslemleri.uygulamalar(o, gid)).first.ad,
      'Yeni Değişkenler',
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('yeni ödevden Ders Uygulamaları türü oluşturulur', (t) async {
    await ac(
      t,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => OdevTanimScreen(oturum: o)),
            ),
            child: const Text('Yeni'),
          ),
        ),
      ),
    );
    await tikla(t, find.text('Yeni'));
    await t.enterText(
      find.widgetWithText(TextFormField, 'Başlık'),
      'Yeni Ders Uygulamaları',
    );
    await tikla(t, find.text('Diğer ayarlar'));
    await tikla(t, find.byKey(const ValueKey('odev-gorev-turu')));
    await tikla(t, find.text('Ders Uygulamaları').last);
    await tikla(t, find.widgetWithText(FilledButton, 'Kaydet').last);
    final rows = await db.query(
      'OdevTanim',
      where: 'Baslik=?',
      whereArgs: ['Yeni Ders Uygulamaları'],
    );
    expect(rows.single['DersUygulamalari'], 1);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'toplu işlem yalnız seçilen öğrenciye uygulanır, rapor ve bilgiler açılır',
    (t) async {
      await ac(t);
      await tikla(t, find.text('Toplu İşlem'));
      final sonucSecici=find.byType(DropdownButton<OdevKontrolDurumu>);
      final secenekler=t.widget<DropdownButton<OdevKontrolDurumu>>(sonucSecici).items!.map((e)=>e.value!.kayitDegeri).toList();
      for (final ad in ['Geldi','Muaf','Katilmadi']) { expect(secenekler, isNot(contains(ad))); }
      expect(secenekler,containsAll(['Gelmedi','Mazeretli','KontrolEdilmedi']));
      await tikla(
        t,
        find.widgetWithText(CheckboxListTile, 'İbrahim Alperen Öztürk'),
      );
      await tikla(t, find.text('1 öğrenciye uygula'));
      await tikla(t, find.widgetWithText(FilledButton, 'Kaydet').last);
      final rows = await DersUygulamaIslemleri.gecmis(o, gid, guncel: true);
      expect(
        rows.where((s) => s.ogrenciId == 3).single.durum,
        OdevKontrolDurumu.yapti,
      );
      expect(rows.where((s) => s.ogrenciId == 1), hasLength(3));
      await tikla(t, find.text('Rapor'));
      expect(find.text('Uygulama raporu'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await tikla(t, find.text('Bilgiler'));
      expect(find.text('Ödev bilgileri'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'geçmiş tarih seçimi, bekleyen değişiklik onayı ve kontrol silme',
    (t) async {
      final k2 = await BireyselOdevKontrolService.kontrolOlustur(
        o,
        gid,
        kontrolTarihi: DateTime(2026, 11, 6),
      );
      await ac(t);
      await tikla(
        t,
        find.byKey(ValueKey('uygulama-sonuc-1-${uygulamalar.first}')),
      );
      await tikla(t, find.text('Eksik'));
      await yukari(t);
      await tikla(t, find.text('Puanlama'));
      await tikla(t, find.byKey(const ValueKey('uygulama-kontrol-sec')));
      await tikla(t, find.text('1. Kontrol • 05.11.2026'));
      expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
      await tikla(t, find.text('Düzenlemeye devam et'));
      await tikla(t, find.text('Puanlama'));
      expect(find.text('2. Kontrol • 06.11.2026'), findsOneWidget);
      await tikla(t, find.byKey(const ValueKey('uygulama-kontrol-sec')));
      await tikla(t, find.text('1. Kontrol • 05.11.2026'));
      await tikla(t, find.text('Değişiklikleri bırak'));
      await tikla(t, find.text('Puanlama'));
      expect(find.text('1. Kontrol • 05.11.2026'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await tikla(t, find.byTooltip('Uygulama işlemleri'));
      await tikla(t, find.text('Seçili kontrolü sil'));
      await tikla(t, find.widgetWithText(FilledButton, 'Kontrolü sil'));
      expect(
        (await BireyselOdevKontrolService.kontroller(
          o,
          gid,
        )).single.odevKontrolId,
        k2,
      );
      expect(await DersUygulamaIslemleri.uygulamalar(o, gid), hasLength(5));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('pasifleştirme ve etkinleştirme geçmişi korur', (t) async {
    await ac(t);
    await tikla(t, find.byTooltip('Uygulama işlemleri'));
    await tikla(t, find.text('Uygulama yönetimi'));
    await tikla(t, find.text('Pasifleştir').first);
    await tikla(t, find.text('Onayla'));
    expect(
      (await DersUygulamaIslemleri.uygulamalar(o, gid)).first.aktif,
      isFalse,
    );
    expect(await DersUygulamaIslemleri.gecmis(o, gid), hasLength(8));
    await tikla(t, find.byTooltip('Uygulama işlemleri'));
    await tikla(t, find.text('Uygulama yönetimi'));
    await tikla(t, find.text('Etkinleştir'));
    await tikla(t, find.text('Onayla'));
    expect(
      (await DersUygulamaIslemleri.uygulamalar(o, gid)).first.aktif,
      isTrue,
    );
    expect(t.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('320 px $scale yazı ve 30 uygulama taşmaz', (t) async {
      for (var i = 6; i <= 30; i++) {
        await DersUygulamaIslemleri.uygulamaKaydet(
          o,
          gid,
          '$i. Uzun uygulama değerlendirmesi',
        );
      }
      await ac(t, width: 320, scale: scale, brightness: Brightness.dark);
      await tikla(
        t,
        find.byKey(ValueKey('uygulama-sonuc-1-${uygulamalar.first}')),
      );
      await tikla(t, find.text('Tam'));
      await foto(t, 'dar-$scale');
      expect(t.takeException(), isNull);
    });
  }
}
