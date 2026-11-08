import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/services/xls_import_okuyucu.dart';

void main() {
  List<String> read(List<List<int>> segments) =>
      XlsImportOkuyucu.metinleriOku(segments.map(Uint8List.fromList).toList());
  test('SST devamında karakter kodlaması değişebilir', () {
    expect(
      read([
        [1, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 65, 66],
        [1, 199, 0, 208, 0],
      ]),
      ['ABÇÐ'],
    );
  });
  test('Yeni metin devam sınırında başlarsa kodlama baytı atılmaz', () {
    expect(
      read([
        [2, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 65],
        [1, 0, 0, 66],
      ]),
      ['A', 'B'],
    );
  });
  test('Zengin metin biçim verisi devamında kodlama baytı bulunmaz', () {
    expect(
      read([
        [2, 0, 0, 0, 2, 0, 0, 0, 1, 0, 8, 1, 0, 65, 0, 0],
        [0, 0, 1, 0, 0, 66],
      ]),
      ['A', 'B'],
    );
  });
  test('Eksik devam parçası sessizce boş metne dönüşmez', () {
    expect(
      () => read([
        [1, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 65],
      ]),
      throwsFormatException,
    );
  });
}
