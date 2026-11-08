import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import 'calisma_modu_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ImportKurulumDurumu {
  const ImportKurulumDurumu(this.anahtar, this.sayilar, this.otomatik);
  final String anahtar;

  /// Ders saati, öğrenci, öğretmen-ders ilişkisi, fotoğraflı öğrenci.
  final List<int> sayilar;
  final bool otomatik;
}

/// Yalnız aktif profil/yılın ders kapsamını okur; import verilerine yazmaz.
class ImportKurulumService {
  Future<ImportKurulumDurumu?> getir() async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError('Kurulum yalnız bireysel öğretmen modunda açılabilir.');
    }
    final db = await LocalDatabase.instance.database;
    final durum = await db.transaction((tx) async {
      final profiller = await tx.query(
        'OgretmenProfil',
        where: 'Aktif=1',
        orderBy: 'OgretmenProfilId DESC',
        limit: 1,
      );
      final okullar = await tx.query('OkulProfil', where: 'Id=1 AND AktifMi=1');
      if (profiller.isEmpty || okullar.isEmpty) return null;
      final p = profiller.single, o = okullar.single;
      if (p['OkulAdi'] != o['OkulAdi'] ||
          p['EgitimOgretimYili'] != o['EgitimYili']) {
        throw StateError(
          'Öğretmen ve okul profilinin eğitim yılı/okul bilgileri uyuşmuyor.',
        );
      }
      final id = p['OgretmenProfilId'], yil = p['EgitimOgretimYili'];
      final args = [id, yil];
      const kapsam = '''SELECT dp.SinifSubeId FROM GecerliDersProgrami dp
        JOIN SinifSube s ON s.SinifSubeId=dp.SinifSubeId
        WHERE dp.OgretmenProfilId=? AND dp.EgitimOgretimYili=? AND dp.Aktif=1
        AND s.Aktif=1 AND s.EgitimOgretimYili=dp.EgitimOgretimYili''';
      Future<int> say(String sql, List<Object?> a) async =>
          (await tx.rawQuery(sql, a)).single['n'] as int;
      final program = await say(
        'SELECT count(*) n FROM GecerliDersProgrami WHERE OgretmenProfilId=? AND EgitimOgretimYili=? AND Aktif=1',
        args,
      );
      const ogrenciler =
          '''FROM Ogrenci o JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
        WHERE o.Aktif=1 AND k.Aktif=1 AND k.EgitimOgretimYili=?
        AND k.SinifSubeId IN ($kapsam)''';
      final ogrenci = await say(
        'SELECT count(DISTINCT o.OgrenciId) n $ogrenciler',
        [yil, ...args],
      );
      final foto = await say(
        '''SELECT count(DISTINCT o.OgrenciId) n $ogrenciler
        AND EXISTS(SELECT 1 FROM OgrenciFotograf f WHERE f.OgrenciId=o.OgrenciId AND f.Aktif=1)''',
        [yil, ...args],
      );
      final ogretmen = await say(
        '''SELECT count(*) n FROM MesajOgretmenSinifDers b
        JOIN MesajOgretmenKisi k ON k.KisiId=b.KisiId
        JOIN Ders d ON d.DersId=b.DersId AND d.Aktif=1
        WHERE k.Aktif=1 AND k.SahipProfilId=? AND k.OkulId=? AND b.EgitimOgretimYili=?
        AND b.SinifSubeId IN ($kapsam)''',
        [id, o['OkulId'], yil, ...args],
      );
      return (
        'import_kurulum_v1_${o['OkulId']}_${id}_$yil',
        [program, ogrenci, ogretmen, foto],
      );
    });
    if (durum == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return ImportKurulumDurumu(
      durum.$1,
      durum.$2,
      durum.$2[0] == 0 &&
          durum.$2[1] == 0 &&
          !(prefs.getBool(durum.$1) ?? false),
    );
  }

  Future<void> kapat(ImportKurulumDurumu? durum) async {
    if (durum == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(durum.anahtar, true)) {
      throw StateError('Kurulum tercihi kaydedilemedi.');
    }
  }
}
