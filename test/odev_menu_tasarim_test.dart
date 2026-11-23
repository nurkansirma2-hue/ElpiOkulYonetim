import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/widgets/odev_islem_menusu.dart';
import 'package:elpi_okul_yonetim/widgets/odev_ortak_alt_islemler.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [320.0, 420.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'menü $width dp $scale yazıda açılır, kayar ve işlemi seçer',
        (t) async {
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          String? selected;
          var saved = false;
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('gorsel'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  useMaterial3: true,
                  fontFamily: 'NotoSans',
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xff176a9d),
                    brightness: scale == 2 ? Brightness.dark : Brightness.light,
                  ),
                ),
                builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(
                    ctx,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  appBar: AppBar(
                    backgroundColor: const Color(0xff176a9d),
                    foregroundColor: Colors.white,
                    title: const Text('Ödev Kontrol'),
                    actions: [
                      OdevIslemMenusu(
                        onSelected: (v) => selected = v,
                        islemler: const [
                          OdevMenuIslemi(
                            'bilgiler',
                            'Bilgiler',
                            Icons.info_outline,
                          ),
                          OdevMenuIslemi(
                            'rapor',
                            'Rapor / Excel’e aktar',
                            Icons.file_download_outlined,
                          ),
                          OdevMenuIslemi(
                            'duzenle',
                            'Ödevi düzenle',
                            Icons.edit_outlined,
                            ayrac: true,
                          ),
                          OdevMenuIslemi(
                            'yeni',
                            'Yeni kontrol',
                            Icons.calendar_month_outlined,
                          ),
                          OdevMenuIslemi(
                            'aciklama',
                            'Kontrol açıklaması',
                            Icons.chat_bubble_outline,
                          ),
                          OdevMenuIslemi(
                            'ogrenciler',
                            'Öğrenci İşlemleri',
                            Icons.groups_outlined,
                            ayrac: true,
                            altIslemler: [
                              OdevMenuIslemi(
                                'ekle',
                                'Öğrenci Ekle',
                                Icons.person_add_alt_1_outlined,
                              ),
                              OdevMenuIslemi(
                                'cikar',
                                'Öğrenci Çıkar',
                                Icons.person_remove_outlined,
                              ),
                            ],
                          ),
                          OdevMenuIslemi(
                            'tamam',
                            'Tamamlandı olarak işaretle',
                            Icons.check_circle_outline,
                            ayrac: true,
                            basarili: true,
                          ),
                          OdevMenuIslemi(
                            'pasif',
                            'Ödevi pasifleştir',
                            Icons.inventory_2_outlined,
                            arsiv: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                  body: const Center(child: Text('Öğrenci değerlendirmeleri')),
                  bottomNavigationBar: OdevOrtakAltIslemler(
                    sadeceKaydet: true,
                    kaydet: () => saved = true,
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Kaydet'));
          expect(saved, isTrue);
          expect(find.text('Öğrenci Ekle'), findsNothing);
          await t.tap(find.byTooltip('Diğer işlemler'));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Öğrenci İşlemleri'));
          await t.tap(find.text('Öğrenci İşlemleri'));
          await t.pumpAndSettle();
          expect(find.text('Öğrenci Ekle'), findsOneWidget);
          expect(find.text('Öğrenci Çıkar'), findsOneWidget);
          expect(t.takeException(), isNull);
          if (width == 420 && scale == 1) {
            await t.runAsync(() async {
              final boundary = t.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('gorsel')),
              );
              final img = await boundary.toImage(pixelRatio: 2);
              final data = await img.toByteData(format: ui.ImageByteFormat.png);
              await Directory('build/menu-tasarim').create(recursive: true);
              await File(
                'build/menu-tasarim/menu.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              img.dispose();
            });
          }
          await t.ensureVisible(find.text('Öğrenci Çıkar'));
          await t.tap(find.text('Öğrenci Çıkar'));
          await t.pumpAndSettle();
          expect(selected, 'cikar');
          expect(find.text('Ödev işlemleri'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
