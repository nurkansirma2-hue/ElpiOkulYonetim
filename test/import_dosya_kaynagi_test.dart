import 'dart:io';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/models/bireysel_belge.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_belgelerim_screen.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Picker extends FilePicker {
  FilePickerResult? sonuc;
  int cagrilar = 0;
  List<String>? uzantilar;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    cagrilar++;
    uzantilar = allowedExtensions;
    return sonuc;
  }
}

class _Belgeler extends BireyselBelgeService {
  _Belgeler(this.yol, this.boyut);
  final String yol;
  final int boyut;
  int okumalar = 0;
  static const arsiv = BelgeArsivi(
    id: 'arsiv',
    okulId: 'okul',
    ogretmenProfilId: 1,
    okulAdi: 'Okul',
    ogretmenAdi: 'Öğretmen',
  );

  @override
  Future<BelgeArsivListesi> arsivleriGetir() async {
    okumalar++;
    return const BelgeArsivListesi(arsiv, [arsiv]);
  }

  @override
  Future<List<BelgeKlasoru>> klasorleriGetir(String arsivId) async => [];
  @override
  Future<List<String>> yillariGetir(String arsivId) async => [];
  @override
  Future<List<BireyselBelge>> listele({
    required String arsivId,
    String arama = '',
    int offset = 0,
    int limit = 50,
    String? klasorId,
    bool tumKlasorler = true,
    String? tur,
    String? yil,
    bool copKutusu = false,
  }) async => [
    BireyselBelge(
      id: 'belge',
      arsivId: arsivId,
      dosyaAdi: 'plan.txt',
      goreliYol: 'plan.txt',
      uzanti: 'txt',
      boyut: boyut,
      icerikOzeti: null,
      egitimOgretimYili: '2026/2027',
      eklenmeTarihi: DateTime(2026),
      durum: 'Hazir',
    ),
  ];

  @override
  Future<BelgeImportKaynagi> importKaynaginiGetir(BireyselBelge belge) async =>
      const BelgeImportKaynagi('arsiv', 'belge', '2026/2027');
  @override
  Future<String> dosyaYolunuGetir({
    required String arsivId,
    required String belgeId,
  }) async => yol;
  @override
  Future<void> importKapsaminiDogrula(BelgeImportKaynagi kaynak) async {}
}

void main() {
  late _Picker picker;
  late _Belgeler belgeler;
  late Directory gecici;
  final bytes = Uint8List.fromList('Aynı plan içeriği'.codeUnits);
  final okunanlar = <ImportDosya>[];
  var aktarimlar = 0;

  Future<ImportOnIzleme> onIzle(ImportDosya dosya) async {
    okunanlar.add(dosya);
    return ImportOnIzleme([
      ImportKaydi('1', 'Plan satırı', {
        'konu': String.fromCharCodes(dosya.bytes),
      }),
    ]);
  }

  Future<void> ac(WidgetTester tester, {bool birlesik = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrtakImportScreen(
          birlesikKaynakSecimi: birlesik,
          belgeService: belgeler,
          tanim: ImportTanimi(
            id: 'kaynak_test',
            ad: 'Plan',
            aciklama: 'Plan kaynağı',
            alanlar: const [ImportAlan('konu', 'Konu')],
            uzantilar: const {'txt'},
            ozelOku: onIzle,
            hazirla: (_) async => ImportOnIzleme([]),
            aktar: (_, secimler) async {
              aktarimlar++;
              return ImportOzet(
                eklenen: secimler.length,
                guncellenen: 0,
                atlanan: 0,
                hatali: 0,
                mesaj: 'Kaydedildi',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tikla(WidgetTester tester, Finder hedef) async {
    await tester.ensureVisible(hedef);
    await tester.runAsync(() async {
      await tester.tap(hedef);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    });
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    picker = _Picker();
    FilePicker.platform = picker;
    gecici = await Directory.systemTemp.createTemp('import_kaynak_');
    final file = await File('${gecici.path}/plan.txt').writeAsBytes(bytes);
    belgeler = _Belgeler(file.path, bytes.length);
    picker.sonuc = FilePickerResult([
      PlatformFile(name: 'plan.txt', size: bytes.length, bytes: bytes),
    ]);
    okunanlar.clear();
    aktarimlar = 0;
  });
  tearDown(() async => gecici.delete(recursive: true));

  testWidgets('Diğer modüller mevcut ayrı kaynak düğmelerini korur', (
    tester,
  ) async {
    await ac(tester, birlesik: false);
    expect(find.text('Cihazdan Dosya Seç'), findsOneWidget);
    expect(find.text('Belgelerimden Seç'), findsOneWidget);
    expect(find.text('Dosya Seç'), findsNothing);
  });

  testWidgets('Küçük ekranda kaynak seçimi iptali dosya okumaz veya aktarmaz', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await ac(tester);
    await tikla(tester, find.text('Dosya Seç'));
    expect(find.text('Cihazımdan Seç'), findsOneWidget);
    expect(find.text('Belgelerimden Seç'), findsOneWidget);
    await tikla(tester, find.text('İptal'));
    expect(picker.cagrilar, 0);
    expect(belgeler.okumalar, 0);
    expect(aktarimlar, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('İki kaynak aynı okuyucuya gider; belge bağlantısı korunur', (
    tester,
  ) async {
    await ac(tester);
    await tikla(tester, find.text('Dosya Seç'));
    await tikla(tester, find.text('Cihazımdan Seç'));
    expect(picker.uzantilar, ['txt']);
    await tikla(tester, find.text('Ön İzleme Hazırla'));
    expect(okunanlar.single.belgeKaynagi, isNull);
    await tikla(tester, find.text('Başka Dosya Seç'));
    await tikla(tester, find.text('Belgelerimden Seç'));
    expect(find.byType(BireyselBelgelerimScreen), findsOneWidget);
    await tikla(tester, find.byKey(const ValueKey('belge')));
    await tikla(tester, find.text('Ön İzleme Hazırla'));
    expect(okunanlar, hasLength(2));
    expect(okunanlar.last.bytes, orderedEquals(okunanlar.first.bytes));
    expect(okunanlar.last.belgeKaynagi!.belgeId, 'belge');
    expect(aktarimlar, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cihaz seçimi iptali mevcut dosya ve ön izlemeyi korur', (
    tester,
  ) async {
    await ac(tester);
    await tikla(tester, find.text('Dosya Seç'));
    await tikla(tester, find.text('Cihazımdan Seç'));
    await tikla(tester, find.text('Ön İzleme Hazırla'));
    picker.sonuc = null;
    await tikla(tester, find.text('Başka Dosya Seç'));
    await tikla(tester, find.text('Cihazımdan Seç'));
    expect(find.text('plan.txt'), findsOneWidget);
    expect(find.text('Ön İzleme ve Seçim'), findsOneWidget);
    expect(okunanlar, hasLength(1));
    expect(aktarimlar, 0);
    expect(tester.takeException(), isNull);
  });
}
