import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bireysel_belge_service.dart';

/// Bu kurulumla gelen özgün dosyaları bir kez özel belge arşivine kopyalar.
/// İşaretler arşivden bağımsızdır: silme ve okul sıfırlama dosyaları diriltmez.
class BaslangicBelgeleriService {
  BaslangicBelgeleriService({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static final instance = BaslangicBelgeleriService();
  static const dosyalar = [
    '9C_Kulup_Ogrenci_Dagilim_Listesi_ODY.docx',
    'Ders_Programi.xlsx',
    'TUMSINIFLAR.XLS',
    '12.xls',
    '11.xls',
    '10.xls',
    '9.xls',
    'Oturma Planı.png',
  ];
  final AssetBundle _bundle;
  static Future<void> _sira = Future.value();

  Future<void> yukle(BireyselBelgeService service, String arsivId) {
    final result = _sira.then((_) => _yukle(service, arsivId));
    _sira = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _yukle(BireyselBelgeService service, String arsivId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final ad in dosyalar) {
      final anahtar = 'baslangic_belgesi_v1_$ad';
      if (prefs.getBool(anahtar) == true) continue;
      final data = await _bundle.load('assets/baslangic_belgeleri/$ad');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await service.ekle(
        arsivId: arsivId,
        dosya: PlatformFile(name: ad, size: bytes.length, bytes: bytes),
      );
      // Başarısız dosya işaretlenmez; sonraki açılış yalnız kalanı tamamlar.
      if (!await prefs.setBool(anahtar, true)) {
        throw StateError(
          'Başlangıç belgesinin yükleme bilgisi kaydedilemedi: $ad',
        );
      }
    }
  }
}
