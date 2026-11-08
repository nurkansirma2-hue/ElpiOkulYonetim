import '../models/ogrenci_bilgi_formu.dart';
import '../models/ortak_import.dart';
import 'bireysel_rehberlik_service.dart';
import 'rehberlik_form_import.dart';

class TopluFormOnIzlemeVerisi {
  TopluFormOnIzlemeVerisi(Map<int, int?> surumler)
    : surumler = Map.unmodifiable(surumler);
  final Map<int, int?> surumler;
}

class RehberlikTopluFormImport {
  RehberlikTopluFormImport({
    required this.service,
    required this.baglam,
    required this.atamaId,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final int atamaId;
  static const azamiDosya = 50;
  static const azamiToplamBoyut = 100 * 1024 * 1024;
  List<String> get sorular => ogrenciBilgiFormuSorulari;
  ImportTanimi get tanim => ImportTanimi(
    id: 'bireysel_rehberlik_toplu_form',
    ad: 'Toplu Öğrenci Bilgi Formu Import',
    aciklama:
        'Bir resim bir öğrenci formudur. En fazla 50 resim / toplam 100 MB seçin. Her resim cihazda okunur; okul numarası ve ad soyad bu rehberlik sınıfının aktif öğrencileriyle eşleştirilir. Kaynak resmi açıp cevapları kontrol edin; düzeltmek için kayıt bilgilerine uzun basın. El yazısı sonuçları kendiliğinden seçilmez. Yalnız seçilen formlar yeni sürüm olarak kaydedilir; boş alanlar önceki cevapları silmez. Aynı öğrenciye ait tekrarlarda bir formun İşlem alanını Atla yapın.',
    alanlar: [
      const ImportAlan('islem', 'İşlem (Aktar / Atla)'),
      const ImportAlan('eslesen', 'Eşleşen öğrenci', kolondan: false),
      const ImportAlan('adet', 'Dolu alan sayısı', kolondan: false),
      for (var i = 0; i < sorular.length; i++)
        ImportAlan(
          'q$i',
          sorular[i],
          onIzlemede: [
            'Adınız Soyadınız',
            'Okul numaranız',
            'Sınıfınız',
          ].contains(sorular[i]),
          filtrelenebilir: sorular[i] == 'Sınıfınız',
          gruplanabilir: sorular[i] == 'Sınıfınız',
        ),
    ],
    uzantilar: RehberlikFormImport.uzantilar,
    yalnizOzelOkuyucu: true,
    ozelOkuyucuAdi: 'Seçilen form resimlerini sırayla oku ve eşleştir',
    ozelOku: (_) async => throw StateError('Toplu resim okuyucusunu kullanın.'),
    hazirla: hazirla,
    duzenlemeHazirla: (once, satirlar) =>
        hazirla(satirlar, onceki: once.veri as TopluFormOnIzlemeVerisi),
    aktar: kaydet,
  );
  ImportKaynakSatiri kaynak(
    String id,
    String dosya,
    Map<String, String> values, {
    String? hata,
  }) => ImportKaynakSatiri(id, dosya, {
    'islem': 'Aktar',
    for (var i = 0; i < sorular.length; i++) 'q$i': values[sorular[i]] ?? '',
    if (hata != null) 'okumaHatasi': hata,
  });
  Map<String, String> cevaplar(ImportKaydi row) => {
    for (var i = 0; i < sorular.length; i++)
      sorular[i]: (row.degerler['q$i'] ?? '').trim(),
  };
  String alan(Map<String, String> row, String soru) =>
      row['q${sorular.indexOf(soru)}']?.trim() ?? '';

  Future<ImportOnIzleme> hazirla(
    List<ImportKaynakSatiri> sources, {
    TopluFormOnIzlemeVerisi? onceki,
  }) async {
    if (sources.isEmpty ||
        sources.length > azamiDosya ||
        sources.map((r) => r.id).toSet().length != sources.length) {
      throw const FormatException('1–50 farklı form resmi seçin.');
    }
    final students = await service.formImportOgrencileri(
      baglam,
      atamaId,
      hassasOnay: true,
    );
    final snapshot =
        onceki ??
        TopluFormOnIzlemeVerisi({
          for (final s in students)
            s['OgrenciId'] as int: s['SonFormId'] as int?,
        });
    final matches = <String, List<Map<String, Object?>>>{};
    final errors = <String, List<String>>{};
    final ids = <int, List<String>>{};
    for (final row in sources) {
      final e = errors[row.id] = [];
      final action = importNormalize(row.degerler['islem'] ?? '');
      if (action == 'atla') continue;
      if (action != 'aktar') e.add('İşlem alanı Aktar veya Atla olmalı.');
      final no = alan(row.degerler, 'Okul numaranız'),
          name = alan(row.degerler, 'Adınız Soyadınız');
      if (no.isEmpty || name.isEmpty) {
        e.add('Okul numarası ve ad soyad okunamadı; kaynak resimden düzeltin.');
      }
      final found = students
          .where(
            (s) =>
                RehberlikFormImport.numara('${s['OkulNo']}') ==
                    RehberlikFormImport.numara(no) &&
                importNormalize('${s['Ad']} ${s['Soyad']}') ==
                    importNormalize(name),
          )
          .toList();
      matches[row.id] = found;
      if (found.length != 1) {
        e.add(
          found.isEmpty
              ? 'Bu numara ve ad soyad sınıfınızın aktif öğrencileriyle eşleşmedi.'
              : 'Birden fazla öğrenci eşleşti; öğrenci kayıtlarını kontrol edin.',
        );
      } else {
        final id = found.single['OgrenciId'] as int;
        ids.putIfAbsent(id, () => []).add(row.id);
        final klass = alan(row.degerler, 'Sınıfınız');
        if (klass.isNotEmpty &&
            importNormalize(klass).replaceAll(' ', '') !=
                importNormalize(
                  '${found.single['SinifKodu']}',
                ).replaceAll(' ', '')) {
          e.add('Formdaki sınıf seçili rehberlik sınıfıyla uyuşmuyor.');
        }
        if (!snapshot.surumler.containsKey(id) ||
            snapshot.surumler[id] != found.single['SonFormId']) {
          e.add(
            'Bu öğrencinin formu ön izlemeden sonra değişti; resimleri yeniden ön izleyin.',
          );
        }
      }
      if (sorular.any((s) => alan(row.degerler, s).length > 5000) ||
          sorular.fold<int>(0, (sum, s) => sum + alan(row.degerler, s).length) >
              80000) {
        e.add('Form cevapları içerik sınırını aşıyor.');
      }
    }
    for (final duplicates in ids.values.where((x) => x.length > 1)) {
      for (final id in duplicates) {
        errors[id]!.add(
          'Aynı öğrenci için birden fazla resim var. Birini düzenleyip İşlem alanını Atla yapın.',
        );
      }
    }
    return ImportOnIzleme(
      [
        for (final row in sources)
          ImportKaydi(
            row.id,
            row.konum,
            {
              ...row.degerler,
              'eslesen': matches[row.id]?.length == 1
                  ? '${matches[row.id]!.single['OkulNo']} • ${matches[row.id]!.single['Ad']} ${matches[row.id]!.single['Soyad']}'
                  : 'Eşleşmedi',
              'adet':
                  '${sorular.where((s) => alan(row.degerler, s).isNotEmpty).length}',
            },
            durum: importNormalize(row.degerler['islem'] ?? '') == 'atla'
                ? ImportDurumu.atlanan
                : errors[row.id]!.isNotEmpty
                ? ImportDurumu.hatali
                : ImportDurumu.uyarili,
            mesajlar: importNormalize(row.degerler['islem'] ?? '') == 'atla'
                ? const ['Kullanıcı bu formu atladı.']
                : [
                    ...errors[row.id]!,
                    if (row.degerler['okumaHatasi'] != null)
                      'Resim otomatik okunamadı; değerleri elle düzeltin. Orijinal hata: ${row.degerler['okumaHatasi']}',
                    'Kaynak resimdeki tüm cevapları kontrol ederek seçin.',
                  ],
          ),
      ],
      veri: snapshot,
      bilgiler: const [
        'Hatalı/eşleşmeyen formlar kaydedilmez. Geçerli formları seçerek devam edebilirsiniz.',
        'Önceki sürümler, özel sorular ve boş bırakılan cevaplar korunur. Öğrenci/veli ana kayıtları değiştirilmez.',
      ],
    );
  }

  Future<ImportOzet> kaydet(
    ImportOnIzleme preview,
    Set<String> selected,
  ) async {
    if (preview.veri is! TopluFormOnIzlemeVerisi ||
        selected.isEmpty ||
        selected
            .difference(preview.kayitlar.map((r) => r.id).toSet())
            .isNotEmpty) {
      throw const FormatException(
        'Geçerli ön izleme ve form seçimi gereklidir.',
      );
    }
    final checked = await hazirla([
      for (final r in preview.kayitlar)
        ImportKaynakSatiri(r.id, r.konum, r.degerler),
    ], onceki: preview.veri as TopluFormOnIzlemeVerisi);
    final chosen = checked.kayitlar
        .where((r) => selected.contains(r.id))
        .toList();
    if (chosen.any((r) => !r.aktarilabilir)) {
      throw StateError(
        'Seçilen bir form artık aktarılabilir değil. Ön izlemeyi yenileyin.',
      );
    }
    final students = await service.formImportOgrencileri(
      baglam,
      atamaId,
      hassasOnay: true,
    );
    final data = preview.veri as TopluFormOnIzlemeVerisi;
    final requests = <RehberlikFormAktarimi>[];
    for (final row in chosen) {
      final values = cevaplar(row);
      final student = students.singleWhere(
        (s) =>
            RehberlikFormImport.numara('${s['OkulNo']}') ==
                RehberlikFormImport.numara(values['Okul numaranız']!) &&
            importNormalize('${s['Ad']} ${s['Soyad']}') ==
                importNormalize(values['Adınız Soyadınız']!),
      );
      requests.add(
        RehberlikFormAktarimi(
          ogrenciId: student['OgrenciId'] as int,
          beklenenSonFormId: data.surumler[student['OgrenciId']],
          cevaplar: values,
        ),
      );
    }
    final result = await service.formlariTopluKaydet(
      baglam,
      atamaId,
      requests,
      hassasOnay: true,
    );
    final errors = checked.kayitlar
        .where(
          (r) => !selected.contains(r.id) && r.durum == ImportDurumu.hatali,
        )
        .length;
    return ImportOzet(
      eklenen: result.eklenen,
      guncellenen: result.guncellenen,
      atlanan:
          result.atlanan + preview.kayitlar.length - selected.length - errors,
      hatali: errors,
      mesaj: result.mesaj,
    );
  }
}
