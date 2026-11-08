import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/admin_import_screen.dart';
import 'package:elpi_okul_yonetim/screens/fotograf_import_hucre_secim_screen.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/services/fotograf_import_tanimi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ImportOnIzleme _preview(List<String> ids) => ImportOnIzleme([
  for (final id in ids)
    ImportKaydi(id, 'Mevcut öğrenci $id', {
      'okulNo': id,
      'adSoyad': 'Öğrenci $id',
    }),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alternatifAdi = 'Excel Hücrelerinden Elle Eşleştir';
  final alternatif = find.byKey(const ValueKey('import-alternatif-onizle'));
  late int otomatikCagrisi, manualCagrisi, kayitCagrisi;
  late Future<ImportOnIzleme?> Function() manualHazirla;

  Future<ImportOnIzleme> otomatik(ImportDosya _) async {
    otomatikCagrisi++;
    return _preview(['101', '102']);
  }

  Future<void> ac(
    WidgetTester tester, {
    bool manual = true,
    bool dar = false,
  }) async {
    await tester.binding.setSurfaceSize(
      dar ? const Size(320, 840) : const Size(800, 2000),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tanim = ImportTanimi(
      id: 'foto_akis_test',
      ad: 'Fotoğraf Import',
      aciklama: 'Mevcut öğrenci fotoğrafları',
      alanlar: const [
        ImportAlan('okulNo', 'Okul No'),
        ImportAlan('adSoyad', 'Ad Soyad'),
      ],
      uzantilar: const {'csv'},
      yalnizOzelOkuyucu: true,
      ozelOku: otomatik,
      hazirla: (_) async => _preview(['101', '102']),
      aktar: (_, selected) async {
        kayitCagrisi++;
        return ImportOzet(
          eklenen: selected.length,
          guncellenen: 0,
          atlanan: 0,
          hatali: 0,
          mesaj: 'Fotoğraflar kaydedildi.',
        );
      },
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          builder: dar
              ? (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!,
                )
              : null,
          home: OrtakImportScreen(
            tanim: tanim,
            baslangicDosyasi: ImportDosya(
              'foto.csv',
              Uint8List.fromList(utf8.encode('Okul No\n101\n')),
            ),
            ozelOnIzlemeyiHazirla: (_, dosya) => otomatik(dosya),
            alternatifOnIzlemeyiHazirla: !manual
                ? null
                : (_, _) {
                    manualCagrisi++;
                    return manualHazirla();
                  },
            alternatifOnIzlemeAdi: !manual ? null : alternatifAdi,
          ),
        ),
      );
      await tester.pump();
      for (
        var i = 0;
        i < 100 && find.text('foto.csv').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    expect(find.text('foto.csv'), findsOneWidget);
    await tester.pumpAndSettle();
  }

  Future<void> dokun(WidgetTester tester, Finder finder) async {
    final disKaydirma = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(finder, 200, scrollable: disKaydirma);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    otomatikCagrisi = manualCagrisi = kayitCagrisi = 0;
    manualHazirla = () async => null;
  });

  testWidgets('Dar ekranda ilk sonuç otomatik gelir; grid isteğe bağlıdır', (
    tester,
  ) async {
    await ac(tester, dar: true);
    expect(alternatif, findsNothing);
    await dokun(tester, find.text('Ön İzleme Hazırla'));
    expect(otomatikCagrisi, 1);
    expect(manualCagrisi, 0);
    expect(find.byType(FotografImportHucreSecimScreen), findsNothing);
    await tester.scrollUntilVisible(
      alternatif,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(alternatif);
    expect(find.text(alternatifAdi), findsOneWidget);
    expect(kayitCagrisi, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Manual iptal ve hata otomatik seçimleri korur; başarı yeni sonucu açar',
    (tester) async {
      await ac(tester);
      await dokun(tester, find.text('Ön İzleme Hazırla'));
      await dokun(tester, find.byKey(const ValueKey('101')));
      bool secili(String id) =>
          tester.widget<CheckboxListTile>(find.byKey(ValueKey(id))).value!;
      expect(secili('101'), isFalse);
      expect(secili('102'), isTrue);

      await dokun(tester, alternatif);
      expect(secili('101'), isFalse);
      expect(secili('102'), isTrue);

      manualHazirla = () async =>
          throw StateError('Elle eşleştirme test hatası');
      await dokun(tester, alternatif);
      expect(find.textContaining('Elle eşleştirme test hatası'), findsWidgets);
      expect(secili('101'), isFalse);
      expect(secili('102'), isTrue);

      manualHazirla = () async =>
          ImportOnIzleme([], engeller: ['Geçersiz eşleştirme']);
      await dokun(tester, alternatif);
      expect(find.textContaining('Geçersiz eşleştirme'), findsWidgets);
      expect(secili('101'), isFalse);
      expect(secili('102'), isTrue);

      manualHazirla = () async => _preview(['303']);
      await dokun(tester, alternatif);
      expect(find.byKey(const ValueKey('101')), findsNothing);
      expect(find.byKey(const ValueKey('102')), findsNothing);
      expect(secili('303'), isTrue);
      expect(manualCagrisi, 4);
      expect(kayitCagrisi, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Manual işlem beklerken ikinci işlem ve geri dönüş kilitlenir', (
    tester,
  ) async {
    await ac(tester);
    await dokun(tester, find.text('Ön İzleme Hazırla'));
    final bekleyen = Completer<ImportOnIzleme?>();
    manualHazirla = () => bekleyen.future;
    await tester.tap(alternatif);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(alternatif).onPressed, isNull);
    expect(
      tester.widget<PopScope>(find.byType(PopScope).first).canPop,
      isFalse,
    );
    expect(manualCagrisi, 1);
    bekleyen.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(alternatif).onPressed, isNotNull);
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const ValueKey('101'))).value,
      isTrue,
    );
    expect(kayitCagrisi, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Alternatif callback olmayan importun onay ve kayıt yolu korunur',
    (tester) async {
      await ac(tester, manual: false);
      await dokun(tester, find.text('Ön İzleme Hazırla'));
      expect(alternatif, findsNothing);
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.save));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(kayitCagrisi, 0);
      await tester.tap(find.text('Onayla ve Aktar'));
      await tester.pumpAndSettle();
      expect(kayitCagrisi, 1);
      expect(find.text('Aktarım Tamamlandı'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Öğrencilerim fotoğraf girişinde otomatik ve manual bağlantılar hazırdır',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AdminImportScreen(bireyselFoto: true),
        ),
      );
      final ekran = tester.widget<OrtakImportScreen>(
        find.byType(OrtakImportScreen),
      );
      expect(
        ekran.ozelOnIzlemeyiHazirla,
        FotografImportTanimi.onIzlemeyiHazirla,
      );
      expect(
        ekran.alternatifOnIzlemeyiHazirla,
        FotografImportTanimi.hucrelerdenOnIzlemeyiHazirla,
      );
      expect(ekran.alternatifOnIzlemeAdi, alternatifAdi);
      expect(find.textContaining('öğrenci bilgileri korunur'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
