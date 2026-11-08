import '../models/ortak_import.dart';
import '../models/bireysel_seflik.dart';
import 'bireysel_import_service.dart';

class DersProgramiImportTanimi {
  static ImportTanimi olustur(
    String ogretmen, {
    required bool meslekPaketi,
  }) => ImportTanimi(
    id: 'bireysel_ders_programi',
    ad: 'Ders Programı Import',
    aciklama:
        'Seçilen ders ve görevler mevcut saat, sınıf, derslik ve başlangıç tarihi onaylarına gönderilir. Kaydetmeden önce bu onayları tamamlayın.',
    alanlar: const [
      ImportAlan(
        'gun',
        'Gün',
        zorunlu: true,
        alternatifler: ['Günü'],
        kolonDisiKapsam: ImportBilgiKapsami.blok,
        filtrelenebilir: true,
        gruplanabilir: true,
      ),
      ImportAlan(
        'dersSaatiNo',
        'Ders Saati No',
        zorunlu: true,
        alternatifler: ['Ders Saati', 'Saat No', 'Sıra No'],
      ),
      ImportAlan('baslangic', 'Başlangıç', alternatifler: ['Başlangıç Saati']),
      ImportAlan('bitis', 'Bitiş', alternatifler: ['Bitiş Saati']),
      ImportAlan(
        'dersAdi',
        'Ders',
        zorunlu: true,
        alternatifler: ['Ders Adı', 'Görev'],
        kolonDisiKapsam: ImportBilgiKapsami.blok,
        filtrelenebilir: true,
        gruplanabilir: true,
      ),
      ImportAlan(
        'sinif',
        'Sınıf',
        alternatifler: ['Sınıf Şube', 'Sınıf/Şube'],
        kolonDisiKapsam: ImportBilgiKapsami.blok,
        filtrelenebilir: true,
        gruplanabilir: true,
      ),
      ImportAlan(
        'derslik',
        'Derslik',
        alternatifler: ['Derslik Adı', 'Atölye'],
        filtrelenebilir: true,
      ),
      ImportAlan('tur', 'Kayıt Türü', kolondan: false, filtrelenebilir: true),
    ],
    duzenlemeHazirla: (preview, rows) async {
      final asil = preview.veri as BireyselDersProgramiOnIzleme;
      final yeni = satirlardanHazirla(
        rows.where((r) => r.degerler['tur'] != 'Şeflik').toList(),
        meslekPaketi: meslekPaketi,
      );
      final program = yeni.veri as BireyselDersProgramiOnIzleme;
      final slots = program.gunlukDersSaatAdaylari
          .map((s) => '${s.gun}|${s.dersSaatiNo}')
          .toSet();
      final sonuc = onIzlemeyeCevir(
        BireyselDersProgramiOnIzleme(
          sayfaSayisi: asil.sayfaSayisi,
          doluHucreSayisi: asil.doluHucreSayisi,
          ogretmenBulundu: asil.ogretmenBulundu,
          ogretmenEslesmeleri: asil.ogretmenEslesmeleri,
          gunlukDersSaatAdaylari: [
            ...program.gunlukDersSaatAdaylari,
            ...asil.gunlukDersSaatAdaylari.where(
              (s) => !slots.contains('${s.gun}|${s.dersSaatiNo}'),
            ),
          ],
          dersler: program.dersler,
          seflikSaatleri: asil.seflikSaatleri,
          uyarilar: asil.uyarilar,
          baslangicTarihi: asil.baslangicTarihi,
        ),
        meslekPaketi: meslekPaketi,
      );
      return ImportOnIzleme(
        [
          ...sonuc.kayitlar,
          ...yeni.kayitlar.where((r) => r.durum == ImportDurumu.hatali),
        ],
        veri: sonuc.veri,
        engeller: sonuc.engeller,
        bilgiler: sonuc.bilgiler,
      );
    },
    hazirla: (rows) async =>
        satirlardanHazirla(rows, meslekPaketi: meslekPaketi),
    aktar: (_, _) async =>
        throw StateError('Ders programının mevcut onay ekranını kullanın.'),
    ozelDuzeniTani: (_) => true,
    ozelOkuyucuAdi: 'Mevcut öğretmen programı / gün sütunları',
    ozelOku: (file) async => onIzlemeyeCevir(
      await BireyselImportService.dersProgramiOnIzlemeHazirla(
        dosyaBytes: file.bytes,
        dosyaUzantisi: file.uzanti,
        adSoyad: ogretmen,
      ),
      meslekPaketi: meslekPaketi,
    ),
  );

  static ImportOnIzleme satirlardanHazirla(
    List<ImportKaynakSatiri> rows, {
    required bool meslekPaketi,
  }) {
    final dersler = <BireyselDersProgramiKaydi>[];
    final saatler = <BireyselGunlukDersSaatiAdayi>[];
    final hatalar = <ImportKaydi>[];
    for (final row in rows) {
      final v = row.degerler;
      final gun = _gun(v['gun'] ?? '');
      final no = int.tryParse(v['dersSaatiNo'] ?? '') ?? 0;
      final ders = (v['dersAdi'] ?? '').trim();
      final sinif = (v['sinif'] ?? '').trim();
      final bas = (v['baslangic'] ?? '').trim();
      final bit = (v['bitis'] ?? '').trim();
      final errors = <String>[
        if (gun == null) 'Geçerli bir gün girin.',
        if (no <= 0) 'Ders saati numarası pozitif olmalıdır.',
        if (ders.isEmpty) 'Ders adı boş.',
        if (sinif.isEmpty && ders != 'Koordinatörlük') 'Sınıf bilgisi boş.',
      ];
      if (errors.isNotEmpty) {
        hatalar.add(
          ImportKaydi(
            'hata:${row.id}',
            row.konum,
            v,
            durum: ImportDurumu.hatali,
            mesajlar: errors,
          ),
        );
        continue;
      }
      dersler.add(
        BireyselDersProgramiKaydi(
          gun: gun!,
          dersSaatiNo: no,
          saatAraligi: '$bas - $bit',
          dersAdi: ders,
          sinif: sinif,
          derslik: v['derslik'] ?? '',
        ),
      );
      saatler.add(
        BireyselGunlukDersSaatiAdayi(
          gun: gun,
          dersSaatiNo: no,
          baslangic: bas,
          bitis: bit,
          hamMetin: row.konum,
        ),
      );
    }
    final p = onIzlemeyeCevir(
      BireyselDersProgramiOnIzleme(
        sayfaSayisi: 1,
        doluHucreSayisi: rows.length,
        ogretmenBulundu: true,
        ogretmenEslesmeleri: const [],
        gunlukDersSaatAdaylari: saatler,
        dersler: dersler,
      ),
      meslekPaketi: meslekPaketi,
    );
    return ImportOnIzleme(
      [...p.kayitlar, ...hatalar],
      veri: p.veri,
      engeller: p.engeller,
      bilgiler: p.bilgiler,
    );
  }

  static ImportOnIzleme onIzlemeyeCevir(
    BireyselDersProgramiOnIzleme p, {
    required bool meslekPaketi,
  }) {
    final rows = <ImportKaydi>[];
    final seen = <String>{};
    for (var i = 0; i < p.dersler.length; i++) {
      final d = p.dersler[i];
      final key =
          '${d.gun}|${d.dersSaatiNo}|${d.sinif}|${d.dersAdi}|${d.derslik}';
      final repeated = !seen.add(key);
      rows.add(
        ImportKaydi(
          'ders:$i',
          '${i + 1}. program kaydı',
          {
            'gun': d.gun,
            'dersSaatiNo': '${d.dersSaatiNo}',
            'dersAdi': d.dersAdi,
            'sinif': d.sinif,
            'derslik': d.derslik,
            'tur': d.gorevMi ? 'Koordinatörlük' : 'Ders',
            'baslangic': d.saatAraligi.split(' - ').first,
            'bitis': d.saatAraligi.split(' - ').last,
          },
          durum: repeated ? ImportDurumu.atlanan : ImportDurumu.uygun,
          mesajlar: repeated
              ? const ['Aynı ders/görev tekrar ediyor.']
              : const [],
        ),
      );
    }
    final programSaatleri = {
      for (final saat in p.gunlukDersSaatAdaylari)
        '${saat.gun}|${saat.dersSaatiNo}': saat,
    };
    for (var i = 0; i < p.seflikSaatleri.length; i++) {
      final s = p.seflikSaatleri[i];
      final saat = programSaatleri['${s.gun}|${s.dersSaatiNo}'];
      rows.add(
        ImportKaydi(
          'seflik:$i',
          s.hamMetin,
          {
            'gun': s.gun,
            'dersSaatiNo': '${s.dersSaatiNo}',
            'dersAdi': s.hamMetin,
            'tur': 'Şeflik',
            'baslangic': saat?.baslangic ?? '',
            'bitis': saat?.bitis ?? '',
          },
          durum: meslekPaketi ? ImportDurumu.uygun : ImportDurumu.atlanan,
          mesajlar: [
            meslekPaketi
                ? 'Şeflik saatlerini sonraki ekranda onaylayın. Sınıf ve yıllık plan gerekmez.'
                : 'Şeflik için meslek paketini etkinleştirin.',
          ],
        ),
      );
    }
    return ImportOnIzleme(
      rows,
      veri: p,
      bilgiler: p.uyarilar,
      engeller: [
        if (!p.ogretmenBulundu) 'Dosyada öğretmenin programı bulunamadı.',
      ],
    );
  }

  static BireyselDersProgramiOnIzleme secimiUygula(
    ImportOnIzleme preview,
    Set<String> selected,
  ) {
    _secimiDogrula(preview, selected);
    final p = preview.veri as BireyselDersProgramiOnIzleme;
    final dersler = <BireyselDersProgramiKaydi>[
      for (var i = 0; i < p.dersler.length; i++)
        if (selected.contains('ders:$i')) p.dersler[i],
    ];
    final seflik = <SeflikProgramSaatiAdayi>[
      for (var i = 0; i < p.seflikSaatleri.length; i++)
        if (selected.contains('seflik:$i')) p.seflikSaatleri[i],
    ];
    final slots = {
      ...dersler.map((d) => '${d.gun}|${d.dersSaatiNo}'),
      ...seflik.map((s) => '${s.gun}|${s.dersSaatiNo}'),
    };
    final seen = <String>{};
    return BireyselDersProgramiOnIzleme(
      sayfaSayisi: p.sayfaSayisi,
      doluHucreSayisi: p.doluHucreSayisi,
      ogretmenBulundu: p.ogretmenBulundu,
      ogretmenEslesmeleri: p.ogretmenEslesmeleri,
      gunlukDersSaatAdaylari: p.gunlukDersSaatAdaylari
          .where(
            (s) =>
                slots.contains('${s.gun}|${s.dersSaatiNo}') &&
                seen.add('${s.gun}|${s.dersSaatiNo}'),
          )
          .toList(),
      dersler: dersler,
      seflikSaatleri: seflik,
      uyarilar: p.uyarilar,
      baslangicTarihi: p.baslangicTarihi,
    );
  }

  static String? _gun(String text) {
    for (final day in const [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
    ]) {
      if (importNormalize(text) == importNormalize(day)) return day;
    }
    return null;
  }

  static void _secimiDogrula(ImportOnIzleme preview, Set<String> selected) {
    final eligible = preview.kayitlar
        .where((r) => r.aktarilabilir)
        .map((r) => r.id)
        .toSet();
    if (preview.engeller.isNotEmpty ||
        selected.isEmpty ||
        !eligible.containsAll(selected)) {
      throw StateError('Geçerli kayıtları seçip ön izlemeyi onaylayın.');
    }
  }
}
