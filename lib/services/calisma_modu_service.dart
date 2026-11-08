import 'package:shared_preferences/shared_preferences.dart';

import '../core/calisma_modu.dart';

class CalismaModuService {
  CalismaModuService._();

  static const String _calismaModuKey = 'calisma_modu';

  static Future<CalismaModu?> getir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deger = prefs.getString(_calismaModuKey);

      return calismaModuFromString(deger);
    } catch (e) {
      throw Exception(
        'Çalışma modu bilgisi okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<void> kaydet(CalismaModu mod) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final basarili = await prefs.setString(_calismaModuKey, mod.kayitDegeri);

      if (!basarili) {
        throw Exception('SharedPreferences çalışma modu bilgisini kaydetmedi.');
      }
    } catch (e) {
      throw Exception(
        'Çalışma modu bilgisi kaydedilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<bool> secilmisMi() async {
    try {
      final mod = await getir();
      return mod != null;
    } catch (e) {
      throw Exception(
        'Çalışma modu seçim durumu kontrol edilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<void> temizle() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final basarili = await prefs.remove(_calismaModuKey);

      if (!basarili && prefs.containsKey(_calismaModuKey)) {
        throw Exception('SharedPreferences çalışma modu bilgisini silemedi.');
      }
    } catch (e) {
      throw Exception(
        'Çalışma modu bilgisi temizlenirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }
}
