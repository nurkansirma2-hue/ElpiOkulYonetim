import 'odev_kontrol.dart';

class PerformansKriteri {
  const PerformansKriteri(this.id, this.baslik, this.azami);
  final String id, baslik;
  final int azami;
  Map<String, Object> get json => {'id': id, 'baslik': baslik, 'azami': azami};
  factory PerformansKriteri.oku(Map r) => PerformansKriteri(
    r['id'] as String,
    r['baslik'] as String,
    r['azami'] as int,
  );
}

const performansKriterSablonlari = {
  1: [
    PerformansKriteri('bilgi', 'Bilgi ve beceri', 20),
    PerformansKriteri('uygulama', 'Uygulamayı doğru gerçekleştirme', 30),
    PerformansKriteri('problem', 'Problem çözme / eleştirel düşünme', 20),
    PerformansKriteri('urun', 'Ürünü tamamlama', 20),
    PerformansKriteri('sunum', 'Açıklama / sunma', 10),
  ],
  2: [
    PerformansKriteri('hazirlik', 'Derse hazırlık', 15),
    PerformansKriteri('devam', 'Derse devam', 10),
    PerformansKriteri('katilim', 'Aktif katılım', 20),
    PerformansKriteri('davranis', 'Örnek davranış', 15),
    PerformansKriteri('beceri', 'Ünite / tema becerileri', 25),
    PerformansKriteri('okuma', 'Okuryazarlık / kitap okuma', 15),
  ],
};

/// Kontrol ortalamalarının ortalaması: her ödev en fazla 10 puandır.
class OdevPuanOzeti {
  const OdevPuanOzeti(this.puan, this.dahil, this.bos, this.disarida);
  final double? puan;
  final int dahil, bos, disarida;
  static OdevPuanOzeti hesapla(Iterable<Iterable<OdevKontrolSonuc>> odevler) {
    var toplam = 0.0, dahil = 0, bos = 0, disarida = 0;
    for (final kontroller in odevler) {
      final puanlar = <double>[];
      final rows = kontroller.toList();
      if (rows.isEmpty) bos++;
      for (final s in rows) {
        if (s.durum.degerlendirmeDisi) {
          disarida++;
        } else if (s.durum.bekliyor) {
          bos++;
        } else {
          puanlar.add(s.puan!);
        }
      }
      if (puanlar.isNotEmpty) {
        toplam += puanlar.reduce((a, b) => a + b) / puanlar.length;
        dahil++;
      }
    }
    return OdevPuanOzeti(
      dahil == 0 ? null : toplam / (dahil * 10) * 100,
      dahil,
      bos,
      disarida,
    );
  }
}

class PerformansOgrenciSonucu {
  PerformansOgrenciSonucu({
    required this.ogrenci,
    required this.odev,
    required this.kriterPuanlari,
    required this.kriterPuani,
    required this.oneri,
    required this.nihai,
    required this.imza,
    required this.guncel,
  });
  final Map<String, Object?> ogrenci;
  final OdevPuanOzeti odev;
  final Map<String, int?> kriterPuanlari;
  final int? kriterPuani, oneri, nihai;
  final String imza;
  final bool guncel;
}

class PerformansVerisi {
  PerformansVerisi(
    this.tanim,
    this.kriterler,
    this.odevler,
    this.secilenler,
    this.ogrenciler,
  );
  final Map<String, Object?> tanim;
  final List<PerformansKriteri> kriterler;
  final List<OdevTanim> odevler;
  final Set<int> secilenler;
  final List<PerformansOgrenciSonucu> ogrenciler;
}
