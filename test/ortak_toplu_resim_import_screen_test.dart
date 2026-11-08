import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/screens/rehberlik_form_hizalama_screen.dart';

class TopluTestPicker extends FilePicker {
  TopluTestPicker(this.files);
  final List<PlatformFile>? files;
  bool? multiple, data, stream;
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
    multiple = allowMultiple;
    data = withData;
    stream = withReadStream;
    return files == null ? null : FilePickerResult(files!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
  });
  tearDown(() => FilePicker.platform = TopluTestPicker(null));
  ImportTanimi definition(void Function() saved) => ImportTanimi(
    id: 'test_resim',
    ad: 'Form Import',
    aciklama: 'Ön izleyip seçin.',
    alanlar: const [ImportAlan('dosya', 'Dosya')],
    uzantilar: const {'png'},
    yalnizOzelOkuyucu: true,
    hazirla: (_) async => ImportOnIzleme([]),
    ozelOku: (f) async => ImportOnIzleme([
      ImportKaydi('tek', 'tek', {'dosya': f.ad}),
    ]),
    aktar: (preview, selected) async {
      saved();
      return ImportOzet(
        eklenen: selected.length,
        guncellenen: 0,
        atlanan: 0,
        hatali: 0,
        mesaj: 'Tamam',
      );
    },
  );
  Future<void> tapAsync(WidgetTester t, String text) async {
    await t.runAsync(() async {
      await t.tap(find.text(text));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await t.pumpAndSettle();
  }

  testWidgets(
    'Ortak import çoklu seçimi tek ön izlemede toplar ve onaydan önce yazmaz',
    (t) async {
      final picker = TopluTestPicker([
        PlatformFile(
          name: 'bir.png',
          size: 3,
          readStream: Stream.value([1, 2, 3]),
        ),
        PlatformFile(
          name: 'iki.png',
          size: 2,
          readStream: Stream.value([4, 5]),
        ),
      ]);
      FilePicker.platform = picker;
      var saves = 0, reads = 0;
      await t.pumpWidget(
        MaterialApp(
          home: OrtakImportScreen(
            tanim: definition(() => saves++),
            cokluOnIzlemeyiHazirla: (_, files) async {
              reads++;
              expect(files.map((f) => f.ad), ['bir.png', 'iki.png']);
              expect(files.last.bytes, [4, 5]);
              return ImportOnIzleme([
                for (var i = 0; i < files.length; i++)
                  ImportKaydi('$i', files[i].ad, {
                    'dosya': files[i].ad,
                  }, durum: ImportDurumu.uyarili),
              ]);
            },
          ),
        ),
      );
      await tapAsync(t, 'Cihazdan Birden Fazla Resim Seç');
      expect(picker.multiple, true);
      expect(picker.data, false);
      expect(picker.stream, true);
      expect(find.text('2 resim seçildi'), findsOneWidget);
      expect(saves, 0);
      await t.ensureVisible(find.text('Ön İzleme Hazırla'));
      await t.pumpAndSettle();
      await tapAsync(t, 'Ön İzleme Hazırla');
      expect(reads, 1);
      expect(saves, 0);
      final scroll = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.text('Tüm Aktarılabilirleri Seç'),
        250,
        scrollable: scroll,
        maxScrolls: 25,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Tüm Aktarılabilirleri Seç'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tüm Aktarılabilirleri Seç'));
      await t.pumpAndSettle();
      await tapAsync(t, '2 Seçili Kaydı Aktar');
      expect(saves, 0);
      await tapAsync(t, 'Onayla ve Aktar');
      expect(saves, 1);
      expect(find.text('Aktarım Tamamlandı'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Çoklu resim sayısı sınırı dosyalar okunmadan uygulanır', (
    t,
  ) async {
    var consumed = 0;
    Stream<List<int>> bytes() async* {
      consumed++;
      yield [1];
    }

    FilePicker.platform = TopluTestPicker(
      List.generate(
        51,
        (i) => PlatformFile(name: '$i.png', size: 1, readStream: bytes()),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: OrtakImportScreen(
          tanim: definition(() {}),
          cokluOnIzlemeyiHazirla: (_, __) async => ImportOnIzleme([]),
        ),
      ),
    );
    await tapAsync(t, 'Cihazdan Birden Fazla Resim Seç');
    expect(consumed, 0);
    expect(find.textContaining('en fazla 50 resim'), findsOneWidget);
  });
  testWidgets('Tek dosyalı mevcut modül çoklu seçim açmaz', (t) async {
    final picker = TopluTestPicker([
      PlatformFile(name: 'tek.png', size: 1, bytes: Uint8List.fromList([1])),
    ]);
    FilePicker.platform = picker;
    await t.pumpWidget(
      MaterialApp(home: OrtakImportScreen(tanim: definition(() {}))),
    );
    await tapAsync(t, 'Cihazdan Dosya Seç');
    expect(picker.multiple, false);
    expect(picker.data, true);
    expect(picker.stream, false);
    expect(find.text('tek.png'), findsOneWidget);
  });
  testWidgets('Hizalamada kalan resimler tek işlemle durdurulabilir', (
    t,
  ) async {
    final bytes = await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xffffffff), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(40, 60);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    });
    var stopped = false;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => RehberlikFormHizalamaScreen(
                    bytes: bytes!,
                    boyut: const Size(40, 60),
                    dosyaAdi: 'form.png',
                    kalanlariAtla: () => stopped = true,
                  ),
                ),
              ),
              child: const Text('Başlat'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Başlat'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bu ve kalan resimleri atla'));
    await t.pumpAndSettle();
    expect(stopped, true);
    expect(find.text('Başlat'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
