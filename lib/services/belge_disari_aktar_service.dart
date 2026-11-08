import 'dart:io';
import 'dart:isolate';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/ortak_import.dart';

class BelgeDisariAktarService {
  static Future<void> paylas(String kopyaYolu, String ad) async {
    if (Platform.isAndroid) {
      await const MethodChannel(
        'elpi_okul_yonetim/dosya_secici',
      ).invokeMethod<void>('belgePaylas', {'yol': kopyaYolu, 'ad': ad});
    } else {
      await kaydet(ad, await File(kopyaYolu).readAsBytes());
    }
  }

  static Future<String?> kaydet(String ad, Uint8List bytes) async {
    final yol = await FilePicker.platform.saveFile(
      dialogTitle: 'Dosyayı dışa aktar',
      fileName: ad,
      bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
    );
    if (yol != null && !Platform.isAndroid && !Platform.isIOS) {
      await File(yol).writeAsBytes(bytes, flush: true);
    }
    return yol;
  }

  static Future<Uint8List> excelOlustur(
    ImportTanimi tanim,
    List<ImportKaydi> kayitlar, {
    bool sablon = false,
  }) => Isolate.run(() {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    final fields = tanim.alanlar.where((f) => f.kolondan).toList();
    sheet.appendRow(fields.map((f) => f.ad).toList());
    for (final row in kayitlar) {
      // Metin hücreleri kaynakta '=' olsa da formül olarak çalıştırılmaz.
      sheet.appendRow(
        fields.map((f) => row.degerler[f.anahtar] ?? '').toList(),
      );
    }
    if (sablon) {
      excel['Rehber'].appendRow([
        'Bu dosya rehberdir. Mevcut farklı düzenler de import ön izlemesinde eşleştirilebilir.',
      ]);
      excel['Rehber'].appendRow([tanim.aciklama]);
    }
    return Uint8List.fromList(excel.encode()!);
  });
}
