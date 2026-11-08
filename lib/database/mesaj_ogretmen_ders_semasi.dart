import 'package:sqflite/sqflite.dart';

/// Ders adını kişiye kopyalamaz; aynı kişinin sınıf/yıl içindeki derslerini bağlar.
class MesajOgretmenDersSemasi {
  static const tablo = 'MesajOgretmenSinifDers';
  static Future<void> hazirla(DatabaseExecutor db) => db.execute('''
    CREATE TABLE $tablo (
      KisiId TEXT NOT NULL,
      SinifSubeId INTEGER NOT NULL,
      EgitimOgretimYili TEXT NOT NULL,
      DersId INTEGER NOT NULL REFERENCES Ders(DersId) ON DELETE RESTRICT,
      PRIMARY KEY(KisiId,SinifSubeId,EgitimOgretimYili,DersId),
      FOREIGN KEY(KisiId,SinifSubeId,EgitimOgretimYili)
        REFERENCES MesajOgretmenSinif(KisiId,SinifSubeId,EgitimOgretimYili) ON DELETE CASCADE
    )
  ''');
}
