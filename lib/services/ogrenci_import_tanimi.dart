import 'package:flutter/material.dart';

import '../models/ortak_import.dart';
import 'bireysel_import_service.dart';

class OgrenciImportTanimi {
  static const tanim = ImportTanimi(
    id: 'bireysel_ogrenci',
    ad: 'Öğrenci Import',
    aciklama:
        'Tek sınıf veya tüm sınıfları içeren e-Okul dosyasını seçebilirsiniz. '
        'Dosyadaki ders verdiğiniz sınıflar birlikte bu cihaza kaydedilir. '
        'Diğer sınıfları Kaydet adımında ayrıca seçebilirsiniz. '
        'Önce ders programınızı yükleyin. Dosyada olmayan öğrenciler korunur.',
    alanlar: [
      ImportAlan(
        'okulNo',
        'Okul No',
        zorunlu: true,
        alternatifler: [
          'Öğrenci No',
          'Öğrenci Numarası',
          'Okul Numarası',
          'Numara',
        ],
      ),
      ImportAlan(
        'ad',
        'Ad',
        zorunlu: true,
        alternatifler: ['Adı', 'Öğrenci Adı'],
      ),
      ImportAlan(
        'soyad',
        'Soyad',
        zorunlu: true,
        alternatifler: ['Soyadı', 'Öğrenci Soyadı'],
      ),
      ImportAlan(
        'sinif',
        'Sınıf',
        zorunlu: true,
        kolonDisiKapsam: ImportBilgiKapsami.blok,
        alternatifler: ['Sınıfı', 'Sınıf Şube', 'Sınıf/Şube', 'Sınıf Kodu'],
        filtrelenebilir: true,
        gruplanabilir: true,
      ),
      ImportAlan(
        'cinsiyet',
        'Cinsiyet',
        alternatifler: ['Cinsiyeti'],
        filtrelenebilir: true,
      ),
      ImportAlan(
        'alan',
        'Alan',
        kolonDisiKapsam: ImportBilgiKapsami.blok,
        alternatifler: ['Alanı', 'Bölüm'],
        filtrelenebilir: true,
      ),
      ImportAlan('veliAdi', 'Veli Adı', alternatifler: ['Veli Ad Soyad', 'Velisi']),
      ImportAlan('veliTelefonu', 'Veli Telefonu', alternatifler: ['Veli Telefon', 'Veli Cep Telefonu']),
      ImportAlan(
        'rehberOgretmen',
        'Rehber Öğretmen',
        kolonDisiKapsam: ImportBilgiKapsami.blok,
        alternatifler: [
          'Sınıf Öğretmeni',
          'Öğretmen',
          'Öğretmen Adı',
          'Öğretmen Ad Soyad',
        ],
        filtrelenebilir: true,
        gruplanabilir: true,
      ),
    ],
    hazirla: BireyselImportService.ortakOgrenciTumSinifOnIzlemeHazirla,
    aktar: BireyselImportService.ortakOgrencileriKaydet,
    ozelOku: BireyselImportService.ortakOgrenciOzelOku,
    ozelDuzeniTani: _sinifBloklariniTani,
    blokBaslangici: _sinifBlogunuOku,
    ozelOkuyucuAdi: 'e-Okul özel düzeni (tüm sayfalar)',
  );

  static Map<String, String>? _sinifBlogunuOku(List<String> satir) {
    final text = satir.join(' ');
    final match = RegExp(
      r'\b(\d{1,2})\s+sinif\s+([a-z])\s+subesi(?:\s|$)',
    ).firstMatch(importNormalize(text));
    if (match == null) return null;
    return {
      'sinif': '${int.parse(match[1]!)}-${match[2]!.toUpperCase()}',
      'alan': RegExp(r'\(([^)]+)\)').firstMatch(text)?.group(1)?.trim() ?? '',
    };
  }

  static bool _sinifBloklariniTani(List<List<List<String>>> sayfalar) =>
      sayfalar.any(
        (sayfa) => sayfa.any(
          (satir) => RegExp(
            r'\b\d{1,2}\s+sinif\s+[a-z]\s+subesi(?:\s|$)',
          ).hasMatch(importNormalize(satir.join(' '))),
        ),
      );
}

class OgrenciImportKayitAkisi {
  OgrenciImportKayitAkisi({
    Map<String, int> Function(ImportOnIzleme)? ekSinifOzeti,
    Future<ImportOzet> Function(ImportOnIzleme, Set<String>,
        {Set<String> ekSiniflar})? kaydet,
  }) : _ekSinifOzeti = ekSinifOzeti ?? BireyselImportService.ogrenciEkSinifOzeti,
       _kaydet = kaydet ?? BireyselImportService.ortakOgrencileriKaydet;

  final Map<String, int> Function(ImportOnIzleme) _ekSinifOzeti;
  final Future<ImportOzet> Function(ImportOnIzleme, Set<String>,
      {Set<String> ekSiniflar}) _kaydet;
  ImportOnIzleme? _onIzleme;
  final _ekSiniflar = <String>{};

  bool bosSecimleAktarilabilir(ImportOnIzleme preview) =>
      _ekSinifOzeti(preview).isNotEmpty;

  Map<String, int> _normalSinifOzeti(ImportSecimi secim) {
    final ogrenciler = <String, Set<String>>{};
    for (final row in secim.onIzleme.kayitlar) {
      if (!row.aktarilabilir || !secim.secimler.contains(row.id)) {
        continue;
      }
      final sinif = row.degerler['sinif'] ?? '';
      (ogrenciler[sinif] ??= <String>{}).add(row.id);
    }
    final siniflar = ogrenciler.keys.toList()..sort((a, b) {
      final seviye = (int.tryParse(a.split('-').first) ?? 0)
          .compareTo(int.tryParse(b.split('-').first) ?? 0);
      return seviye == 0 ? a.compareTo(b) : seviye;
    });
    return {for (final s in siniflar) s: ogrenciler[s]!.length};
  }

  Future<bool> onayla(
    BuildContext context,
    ImportSecimi secim,
    String ortakOzet,
  ) async {
    final ekler = _ekSinifOzeti(secim.onIzleme);
    if (!identical(_onIzleme, secim.onIzleme)) {
      _onIzleme = secim.onIzleme;
      _ekSiniflar.clear();
    }
    _ekSiniflar.retainAll(ekler.keys);
    final normal = _normalSinifOzeti(secim);
    final ekToplam = ekler.values.fold<int>(0, (n, v) => n + v);
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: const Text('Öğrenci Kayıt Özeti'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ortakOzet),
                  const Divider(),
                  Text('Seçili normal sınıflar: ${normal.length} • '
                      'Öğrenci: ${secim.secimler.length}'),
                  for (final e in normal.entries)
                    Text('${e.key}: ${e.value} öğrenci'),
                  if (ekler.isNotEmpty) ...[
                    const Divider(),
                    const Text('Ders programınızda olmayan sınıflar'),
                    Text('${ekler.length} sınıf • $ekToplam öğrenci. '
                        'Kaydetmek istediğiniz sınıfları seçin. '
                        'Seçilmeyen sınıflar kaydedilmez.'),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tüm Ek Sınıfları Seç'),
                      tristate: true,
                      value: _ekSiniflar.isEmpty
                          ? false
                          : _ekSiniflar.length == ekler.length ? true : null,
                      onChanged: (value) => yenile(() {
                        _ekSiniflar.clear();
                        if (value != false) {
                          _ekSiniflar.addAll(ekler.keys);
                        }
                      }),
                    ),
                    for (final e in ekler.entries)
                      CheckboxListTile(
                        key: ValueKey('ek-sinif:${e.key}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.key),
                        subtitle: Text('${e.value} öğrenci'),
                        value: _ekSiniflar.contains(e.key),
                        onChanged: (value) => yenile(() {
                          if (value == true) {
                            _ekSiniflar.add(e.key);
                          } else {
                            _ekSiniflar.remove(e.key);
                          }
                        }),
                      ),
                    Text('Seçilen ek sınıf: ${_ekSiniflar.length} • '
                        'Öğrenci: ${_ekSiniflar.fold<int>(0, (n, s) => n + ekler[s]!)}'),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            if (ekler.isNotEmpty)
              TextButton(
                onPressed: secim.secimler.isEmpty ? null : () {
                  _ekSiniflar.clear();
                  Navigator.pop(ctx, true);
                },
                child: const Text('Yalnız Normal Sınıfları Kaydet'),
              ),
            FilledButton(
              onPressed: secim.secimler.isEmpty && _ekSiniflar.isEmpty
                  ? null : () => Navigator.pop(ctx, true),
              child: Text(ekler.isEmpty ? 'Onayla ve Aktar' : 'Seçilenlerle Kaydet'),
            ),
          ],
        ),
      ),
    );
    return onay == true;
  }

  Future<ImportOzet> kaydet(ImportSecimi secim) async {
    final ekler = _ekSinifOzeti(secim.onIzleme);
    final ekSecimler = Set<String>.unmodifiable(_ekSiniflar);
    final sonuc = await _kaydet(secim.onIzleme, secim.secimler,
        ekSiniflar: ekSecimler);
    final siniflar = _normalSinifOzeti(secim);
    for (final kod in ekSecimler) {
      siniflar[kod] = (siniflar[kod] ?? 0) + ekler[kod]!;
    }
    final toplam = siniflar.values.fold<int>(0, (n, v) => n + v);
    return ImportOzet(
      eklenen: sonuc.eklenen,
      guncellenen: sonuc.guncellenen,
      atlanan: sonuc.atlanan,
      hatali: sonuc.hatali,
      mesaj: '${sonuc.mesaj}\n\nİşleme alınan: ${siniflar.length} sınıf • '
          '$toplam öğrenci\n${siniflar.entries.map((e) => '${e.key}: ${e.value} öğrenci').join('\n')}',
    );
  }
}
