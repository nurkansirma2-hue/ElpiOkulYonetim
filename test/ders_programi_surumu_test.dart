import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/ders_programi_surumu.dart';

class ProgramDb implements DatabaseExecutor {
  final versions = <Map<String, Object?>>[];
  final calendar = <Map<String, Object?>>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => calendar;
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns,
    String? where, List<Object?>? whereArgs, String? groupBy, String? having,
    String? orderBy, int? limit, int? offset}) async => versions.where((v) =>
      v['OgretmenProfilId'] == whereArgs![0] && v['EgitimOgretimYili'] == whereArgs[1] && v['Aktif'] == 1).toList();
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where,
    List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    versions.singleWhere((v) => v['ProgramSurumId'] == whereArgs!.single).addAll(values);
    return 1;
  }
  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm}) async {
    final id = versions.length + 1;
    versions.add({...values, 'ProgramSurumId': id});
    return id;
  }
}

void main() {
  test('Pazartesi başlangıcı önceki cuma günü kapatır; tatil varsa geri gider', () async {
    final db = ProgramDb();
    expect(await DersProgramiSurumu.oncekiDersGunu(db, 1, '2026/2027', DateTime(2026,10,5)), DateTime(2026,10,2));
    db.calendar.add({'BaslangicTarihi':'2026-10-02', 'BitisTarihi':'2026-10-02', 'CalismaVarMi':0});
    expect(await DersProgramiSurumu.oncekiDersGunu(db, 1, '2026/2027', DateTime(2026,10,5)), DateTime(2026,10,1));
  });
  test('Yeni sürüm eskiyi kapatır, aynı tarih tekrarında çoğaltmaz, geçmiş yükleme reddedilir', () async {
    final db = ProgramDb();
    await DersProgramiSurumu.yeniSurum(db, 1, '2026/2027', DateTime(2026,9,14), 'now');
    await DersProgramiSurumu.yeniSurum(db, 1, '2026/2027', DateTime(2026,10,5), 'now');
    expect(db.versions.first['BitisTarihi'], '2026-10-02');
    expect(db.versions.last['BitisTarihi'], isNull);
    await DersProgramiSurumu.yeniSurum(db, 1, '2026/2027', DateTime(2026,10,5), 'now');
    expect(db.versions[1]['Aktif'], 0);
    expect(db.versions.last['Aktif'], 1);
    expect(() => DersProgramiSurumu.yeniSurum(db, 1, '2026/2027', DateTime(2026,9,21), 'now'), throwsStateError);
  });
  test('Başlangıcı bilinmeyen eski program korunur; başka yıl ve profil etkilenmez', () async {
    final db = ProgramDb();
    await db.insert('DersProgramiSurum', {'OgretmenProfilId':1, 'EgitimOgretimYili':'2026/2027', 'BaslangicTarihi':null, 'BitisTarihi':null, 'Aktif':1});
    await db.insert('DersProgramiSurum', {'OgretmenProfilId':2, 'EgitimOgretimYili':'2026/2027', 'BitisTarihi':null, 'Aktif':1});
    await DersProgramiSurumu.yeniSurum(db, 1, '2026/2027', DateTime(2026,10,5), 'now');
    expect(db.versions.first['BaslangicTarihi'], isNull);
    expect(db.versions.first['BitisTarihi'], '2026-10-02');
    expect(db.versions[1]['BitisTarihi'], isNull);
  });
}
