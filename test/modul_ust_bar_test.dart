import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/widgets/modul_ust_bar.dart';

void main() {
  var ayarlar = 0, profil = 0, bildirim = 0;
  setUp(() {
    ayarlar = profil = bildirim = 0;
    ModulUstBarBaglantisi.aktif = ModulUstBarBaglantisi(
      sahip: Object(),
      ayarlar: () async {
        ayarlar++;
      },
      profil: () async {
        profil++;
      },
      bildirimler: () async {
        bildirim++;
      },
    );
  });
  tearDown(() => ModulUstBarBaglantisi.aktif = null);

  Widget app(Widget home) => MaterialApp(home: home);
  Widget sayfa({List<Widget>? actions, Widget? body}) => Scaffold(
    appBar: ModulUstBar(
      title: const Text('Modül / Alt modül'),
      actions: actions,
    ),
    body: body,
  );

  testWidgets(
    'bildirim ve genel menü ana sayfanın gerçek işlemlerini çağırır',
    (t) async {
      await t.pumpWidget(app(sayfa()));
      await t.tap(find.byTooltip('Bildirimler'));
      await t.pumpAndSettle();
      expect(bildirim, 1);
      for (final ad in ['Ayarlar', 'Profilim']) {
        await t.tap(find.byTooltip('Diğer işlemler'));
        await t.pumpAndSettle();
        await t.tap(find.text(ad));
        await t.pumpAndSettle();
      }
      expect(ayarlar, 1);
      expect(profil, 1);
    },
  );

  testWidgets('Home iki alt modülden köke döner', (t) async {
    await t.pumpWidget(
      app(
        Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (c) => sayfa(
                    body: TextButton(
                      onPressed: () => Navigator.of(
                        c,
                      ).push(MaterialPageRoute<void>(builder: (_) => sayfa())),
                      child: const Text('Alt modül'),
                    ),
                  ),
                ),
              ),
              child: const Text('Kök'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Kök'));
    await t.pumpAndSettle();
    await t.tap(find.text('Alt modül'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Ana Sayfa'));
    await t.pumpAndSettle();
    expect(find.text('Kök'), findsOneWidget);
    expect(find.byType(ModulUstBar), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Home işlem kilidini ve kaydetme uyarısını atlamaz', (t) async {
    var engel = 0;
    await t.pumpWidget(
      app(
        Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (c) => PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) {
                        engel++;
                        showDialog<void>(
                          context: c,
                          builder: (_) => const AlertDialog(
                            title: Text('Kaydedilmemiş değişiklik'),
                          ),
                        );
                      }
                    },
                    child: sayfa(),
                  ),
                ),
              ),
              child: const Text('Kök'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Kök'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Ana Sayfa'));
    await t.pumpAndSettle();
    expect(engel, 1);
    expect(find.text('Kaydedilmemiş değişiklik'), findsOneWidget);
    expect(find.byType(ModulUstBar, skipOffstage: false), findsOneWidget);
  });

  testWidgets('320px büyük yazıda işlem simgeleri ve durumları korunur', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var kayit = 0;
    await t.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: sayfa(
          actions: [
            IconButton(
              tooltip: 'Kaydet',
              onPressed: () {
                kayit++;
              },
              icon: const Icon(Icons.save),
            ),
            const IconButton(
              tooltip: 'Sil',
              onPressed: null,
              icon: Icon(Icons.delete),
            ),
            IconButton(
              tooltip: 'Yenile',
              onPressed: () {},
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
    expect(find.byTooltip('Kaydet').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Yenile').hitTestable(), findsOneWidget);
    expect(
      t
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete))
          .onPressed,
      isNull,
    );
    await t.tap(find.byTooltip('Kaydet'));
    expect(kayit, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('kurulumda mevcut olmayan ana sayfaya çıkılmaz', (t) async {
    ModulUstBarBaglantisi.aktif = null;
    await t.pumpWidget(app(sayfa()));
    expect(
      t
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.home_rounded),
          )
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.notifications_outlined),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('Home tam ekran alt modül penceresinden de döner', (t) async {
    await t.pumpWidget(
      app(
        Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                builder: (_) => Dialog.fullscreen(child: sayfa()),
              ),
              child: const Text('Alt ekranı aç'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Alt ekranı aç'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Ana Sayfa'));
    await t.pumpAndSettle();
    expect(find.byType(ModulUstBar), findsNothing);
    expect(find.text('Alt ekranı aç'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Home kayıttan vazgeçme onayından sonra köke devam eder', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (c) => sayfa(
                    body: TextButton(
                      onPressed: () => Navigator.of(c).push(
                        MaterialPageRoute<void>(
                          builder: (editorContext) => PopScope(
                            canPop: false,
                            onPopInvokedWithResult: (didPop, _) async {
                              if (didPop) return;
                              final cik = await showDialog<bool>(
                                context: editorContext,
                                builder: (d) => AlertDialog(
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(d, true),
                                      child: const Text('Vazgeç ve çık'),
                                    ),
                                  ],
                                ),
                              );
                                if (cik == true && editorContext.mounted) {
                                  Navigator.pop(editorContext);
                                }
                            },
                            child: sayfa(),
                          ),
                        ),
                      ),
                      child: const Text('Editör'),
                    ),
                  ),
                ),
              ),
              child: const Text('Kök'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Kök'));
    await t.pumpAndSettle();
    await t.tap(find.text('Editör'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Ana Sayfa'));
    await t.pumpAndSettle();
    await t.tap(find.text('Vazgeç ve çık'));
    await t.pumpAndSettle();
    expect(find.text('Kök'), findsOneWidget);
    expect(find.byType(ModulUstBar), findsNothing);
    expect(t.takeException(), isNull);
  });
}
