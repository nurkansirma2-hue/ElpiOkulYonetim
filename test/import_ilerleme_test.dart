import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/models/import_ilerleme.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/services/calisma_modu_service.dart';
import 'package:elpi_okul_yonetim/services/drive_belge_service.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/widgets/import_ilerleme_karti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('dar ekranda gerçek oran, geçen süre ve uzun bekleme açıklaması', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImportIlerlemeKarti(
            durum: ImportIlerleme('PDF okunuyor', tamamlanan: 8, toplam: 24),
          ),
        ),
      ),
    );
    expect(
      t
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(1 / 3, .001),
    );
    expect(find.textContaining('%33'), findsOneWidget);
    // Stopwatch gerçek zamana bağlıdır; testte yalnız metnin/sayacın varlığını doğrula.
    expect(find.textContaining('Geçen süre:'), findsOneWidget);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImportIlerlemeKarti(
            durum: ImportIlerleme('Google bağlantısı bekleniyor'),
          ),
        ),
      ),
    );
    expect(
      t
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  test('Drive indirme bildirimi yalnız alınan baytları gösterir', () async {
    final events = <ImportIlerleme>[];
    final client = MockClient(
      (r) async => r.url.queryParameters['alt'] == 'media'
          ? http.Response('abc', 200)
          : http.Response(
              jsonEncode({
                'id': 'file',
                'name': 'a.csv',
                'mimeType': 'text/csv',
                'size': '3',
                'version': '1',
                'capabilities': {'canDownload': true},
              }),
              200,
            ),
    );
    final service = DriveBelgeService(client: client);
    await service.indir(
      token: 'test',
      dosyaId: 'file',
      uzantilar: {'csv'},
      ilerleme: events.add,
    );
    expect(events.where((e) => e.tamamlanan != null).last.tamamlanan, 3);
    expect(events.where((e) => e.tamamlanan != null).last.oran, 1);
    expect(events.last.aciklama, contains('doğrulanıyor'));
    client.close();
  });
  testWidgets('özel okuyucu beklerken aşama görünür; bittiğinde kart kalkar', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
    final durum = ValueNotifier<ImportIlerleme?>(null);
    final bekleyen = Completer<ImportOnIzleme>();
    final tanim = ImportTanimi(
      id: 'test',
      ad: 'Test',
      aciklama: 'Test',
      alanlar: const [],
      uzantilar: const {'pdf'},
      yalnizOzelOkuyucu: true,
      hazirla: (_) async => ImportOnIzleme([]),
      aktar: (_, __) async => throw StateError('Kayıt yapılmamalı'),
      ozelOku: (_) => bekleyen.future,
    );
    await t.pumpWidget(
      MaterialApp(
        home: OrtakImportScreen(
          tanim: tanim,
          ilerleme: durum,
          baslangicDosyasi: ImportDosya(
            'a.pdf',
            Uint8List.fromList('%PDF-test'.codeUnits),
          ),
          ozelOnIzlemeyiHazirla: (_, __) {
            durum.value = const ImportIlerleme(
              'PDF: sayfa 8 / 24',
              tamamlanan: 8,
              toplam: 24,
            );
            return bekleyen.future;
          },
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
    }
    await t.tap(find.text('Ön İzleme Hazırla'));
    await t.pump();
    expect(find.text('PDF: sayfa 8 / 24'), findsOneWidget);
    bekleyen.complete(ImportOnIzleme([]));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(ImportIlerlemeKarti), findsNothing);
    await t.pumpWidget(const SizedBox());
    durum.dispose();
    expect(t.takeException(), isNull);
  });
}
