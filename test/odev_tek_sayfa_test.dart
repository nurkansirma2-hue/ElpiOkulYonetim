import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/odev_kontrol.dart';
import 'package:elpi_okul_yonetim/services/bireysel_odev_kontrol_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'support/windows_memory_database.dart';
import 'package:elpi_okul_yonetim/screens/odev_tanim_screen.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_screen.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_detay_screen.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'package:elpi_okul_yonetim/widgets/ogrenci_foto_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselListeOturumu oturum;
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
    for (final id in [1, 2]) {
      await db.insert('SinifSube', {
        'SinifSubeId': id,
        'SinifKodu': '9-${id == 1 ? 'C' : 'D'}',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': id,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': id == 1 ? 'Pazartesi' : 'Salı',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '$id',
        'Ad': 'Öğrenci',
        'Soyad': '$id',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': id,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    oturum = await BireyselOdevKontrolService.hazirla();
  });
  tearDown(LocalDatabase.instance.close);
  Future<void> tikla(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<int> hazirGorev() async {
    await db.insert('Ogrenci', {
      'OgrenciId': 3,
      'OkulNo': '3003',
      'Ad': 'Ayşe',
      'Soyad': 'Demir',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 3,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    final id = await BireyselOdevKontrolService.gorevOlustur(
      oturum,
      sinifSubeId: 1,
      dersId: 1,
      gorevTuru: OdevGorevTuru.normalOdev,
      baslik: 'Windows Forms Mini Proje',
      aciklama: 'Arayüz ve kod çalışmasını değerlendiriniz.',
      baslangicTarihi: DateTime(2026, 9, 1),
      ogrenciIdleri: [1, 3],
      kontrolBaslat: true,
    );
    return id;
  }

  Future<void> sayfa(
    WidgetTester t,
    Widget home, {
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('ODEV_GORSEL')) {
      await t.runAsync(() async {
        await (FontLoader('NotoSans')
              ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('tek-root'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AnaSayfaTemasi.mavi.olustur(brightness),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> foto(WidgetTester t, String ad) async {
    if (!const bool.fromEnvironment('ODEV_GORSEL')) return;
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('tek-root')),
      );
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'C:/OkulYonetim/work/odev-ui-20261031/$ad.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      img.dispose();
    });
  }

  Finder kaydet() => find.widgetWithText(TextButton, 'Kaydet');
  for (final vazgec in [false, true]) {
    testWidgets('kontrol degisimi kaydedilmemis notu korur: $vazgec', (t) async {
      final id = await hazirGorev();
      final ilk = (await BireyselOdevKontrolService.kontroller(oturum, id)).single;
      final son = await BireyselOdevKontrolService.kontrolOlustur(oturum, id,
        kontrolTarihi: DateTime(2026, 11, 5));
      await sayfa(t, OdevKontrolDetayScreen(oturum: oturum, odevId: id), width: 320, scale: 2);
      await tikla(t, find.byKey(const ValueKey('durum-1-yapti')));
      await t.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await t.pumpAndSettle();
      await tikla(t, find.byKey(const ValueKey('odev-kontrol-secici')));
      await tikla(t, find.byKey(ValueKey('kontrol-sec-${ilk.odevKontrolId}')));
      expect(find.text('Kontroller kaydedilmedi'), findsOneWidget);
      await tikla(t, find.text(vazgec ? 'Vazgeç' : 'Devam et'));
      final satir = find.byKey(const ValueKey('satir-puan-1'));
      await t.scrollUntilVisible(satir, 120, scrollable: find.byType(Scrollable).first);
      expect(t.widget<TextField>(satir).controller!.text, vazgec ? '' : '10');
      await t.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await t.pumpAndSettle();
      await tikla(t, find.byKey(const ValueKey('odev-kontrol-secici')));
      final secili = t.widget<ListTile>(find.byKey(ValueKey('kontrol-sec-${vazgec ? ilk.odevKontrolId : son}')));
      expect(secili.selected, isTrue);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('altinci kontrol silinince besinci kontrol listesi tekrar acilir', (t) async {
    final id = await hazirGorev();
    for (var i = 2; i <= 6; i++) {
      await BireyselOdevKontrolService.kontrolOlustur(oturum, id,
        kontrolTarihi: DateTime(2026, 11, i));
    }
    await sayfa(t, OdevKontrolDetayScreen(oturum: oturum, odevId: id));
    for (var kalan = 6; kalan > 0; kalan--) {
      final secici = find.byKey(const ValueKey('odev-kontrol-secici'));
      await tikla(t, secici);
      await tikla(t, find.text(kalan == 1 ? '1. kontrol • 2026-09-01' : '$kalan. kontrol • 2026-11-0$kalan').last);
      await tikla(t, find.byTooltip('Seçili kontrolü sil'));
      await tikla(t, find.widgetWithText(FilledButton, 'Kontrolü Sil'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(await BireyselOdevKontrolService.kontroller(oturum, id), hasLength(kalan - 1));
    }
  });
  testWidgets('yeni ödevde öğrenci listesi kapalı, seçim ve kayıt korunur', (
    t,
  ) async {
    await sayfa(t, OdevTanimScreen(oturum: oturum));
    expect(find.byKey(const ValueKey('ogrenci-1')).hitTestable(), findsNothing);
    await foto(t, '01-yeni-odev');
    await tikla(t, find.byKey(const ValueKey('odev-ogrenci-secimi')));
    expect(
      find.byKey(const ValueKey('ogrenci-1')).hitTestable(),
      findsOneWidget,
    );
    await foto(t, '02-yeni-odev-ogrenciler');
    await t.enterText(
      find.widgetWithText(TextFormField, 'Başlık'),
      'Deneme ödevi',
    );
    await tikla(t, find.widgetWithText(FilledButton, 'Kaydet'));
    expect(
      await db.query(
        'OdevTanim',
        where: 'Baslik=?',
        whereArgs: ['Deneme ödevi'],
      ),
      hasLength(1),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'tek sayfada puan, sınır kontrolü, hızlı durum, aç kapa ve kayıt',
    (t) async {
      final id = await hazirGorev();
      await sayfa(t, OdevKontrolDetayScreen(oturum: oturum, odevId: id));
      expect(find.byKey(const ValueKey('satir-puan-1')), findsOneWidget);
      await foto(t, '03-not-girisi-kapali');
      final f = find.byKey(const ValueKey('satir-puan-1'));
      await tikla(t, f);
      await t.enterText(f, '11');
      await t.pumpAndSettle();
      expect(find.text('0–10 girin.'), findsOneWidget);
      expect(t.widget<TextButton>(kaydet()).onPressed, isNull);
      await t.enterText(f, '8');
      await t.pumpAndSettle();
      expect(find.byTooltip('Puanı artır'), findsNothing);
      expect(find.byTooltip('Puanı azalt'), findsNothing);
      final plus = t.getRect(find.byKey(const ValueKey('durum-1-yapti')));
      final puanKutusu = t.getRect(f);
      expect(puanKutusu.left, greaterThanOrEqualTo(plus.right));
      expect((puanKutusu.center.dy - plus.center.dy).abs(), lessThan(3));
      await t.enterText(f, '9');
      await t.pumpAndSettle();
      expect(t.widget<TextField>(f).controller!.text, '9');
      await foto(t, '04-not-girisi-acik');
      await tikla(t, kaydet());
      final rows = await db.query('OdevKontrolSonuc', where: 'OgrenciId=1');
      expect(rows.single['NotDegeri'], 9);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      await tikla(t, find.byKey(const ValueKey('durum-1-gelmedi')));
      await tikla(t, kaydet());
      expect(
        (await db.query(
          'OdevKontrolSonuc',
          where: 'OgrenciId=1',
        )).single['NotDegeri'],
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'toplu panel kısa, özel puan doğrulanır, yalnız seçilenler etkilenir',
    (t) async {
      final id = await hazirGorev();
      await sayfa(t, OdevKontrolDetayScreen(oturum: oturum, odevId: id));
      await tikla(t, find.text('Toplu giriş'));
      await tikla(t, find.byKey(const ValueKey('odev-ogrenci-sec-1')));
      await tikla(t, find.text('Toplu uygula'));
      expect(find.text('Ödev Not Girişi'), findsOneWidget);
      expect(t.getSize(find.byType(BottomSheet)).height, lessThan(500));
      await foto(t, '05-toplu-giris');
      await tikla(t, find.byKey(const ValueKey('toplu-durum')));
      await tikla(t, find.text('Özel puan (0–10)').last);
      await t.enterText(find.byKey(const ValueKey('toplu-puan')), '12');
      await tikla(t, find.text('Uygula'));
      expect(find.text('0–10 arasında tam sayı girin.'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('toplu-puan')), '7');
      await foto(t, '06-toplu-ozel-puan');
      await tikla(t, find.text('Uygula'));
      await tikla(t, kaydet());
      final rows = await db.query('OdevKontrolSonuc');
      expect(rows.firstWhere((r) => r['OgrenciId'] == 1)['NotDegeri'], 7);
      expect(rows.firstWhere((r) => r['OgrenciId'] == 3)['NotDegeri'], isNull);
      await tikla(t, find.text('Toplu giriş'));
      await tikla(t, find.text('Toplu uygula'));
      await tikla(t, find.byTooltip('Kapat'));
      expect(
        (await db.query(
          'OdevKontrolSonuc',
        )).firstWhere((r) => r['OgrenciId'] == 3)['NotDegeri'],
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'puan ekranı fotoğrafı gösterir, küçük oklar kaydedip doğru öğrenciye geçer',
    (t) async {
      final id = await hazirGorev();
      final bytes = await t.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(32, 32);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      await db.insert('OgrenciFotograf', {
        'OgrenciId': 1,
        'DosyaYolu': '',
        'FotoVerisi': bytes,
        'Aktif': 1,
        'OlusturmaTarihi': 'test',
      });
      final katilimcilar = await BireyselOdevKontrolService.katilimcilar(
        oturum,
        id,
      );
      expect(katilimcilar.first.fotoVerisi, bytes);
      await sayfa(t, OdevKontrolDetayScreen(oturum: oturum, odevId: id));
      await tikla(t, find.byKey(const ValueKey('puan-1')));
      final geri = find.byKey(const ValueKey('odev-puan-onceki'));
      final ileri = find.byKey(const ValueKey('odev-puan-sonraki'));
      expect(
        t.widget<OgrenciFotoWidget>(find.byType(OgrenciFotoWidget)).fotoVerisi,
        bytes,
      );
      expect(t.widget<IconButton>(geri).onPressed, isNull);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Önceki'), findsNothing);
      expect(find.text('Sonraki'), findsNothing);
      await tikla(t, find.byKey(const ValueKey('manuel-odev-puani')));
      await t.enterText(find.byKey(const ValueKey('manuel-odev-puani')), '8');
      await tikla(t, ileri);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        t.widget<OgrenciFotoWidget>(find.byType(OgrenciFotoWidget)).fotoVerisi,
        isNull,
      );
      expect(t.widget<IconButton>(ileri).onPressed, isNull);
      expect(
        (await db.query(
          'OdevKontrolSonuc',
          where: 'OgrenciId=1',
        )).single['NotDegeri'],
        8,
      );
      await tikla(t, geri);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('manuel-odev-puani')))
            .controller!
            .text,
        '8',
      );
      expect(
        t.widget<OgrenciFotoWidget>(find.byType(OgrenciFotoWidget)).fotoVerisi,
        bytes,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('ödev silme onayı mesaj seçimini sorar, iptal kayıtları korur', (
    t,
  ) async {
    final id = await hazirGorev();
    await sayfa(t, const OdevKontrolScreen());
    await tikla(t, find.byKey(ValueKey('odev-sec-$id')));
    await tikla(t, find.byTooltip('Seçili ödevleri sil'));
    expect(find.text('Arşive kaldır'), findsOneWidget);
    expect(find.text('Mesaj kayıtlarını sil'), findsOneWidget);
    await tikla(t, find.text('Mesaj kayıtlarını sil'));
    await tikla(t, find.text('Vazgeç'));
    expect(
      await db.query('OdevTanim', where: 'OdevId=?', whereArgs: [id]),
      hasLength(1),
    );
    expect(t.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('320 px $scale yazıda iki sayfa ve panel taşmaz', (t) async {
      final id = await hazirGorev();
      await sayfa(
        t,
        OdevKontrolDetayScreen(oturum: oturum, odevId: id),
        width: 320,
        scale: scale,
        brightness: Brightness.dark,
      );
      await tikla(t, find.byKey(const ValueKey('satir-puan-1')));
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await tikla(t, find.text('Toplu giriş'));
      await tikla(t, find.text('Toplu uygula'));
      await tikla(t, find.byTooltip('Kapat'));
      final hata = t.takeException();
      expect(hata, isNull, reason: hata is FlutterError ? hata.diagnostics.map((d) => d.toStringDeep()).join('\n') : '$hata');
      await sayfa(t, OdevTanimScreen(oturum: oturum), width: 320, scale: scale);
      await tikla(t, find.byKey(const ValueKey('odev-ogrenci-secimi')));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('sonuç özeti küçüktür, tüm durumlar ayrıntıda ve notlar korunur', (t) async {
    final id = await hazirGorev();
    final kontroller = await BireyselOdevKontrolService.kontroller(oturum, id);
    await BireyselOdevKontrolService.sonuclariKaydet(oturum,
      kontroller.single.odevKontrolId, const [
        OdevSonucGirdisi(ogrenciId: 1, durum: OdevKontrolDurumu.yapti),
        OdevSonucGirdisi(ogrenciId: 3, durum: OdevKontrolDurumu.manuel, notDegeri: 7),
      ]);
    final once = await BireyselOdevKontrolService.sonuclar(oturum, kontroller.single.odevKontrolId);
    await sayfa(t, OdevKontrolDetayScreen(oturum: oturum, odevId: id));
    expect(find.byKey(const ValueKey('odev-sonuc-ozeti')), findsNothing);
    expect(find.text('Arayüz ve kod çalışmasını değerlendiriniz.'), findsNothing);
    expect(find.byTooltip('Windows Forms Mini Proje'), findsOneWidget);
    await foto(t, '11-yalniz-odev-basligi');
    await tikla(t, find.text('Bilgiler'));
    final ozet = find.byKey(const ValueKey('odev-sonuc-ozeti'));
    expect(find.text('Tam: 1 · Yarı: 0 · Eksik: 0'), findsOneWidget);
    expect(t.getSize(ozet).height, lessThan(64));
    await foto(t, '07-kompakt-sonuc-ozeti');
    await tikla(t, ozet);
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.byType(ListTile)), findsNWidgets(OdevKontrolDurumu.values.length));
    final manuel = find.ancestor(of: find.text('Manuel puan'), matching: find.byType(ListTile));
    expect(find.descendant(of: manuel, matching: find.text('1')), findsOneWidget);
    await foto(t, '08-sonuc-ayrintilari');
    await tikla(t, find.text('Kapat'));
    await tikla(t, find.byTooltip('Bilgileri kapat'));
    final sonra = await BireyselOdevKontrolService.sonuclar(oturum, kontroller.single.odevKontrolId);
    expect(sonra.map((s) => (s.durum, s.notDegeri)), once.map((s) => (s.durum, s.notDegeri)));
    expect(t.takeException(), isNull);
  });

  testWidgets('normal listede seçim ve arama gizli; toplu seçim ve arama isteğe bağlı', (t) async {
    final id = await hazirGorev();
    await sayfa(t, OdevKontrolDetayScreen(oturum: oturum, odevId: id));
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Görünenleri seç'), findsNothing);
    expect(find.widgetWithText(TextField, 'Öğrenci ara...'), findsNothing);
    expect(find.byKey(const ValueKey('satir-puan-1')), findsOneWidget);
    await foto(t, '09-sade-ogrenci-listesi');
    await tikla(t, find.text('Ara'));
    final arama = find.widgetWithText(TextField, 'Öğrenci ara...');
    await tikla(t, arama);
    await t.enterText(arama, '3003');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('satir-puan-1')), findsNothing);
    expect(find.byKey(const ValueKey('satir-puan-3')), findsOneWidget);
    await tikla(t, find.text('Ara'));
    expect(arama, findsNothing);
    expect(find.byKey(const ValueKey('satir-puan-1')), findsOneWidget);
    await tikla(t, find.text('Toplu giriş'));
    await tikla(t, find.byKey(const ValueKey('odev-ogrenci-sec-1')));
    await foto(t, '10-toplu-secim');
    expect(find.text('2 öğrenci • 1 seçili'), findsOneWidget);
    await tikla(t, find.text('Seçimi bitir'));
    expect(find.byType(Checkbox), findsNothing);
    await tikla(t, find.text('Toplu giriş'));
    expect(find.text('2 öğrenci • 0 seçili'), findsOneWidget);
    await tikla(t, find.text('Seçimi bitir'));
    final k = (await BireyselOdevKontrolService.kontroller(oturum, id)).single;
    final rows = await BireyselOdevKontrolService.sonuclar(oturum, k.odevKontrolId);
    expect(rows.every((r) => r.durum.bekliyor), isTrue);
    expect(t.takeException(), isNull);
  });
}
