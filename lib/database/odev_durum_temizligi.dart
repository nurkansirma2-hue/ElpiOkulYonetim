import 'package:sqflite/sqflite.dart';

/// V31: kaldırılan üç durum kullanıcı kararıyla bekleyen değerlendirmeye dönüşür.
class OdevDurumTemizligi {
  static const kaldirilan = {'Geldi', 'Muaf', 'Katilmadi'};
  static const durumlar =
      "'Yapti','Kismen','Yapmadi','Gelmedi','Mazeretli','KontrolEdilmedi','Manuel'";

  static Future<void> hazirla(DatabaseExecutor db) async {
    await db.execute(
      '''UPDATE OdevKontrolSonuc
      SET Durum='KontrolEdilmedi',NotDegeri=NULL
      WHERE NotDegeri IN (-1,-2,-3) OR Durum IN ('Geldi','Muaf','Katilmadi')''',
    );
    await db.execute(
      '''UPDATE OdevUygulamaSonuc
      SET Durum='KontrolEdilmedi',NotDegeri=NULL,Yapilan=NULL,Adet=NULL
      WHERE NotDegeri IN (-1,-2,-3) OR Durum IN ('Geldi','Muaf','Katilmadi')''',
    );

    // Bu yaprak tabloya başka tablo bağlanmıyor. Kimlikler ve bütün sütunlar korunur.
    final row = (await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='OdevUygulamaSonuc'",
    )).single;
    final sql = row['sql'] as String;
    if (sql.contains("'Geldi'") || sql.contains('BETWEEN -3 AND 10')) {
      final indexes = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='OdevUygulamaSonuc' AND sql IS NOT NULL",
      );
      final triggers = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='trigger' AND tbl_name='OdevUygulamaSonuc'",
      );
      final columns = (await db.rawQuery(
        'PRAGMA table_info(OdevUygulamaSonuc)',
      )).map((r) => '"${r['name']}"').join(',');
      final yeni = sql
          .replaceFirst('OdevUygulamaSonuc', 'OdevUygulamaSonucV31')
          .replaceAll(RegExp(",\\s*'(Geldi|Muaf|Katilmadi)'"), '')
          .replaceAll('BETWEEN -3 AND 10', 'BETWEEN 0 AND 10');
      await db.execute(yeni);
      await db.execute(
        'INSERT INTO OdevUygulamaSonucV31 ($columns) SELECT $columns FROM OdevUygulamaSonuc',
      );
      await db.execute('DROP TABLE OdevUygulamaSonuc');
      await db.execute(
        'ALTER TABLE OdevUygulamaSonucV31 RENAME TO OdevUygulamaSonuc',
      );
      for (final i in [...indexes, ...triggers]) {
        await db.execute(i['sql'] as String);
      }
    }
    // Ana sonuç tablosuna ekler/ölçütler bağlıdır: yeniden kurmadan SQL yazmalarını sınırla.
    for (final table in ['OdevKontrolSonuc', 'OdevUygulamaSonuc']) {
      for (final action in ['INSERT', 'UPDATE']) {
        await db.execute(
          '''CREATE TRIGGER IF NOT EXISTS TR_${table}_Durum31_$action
          BEFORE $action ON $table
          WHEN NEW.Durum NOT IN ($durumlar)
            OR NEW.NotDegeri IS NOT NULL AND (typeof(NEW.NotDegeri)!='integer' OR NEW.NotDegeri NOT BETWEEN 0 AND 10)
          BEGIN SELECT RAISE(ABORT,'Gecersiz odev durumu veya puani'); END''',
        );
      }
    }
  }

  /// Eski yedek geri yüklenince kaldırılmış durumlar yeniden oluşmaz.
  static void yedegiUyarla(Map tables) {
    for (final table in ['OdevKontrolSonuc', 'OdevUygulamaSonuc']) {
      for (final r in (tables[table] as List? ?? [])) {
        final n = r['NotDegeri'];
        if (kaldirilan.contains(r['Durum']) ||
            n is num && const {-1, -2, -3}.contains(n)) {
          r['Durum'] = 'KontrolEdilmedi';
          r['NotDegeri'] = null;
          if (table == 'OdevUygulamaSonuc') {
            r['Yapilan'] = null;
            r['Adet'] = null;
          }
        }
      }
    }
  }
}
