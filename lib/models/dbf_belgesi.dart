import 'dart:typed_data';
import 'ortak_import.dart';

/// DBF'nin kaynak sayfaları korunur; tablo sütunları tahminle birleştirilmez.
class DbfBelgesi {
  DbfBelgesi({
    required this.dosyaAdi,
    required this.dersAdi,
    required this.sinifSeviyesi,
    required List<String> sayfalar,
    required this.icerikOzeti,
    this.surum = 0,
    this.kaynakAdresi = '',
    this.programSurumu = '',
    this.kayitTarihi = '',
    this.belgeId,
    this.arsivId,
    Uint8List? pdfBytes,
  }) : sayfalar = List.unmodifiable(sayfalar),
       pdfBytes = pdfBytes == null
           ? null
           : Uint8List.fromList(pdfBytes).asUnmodifiableView();

  final String dosyaAdi,
      dersAdi,
      icerikOzeti,
      kaynakAdresi,
      programSurumu,
      kayitTarihi;
  final int sinifSeviyesi, surum;
  final List<String> sayfalar;
  final String? belgeId, arsivId;
  final Uint8List? pdfBytes;

  static DbfBelgesi metinden({
    required String dosyaAdi,
    required List<String> sayfalar,
    required String icerikOzeti,
    Uint8List? pdfBytes,
  }) {
    if (sayfalar.isEmpty ||
        sayfalar.length > 100 ||
        sayfalar.join().length > 1000000 ||
        sayfalar.any((s) => s.trim().isEmpty)) {
      throw const FormatException(
        'PDF metni eksik veya boyut sınırını aşıyor. Taranmış sayfalar için metin içeren DBF kullanın.',
      );
    }
    final ilk = sayfalar.first.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!importNormalize(ilk).contains('ders bilgi formu')) {
      throw const FormatException(
        'Bu dosyada Ders Bilgi Formu başlığı bulunamadı. Günlük/yıllık plan yerine DBF seçin.',
      );
    }
    final ad = RegExp(
      r'DERS[İI]N ADI\s*[:：]?\s*(.*?)\s*DERS[İI]N SINIFI',
      caseSensitive: false,
    ).firstMatch(ilk)?.group(1)?.trim();
    final sinif = RegExp(
      r'DERS[İI]N SINIFI\s*[:：]?\s*(\d+)\s*[.\s]',
      caseSensitive: false,
    ).firstMatch(ilk)?.group(1);
    if (ad == null || ad.isEmpty || int.tryParse(sinif ?? '') == null) {
      throw const FormatException(
        'Ders adı veya sınıf seviyesi güvenilir biçimde okunamadı. Desteklenen MEB DBF düzenindeki PDF’yi seçin.',
      );
    }
    return DbfBelgesi(
      dosyaAdi: dosyaAdi,
      dersAdi: ad,
      sinifSeviyesi: int.parse(sinif!),
      sayfalar: sayfalar,
      icerikOzeti: icerikOzeti,
      pdfBytes: pdfBytes,
    );
  }

  Map<String, Object?> toJson() => {
    'bicim': 1,
    'dosyaAdi': dosyaAdi,
    'dersAdi': dersAdi,
    'sinifSeviyesi': sinifSeviyesi,
    'sayfalar': sayfalar,
    'icerikOzeti': icerikOzeti,
    'surum': surum,
    'kaynakAdresi': kaynakAdresi,
    'programSurumu': programSurumu,
    'kayitTarihi': kayitTarihi,
    'belgeId': belgeId,
    'arsivId': arsivId,
  };

  factory DbfBelgesi.fromJson(Map<String, dynamic> m) {
    if (m['bicim'] != 1) {
      throw const FormatException('DBF kayıt biçimi desteklenmiyor.');
    }
    return DbfBelgesi(
      dosyaAdi: m['dosyaAdi'] as String,
      dersAdi: m['dersAdi'] as String,
      sinifSeviyesi: m['sinifSeviyesi'] as int,
      sayfalar: (m['sayfalar'] as List).cast<String>(),
      icerikOzeti: m['icerikOzeti'] as String,
      surum: m['surum'] as int,
      kaynakAdresi: m['kaynakAdresi'] as String,
      programSurumu: m['programSurumu'] as String,
      kayitTarihi: m['kayitTarihi'] as String,
      belgeId: m['belgeId'] as String?,
      arsivId: m['arsivId'] as String?,
    );
  }
}
