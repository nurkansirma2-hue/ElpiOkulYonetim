import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/screens/belge_on_izleme_screen.dart';

void main() {
  Future<void> ac(
    WidgetTester tester,
    String yol,
    String ad,
    String uzanti,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: BelgeOnIzlemeScreen(yol: yol, ad: ad, uzanti: uzanti),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('Metin ön izleme salt okunur; özgün dosya değişmez', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('belge_preview_'),
    );
    final file = File('${dir!.path}/orijinal.txt');
    await tester.runAsync(() => file.writeAsString('Türkçe özgün içerik'));
    await ac(tester, file.path, 'orijinal.txt', 'txt');
    expect(find.text('Türkçe özgün içerik'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(await tester.runAsync(file.readAsString), 'Türkçe özgün içerik');
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('CSV ön izleme hücreleri ve sayfa seçimini gösterir', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('belge_preview_'),
    );
    final file = File('${dir!.path}/liste.csv');
    await tester.runAsync(
      () => file.writeAsString('Okul No;Ad Soyad\n001;Ali Yılmaz'),
    );
    await ac(tester, file.path, 'liste.csv', 'csv');
    expect(find.text('Ali Yılmaz'), findsOneWidget);
    expect(find.text('001'), findsOneWidget);
    expect(find.textContaining('Salt okunur ön izleme'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
