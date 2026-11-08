import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/ortak_import.dart';
import 'ogrenci_import_tanimi.dart';
import 'ortak_import_service.dart';
import 'yillik_plan_import_tanimi.dart';

class BelgeAnalizi {
  const BelgeAnalizi(this.tur, this.aciklama, this.adaylar);
  final String tur, aciklama;
  final List<String> adaylar;
  String toJson() => jsonEncode({
    'surum': 1,
    'tur': tur,
    'aciklama': aciklama,
    'adaylar': adaylar,
  });
  static BelgeAnalizi? fromJson(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      if (m['surum'] != 1) return null;
      return BelgeAnalizi(
        m['tur'] as String,
        m['aciklama'] as String,
        (m['adaylar'] as List).cast<String>(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Tanıma bir öneridir. Kaydetme uygunluğu her zaman modülün gerçek
/// okuyucusu, hata kontrolü ve kullanıcı onayı ile belirlenir.
class BelgeAnalizService {
  static Future<String> docxMetni(Uint8List bytes) => Isolate.run(() {
    final f = _officeZip(bytes).findFile('word/document.xml');
    if (f == null) {
      throw const FormatException('Word belge içeriği bulunamadı.');
    }
    final xml = XmlDocument.parse(utf8.decode(f.content as List<int>));
    return xml.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p')
        .map(
          (e) => e.descendants
              .whereType<XmlElement>()
              .where((t) => t.name.local == 't')
              .map((t) => t.innerText)
              .join(),
        )
        .join('\n');
  });
  static Future<void> bicimiDogrulaAsync(ImportDosya dosya) =>
      Isolate.run(() => bicimiDogrula(dosya));
  static void bicimiDogrula(ImportDosya dosya) {
    if (dosya.bytes.isEmpty || dosya.bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('Dosya boş veya 50 MB sınırından büyük.');
    }
    final b = dosya.bytes, ext = dosya.uzanti;
    if (ext == 'xls' || ext == 'doc') {
      const sig = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
      if (b.length < 8 ||
          List.generate(8, (i) => b[i]).join(',') != sig.join(',')) {
        throw const FormatException(
          'Dosya gerçek bir eski Office dosyası değil. Uzantısını değiştirerek import yapmayın.',
        );
      }
    } else if (ext == 'xlsx' || ext == 'docx') {
      final archive = _officeZip(b);
      final entry = ext == 'xlsx' ? 'xl/workbook.xml' : 'word/document.xml';
      if (archive.findFile(entry) == null) {
        throw FormatException('Dosya içeriği .$ext biçimiyle uyuşmuyor.');
      }
    } else if (ext == 'csv') {
      final text = utf8.decode(b, allowMalformed: true);
      if (text.contains('\u0000')) {
        throw const FormatException('CSV dosyası metin içermiyor.');
      }
    }
  }

  static Archive _officeZip(Uint8List b) {
    if (b.length < 4 || b[0] != 0x50 || b[1] != 0x4b) {
      throw const FormatException(
        'Office dosyası geçerli bir ZIP kapsayıcısı değil.',
      );
    }
    final a = ZipDecoder().decodeBytes(b);
    if (a.files.length > 20000 ||
        a.files.fold<int>(0, (sum, f) => sum + f.size) > 100 * 1024 * 1024) {
      throw const FormatException(
        'Office dosyasının açılmış içeriği güvenli boyut sınırını aşıyor.',
      );
    }
    return a;
  }

  static Future<BelgeAnalizi> analizEt(ImportDosya file) async {
    try {
      await Isolate.run(() => bicimiDogrula(file));
      final adaylar = <String>{};
      String text = '';
      if (const {'xlsx', 'xls', 'csv'}.contains(file.uzanti)) {
        final tables = await OrtakImportService.oku(file);
        for (final table in tables) {
          final sh = table.baslikBul(OgrenciImportTanimi.tanim);
          final sm = table.otomatikEsle(OgrenciImportTanimi.tanim, sh);
          if (sm.containsKey('okulNo') &&
              sm.containsKey('ad') &&
              sm.containsKey('soyad')) {
            adaylar.add('Öğrenci listesi');
          }
          final yr = YillikPlanImportTanimi.olustur('');
          final yh = table.baslikBul(yr),
              ym = table.otomatikEsle(yr, table.baslikBul(yr));
          if (yh >= 0 &&
              ym.containsKey('hafta') &&
              const [
                'konu',
                'kazanim',
                'ogrenmeCiktisi',
                'icerikCercevesi',
              ].any(ym.containsKey)) {
            adaylar.add('Yıllık plan');
          }
        }
        text = tables
            .expand((t) => t.satirlar.take(100))
            .map((r) => r.join(' '))
            .join('\n');
      } else if (file.uzanti == 'docx') {
        text = await Isolate.run(() {
          final f = _officeZip(file.bytes).findFile('word/document.xml')!;
          final xml = XmlDocument.parse(utf8.decode(f.content as List<int>));
          return xml.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join(' ');
        });
      } else if (file.uzanti == 'txt') {
        text = utf8.decode(file.bytes, allowMalformed: true);
      }
      final n = importNormalize(text);
      bool has(String s) => n.contains(s);
      if ((has('pazartesi') && has('sali') && has('carsamba')) ||
          (has('ders saati') && has('gun') && has('ders'))) {
        adaylar.add('Ders programı');
      }
      if (has('hafta') &&
          (has('kazanim') || has('ogrenme ciktisi')) &&
          (has('yillik') || has('plan'))) {
        adaylar.add('Yıllık plan');
      }
      if (has('okul no') && has('ad soyad') && has('sinif')) {
        adaylar.add('Öğrenci listesi');
      }
      if ((has('ogretmen listesi') || has('ogretmen adi')) && has('brans')) {
        adaylar.add('Öğretmen listesi');
      }
      if (has('ders kodu') && has('ders adi')) adaylar.add('Ders listesi');
      if (has('bireysellestirilmis egitim') || has('bep plani')) {
        adaylar.add('BEP belgesi');
      }
      final tur = adaylar.length == 1 ? adaylar.single : 'Genel belge';
      return BelgeAnalizi(
        tur,
        adaylar.isEmpty
            ? 'İçerik otomatik tanınamadı. Genel belge olarak saklanır; türü kendiniz seçebilirsiniz.'
            : adaylar.length > 1
            ? 'Birden fazla tür adayı bulundu. Türü siz seçin; sessiz atama yapılmadı.'
            : 'İçerikten önerilen tür: $tur. Aktarımdan önce mevcut import ön izlemesini kontrol edin.',
        adaylar.toList(),
      );
    } catch (e) {
      return BelgeAnalizi(
        'Genel belge',
        'Otomatik analiz tamamlanamadı; belge korunuyor. Orijinal hata: $e',
        const [],
      );
    }
  }
}
