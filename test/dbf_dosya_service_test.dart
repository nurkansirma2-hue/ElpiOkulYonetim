import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';
import 'package:elpi_okul_yonetim/services/dbf_dosya_service.dart';
import 'package:elpi_okul_yonetim/services/dbf_rar_okuyucu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Resmi MEB PDF altı sayfa ve doğru ders/sınıf olarak okunur', () async {
    loadPdfium(
      modulePath: File('build/native_assets/windows/pdfium.dll').absolute.path,
    );
    final belge = await DbfDosyaService.pdfOku(
      'meb.pdf',
      await File('test/fixtures/dbf/meb_dbf.pdf').readAsBytes(),
      hazirla: () async {},
    );
    expect(belge.sinifSeviyesi, 9);
    expect(belge.dersAdi, contains('TASARIM'));
    expect(belge.sayfalar, hasLength(6));
    expect(belge.pdfBytes, isNotNull);
  }, skip: !Platform.isWindows);
  test('Resmi RAR PDF listeler ve seçilen PDF belleğe okunur', () async {
    final yol = File('test/fixtures/dbf/meb_dbf.rar').absolute.path;
    final liste = await DbfRarOkuyucu.listele(yol);
    expect(liste, isNotEmpty);
    final secim = liste.firstWhere(
      (p) => p.ad.toUpperCase().contains('TASARIM'),
    );
    final bytes = await DbfRarOkuyucu.oku(yol, secim);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes, await File('test/fixtures/dbf/meb_dbf.pdf').readAsBytes());
  }, skip: !Platform.isWindows);
  test('Sahte PDF kabul edilmez', () async {
    await expectLater(
      DbfDosyaService.pdfOku('yanlis.pdf', Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
