import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/ders_programi_import_tanimi.dart';

Uint8List workbook(List<List<Object?>> rows, {String name = 'Program'}) {
  final excel = Excel.createExcel();
  final sheet = excel[name];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      if (rows[r][c] != null) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = rows[r][c];
      }
    }
  }
  return Uint8List.fromList(excel.encode()!);
}

Future<BireyselDersProgramiOnIzleme> preview(Uint8List bytes) =>
    BireyselImportService.dersProgramiOnIzlemeHazirla(
      dosyaBytes: bytes, adSoyad: 'NURKAN SIRMA', dosyaUzantisi: 'xlsx');

void main() {
  test('Günler sütunlarda, numara ve saatler ayrı sütunlarda olabilir', () async {
    final p = await preview(workbook([
      [null, 'Sayın NURKAN SIRMA'], [],
      ['Ders', 'Saat', 'Pazartesi', 'Salı'],
      [1, '08:00 - 08:40', 'MATEMATİK\n10-D', 'REHBERLİK\n9-C'],
      [2, '08:50 - 09:30', null, 'ATÖLYE ŞEFLİĞİ'],
    ]));
    expect(p.dersler.length, 2);
    expect(p.seflikSaatleri.length, 1);
    expect(p.dersler.first.saatAraligi, '08:00 - 08:40');
  });
  test('Gerçek dosya: 25 ders, 6 şeflik, 13 koordinatörlük ve başlangıç', () async {
    final p = await preview(File('test/fixtures/Ders_Programi.xlsx').readAsBytesSync());
    expect(p.ogretmenBulundu, isTrue);
    expect(p.dersler.length, 38);
    expect(p.dersler.where((d) => d.gorevMi), hasLength(13));
    expect(p.baslangicTarihi, DateTime(2026, 9, 14));
    expect(p.seflikSaatleri.length, 6);
    expect(p.gunlukDersSaatAdaylari.length, 55);
    expect(p.uyarilar, isEmpty);
    final paz7 = p.dersler.singleWhere((d) => d.gun == 'Pazartesi' && d.dersSaatiNo == 7);
    expect(paz7.sinif, '10-D');
    expect(paz7.saatAraligi, '13:55 - 14:35');
    expect(paz7.derslik, 'BİLGLAB-3, BİLGLAB-2');
    expect(p.dersler.singleWhere((d) => d.dersAdi == 'REHBERLİK').derslik, isEmpty);
  });

  test('Şeflik saatleri ortak önizlemede dersler gibi seçilir ve saatleri görünür', () async {
    final p = await preview(File('test/fixtures/Ders_Programi.xlsx').readAsBytesSync());
    final onIzleme = DersProgramiImportTanimi.onIzlemeyeCevir(p, meslekPaketi: true);
    final oturum = ImportOturumu(onIzleme);
    oturum.topluSec(onIzleme.kayitlar.where((r) => r.durum == ImportDurumu.uygun), true);
    expect(oturum.secimler, hasLength(44));
    final secim = DersProgramiImportTanimi.secimiUygula(onIzleme, oturum.secimler);
    expect(secim.seflikSaatleri, hasLength(6));
    expect(secim.dersler.where((d) => d.gorevMi), hasLength(13));
    for (final satir in onIzleme.kayitlar.where((r) => r.id.startsWith('seflik:'))) {
      final saat = p.gunlukDersSaatAdaylari.singleWhere((s) =>
          s.gun == satir.degerler['gun'] && '${s.dersSaatiNo}' == satir.degerler['dersSaatiNo']);
      expect(satir.degerler['baslangic'], saat.baslangic);
      expect(satir.degerler['bitis'], saat.bitis);
      expect(satir.degerler['baslangic'], isNotEmpty);
    }
    final ilkSeflik = onIzleme.kayitlar.firstWhere((r) => r.id.startsWith('seflik:'));
    oturum.sec(ilkSeflik, false);
    expect(DersProgramiImportTanimi.secimiUygula(onIzleme, oturum.secimler).seflikSaatleri, hasLength(5));

    final kapali = DersProgramiImportTanimi.onIzlemeyeCevir(p, meslekPaketi: false);
    final kapaliOturum = ImportOturumu(kapali);
    kapaliOturum.topluSec(kapali.kayitlar, true);
    expect(kapaliOturum.secimler, hasLength(38));
    expect(DersProgramiImportTanimi.secimiUygula(kapali, kapaliOturum.secimler).seflikSaatleri, isEmpty);
  });

  test('Başlık ve program satır/sütun kaydırılınca bulunur, boş slotta durmaz', () async {
    final p = await preview(workbook([
      [], [], [null, null, 'Sayın Nurkan Sırma'], [],
      [null, null, null, 1, 'ÖĞLE ARASI', 7, 8],
      [null, null, null, '7.45 – 8.25', '12:00 - 13:00', '13:00 - 13:40', '13:50 - 14:30'],
      [null, 'Pazartesi', null, 'NESNE TABANLI\nPROGRAMLAMA', null, null, 'MOBİL\nUYGULAMALAR'],
      [null, null, null, 'BİLGLAB-1', null, null, 'BİLGLAB-2'],
      [null, null, null, '10-D', null, null, '11-D'],
    ]));
    expect(p.dersler.length, 2);
    expect(p.dersler.first.saatAraligi, '07:45 - 08:25');
    expect(p.dersler.last.dersSaatiNo, 8);
    expect(p.gunlukDersSaatAdaylari.map((e) => e.dersSaatiNo), [1, 7, 8]);
  });

  test('Eski tek hücre düzeni ve öğretmen sekmesi korunur', () async {
    final p = await preview(workbook([
      [], ['Saat', '1. 08:00 - 08:40', '2. 08:50 - 09:30'],
      ['Pazartesi', 'NESNE TABANLI\nPROGRAMLAMA\nBİLGLAB-1\n10-D', 'ATÖLYE ŞEFLİĞİ'],
      ['Salı', 'REHBERLİK\n9-C', null],
    ], name: 'NURKAN SIRMA'));
    expect(p.dersler.length, 2);
    expect(p.seflikSaatleri.length, 1);
    expect(p.dersler.first.saatAraligi, '08:00 - 08:40');
  });

  test('Başka öğretmenin programına geçilmez', () async {
    final p = await preview(workbook([
      ['Sayın NURKAN SIRMA'], [null, '1. 08:00 - 08:40'],
      ['Pazartesi', 'REHBERLİK\n9-C'],
      ['Sayın BAŞKA ÖĞRETMEN'], [null, '1. 09:00 - 09:40'],
      ['Salı', 'MATEMATİK\n11-A'],
    ]));
    expect(p.dersler.length, 1);
    expect(p.dersler.single.sinif, '9-C');
  });

  test('Birden fazla eşleşen program birleştirilmez', () async {
    expect(preview(workbook([
      ['Sayın NURKAN SIRMA'], [null, '1. 08:00 - 08:40'],
      ['Pazartesi', 'REHBERLİK\n9-C'],
      ['Sayın NURKAN SIRMA'], [null, '1. 09:00 - 09:40'],
      ['Salı', 'MATEMATİK\n11-A'],
    ])), throwsException);
  });

  test('Yanlış öğretmen, eksik sınıf ve yinelenen saat görünür', () async {
    final wrong = await preview(workbook([
      ['Sayın NURKAN SIRMAOĞLU'], [null, '1. 08:00 - 08:40'],
      ['Pazartesi', 'REHBERLİK\n9-C'],
    ]));
    expect(wrong.ogretmenBulundu, isFalse);
    final missing = await preview(workbook([
      ['Sayın NURKAN SIRMA'], [null, '1. 08:00 - 08:40'],
      ['Pazartesi', 'MATEMATİK'],
    ]));
    expect(missing.dersler, isEmpty);
    expect(missing.uyarilar.single, contains('ayrıştırılamadı'));
    expect(preview(workbook([
      ['Sayın NURKAN SIRMA'], [null, '1. 08:00 - 08:40', '1. 09:00 - 09:40'],
      ['Pazartesi', 'REHBERLİK\n9-C', 'MATEMATİK\n11-A'],
    ])), throwsException);
  });
}
