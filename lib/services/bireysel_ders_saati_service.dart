import '../database/local_database.dart';

/// Okulun ders saati çizelgesi; mevcut ders ve görev kayıtlarına dokunmaz.
class BireyselDersSaatiService {
  BireyselDersSaatiService._();

  static Future<Map<int, ({String bas, String bit})>> getir() async {
    final db = await LocalDatabase.instance.database;
    final saatler = await db.query('DersSaati',
      columns: ['SiraNo', 'Baslangic', 'Bitis'], where: 'Aktif = 1',
      orderBy: 'SiraNo');
    final program = await db.rawQuery('''
      SELECT ds.SiraNo, dp.Baslangic, dp.Bitis
      FROM DersProgrami dp
      JOIN DersSaati ds ON ds.DersSaatiId = dp.DersSaatiId
      WHERE dp.Aktif = 1 AND dp.Baslangic IS NOT NULL AND dp.Bitis IS NOT NULL
      ORDER BY dp.DersProgramiId DESC
    ''');
    final sonuc = <int, ({String bas, String bit})>{};
    for (final s in program) {
      final no = s['SiraNo'] as int;
      sonuc.putIfAbsent(no, () => (
        bas: (s['Baslangic'] ?? '').toString(),
        bit: (s['Bitis'] ?? '').toString()));
    }
    for (final s in saatler) {
      final no = s['SiraNo'] as int;
      final bas = (s['Baslangic'] ?? '').toString();
      final bit = (s['Bitis'] ?? '').toString();
      if (bas.isNotEmpty && bit.isNotEmpty) sonuc[no] = (bas: bas, bit: bit);
    }
    return sonuc;
  }

  static int? _dakika(String s) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final d = int.parse(m.group(2)!);
    if (h > 23 || d > 59) return null;
    return h * 60 + d;
  }

  static Future<void> ekle({
    required int no, required String bas, required String bit,
  }) async {
    final b = _dakika(bas), e = _dakika(bit);
    if (no < 1 || no > 20 || b == null || e == null || b >= e) {
      throw const FormatException('Ders numarası veya saat aralığı geçersiz.');
    }
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final mevcut = await txn.query('DersSaati',
        where: 'SiraNo = ?', whereArgs: [no]);
      if (mevcut.isNotEmpty) {
        throw StateError('Bu ders saati zaten tanımlı. Mevcut dersler korunuyor.');
      }
      final diger = await txn.query('DersSaati',
        columns: ['Baslangic', 'Bitis'], where: 'Aktif = 1');
      for (final s in diger) {
        final sb = _dakika((s['Baslangic'] ?? '').toString());
        final se = _dakika((s['Bitis'] ?? '').toString());
        if (sb != null && se != null && b < se && e > sb) {
          throw StateError('Bu saat aralığı başka bir ders saatiyle çakışıyor.');
        }
      }
      await txn.insert('DersSaati', {
        'SiraNo': no, 'Baslangic': bas, 'Bitis': bit, 'Aktif': 1,
      });
    });
  }
  /// Yalnız hiçbir ders veya görev tarafından kullanılmayan saati kaldırır.
  static Future<void> sil(int no) async {
    if (no <= 0) throw ArgumentError('Geçersiz ders saati.');
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final saatler = await txn.query('DersSaati',
        where: 'SiraNo = ? AND Aktif = 1', whereArgs: [no]);
      if (saatler.length != 1) {
        throw StateError('Ders saati artık mevcut değil.');
      }
      final id = saatler.single['DersSaatiId'] as int;
      final dersler = await txn.query('DersProgrami',
        columns: ['DersProgramiId'],
        where: 'DersSaatiId = ?', whereArgs: [id], limit: 1);
      final gorevler = await txn.query('DersProgramiGorev',
        columns: ['GorevId'], where: 'DersSaatiNo = ?',
        whereArgs: [no], limit: 1);
      final seflikler = await txn.query('SeflikProgramSaati',
        columns: ['SeflikProgramSaatiId'], where: 'DersSaatiNo = ?',
        whereArgs: [no], limit: 1);
      if (dersler.isNotEmpty || gorevler.isNotEmpty || seflikler.isNotEmpty) {
        throw StateError('Bu ders saatinde kayıtlı ders veya görev var. '
          'Verileri korumak için silme engellendi.');
      }
      final sayi = await txn.delete('DersSaati',
        where: 'DersSaatiId = ?', whereArgs: [id]);
      if (sayi != 1) throw StateError('Ders saati silinemedi.');
    });
  }

}
