import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/fotograf_import_hucre_secim_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'package:elpi_okul_yonetim/services/xls_import_okuyucu.dart';

BireyselFotoExcelDosyasi _dosya({bool ikinciSayfa = false}) {
  final hucreler = [
    for (var i = 0; i < 4; i++)
      BireyselFotoOgrenciHucresi(
        sayfa: 0,
        satir: i < 2 ? 1 : 3,
        sutun: i.isEven ? 0 : 2,
        okulNo: '${101 + i}',
        ad: i == 0 ? 'UZUN ADLI ÖĞRENCİ BİRİNCİ İKİNCİ' : 'ÖĞRENCİ',
        soyad: 'SOYAD $i',
      ),
    if (ikinciSayfa)
      BireyselFotoOgrenciHucresi(
        sayfa: 1,
        satir: 0,
        sutun: 0,
        okulNo: '201',
        ad: 'İKİNCİ',
        soyad: 'SAYFA',
      ),
  ];
  return BireyselFotoExcelDosyasi([
    XlsImportSayfasi('Sheet1', [
      ['Dosyadaki sınıf başlığı', '', ''],
      ['UZUN ADLI ÖĞRENCİ\n101', '', 'ÖĞRENCİ SOYAD 1\n102'],
      ['', '', ''],
      ['ÖĞRENCİ SOYAD 2\n103', '', 'ÖĞRENCİ SOYAD 3\n104'],
    ]),
    if (ikinciSayfa)
      XlsImportSayfasi('Sheet2', [
        ['İKİNCİ SAYFA\n201'],
      ]),
  ], hucreler);
}

Future<void> _ac(
  WidgetTester tester,
  Future<ImportOnIzleme> Function(Map<String, String>?) hazirla, {
  bool ikinciSayfa = false,
  Size boyut = const Size(900, 1200),
  double olcek = 1,
  void Function(ImportOnIzleme?)? sonuc,
}) async {
  tester.view.physicalSize = boyut;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              final preview = await Navigator.of(context).push<ImportOnIzleme>(
                MaterialPageRoute(
                  builder: (_) => FotografImportHucreSecimScreen(
                    dosya: _dosya(ikinciSayfa: ikinciSayfa),
                    siniflar: const ['9-A', '10-B'],
                    onIzlemeyiHazirla: hazirla,
                  ),
                ),
              );
              sonuc?.call(preview);
            },
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
}

Future<void> _dokun(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _sinifSec(WidgetTester tester, String sinif) async {
  await _dokun(tester, find.byKey(const ValueKey('foto-sinif-secimi')));
  await _dokun(tester, find.text(sinif).last);
}

void main() {
  testWidgets(
    'Öğrenci hücreleri farklı sınıflara atanır; yalnız atananlar ön izlenir',
    (tester) async {
      Map<String, String>? gonderilen;
      ImportOnIzleme? donen;
      final preview = ImportOnIzleme([
        ImportKaydi('101', 'A2', {'sinif': '9-A'}),
      ]);
      await _ac(tester, (map) async {
        gonderilen = map;
        expect(() => map!['yeni'] = '9-A', throwsUnsupportedError);
        return preview;
      }, sonuc: (result) => donen = result);

      expect(find.text('A'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre:0:1:0')));
      await _sinifSec(tester, '9-A');
      await _dokun(tester, find.byKey(const ValueKey('foto-sinif-ata')));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('foto-atama:0:1:0')))
            .data,
        'Sınıf: 9-A',
      );
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre:0:1:2')));
      await _sinifSec(tester, '10-B');
      await _dokun(tester, find.byKey(const ValueKey('foto-sinif-ata')));
      expect(find.text('2 Öğrenciyle Ön İzle'), findsOneWidget);
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre-onizle')));

      expect(gonderilen, {'0:1:0': '9-A', '0:1:2': '10-B'});
      expect(donen, same(preview));
      expect(find.byType(FotografImportHucreSecimScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ters köşeler arasındaki dikdörtgen yalnız aynı sayfanın öğrenci hücrelerini seçer',
    (tester) async {
      Map<String, String>? gonderilen;
      await _ac(tester, (map) async {
        gonderilen = map;
        return ImportOnIzleme([]);
      }, ikinciSayfa: true);
      await _dokun(tester, find.byKey(const ValueKey('foto-aralik-secimi')));
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre:0:3:2')));
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre:0:1:0')));
      expect(find.textContaining('4 seçili'), findsOneWidget);
      await _sinifSec(tester, '9-A');
      await _dokun(tester, find.byKey(const ValueKey('foto-sinif-ata')));
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre-onizle')));
      expect(gonderilen, {
        '0:1:0': '9-A',
        '0:1:2': '9-A',
        '0:3:0': '9-A',
        '0:3:2': '9-A',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Hatalı ön izleme ve exception atamaları korur; tekrar işlemde tek immutable seçim gider',
    (tester) async {
      var cagrilar = 0;
      final bekleyen = Completer<ImportOnIzleme>();
      await _ac(tester, (map) async {
        cagrilar++;
        expect(map, {
          '0:1:0': '9-A',
          '0:1:2': '9-A',
          '0:3:0': '9-A',
          '0:3:2': '9-A',
        });
        if (cagrilar == 1) {
          return ImportOnIzleme([], engeller: ['Fotoğraf eşleşmesi belirsiz.']);
        }
        if (cagrilar == 2) throw StateError('Örnek orijinal hata');
        return bekleyen.future;
      });
      await _dokun(tester, find.byKey(const ValueKey('foto-tumunu-sec')));
      await _sinifSec(tester, '9-A');
      await _dokun(tester, find.byKey(const ValueKey('foto-sinif-ata')));
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre-onizle')));
      expect(find.byType(FotografImportHucreSecimScreen), findsOneWidget);
      expect(find.textContaining('Fotoğraf eşleşmesi belirsiz.'), findsWidgets);
      expect(find.text('4 Öğrenciyle Ön İzle'), findsOneWidget);
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre-onizle')));
      expect(find.textContaining('Örnek orijinal hata'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('foto-hucre-onizle')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('foto-hucre-onizle')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('foto-otomatik-onizle')),
            )
            .onPressed,
        isNull,
      );
      expect(cagrilar, 3);
      bekleyen.complete(ImportOnIzleme([]));
      await tester.pumpAndSettle();
      expect(find.byType(FotografImportHucreSecimScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Atamalar kaldırılabilir; otomatik akış açık seçimle null kapsamı gönderir',
    (tester) async {
      var otomatikCagrildi = false;
      await _ac(tester, (map) async {
        expect(map, isNull);
        otomatikCagrildi = true;
        return ImportOnIzleme([]);
      });
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre:0:1:0')));
      await _sinifSec(tester, '9-A');
      await _dokun(tester, find.byKey(const ValueKey('foto-sinif-ata')));
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre:0:1:0')));
      await _dokun(tester, find.text('Seçililerin Atamasını Kaldır'));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('foto-hucre-onizle')),
            )
            .onPressed,
        isNull,
      );
      await _dokun(tester, find.byKey(const ValueKey('foto-otomatik-onizle')));
      expect(otomatikCagrildi, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320 piksel ve büyük yazıda seçim, sınıf atama ve yatay kaydırma taşmaz',
    (tester) async {
      final oncekiUyari = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = oncekiUyari);
      await _ac(
        tester,
        (_) async => ImportOnIzleme([]),
        boyut: const Size(320, 760),
        olcek: 1.5,
      );
      expect(tester.takeException(), isNull);
      await _dokun(tester, find.byKey(const ValueKey('foto-tumunu-sec')));
      await _sinifSec(tester, '10-B');
      await _dokun(tester, find.byKey(const ValueKey('foto-sinif-ata')));
      expect(find.text('4 Öğrenciyle Ön İzle'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('foto-excel-yatay')),
        const Offset(-350, 0),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('foto-hucre:0:1:2')),
        80,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('foto-excel-dikey')),
          matching: find.byType(Scrollable),
        ),
      );
      await _dokun(tester, find.byKey(const ValueKey('foto-hucre:0:1:2')));
      expect(find.textContaining('1 seçili'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
