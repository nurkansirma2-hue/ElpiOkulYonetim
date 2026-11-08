import 'dart:typed_data';
import 'dart:collection';
import 'bireysel_belge.dart';

String importNormalize(String value) {
  var text = value.replaceAll('İ', 'i').toLowerCase();
  const replacements = {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
    'â': 'a',
    'î': 'i',
    'û': 'u',
  };
  replacements.forEach((a, b) => text = text.replaceAll(a, b));
  return text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

enum ImportBilgiKapsami { dosya, sayfa, blok }

class ImportAlan {
  const ImportAlan(
    this.anahtar,
    this.ad, {
    this.zorunlu = false,
    this.alternatifler = const [],
    this.onIzlemede = true,
    this.filtrelenebilir = false,
    this.gruplanabilir = false,
    this.kolonDisiKapsam,
    this.kolondan = true,
  });
  final String anahtar, ad;
  final bool zorunlu, onIzlemede, filtrelenebilir, gruplanabilir;
  final List<String> alternatifler;

  /// Etiket: değer veya etiket ve yan hücresi; kolon değeri varsa önceliklidir.
  final ImportBilgiKapsami? kolonDisiKapsam;
  final bool kolondan;
  bool baslikEslesir(String text) => [
    ad,
    anahtar,
    ...alternatifler,
  ].any((a) => importNormalize(a) == importNormalize(text));
}

class ImportDosya {
  ImportDosya(this.ad, Uint8List veri, {this.belgeKaynagi})
    : bytes = Uint8List.fromList(veri).asUnmodifiableView();
  final String ad;
  final BelgeImportKaynagi? belgeKaynagi;
  final Uint8List bytes;
  String get uzanti => ad.split('.').last.toLowerCase();
}

class ImportKaynakSatiri {
  ImportKaynakSatiri(this.id, this.konum, Map<String, String> values)
    : degerler = Map.unmodifiable(values);
  final String id, konum;
  final Map<String, String> degerler;
}

enum ImportDurumu { uygun, uyarili, hatali, atlanan }

class ImportKaydi {
  ImportKaydi(
    this.id,
    this.konum,
    Map<String, String> values, {
    this.durum = ImportDurumu.uygun,
    List<String> mesajlar = const [],
  }) : degerler = Map.unmodifiable(values),
       mesajlar = List.unmodifiable(mesajlar);
  final String id, konum;
  final Map<String, String> degerler;
  final ImportDurumu durum;
  final List<String> mesajlar;
  bool get aktarilabilir =>
      durum == ImportDurumu.uygun || durum == ImportDurumu.uyarili;
}

class ImportOnIzleme {
  ImportOnIzleme(
    List<ImportKaydi> rows, {
    this.veri,
    List<String> engeller = const [],
    List<String> bilgiler = const [],
    this.onceAtlanan = 0,
  }) : kayitlar = List.unmodifiable(rows),
       engeller = List.unmodifiable(engeller),
       bilgiler = List.unmodifiable(bilgiler) {
    if (rows.map((r) => r.id).toSet().length != rows.length) {
      throw StateError('Ön izleme kayıt kimlikleri benzersiz olmalıdır.');
    }
  }
  final List<ImportKaydi> kayitlar;
  final Object? veri;
  final List<String> engeller, bilgiler;
  final int onceAtlanan;
}

class ImportOzet {
  const ImportOzet({
    required this.eklenen,
    required this.guncellenen,
    required this.atlanan,
    required this.hatali,
    required this.mesaj,
  });
  final int eklenen, guncellenen, atlanan, hatali;
  final String mesaj;
}

/// Ek modül onayları gerektiğinde ortak ekran henüz veritabanına yazmaz.
class ImportSecimi {
  ImportSecimi(this.dosya, this.onIzleme, Set<String> secimler)
    : secimler = Set.unmodifiable(secimler);
  final ImportDosya dosya;
  final ImportOnIzleme onIzleme;
  final Set<String> secimler;
}

/// Yeni bir modül yalnız kendi alanlarını ve yerel iş kurallarını sağlar.
class ImportTanimi {
  const ImportTanimi({
    required this.id,
    required this.ad,
    required this.alanlar,
    required this.hazirla,
    required this.aktar,
    required this.aciklama,
    this.surum = 1,
    this.uzantilar = const {'xls', 'xlsx', 'csv'},
    this.ozelOku,
    this.ozelDuzeniTani,
    this.blokBaslangici,
    this.kartKayitlariniOku,
    this.ozelOkuyucuAdi = 'Özel dosya düzeni',
    this.yalnizOzelOkuyucu = false,
    this.duzenlemeHazirla,
  });
  final String id, ad, aciklama, ozelOkuyucuAdi;
  final int surum;
  final bool yalnizOzelOkuyucu;
  final List<ImportAlan> alanlar;
  final Set<String> uzantilar;
  final Future<ImportOnIzleme> Function(List<ImportKaynakSatiri>) hazirla;
  final Future<ImportOzet> Function(ImportOnIzleme, Set<String>) aktar;
  final Future<ImportOnIzleme> Function(ImportDosya)? ozelOku;
  final Future<ImportOnIzleme> Function(ImportOnIzleme, List<ImportKaynakSatiri>)? duzenlemeHazirla;

  /// Modül, kolonlardan bağımsız blok/kart düzenini kaynak hücrelerden tanır.
  final bool Function(List<List<List<String>>>)? ozelDuzeniTani;

  /// null: sıradan satır; map (boş da olabilir): yeni blok ve ortak bilgileri.
  final Map<String, String>? Function(List<String>)? blokBaslangici;

  /// Kolonsuz kart düzeninde bir kaynak satırından sıfır veya çok kayıt çıkarır.
  /// null normal kolon akışını kullanır; boş liste satırı atlar.
  final List<Map<String, String>>? Function(List<String>)? kartKayitlariniOku;
  bool get karmaKaynakli =>
      blokBaslangici != null ||
      kartKayitlariniOku != null ||
      alanlar.any((a) => a.kolonDisiKapsam != null);
}

/// Filtre yalnız görünümü değiştirir; seçimler oturum kimliği ile tutulur.
class ImportOturumu {
  ImportOturumu(this.onIzleme) : _kayitlar = onIzleme.kayitlar.toSet();
  final ImportOnIzleme onIzleme;
  final Set<ImportKaydi> _kayitlar;
  final Set<String> _secimler = {};
  final Map<String, String> filtreler = {};
  ImportDurumu? durumFiltresi;
  Set<String> get secimler => UnmodifiableSetView(_secimler);
  List<ImportKaydi> get gorunen => onIzleme.kayitlar
      .where(
        (r) =>
            (durumFiltresi == null || r.durum == durumFiltresi) &&
            filtreler.entries.every(
              (f) => (r.degerler[f.key] ?? '') == f.value,
            ),
      )
      .toList();
  void sec(ImportKaydi row, bool selected) {
    if (onIzleme.engeller.isNotEmpty ||
        !row.aktarilabilir ||
        !_kayitlar.contains(row)) {
      return;
    }
    if (selected) {
      _secimler.add(row.id);
    } else {
      _secimler.remove(row.id);
    }
  }

  void topluSec(Iterable<ImportKaydi> rows, bool selected) {
    for (final row in rows) {
      sec(row, selected);
    }
  }

  void secimiKaldir() => _secimler.clear();
}
