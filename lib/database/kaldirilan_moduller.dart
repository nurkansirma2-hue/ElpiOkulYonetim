import 'package:sqflite/sqflite.dart';

/// Yalnız v26 geçişi ve eski yedeklerin uyarlanması için eski tablo adları.
class KaldirilanModuller {
  static const tablolar = ['YoklamaDetay', 'Yoklama', 'BireyselIslenenDers'];
  static Future<void> temizle(DatabaseExecutor db) async {
    for (final tablo in tablolar) {
      await db.execute('DROP TABLE IF EXISTS "$tablo"');
    }
  }
}
