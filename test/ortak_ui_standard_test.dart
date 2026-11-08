import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'package:elpi_okul_yonetim/widgets/modul_ust_bar.dart';
import 'package:elpi_okul_yonetim/widgets/ortak_ui.dart';
import 'package:elpi_okul_yonetim/widgets/odev_gorunum.dart';
import 'package:elpi_okul_yonetim/widgets/mesajlasma_gorunumu.dart';

void main() {
  tearDown(() => ModulUstBarBaglantisi.aktif = null);

  test('ana ve alt ekranlarda ortak iskelet zorunludur', () {
    final dosyalar = Directory(
      'lib/screens',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));
    var ekran = 0;
    for (final f in dosyalar) {
      final s = f.readAsStringSync();
      expect(RegExp(r'\bScaffold\(').hasMatch(s), false, reason: f.path);
      expect(RegExp(r'\bAppBar\(').hasMatch(s), false, reason: f.path);
      ekran += RegExp(r'\bOrtakSayfa\(').allMatches(s).length;
    }
    expect(ekran, greaterThanOrEqualTo(48));
  });

  for (final tema in AnaSayfaTemasi.values) {
    for (final parlaklik in Brightness.values) {
      testWidgets('${tema.name} $parlaklik tüm modül kabında korunur', (
        t,
      ) async {
        final theme = tema.olustur(parlaklik);
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: OdevTema(
              child: MesajlasmaGorunumu(
                child: OrtakSayfa(
                  appBar: const ModulUstBar(title: Text('Alt ekran')),
                  body: Builder(
                    builder: (c) {
                      final actual = Theme.of(c);
                      expect(actual.brightness, parlaklik);
                      expect(
                        actual.colorScheme.primary,
                        theme.colorScheme.primary,
                      );
                      expect(
                        actual.cardTheme.shape,
                        isA<RoundedRectangleBorder>(),
                      );
                      expect(actual.inputDecorationTheme.filled, true);
                      return const Card(
                        child: TextField(
                          decoration: InputDecoration(labelText: 'Telefon'),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final width in [320.0, 360.0, 390.0, 400.0, 420.0, 900.0]) {
    testWidgets('$width px büyük yazı, klavye ve alt işlemler taşmaz', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var kayit = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: AnaSayfaTemasi.mor.olustur(Brightness.light),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: OrtakSayfa(
            appBar: ModulUstBar(
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Öğrenci İşlemleri'),
                  Text('2026-2027', style: TextStyle(fontSize: 11)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Kaydet',
                  onPressed: () => kayit++,
                  icon: const Icon(Icons.save_outlined),
                ),
                TextButton(onPressed: () {}, child: const Text('Ön İzleme')),
              ],
            ),
            body: ListView(
              children: [
                const TextField(decoration: InputDecoration(labelText: 'Ad')),
                for (var i = 0; i < 40; i++)
                  Card(child: ListTile(title: Text('Öğrenci $i'))),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final bar = find.byType(OrtakIslemCubugu);
      expect(bar, findsOneWidget);
      expect(t.getTopLeft(find.byTooltip('Kaydet')).dy, greaterThan(650));
      await t.tap(find.byTooltip('Kaydet'));
      await t.pump();
      expect(kayit, 1);
      final once = t.getTopLeft(bar);
      await t.drag(find.byType(ListView), const Offset(0, -1000));
      await t.pumpAndSettle();
      expect(t.getTopLeft(bar), once);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      t.view.resetViewInsets();
    });
  }

  testWidgets('taşma menüsündeki kayıt callbacki pencereyi kapatır', (t) async {
    var kayit = 0;
    await t.pumpWidget(
      MaterialApp(
        home: OrtakSayfa(
          appBar: ModulUstBar(
            title: const Text('Form'),
            actions: [
              for (var i = 0; i < 4; i++)
                IconButton(
                  tooltip: 'İşlem $i',
                  onPressed: () {},
                  icon: const Icon(Icons.edit_outlined),
                ),
              TextButton(onPressed: () => kayit++, child: const Text('Kaydet')),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.byTooltip('Diğer modül işlemleri'));
    await t.pumpAndSettle();
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    expect(kayit, 1);
    expect(find.text('Modül işlemleri'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('uzun tek kelime bölünmez, başlık iki satırı geçmez', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 75,
              child: OrtakBaslik('Mesajlaşma ÇokUzunBirTekSözcük'),
            ),
          ),
        ),
      ),
    );
    final metinler = t.widgetList<Text>(
      find.descendant(
        of: find.byType(OrtakBaslik),
        matching: find.byType(Text),
      ),
    );
    expect(metinler.length, lessThanOrEqualTo(2));
    expect(
      metinler.every(
        (w) =>
            w.maxLines == 1 &&
            w.softWrap == false &&
            w.overflow == TextOverflow.ellipsis,
      ),
      true,
    );
    expect(find.byTooltip('Mesajlaşma ÇokUzunBirTekSözcük'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
