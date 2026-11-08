import 'package:flutter/services.dart';
import '../models/ogrenci_bilgi_formu.dart';
import '../models/ortak_import.dart';

/// Paylaşılan import ön izlemesinde her form alanı tek satırdır. OCR sonucu
/// doğrulanmış veri değildir; hiçbir satır kendiliğinden seçilmez.
class RehberlikFormImport {
  RehberlikFormImport({required this.okulNo, required this.adSoyad});
  final String okulNo, adSoyad;
  static const kanal = MethodChannel('elpi_okul_yonetim/rehberlik_ocr');
  static const uzantilar = {'jpg', 'jpeg', 'png', 'webp'};
  List<String> get sorular => ogrenciBilgiFormuSorulari;
  ImportTanimi tanim(
    Future<ImportOnIzleme> Function(ImportDosya) oku,
  ) => ImportTanimi(
    id: 'bireysel_rehberlik_form',
    ad: 'Öğrenci Bilgi Formu Import',
    aciklama:
        'Hedef: $okulNo • $adSoyad. Resim cihazda okunur. El yazısı hatalı okunabilir. Her değeri kaynak resimle karşılaştırın, gerekirse satırı düzenleyin ve aktarılacak alanları seçin. Seçim yalnız form taslağına alınır; kalıcı kayıt için Yeni sürüm olarak kaydet düğmesini kullanın. Öğrenci ana kaydı değiştirilmez.',
    alanlar: const [
      ImportAlan('alan', 'Form alanı', kolondan: false),
      ImportAlan('deger', 'Okunan değer'),
    ],
    uzantilar: uzantilar,
    yalnizOzelOkuyucu: true,
    ozelOkuyucuAdi: 'Öğrenci Bilgi Formu resmini oku',
    ozelOku: oku,
    hazirla: hazirla,
    duzenlemeHazirla: (once, satirlar) async => hazirla(satirlar),
    aktar: (_, __) async => throw StateError(
      'Önce form ekranına dönüp yeni sürüm olarak kaydedin.',
    ),
  );
  Future<ImportOnIzleme> resimOku(
    ImportDosya normal,
    List<double> koseler,
  ) async {
    final values = await resimDegerleriniOku(normal, koseler);
    return hazirla([
      for (var i = 0; i < sorular.length; i++)
        ImportKaynakSatiri('$i', sorular[i], {
          'alan': sorular[i],
          'deger': values[sorular[i]] ?? '',
        }),
    ]);
  }

  /// Hedef öğrenci tekli/toplu ön izleme aşamasında belirlenir.
  static Future<Map<String, String>> resimDegerleriniOku(
    ImportDosya normal,
    List<double> koseler,
  ) async {
    final reader = RehberlikFormImport(okulNo: '', adSoyad: '');
    final result = await kanal.invokeMapMethod<String, String>('oku', {
      'bytes': normal.bytes,
      'koseler': koseler,
      'alanlar': reader.bolgeler,
    });
    if (result == null) throw StateError('Görsel okuyucu sonuç döndürmedi.');
    return {
      for (var i = 0; i < reader.sorular.length; i++)
        reader.sorular[i]: temizle(
          result['$i'] ?? '',
          etiketler[reader.sorular[i]] ?? const [],
        ),
    };
  }

  Future<ImportOnIzleme> hazirla(List<ImportKaynakSatiri> sources) async {
    final seen = <String>{};
    final rows = <ImportKaydi>[];
    for (final source in sources) {
      final index = int.tryParse(source.id);
      if (index == null ||
          index < 0 ||
          index >= sorular.length ||
          source.id != '$index' ||
          !seen.add(source.id)) {
        throw const FormatException('Form alanı veya kayıt kimliği geçersiz.');
      }
      final question = sorular[index];
      final value = (source.degerler['deger'] ?? '').trim();
      final errors = <String>[];
      if (value.isEmpty) {
        errors.add(
          'Değer okunamadı veya boş. Resme bakıp satırı düzenleyin; boş alanı aktarmayın.',
        );
      }
      if (value.length > 5000) {
        errors.add('Değer 5000 karakter sınırını aşıyor.');
      }
      if (question == 'Adınız Soyadınız' &&
          importNormalize(value) != importNormalize(adSoyad)) {
        errors.add(
          'Formdaki ad soyad seçili öğrenciyle eşleşmiyor. Resimden kontrol edip düzeltin.',
        );
      }
      if (question == 'Okul numaranız' && numara(value) != numara(okulNo)) {
        errors.add('Formdaki okul numarası seçili öğrenciyle eşleşmiyor.');
      }
      rows.add(
        ImportKaydi(
          source.id,
          question,
          {'alan': question, 'deger': value},
          durum: errors.isEmpty ? ImportDurumu.uyarili : ImportDurumu.hatali,
          mesajlar: errors.isEmpty
              ? const ['Resimdeki el yazısıyla karşılaştırarak onaylayın.']
              : errors,
        ),
      );
    }
    final blockers = <String>[];
    for (final identity in ['Adınız Soyadınız', 'Okul numaranız']) {
      final found = rows.where((r) => r.degerler['alan'] == identity);
      if (found.length != 1 || !found.single.aktarilabilir) {
        blockers.add(
          '$identity alanını resimle karşılaştırıp seçili öğrenciyle eşleştirin.',
        );
      }
    }
    return ImportOnIzleme(
      rows,
      engeller: blockers,
      bilgiler: const [
        'Boş ve seçilmeyen alanlar mevcut taslağı silmez. Resim yalnız bu oturumda bellekte tutulur.',
        'Öğrenci ve veli ana kayıtları güncellenmez; değerler bu formun cevabı olarak tutulur.',
      ],
    );
  }

  static String numara(String value) {
    final v = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) return v;
    return v.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  }

  static String temizle(String raw, List<String> labels) {
    var text = raw.trim();
    for (final label in labels) {
      final words = RegExp(r'\S+').allMatches(text).toList();
      final target = importNormalize(label);
      var best = 0.0, end = 0;
      final maxWords = label.split(' ').length + 3;
      for (var i = 0; i < words.length && i < maxWords; i++) {
        final prefix = importNormalize(text.substring(0, words[i].end));
        final n = prefix.length > target.length ? prefix.length : target.length;
        if (n == 0) continue;
        final score = 1 - _mesafe(prefix, target) / n;
        if (score > best) {
          best = score;
          end = words[i].end;
        }
      }
      if (best >= .78) {
        text = text
            .substring(end)
            .replaceFirst(RegExp(r'^[\s:;?.–-]+'), '')
            .trim();
        break;
      }
    }
    return text;
  }

  static int _mesafe(String a, String b) {
    var prev = List.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final next = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        final sub = prev[j] + (a[i] == b[j] ? 0 : 1);
        final ins = next[j] + 1, del = prev[j + 1] + 1;
        next.add(sub < ins ? (sub < del ? sub : del) : (ins < del ? ins : del));
      }
      prev = next;
    }
    return prev.last;
  }

  static const etiketler = <String, List<String>>{
    'Form tarihi': ['Tarih'],
    'Adınız Soyadınız': ['Adınız Soyadınız'],
    'Okulunuz': ['Okulunuz'],
    'Cinsiyetiniz': ['Cinsiyetiniz'],
    'Doğum yeriniz': ['Doğum Yeri ve', 'Doğum Yeri'],
    'Doğum tarihiniz': ['Doğum Tarihiniz'],
    'Adresiniz': ['Adresiniz'],
    'Okul öncesi eğitim aldınız mı?': ['Okul öncesi eğitim aldınız mı'],
    'Ne yapmaktan hoşlanırsınız?': ['Ne yapmaktan hoşlanırsınız'],
    'Yakın zamanda taşındınız mı, okul değiştirdiniz mi?': [
      'Yakın zamanda taşındınız mı okul değiştirdiniz mi',
    ],
    'Kendinize ait teknolojik aletleriniz var mı? Varsa günde/haftada ne kadar süre kullanırsınız?': [
      'Kendinize ait teknolojik aletleriniz var mı Varsa günde haftada ne kadar süre kullanırsınız',
    ],
    'Sürekli kullandığınız ilaç ve tıbbi cihaz var mı? Nedir?': [
      'Sürekli kullandığınız ilaç ve tıbbi cihaz var mı Nedir',
    ],
    'Sürekli bir hastalığınız var mı? Varsa nedir?': [
      'Sürekli bir hastalığınız var mı Varsa nedir',
    ],
    'Ders dışı faaliyetleriniz nelerdir?': [
      'Ders dışı faaliyetleriniz nelerdir',
    ],
    'Hâlâ etkisi altında olduğunuz bir olay yaşadınız mı? Yaşamışsanız açıklayınız.': [
      'Hâlâ etkisi altında olduğunuz bir olay yaşadınız mı Yaşamışsanız açıklayınız',
    ],
    'Veli adı soyadı': ['Adı Soyadı'],
    'Veli yakınlığı': ['Yakınlığı'],
    'Veli telefon numarası': ['Telefon Numarası'],
    'Veli eğitim durumu': ['Eğitim Durumu'],
    'Veli mesleği': ['Mesleği'],
    'Kaç kardeşsiniz?': ['Kaç kardeşsiniz'],
    'Ailenizin kaçıncı çocuğusunuz?': ['Ailenizin kaçıncı çocuğusunuz'],
    'Okula giden kardeş sayınız': ['Okula giden kardeş sayınız'],
    'Aile üyelerinde sürekli bir hastalığı/engeli olan biri var mı? Varsa yazınız.': [
      'Aile üyelerinde sürekli bir hastalığı engeli olan biri var mı Varsa yazınız',
    ],
    'Evinizde sizinle birlikte kim/kimler yaşıyor? Yakınlık derecelerini belirtiniz.': [
      'Evinizde sizinle birlikte kim kimler yaşıyor Yakınlık derecelerini belirtiniz',
    ],
  };

  /// Kullanıcının paylaştığı basılı formun tablo alanına göre normalize hücreler.
  List<Map<String, Object>> get bolgeler {
    final boxes = <String, List<double>>{};
    void box(String key, double l, double t, double r, double b) =>
        boxes[key] = [l, t, r, b];
    box('Form tarihi', .80, -.14, .995, -.02);
    box('Adınız Soyadınız', .155, .044, .495, .089);
    box('Sınıfınız', .175, .089, .32, .134);
    box('Okul numaranız', .32, .089, .495, .134);
    box('Okulunuz', .005, .134, .495, .177);
    box('Cinsiyetiniz', .505, .044, .995, .089);
    box('Doğum yeriniz', .505, .089, .995, .111);
    box('Doğum tarihiniz', .505, .111, .995, .134);
    box('Adresiniz', .505, .134, .995, .177);
    final left = ogrenciBilgiFormuBolumleri['Öğrenci Bilgisi']!.sublist(9, 13);
    final right = ogrenciBilgiFormuBolumleri['Öğrenci Bilgisi']!.sublist(13);
    const ys = [.177, .231, .285, .339, .405];
    for (var i = 0; i < 4; i++) {
      box(left[i], .005, ys[i], .495, ys[i + 1]);
      box(right[i], .505, ys[i], .995, ys[i + 1]);
    }
    box('Veli adı soyadı', .005, .453, .495, .51);
    box('Veli yakınlığı', .505, .453, .995, .48);
    box('Veli telefon numarası', .505, .48, .995, .51);
    box('Veli eğitim durumu', .005, .51, .495, .54);
    box('Veli mesleği', .505, .51, .995, .54);
    for (final parent in ['Anne', 'Baba']) {
      final fields = ogrenciBilgiFormuBolumleri['$parent Bilgisi']!;
      for (var i = 0; i < fields.length; i++) {
        box(
          fields[i],
          parent == 'Anne' ? .005 : .67,
          .59 + i * .0257,
          parent == 'Anne' ? .33 : .995,
          .59 + (i + 1) * .0257,
        );
      }
    }
    box('Kaç kardeşsiniz?', .005, .831, .495, .883);
    box('Ailenizin kaçıncı çocuğusunuz?', .505, .831, .995, .883);
    box('Okula giden kardeş sayınız', .005, .883, .495, .936);
    box(
      'Aile üyelerinde sürekli bir hastalığı/engeli olan biri var mı? Varsa yazınız.',
      .505,
      .883,
      .995,
      .936,
    );
    box(
      'Evinizde sizinle birlikte kim/kimler yaşıyor? Yakınlık derecelerini belirtiniz.',
      .005,
      .936,
      .995,
      .995,
    );
    return [
      for (var i = 0; i < sorular.length; i++)
        if (boxes.containsKey(sorular[i]))
          {'id': '$i', 'kutu': boxes[sorular[i]]!},
    ];
  }
}
