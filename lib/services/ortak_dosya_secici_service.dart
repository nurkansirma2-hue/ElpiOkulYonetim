import 'dart:typed_data';

import 'package:flutter/services.dart';

class OrtakKlasorBilgisi {
  const OrtakKlasorBilgisi({
    required this.ad,
    required this.uri,
  });

  final String ad;
  final String uri;

  factory OrtakKlasorBilgisi.fromMap(Map<dynamic, dynamic> map) {
    return OrtakKlasorBilgisi(
      ad: (map['ad'] ?? 'Seçili Klasör').toString(),
      uri: (map['uri'] ?? '').toString(),
    );
  }
}

class OrtakDosyaKaydi {
  const OrtakDosyaKaydi({
    required this.ad,
    required this.uri,
    required this.klasorMu,
    required this.mimeType,
    required this.boyut,
    required this.degistirilmeZamani,
  });

  final String ad;
  final String uri;
  final bool klasorMu;
  final String mimeType;
  final int boyut;
  final int degistirilmeZamani;

  String get uzanti {
    if (klasorMu) {
      return '';
    }

    final nokta = ad.lastIndexOf('.');

    if (nokta < 0 || nokta == ad.length - 1) {
      return '';
    }

    return ad.substring(nokta + 1).trim().toLowerCase();
  }

  bool uzantiDestekleniyor(Iterable<String> uzantilar) {
    final desteklenenler = uzantilar
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();

    return desteklenenler.contains(uzanti);
  }

  factory OrtakDosyaKaydi.fromMap(Map<dynamic, dynamic> map) {
    return OrtakDosyaKaydi(
      ad: (map['ad'] ?? '').toString(),
      uri: (map['uri'] ?? '').toString(),
      klasorMu: map['klasorMu'] == true,
      mimeType: (map['mimeType'] ?? '').toString(),
      boyut: _intDegeri(map['boyut']),
      degistirilmeZamani: _intDegeri(map['degistirilmeZamani']),
    );
  }

  static int _intDegeri(dynamic deger) {
    if (deger is int) {
      return deger;
    }

    if (deger is num) {
      return deger.toInt();
    }

    return int.tryParse(deger?.toString() ?? '') ?? 0;
  }
}

class OrtakDosyaSeciciService {
  OrtakDosyaSeciciService._();

  static const MethodChannel _channel = MethodChannel(
    'elpi_okul_yonetim/dosya_secici',
  );

  static Future<OrtakKlasorBilgisi?> kokKlasorSec() async {
    try {
      final sonuc = await _channel.invokeMethod<dynamic>(
        'kokKlasorSec',
      );

      if (sonuc == null) {
        return null;
      }

      if (sonuc is! Map) {
        throw Exception(
          'Android tarafından geçersiz klasör bilgisi döndürüldü.',
        );
      }

      final klasor = OrtakKlasorBilgisi.fromMap(sonuc);

      if (klasor.uri.trim().isEmpty) {
        throw Exception(
          'Seçilen klasörün URI bilgisi boş geldi.',
        );
      }

      return klasor;
    } on PlatformException catch (e) {
      throw Exception(
        'Ana klasör seçilirken hata oluştu.\n'
        'Orijinal hata: ${e.code} - ${e.message}\n'
        'Detay: ${e.details}',
      );
    } catch (e) {
      throw Exception(
        'Ana klasör seçilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<OrtakKlasorBilgisi?> kayitliKokKlasoruGetir() async {
    try {
      final sonuc = await _channel.invokeMethod<dynamic>(
        'kayitliKokKlasoruGetir',
      );

      if (sonuc == null) {
        return null;
      }

      if (sonuc is! Map) {
        throw Exception(
          'Android tarafından geçersiz kayıtlı klasör bilgisi döndürüldü.',
        );
      }

      final klasor = OrtakKlasorBilgisi.fromMap(sonuc);

      if (klasor.uri.trim().isEmpty) {
        return null;
      }

      return klasor;
    } on PlatformException catch (e) {
      throw Exception(
        'Kayıtlı ana klasör okunurken hata oluştu.\n'
        'Orijinal hata: ${e.code} - ${e.message}\n'
        'Detay: ${e.details}',
      );
    } catch (e) {
      throw Exception(
        'Kayıtlı ana klasör okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<List<OrtakDosyaKaydi>> klasorListele(
    String uri,
  ) async {
    if (uri.trim().isEmpty) {
      throw Exception(
        'Listelenecek klasörün URI bilgisi boş.',
      );
    }

    try {
      final sonuc = await _channel.invokeMethod<dynamic>(
        'klasorListele',
        <String, dynamic>{
          'uri': uri,
        },
      );

      if (sonuc == null) {
        return const <OrtakDosyaKaydi>[];
      }

      if (sonuc is! List) {
        throw Exception(
          'Android tarafından geçersiz klasör listesi döndürüldü.',
        );
      }

      return sonuc
          .whereType<Map>()
          .map((e) => OrtakDosyaKaydi.fromMap(e))
          .where(
            (e) => e.ad.trim().isNotEmpty && e.uri.trim().isNotEmpty,
          )
          .toList(growable: false);
    } on PlatformException catch (e) {
      throw Exception(
        'Klasör içeriği okunurken hata oluştu.\n'
        'Orijinal hata: ${e.code} - ${e.message}\n'
        'Detay: ${e.details}',
      );
    } catch (e) {
      throw Exception(
        'Klasör içeriği okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<Uint8List> dosyaOku(
    String uri,
  ) async {
    if (uri.trim().isEmpty) {
      throw Exception(
        'Okunacak dosyanın URI bilgisi boş.',
      );
    }

    try {
      final sonuc = await _channel.invokeMethod<dynamic>(
        'dosyaOku',
        <String, dynamic>{
          'uri': uri,
        },
      );

      Uint8List? bytes;

      if (sonuc is Uint8List) {
        bytes = sonuc;
      } else if (sonuc is List) {
        bytes = Uint8List.fromList(
          sonuc
              .whereType<num>()
              .map((e) => e.toInt())
              .toList(growable: false),
        );
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception(
          'Seçilen dosyanın içeriği boş veya okunamadı.',
        );
      }

      return bytes;
    } on PlatformException catch (e) {
      throw Exception(
        'Dosya okunurken hata oluştu.\n'
        'Orijinal hata: ${e.code} - ${e.message}\n'
        'Detay: ${e.details}',
      );
    } catch (e) {
      throw Exception(
        'Dosya okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }
}
