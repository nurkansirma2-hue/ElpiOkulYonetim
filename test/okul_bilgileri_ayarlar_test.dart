import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/screens/okul_temel_bilgileri_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_okul_bilgi_service.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

class _AyarlarTestEkrani extends StatefulWidget {
  const _AyarlarTestEkrani({this.okulVar = true, this.bakimVar = false});

  final bool okulVar, bakimVar;

  @override
  State<_AyarlarTestEkrani> createState() => _AyarlarTestEkraniState();
}

class _AyarlarTestEkraniState extends State<_AyarlarTestEkrani>
    with AnaSayfaGorunumTercihi<_AyarlarTestEkrani> {
  @override
  void initState() {
    super.initState();
    gorunumTercihiniYukle();
  }

  Future<void> _okuluAc() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const OkulTemelBilgileriScreen()),
    );
  }

  Future<void> _bakimiAc() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Bakım ekranı')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => ayarlariAc(
          onOkulBilgileri: widget.okulVar ? _okuluAc : null,
          onYonetimBakim: widget.bakimVar ? _bakimiAc : null,
        ),
        child: const Text('Ayarları aç'),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  const alanlar = <String, String>{
    'Okul Adı': 'Yeni Test Okulu',
    'Okul Müdürü': 'Ayşe Yönetici',
    'Müdür Yardımcıları': 'Ali Yardımcı\nFatma Yardımcı',
    'Telefon': '0212 555 00 00',
    'E-posta': 'bilgi@okul.edu.tr',
    'Web Sitesi': 'https://okul.edu.tr',
    'Adres': 'Örnek Mahallesi\nOkul Sokak No: 1',
    'Konum / Harita Bağlantısı': 'https://maps.google.com/?q=41,29',
  };
  const alanAnahtarlari = <String, String>{
    'Okul Adı': 'okulAdi',
    'Okul Müdürü': 'mudurAdi',
    'Müdür Yardımcıları': 'mudurYardimcilari',
    'Telefon': 'telefon',
    'E-posta': 'email',
    'Web Sitesi': 'webSitesi',
    'Adres': 'adres',
    'Konum / Harita Bağlantısı': 'konum',
  };

  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
      'OkulAdi': 'Test Okulu',
      'OkulKisaAdi': 'TO',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Test Öğretmen',
      'OkulAdi': 'Test Okulu',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
  });

  tearDown(() async {
    await LocalDatabase.instance.close();
  });

  Finder alan(String etiket) =>
      find.byKey(ValueKey('okul_${alanAnahtarlari[etiket]}'));

  String deger(WidgetTester tester, String etiket) =>
      tester.widget<TextFormField>(alan(etiket)).controller!.text;

  Future<void> doldur(WidgetTester tester, String etiket, String metin) async {
    await tester.ensureVisible(alan(etiket));
    await tester.pumpAndSettle();
    await tester.enterText(alan(etiket), metin);
    await tester.pumpAndSettle();
  }

  Future<void> dokun(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  Future<void> ac(WidgetTester tester, {bool koyuBuyuk = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: koyuBuyuk ? Brightness.dark : Brightness.light,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(koyuBuyuk ? 1.5 : 1)),
          child: child!,
        ),
        home: const _AyarlarTestEkrani(),
      ),
    );
    await tester.pumpAndSettle();
    await dokun(tester, find.text('Ayarları aç'));
    await dokun(tester, find.text('Okul Bilgileri'));
    expect(find.byType(OkulTemelBilgileriScreen), findsOneWidget);
  }

  testWidgets('320px, büyük yazı ve koyu temada temel alanlar erişilebilir', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await ac(tester, koyuBuyuk: true);
    expect(
      Theme.of(
        tester.element(find.byType(OkulTemelBilgileriScreen)),
      ).brightness,
      Brightness.dark,
    );
    for (final etiket in alanlar.keys) {
      await tester.ensureVisible(alan(etiket));
      await tester.pumpAndSettle();
      expect(alan(etiket), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Kaydet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Temel alanlar kaydedilir ve yeniden açılınca aynı değerler okunur',
    (tester) async {
      await ac(tester);
      for (final field in alanlar.entries) {
        await doldur(tester, field.key, field.value);
      }
      await dokun(tester, find.text('Kaydet'));
      final kayit = await BireyselOkulBilgiService.getir();
      expect(kayit.okul.okulAdi, alanlar['Okul Adı']);
      expect(kayit.okul.mudurAdi, alanlar['Okul Müdürü']);
      expect(kayit.okul.kisaAd, 'TO');
      expect(kayit.yil, '2026/2027');
      expect(
        (await db.query('OgretmenProfil')).single['OkulAdi'],
        'Yeni Test Okulu',
      );
      await tester.pumpWidget(const SizedBox());
      await ac(tester);
      for (final field in alanlar.entries) {
        expect(deger(tester, field.key), field.value);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Kayıt hatasında taslak korunur ve mevcut okul değişmez', (
    tester,
  ) async {
    await ac(tester);
    await doldur(tester, 'Okul Adı', 'Kaydedilemeyen taslak');
    await doldur(tester, 'Okul Müdürü', 'Taslak müdür');
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
    await dokun(tester, find.text('Kaydet'));
    expect(find.byType(OkulTemelBilgileriScreen), findsOneWidget);
    expect(deger(tester, 'Okul Adı'), 'Kaydedilemeyen taslak');
    expect(deger(tester, 'Okul Müdürü'), 'Taslak müdür');
    expect((await db.query('OkulProfil')).single['OkulAdi'], 'Test Okulu');
    expect(find.textContaining('Orijinal hata:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Boş okul adı ve hatalı e-posta, web, harita kaydedilmez', (
    tester,
  ) async {
    await ac(tester);
    await doldur(tester, 'Okul Adı', '   ');
    await doldur(tester, 'E-posta', 'adres@');
    await doldur(tester, 'Web Sitesi', 'ftp://okul.edu.tr');
    await doldur(tester, 'Konum / Harita Bağlantısı', 'harita adresi değil');
    await dokun(tester, find.text('Kaydet'));
    for (final etiket in [
      'Okul Adı',
      'E-posta',
      'Web Sitesi',
      'Konum / Harita Bağlantısı',
    ]) {
      expect(
        tester.state<FormFieldState<String>>(alan(etiket)).hasError,
        isTrue,
      );
    }
    expect((await db.query('OkulProfil')).single['OkulAdi'], 'Test Okulu');
    expect(find.byType(OkulTemelBilgileriScreen), findsOneWidget);
    await doldur(tester, 'Okul Adı', 'Geçerli Okul');
    await doldur(tester, 'E-posta', '');
    await doldur(tester, 'Web Sitesi', '');
    await doldur(tester, 'Konum / Harita Bağlantısı', '');
    await dokun(tester, find.text('Kaydet'));
    expect(find.byType(OkulTemelBilgileriScreen), findsNothing);
    expect((await db.query('OkulProfil')).single['OkulAdi'], 'Geçerli Okul');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Geri dönüş taslağı korur; açık onayla kaydetmeden çıkılır', (
    tester,
  ) async {
    await ac(tester);
    await doldur(tester, 'Okul Adı', 'Kaydedilmemiş okul');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
    await dokun(tester, find.text('Düzenlemeye Dön'));
    expect(find.byType(OkulTemelBilgileriScreen), findsOneWidget);
    expect(deger(tester, 'Okul Adı'), 'Kaydedilmemiş okul');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
    await dokun(tester, find.text('Kaydetmeden Çık'));
    expect(find.byType(OkulTemelBilgileriScreen), findsNothing);
    expect((await db.query('OkulProfil')).single['OkulAdi'], 'Test Okulu');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ayarlar yalnız kullanılabilir girişleri sunar ve görünümü açar',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _AyarlarTestEkrani(okulVar: false)),
      );
      await tester.pumpAndSettle();
      await dokun(tester, find.text('Ayarları aç'));
      expect(find.text('Okul Bilgileri'), findsNothing);
      expect(find.text('Yönetim ve Bakım'), findsNothing);
      expect(find.text('Görünüm'), findsOneWidget);
      await dokun(tester, find.text('Görünüm'));
      expect(find.text('Görünüm ayarları'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Yönetim ve bakım ayarlar içinden açılır', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AyarlarTestEkrani(bakimVar: true)),
    );
    await tester.pumpAndSettle();
    await dokun(tester, find.text('Ayarları aç'));
    await dokun(tester, find.text('Yönetim ve Bakım'));
    expect(find.text('Bakım ekranı'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Bireysel ana sayfa okul bilgilerini kart yerine ayarlardan açar',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: BireyselAnaSayfaScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(find.widgetWithText(AnaMenuKart, 'Okul Bilgileri'), findsNothing);
      await dokun(tester, find.byTooltip('Diğer işlemler'));
      await dokun(tester, find.text('Ayarlar'));
      await dokun(tester, find.text('Okul Bilgileri'));
      expect(find.byType(OkulTemelBilgileriScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(BireyselAnaSayfaScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
