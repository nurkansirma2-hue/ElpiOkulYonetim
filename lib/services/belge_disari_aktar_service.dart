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
  }) {
    final fields = tanim.alanlar.where((f) => f.kolondan).toList();
    // Callback'ler servis/veritabanı tutabilir; isolate'a yalnız metin gönder.
    return _excelKodla([
      fields.map((f) => f.ad).toList(),
      for (final row in kayitlar)
        fields.map((f) => row.degerler[f.anahtar] ?? '').toList(),
    ], sablon ? tanim.aciklama : null);
  }

  static Future<Uint8List> _excelKodla(
    List<List<String>> satirlar,
    String? aciklama,
  ) => Isolate.run(() {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    for (final satir in satirlar) {
      // Metinler '=' ile başlasa da formül olarak çalıştırılmaz.
      sheet.appendRow(satir);
    }
    if (aciklama != null) {
      excel['Rehber'].appendRow([
        'Bu dosya rehberdir. Mevcut farklı düzenler de import ön izlemesinde eşleştirilebilir.',
      ]);
      excel['Rehber'].appendRow([aciklama]);
    }
    return Uint8List.fromList(excel.encode()!);
  });
}
