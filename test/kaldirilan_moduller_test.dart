import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/kaldirilan_moduller.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'support/windows_memory_database.dart';

class _Eski25Factory extends WindowsMemoryFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final db = await super.openDatabase(path, options: options);
    expect(options!.version, 27);
    await db.execute('CREATE TABLE Yoklama (Id INTEGER PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE YoklamaDetay (Id INTEGER PRIMARY KEY, UstId INTEGER REFERENCES Yoklama(Id))',
    );
    await db.execute(
      'CREATE TABLE BireyselIslenenDers (Id INTEGER PRIMARY KEY)',
    );
    await db.insert('Yoklama', {'Id': 1});
    await db.insert('YoklamaDetay', {'Id': 1, 'UstId': 1});
    await db.insert('BireyselIslenenDers', {'Id': 1});
    await db.insert('Ogrenci', {
      'OkulNo': '001',
      'Ad': 'Korunan',
      'Soyad': 'Öğrenci',
      'OlusturmaTarihi': 'test',
    });
    await options.onUpgrade!(db, 25, 27);
    return db;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(LocalDatabase.instance.close);
  Future<void> yok(Database db) async {
    for (final t in KaldirilanModuller.tablolar) {
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [t],
        ),
        isEmpty,
      );
    }
    expect(
      BireyselSifirlama.moduller.map((m) => m.id),
      isNot(contains('islenen')),
    );
    expect(
      BireyselSifirlama.moduller.map((m) => m.id),
      isNot(contains('yoklama')),
    );
  }

  test(
    'yeni v26 kurulumunda kaldırılmış modüllerin tabloları oluşmaz',
    () async {
      await LocalDatabase.instance.close();
      databaseFactory = WindowsMemoryFactory();
      await yok(await LocalDatabase.instance.database);
    },
  );
  test(
    'v25 dolu modül tabloları silinir; öğrenci ve diğer şema korunur',
    () async {
      await LocalDatabase.instance.close();
      databaseFactory = _Eski25Factory();
      final db = await LocalDatabase.instance.database;
      await yok(db);
      expect((await db.query('Ogrenci')).single['Ad'], 'Korunan');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}
