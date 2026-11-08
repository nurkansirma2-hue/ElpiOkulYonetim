import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:elpi_okul_yonetim/database/odev_durum_temizligi.dart';
import 'package:elpi_okul_yonetim/models/odev_kontrol.dart';
import 'support/windows_memory_database.dart';
import 'package:elpi_okul_yonetim/widgets/odev_puan_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WindowsMemoryDatabase db;
  setUp(() async {
    db = WindowsMemoryDatabase();
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      '''CREATE TABLE OdevKontrolSonuc (
      Id INTEGER PRIMARY KEY, Durum TEXT NOT NULL, NotDegeri INTEGER CHECK(NotDegeri BETWEEN -3 AND 10),Aciklama TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE OdevEk (Id INTEGER PRIMARY KEY,
      SonucId INTEGER REFERENCES OdevKontrolSonuc(Id) ON DELETE RESTRICT,Veri BLOB)''',
    );
    await db.execute(
      '''CREATE TABLE OdevUygulamaSonuc (
      Id INTEGER PRIMARY KEY, Durum TEXT NOT NULL CHECK(Durum IN
        ('Yapti','Kismen','Yapmadi','Gelmedi','Mazeretli','KontrolEdilmedi','Geldi','Muaf','Katilmadi','Manuel')),
      NotDegeri INTEGER CHECK(NotDegeri BETWEEN -3 AND 10),Yapilan INTEGER,Adet INTEGER,Aciklama TEXT)''',
    );
    await db.execute(
      'CREATE INDEX IX_TestSonuc ON OdevUygulamaSonuc(Id,Durum)',
    );
  });
  tearDown(() => db.close());
  testWidgets('öğrenci puanı beş hızlı durumla liste sınırını aşmaz', (t) async {
    await t.pumpWidget(MaterialApp(home: OdevPuanDialog(ad:'Öğrenci',durum:OdevKontrolDurumu.kontrolEdilmedi,
      notDegeri:null,aciklama:'',kaydet:(n,d,a) async {})));
    await t.pumpAndSettle();
    for(final d in OdevKontrolDurumu.hizli) {expect(find.byKey(ValueKey('detay-hizli-${d.name}')),findsOneWidget);}
    for(final ad in ['Geldi','Muaf','Katılmadı']) {expect(find.text(ad),findsNothing);}
    expect(t.takeException(),isNull);
  });
  test(
    'üç durum bekleyene dönüşür, puan/adet temizlenir; kimlik, ekler ve diğer durumlar korunur',
    () async {
      for (final (id, d, n) in [
        (1, 'Geldi', -1),
        (2, 'Muaf', -2),
        (3, 'Katilmadi', -3),
        (4, 'Yapti', 10),
        (5, 'Gelmedi', null),
        (6, 'Mazeretli', null),
      ]) {
        await db.insert('OdevKontrolSonuc', {
          'Id': id,
          'Durum': d,
          'NotDegeri': n,
          'Aciklama': 'Not $id',
        });
        await db.insert('OdevUygulamaSonuc', {
          'Id': id,
          'Durum': d,
          'NotDegeri': n,
          'Yapilan': 2,
          'Adet': 5,
          'Aciklama': 'Not $id',
        });
      }
      await db.insert('OdevEk', {
        'Id': 77,
        'SonucId': 1,
        'Veri': [1, 2],
      });
      final ek = await db.query('OdevEk');
      await db.transaction(OdevDurumTemizligi.hazirla);
      await db.transaction(OdevDurumTemizligi.hazirla);
      for (final table in ['OdevKontrolSonuc', 'OdevUygulamaSonuc']) {
        final rows = await db.query(table, orderBy: 'Id');
        expect(rows, hasLength(6));
        for (final r in rows.take(3)) {
          expect(r['Durum'], 'KontrolEdilmedi');
          expect(r['NotDegeri'], isNull);
          expect(r['Aciklama'], 'Not ${r['Id']}');
          if (table == 'OdevUygulamaSonuc') {
            expect(r['Yapilan'], isNull);
            expect(r['Adet'], isNull);
          }
        }
        expect(rows[3]['NotDegeri'], 10);
        expect(rows[4]['Durum'], 'Gelmedi');
        expect(rows[5]['Durum'], 'Mazeretli');
      }
      expect(await db.query('OdevEk'), ek);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='IX_TestSonuc'",
        ),
        hasLength(1),
      );
      final sql =
          (await db.rawQuery(
                "SELECT sql FROM sqlite_master WHERE name='OdevUygulamaSonuc'",
              )).single['sql']
              as String;
      expect(sql.contains("'Geldi'"), isFalse);
      expect(sql.contains('BETWEEN -3'), isFalse);
    },
  );
  test(
    'iki tablo da kaldırılan durumları ve negatif puanı SQL seviyesinde reddeder',
    () async {
      await db.transaction(OdevDurumTemizligi.hazirla);
      for (final table in ['OdevKontrolSonuc', 'OdevUygulamaSonuc']) {
        for (final d in ['Geldi', 'Muaf', 'Katilmadi']) {
          await expectLater(
            db.insert(table, {'Id': 1, 'Durum': d}),
            throwsA(anything),
          );
        }
        for (final n in [-1, -2, -3]) {
          await expectLater(
            db.insert(table, {'Id': 1, 'Durum': 'Yapti', 'NotDegeri': n}),
            throwsA(anything),
          );
        }
        await db.insert(table, {'Id': 1, 'Durum': 'Yapti', 'NotDegeri': 10});
        await expectLater(
          db.update(table, {'Durum': 'Muaf'}),
          throwsA(anything),
        );
        await expectLater(
          db.update(table, {'NotDegeri': -1}),
          throwsA(anything),
        );
      }
    },
  );
  test(
    'eski yedekteki üç durum bekleyene çevrilir, yeni seçenek listesinde bulunmaz',
    () {
      final tables = <String, Object?>{
        'OdevKontrolSonuc': <Map<String, Object?>>[
          {'Durum': 'Gelmedi', 'NotDegeri': -1},
          {'Durum': 'Mazeretli', 'NotDegeri': -2},
          {'Durum': 'Yapmadi', 'NotDegeri': -3},
          {'Durum': 'Yapti', 'NotDegeri': 10},
        ],
        'OdevUygulamaSonuc': <Map<String, Object?>>[
          {'Durum': 'Katilmadi', 'NotDegeri': 0, 'Yapilan': 0, 'Adet': 5},
        ],
      };
      OdevDurumTemizligi.yedegiUyarla(tables);
      for (final r in (tables['OdevKontrolSonuc'] as List).take(3)) {
        expect(r['Durum'], 'KontrolEdilmedi');
        expect(r['NotDegeri'], isNull);
      }
      final r = (tables['OdevUygulamaSonuc'] as List).single;
      expect(r['Yapilan'], isNull);
      expect(r['Adet'], isNull);
      expect(
        OdevKontrolDurumu.values.map((d) => d.kayitDegeri),
        isNot(contains(anyOf('Geldi', 'Muaf', 'Katilmadi'))),
      );
      expect(() => OdevKontrolSonuc.notDurumu(-1, null), throwsFormatException);
    },
  );
}
