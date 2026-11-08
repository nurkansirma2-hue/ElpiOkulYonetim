import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';

class _TercihEkrani extends StatefulWidget {
  const _TercihEkrani();
  @override
  State<_TercihEkrani> createState() => _TercihEkraniState();
}

class _TercihEkraniState extends State<_TercihEkrani>
    with AnaSayfaGorunumTercihi<_TercihEkrani> {
  @override
  void initState() {
    super.initState();
    gorunumTercihiniYukle();
  }

  @override
  Widget build(BuildContext context) => temaIleGoster(
    (context) => Scaffold(
      body: Column(
        children: [
          Text(kompaktGorunum ? 'Liste seçili' : 'Kart seçili'),
          Text(derslerAcik ? 'Ders açık' : 'Ders dar'),
          Text('Tema: ${seciliTema.name} / ${ekranModu.name}'),
          AnaMenuKart(icon: Icons.school, baslik: 'Sınıflar', onTap: () {}),
          TextButton(
            onPressed: gorunumAyarlariniAc,
            child: const Text('Ayarlar'),
          ),
          TextButton(
            onPressed: dersleriDaraltGenislet,
            child: const Text('Daralt'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('Ayar değişikliği açık iki ekranı yeniden kurmadan yeniler', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            Expanded(child: _TercihEkrani()),
            Expanded(child: _TercihEkrani()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final onceki = tester.stateList(find.byType(_TercihEkrani)).toList();
    expect(find.text('Kart seçili'), findsNWidgets(2));
    await tester.tap(find.text('Ayarlar').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kompakt liste'));
    await tester.tap(find.text('Kompakt liste'));
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    expect(find.text('Liste seçili'), findsNWidgets(2));
    expect(tester.stateList(find.byType(_TercihEkrani)).toList(), onceki);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ana_sayfa_kompakt'), isTrue);

    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kompakt liste'));
    await tester.tap(find.text('Kompakt liste'));
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Liste seçili'), findsNWidgets(2));
    expect(prefs.getBool('ana_sayfa_kompakt'), isTrue);

    await tester.pumpWidget(const SizedBox());
    await OrtakGorunumTercihi.instance.kaydet(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test(
    'Kalıcı tercih bellekten bağımsız yüklenir; ardışık seçim sırası korunur',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tercih = OrtakGorunumTercihi.instance;
      await Future.wait([
        tercih.kaydet(true),
        tercih.yukle(),
        tercih.kaydet(false),
      ]);
      expect(tercih.kompakt, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ana_sayfa_kompakt'), isFalse);
      SharedPreferences.setMockInitialValues({'ana_sayfa_kompakt': true});
      await tercih.yukle();
      expect(tercih.kompakt, isTrue);
      SharedPreferences.setMockInitialValues({});
      await tercih.yukle();
      expect(tercih.kompakt, isFalse);
    },
  );

  testWidgets('Görünüm ve daraltma tercihi yeniden açılınca korunur', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: _TercihEkrani()));
    await tester.pumpAndSettle();
    expect(find.text('Kart seçili'), findsOneWidget);
    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kompakt liste'));
    await tester.tap(find.text('Kompakt liste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daralt'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: _TercihEkrani()));
    await tester.pumpAndSettle();
    expect(find.text('Liste seçili'), findsOneWidget);
    expect(find.text('Ders dar'), findsOneWidget);
  });

  testWidgets('Altı tema kaydedilir ve yeniden açılınca yüklenir', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    for (final tema in AnaSayfaTemasi.values) {
      await tester.pumpWidget(const MaterialApp(home: _TercihEkrani()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(tema.baslik));
      await tester.tap(find.text(tema.baslik));
      await tester.tap(find.text('Uygula'));
      await tester.pumpAndSettle();
      expect(find.text('Tema: ${tema.name} / light'), findsOneWidget);
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, tema.olustur(Brightness.light).colorScheme.surface);
      final icon = tester.widget<Icon>(find.byIcon(Icons.school));
      expect(icon.color, Color(tema.vurgu));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MaterialApp(home: _TercihEkrani()));
      await tester.pumpAndSettle();
      expect(find.text('Tema: ${tema.name} / light'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Vazgeç seçimi değiştirmez; geçersiz kayıt varsayılana döner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ana_sayfa_tema': 'gecersiz',
      'ana_sayfa_ekran_modu': 'gecersiz',
    });
    await tester.pumpWidget(const MaterialApp(home: _TercihEkrani()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doğa Yeşili'));
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Tema: mavi / light'), findsOneWidget);
  });

  testWidgets('Koyu ve sistem modu 320px büyük yazıda kaydedilir', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    for (final mod in [ThemeMode.dark, ThemeMode.system]) {
      SharedPreferences.setMockInitialValues({
        'ana_sayfa_tema': 'yesil',
        'ana_sayfa_ekran_modu': mod.name,
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              platformBrightness: Brightness.dark,
              textScaler: TextScaler.linear(1.5),
            ),
            child: _TercihEkrani(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final iconContext = tester.element(find.byIcon(Icons.school));
      expect(Theme.of(iconContext).brightness, Brightness.dark);
      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Duru Grafit'));
      await tester.tap(find.text('Duru Grafit'));
      await tester.tap(find.text('Uygula'));
      await tester.pumpAndSettle();
      expect(find.text('Tema: grafit / ${mod.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ana_sayfa_ekran_modu'), mod.name);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Görevde plan uyarısı gizlenir; normal dersin konusu korunur', (
    tester,
  ) async {
    Future<void> goster(
      String ad,
      String sinif,
      String konu, {
      bool gorev = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              GunlukDersGorunumu(
                acik: true,
                onToggle: () {},
                tarih: '12.10.2026 Pazartesi',
                bugun: true,
                oncekiGun: () {},
                sonrakiGun: () {},
                buguneDon: () {},
                dersAdi: ad,
                sinif: sinif,
                saat: '10:00 - 10:40',
                konu: konu,
                durum: 'Seçili günün ders akışı',
                durumIcon: Icons.schedule,
                sira: '1/3',
                gorevMi: gorev,
              ),
            ],
          ),
        ),
      ),
    );

    for (final ad in ['ATÖLYE ŞEFLİĞİ', 'Koordinatörlük']) {
      await goster(ad, '', '', gorev: true);
      expect(find.text(ad), findsOneWidget);
      expect(find.text('$ad · '), findsNothing);
      expect(find.text('Yıllık plan konusu'), findsNothing);
      expect(find.text('Bu tarih için konu bulunamadı.'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await goster('Matematik', '9-A', 'Denklemler');
    expect(find.text('Matematik · 9-A'), findsOneWidget);
    expect(find.text('Yıllık plan konusu'), findsOneWidget);
    expect(find.text('Denklemler'), findsOneWidget);
    await goster('Matematik', '9-A', '');
    expect(find.text('Bu tarih için konu bulunamadı.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Haftalık kazanım bağlantısı yalnız verilen normal derste açılır',
    (tester) async {
      var acilmaSayisi = 0;
      Future<void> goster({bool gorev = false, bool baglanti = false}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ListView(
                  children: [
                    GunlukDersGorunumu(
                      acik: true,
                      onToggle: () {},
                      tarih: '14.10.2026 Çarşamba',
                      bugun: true,
                      oncekiGun: () {},
                      sonrakiGun: () {},
                      buguneDon: () {},
                      dersAdi: gorev ? 'Koordinatörlük' : 'Matematik',
                      sinif: gorev ? '' : '9-A',
                      saat: '10:00 - 10:40',
                      konu: '',
                      durum: 'Seçili günün ders akışı',
                      durumIcon: Icons.schedule,
                      sira: '1/3',
                      gorevMi: gorev,
                      onGunlukPlan: baglanti ? () => acilmaSayisi++ : null,
                    ),
                  ],
                ),
              ),
            ),
          );

      await goster();
      expect(find.text('Günlük Plan'), findsNothing);
      await goster(gorev: true, baglanti: true);
      expect(find.text('Günlük Plan'), findsNothing);
      await goster(baglanti: true);
      expect(find.text('Bu tarih için konu bulunamadı.'), findsOneWidget);
      await tester.tap(find.text('Günlük Plan'));
      expect(acilmaSayisi, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final compact in [false, true]) {
    testWidgets('320px ve büyük yazıda taşma yok: kompakt=$compact', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final expanded in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: ListView(
                  children: [
                    GunlukDersGorunumu(
                      acik: expanded,
                      onToggle: () {},
                      tarih: '06.10.2026 Salı',
                      bugun: true,
                      oncekiGun: () {},
                      sonrakiGun: () {},
                      buguneDon: () {},
                      dersAdi: 'Mesleki ve Teknik Eğitim Uygulamaları',
                      sinif: '12/ATP-A',
                      saat: '10.00 - 10.40',
                      konu: List.filled(
                        20,
                        'Uzun yıllık plan konusu',
                      ).join(' '),
                      durum: 'Şu an ders yok • Sıradaki ders',
                      durumIcon: Icons.schedule,
                      sira: '1/8',
                      sonrakiDers: () {},
                      onGunlukPlan: () {},
                      uyari: 'Seçili tarih çalışma takviminde bulunamadı',
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: AnaMenuYerlesimi(
                        kompakt: compact,
                        children: [
                          AnaMenuKart(
                            icon: Icons.school,
                            baslik: 'Nöbet Bölge Yönetimi',
                            onTap: () {},
                          ),
                          AnaMenuKart(
                            icon: Icons.people,
                            baslik: 'Öğrencilerim',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Mesleki ve Teknik Eğitim Uygulamaları · 12/ATP-A'),
          expanded ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Yıllık plan konusu'),
          expanded ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Sonraki ders'),
          expanded ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('06.10.2026 Salı'),
          expanded ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Seçili tarih çalışma takviminde bulunamadı'),
          expanded ? findsOneWidget : findsNothing,
        );
        expect(find.text(expanded ? 'Daralt' : 'Genişlet'), findsOneWidget);
      }
    });
  }
}
