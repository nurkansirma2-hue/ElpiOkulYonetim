import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/ortak_import_service.dart';
import 'package:elpi_okul_yonetim/services/program_belgesi_okuyucu.dart';
import 'package:elpi_okul_yonetim/services/ogretmen_programi_pdf_okuyucu.dart';

void main() {
  const sinifMetni = '''Sınıfın Adı 9-A
Dersin Adı
Matematik
HDS
4
Öğretmenin Adı
Ayşe Yılmaz, Ömer Çelik
Ayşe Yılmaz
1.
08:30
Müdür Adı
2026/2027 Haftalık Ders Programı''';
  test(
    'sınıf programı tek/çok sayfa; öğretmen özeti, ortak ders ve tekrar',
    () {
      final r = OgretmenProgramiPdfOkuyucu.metindenOku([sinifMetni]);
      expect(r.map((r) => r.degerler['ogretmen']), [
        'Ayşe Yılmaz',
        'Ömer Çelik',
      ]);
      expect(
        r.every(
          (r) =>
              r.degerler['sinif'] == '9-A' &&
              r.degerler['tur'] == 'Sınıf programı',
        ),
        true,
      );
      final cok = OgretmenProgramiPdfOkuyucu.metindenOku([
        sinifMetni,
        sinifMetni.replaceAll('9-A', '10-D'),
      ]);
      expect(cok, hasLength(4));
      expect(cok.map((r) => r.id).toSet(), hasLength(4));
    },
  );
  test(
    'özet eksik veya bir sayfada belirsiz sınıf varsa kısmi aktarım yapılmaz',
    () {
      expect(
        () => OgretmenProgramiPdfOkuyucu.metindenOku([
          sinifMetni,
          'Sınıfın Adı 9-B',
        ]),
        throwsFormatException,
      );
      expect(
        () => OgretmenProgramiPdfOkuyucu.metindenOku([
          '$sinifMetni\nSınıfın Adı 9-B',
        ]),
        throwsFormatException,
      );
    },
  );
  final sutunlar = <List<String>>[
    ['Öğretmen', 'Sınıf', 'Eğitim yılı'],
    ['Ayşe Yılmaz, Ömer Çelik', '9-A', '2026/2027'],
    ['Ayşe Yılmaz', '9-A', '2026/2027'],
    ['Ayşe Yılmaz', '9-B', '2026/2027'],
  ];
  test('Excel sütunları, tek öğretmenin çok sınıfı ve ortak ders ayrılır', () {
    final rows = ProgramBelgesiOkuyucu.tablolardanOku([
      ImportTablosu('Sayfa1', sutunlar),
    ]);
    expect(rows, hasLength(3));
    expect(rows.every((r) => r.degerler['yil'] == '2026-2027'), true);
    expect(rows.map((r) => r.degerler['sinif']), ['9-A', '9-A', '9-B']);
  });
  test('sınıf ve öğretmen bloklarını başlıklardan ayırt eder', () {
    final rows = ProgramBelgesiOkuyucu.tablolardanOku([
      ImportTablosu('Sınıflar', [
        ['Eğitim yılı', '2026-2027'],
        ['Sınıfın Adı', '9-A'],
        ['Dersin Adı', 'HDS', 'Öğretmenin Adı'],
        ['Matematik', '4', 'Ayşe Yılmaz'],
        ['Toplam Saat', '4'],
        ['Sınıfın Adı', '9-B'],
        ['Dersin Adı', 'HDS', 'Öğretmenin Adı'],
        ['Türkçe', '2', 'Ömer Çelik'],
      ]),
      ImportTablosu('Öğretmen', [
        ['Sayın Ali Demir'],
        ['Eğitim yılı', '2026-2027'],
        ['Ders', 'Sınıf'],
        ['Matematik', '10-D'],
      ]),
    ]);
    expect(rows, hasLength(3));
    expect(rows.map((r) => r.degerler['sinif']), ['9-A', '9-B', '10-D']);
    expect(rows.last.degerler['tur'], 'Öğretmen programı');
    expect(rows.map((r) => r.degerler['dersler']), ['Matematik', 'Türkçe', 'Matematik']);
  });
  test(
    'yanlış belge veya belirsiz başlık reddedilir; eksik yıl uydurulmaz',
    () {
      expect(
        () => ProgramBelgesiOkuyucu.tablolardanOku([
          ImportTablosu('a', [
            ['Öğrenci', 'Telefon'],
            ['Ali', '123'],
          ]),
        ]),
        throwsFormatException,
      );
      expect(
        () => ProgramBelgesiOkuyucu.tablolardanOku([
          ImportTablosu('a', [
            ['Öğretmen', 'Öğretmen', 'Sınıf'],
          ]),
        ]),
        throwsFormatException,
      );
      final r = ProgramBelgesiOkuyucu.tablolardanOku([
        ImportTablosu('9-A', [
          ['Öğretmen'],
          ['Ayşe Yılmaz'],
        ]),
      ]);
      expect(r.single.degerler['yil'], '');
    },
  );
  test(
    'gerçek XLSX ve CSV kapsayıcıları okunur; dosya adına bağımlı değildir',
    () async {
      final excel = Excel.createExcel();
      for (final row in sutunlar) {
        excel['Sheet1'].appendRow(row);
      }
      final bytes = excel.encode()!;
      final xlsx = await ProgramBelgesiOkuyucu.oku(
        ImportDosya('rastgele.xlsx', Uint8List.fromList(bytes)),
      );
      final csv = await ProgramBelgesiOkuyucu.oku(
        ImportDosya(
          'rastgele.csv',
          Uint8List.fromList(
            utf8.encode(
              'Öğretmen;Sınıf;Eğitim yılı\nAyşe Yılmaz;9-A;2026-2027',
            ),
          ),
        ),
      );
      expect(xlsx, hasLength(3));
      expect(csv.single.degerler['ogretmen'], 'Ayşe Yılmaz');
    },
  );
  test('gerçek DOCX Word tablosu ve metin etiketleri okunur', () async {
    const xml =
        '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
<w:p><w:r><w:t>Eğitim yılı: 2026-2027</w:t></w:r></w:p>
<w:p><w:r><w:t>Sınıfın Adı 9-A</w:t></w:r></w:p><w:tbl>
<w:tr><w:tc><w:p><w:r><w:t>Dersin Adı</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Öğretmenin Adı</w:t></w:r></w:p></w:tc></w:tr>
<w:tr><w:tc><w:p><w:r><w:t>Matematik</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Ayşe Yılmaz, Ömer Çelik</w:t></w:r></w:p></w:tc></w:tr>
</w:tbl></w:body></w:document>''';
    final data = utf8.encode(xml);
    final zip = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('word/document.xml', data.length, data)),
    )!;
    final rows = await ProgramBelgesiOkuyucu.oku(
      ImportDosya('rastgele.docx', Uint8List.fromList(zip)),
    );
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.degerler['sinif'] == '9-A'), true);
    expect(rows.every((r) => r.degerler['yil'] == '2026-2027'), true);
  });
  test('sahte Word ve aşırı boyut destekleniyor diye kabul edilmez', () async {
    for (final ext in ['doc', 'docx', 'xls', 'xlsx']) {
      await expectLater(
        ProgramBelgesiOkuyucu.oku(
          ImportDosya('x.$ext', Uint8List.fromList([1, 2, 3])),
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      ProgramBelgesiOkuyucu.oku(
        ImportDosya('x.csv', Uint8List(50 * 1024 * 1024 + 1)),
      ),
      throwsFormatException,
    );
  });
}
