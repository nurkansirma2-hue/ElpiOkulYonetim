import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ortak_import.dart';
import '../services/bireysel_import_service.dart';

class FotografImportHucreSecimScreen extends StatefulWidget {
  FotografImportHucreSecimScreen({
    super.key,
    required this.dosya,
    required List<String> siniflar,
    required this.onIzlemeyiHazirla,
  }) : siniflar = List.unmodifiable(siniflar);

  final BireyselFotoExcelDosyasi dosya;
  final List<String> siniflar;
  final Future<ImportOnIzleme> Function(Map<String, String>?) onIzlemeyiHazirla;

  @override
  State<FotografImportHucreSecimScreen> createState() =>
      _FotografImportHucreSecimScreenState();
}

class _FotografImportHucreSecimScreenState
    extends State<FotografImportHucreSecimScreen> {
  final _seciliHucreler = <String>{};
  final _sinifAtamalari = <String, String>{};
  final _yatay = ScrollController();
  final _dikey = ScrollController();
  final _satirNumaralari = ScrollController();
  late final _hucreler = {for (final h in widget.dosya.hucreler) h.id: h};
  int _sayfa = 0;
  String? _sinif, _hata;
  bool _aralikSecimi = false, _mesgul = false;
  BireyselFotoOgrenciHucresi? _aralikBasi;

  @override
  void initState() {
    super.initState();
    _dikey.addListener(_satirNumaralariniKaydir);
  }

  void _satirNumaralariniKaydir() {
    if (!_satirNumaralari.hasClients || !_dikey.hasClients) return;
    _satirNumaralari.jumpTo(
      _dikey.offset
          .clamp(0, _satirNumaralari.position.maxScrollExtent)
          .toDouble(),
    );
  }

  @override
  void dispose() {
    _dikey.removeListener(_satirNumaralariniKaydir);
    _dikey.dispose();
    _yatay.dispose();
    _satirNumaralari.dispose();
    super.dispose();
  }

  void _hucreyiSec(BireyselFotoOgrenciHucresi hucre) {
    if (_mesgul) return;
    setState(() {
      if (!_aralikSecimi) {
        if (!_seciliHucreler.add(hucre.id)) _seciliHucreler.remove(hucre.id);
        return;
      }
      final bas = _aralikBasi;
      if (bas == null) {
        _aralikBasi = hucre;
        _seciliHucreler.add(hucre.id);
        return;
      }
      final ilkSatir = math.min(bas.satir, hucre.satir);
      final sonSatir = math.max(bas.satir, hucre.satir);
      final ilkSutun = math.min(bas.sutun, hucre.sutun);
      final sonSutun = math.max(bas.sutun, hucre.sutun);
      _seciliHucreler.addAll(
        widget.dosya.hucreler
            .where(
              (h) =>
                  h.sayfa == hucre.sayfa &&
                  h.satir >= ilkSatir &&
                  h.satir <= sonSatir &&
                  h.sutun >= ilkSutun &&
                  h.sutun <= sonSutun,
            )
            .map((h) => h.id),
      );
      _aralikBasi = null;
    });
  }

  void _sinifAta() {
    if (_sinif == null || _seciliHucreler.isEmpty || _mesgul) return;
    setState(() {
      for (final id in _seciliHucreler) {
        _sinifAtamalari[id] = _sinif!;
      }
      _seciliHucreler.clear();
      _aralikBasi = null;
      _hata = null;
    });
  }

  Future<void> _onIzle({bool dosyadakiSiniflar = false}) async {
    if (_mesgul || (!dosyadakiSiniflar && _sinifAtamalari.isEmpty)) return;
    final atamalar = dosyadakiSiniflar
        ? null
        : Map<String, String>.unmodifiable(_sinifAtamalari);
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final preview = await widget.onIzlemeyiHazirla(atamalar);
      if (!mounted) return;
      if (preview.engeller.isNotEmpty) {
        _onIzlemeHatasiniGoster(preview.engeller.join('\n'));
        return;
      }
      setState(() => _mesgul = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop<ImportOnIzleme>(context, preview);
    } catch (e) {
      if (mounted) {
        _onIzlemeHatasiniGoster('Orijinal hata: $e');
      }
    }
  }

  void _onIzlemeHatasiniGoster(String ayrinti) {
    setState(() {
      _mesgul = false;
      _hata = 'Ön izleme hazırlanamadı. Sınıf atamalarınız korundu.\n$ayrinti';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_hata!, maxLines: 5, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  static String _sutunAdi(int sutun) {
    var n = sutun + 1;
    var ad = '';
    while (n > 0) {
      n--;
      ad = String.fromCharCode(65 + n % 26) + ad;
      n ~/= 26;
    }
    return ad;
  }

  static String _metin(dynamic value) =>
      value is num && value.isFinite && value == value.roundToDouble()
      ? value.toInt().toString()
      : (value ?? '').toString().trim();

  Widget _kontroller() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Öğrenci hücrelerine dokunun, sınıfı seçin ve atayın. '
          'Fotoğraflar yalnız Öğrencilerim listesindeki mevcut öğrencilerle '
          'eşleştirilir. Öğrenci bilgileri değiştirilmez.',
        ),
        Text(
          '${_seciliHucreler.length} seçili • '
          '${_sinifAtamalari.length}/${widget.dosya.hucreler.length} sınıf atanmış',
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('foto-tumunu-sec'),
              onPressed: _mesgul
                  ? null
                  : () => setState(() {
                      _seciliHucreler.addAll(_hucreler.keys);
                      _aralikBasi = null;
                    }),
              child: const Text('Tüm Öğrencileri Seç'),
            ),
            TextButton(
              onPressed: _mesgul || _seciliHucreler.isEmpty
                  ? null
                  : () => setState(() {
                      _seciliHucreler.clear();
                      _aralikBasi = null;
                    }),
              child: const Text('Seçimi Kaldır'),
            ),
            FilterChip(
              key: const ValueKey('foto-aralik-secimi'),
              label: const Text('Dikdörtgen Aralık'),
              selected: _aralikSecimi,
              onSelected: _mesgul
                  ? null
                  : (value) => setState(() {
                      _aralikSecimi = value;
                      _aralikBasi = null;
                    }),
            ),
          ],
        ),
        if (_aralikSecimi)
          Text(
            _aralikBasi == null
                ? 'Önce aralığın ilk, sonra son öğrenci hücresine dokunun.'
                : '${_sutunAdi(_aralikBasi!.sutun)}${_aralikBasi!.satir + 1} '
                      'seçildi; son öğrenci hücresine dokunun.',
          ),
        DropdownButtonFormField<String>(
          key: const ValueKey('foto-sinif-secimi'),
          initialValue: _sinif,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          decoration: const InputDecoration(labelText: 'Atanacak sınıf'),
          items: [
            for (final sinif in widget.siniflar)
              DropdownMenuItem(
                value: sinif,
                child: Text(sinif, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _mesgul ? null : (value) => setState(() => _sinif = value),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              key: const ValueKey('foto-sinif-ata'),
              onPressed: _mesgul || _sinif == null || _seciliHucreler.isEmpty
                  ? null
                  : _sinifAta,
              child: const Text('Seçili Hücrelere Sınıf Ata'),
            ),
            TextButton(
              onPressed:
                  _mesgul || !_seciliHucreler.any(_sinifAtamalari.containsKey)
                  ? null
                  : () => setState(() {
                      for (final id in _seciliHucreler) {
                        _sinifAtamalari.remove(id);
                      }
                    }),
              child: const Text('Seçililerin Atamasını Kaldır'),
            ),
          ],
        ),
        if (widget.siniflar.isEmpty)
          const Text(
            'Önce Öğrenci Import ile öğrencilerinizi yükleyin; '
            'mevcut öğrencisi bulunan bir sınıf bulunamadı.',
          ),
        if (widget.dosya.sayfalar.length > 1)
          DropdownButtonFormField<int>(
            key: const ValueKey('foto-sayfa-secimi'),
            initialValue: _sayfa,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Excel sayfası'),
            items: [
              for (var i = 0; i < widget.dosya.sayfalar.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(widget.dosya.sayfalar[i].ad),
                ),
            ],
            onChanged: _mesgul
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _sayfa = value;
                      _seciliHucreler.clear();
                      _aralikBasi = null;
                    });
                    for (final controller in [
                      _dikey,
                      _yatay,
                      _satirNumaralari,
                    ]) {
                      if (controller.hasClients) controller.jumpTo(0);
                    }
                  },
          )
        else if (widget.dosya.sayfalar.isNotEmpty)
          Text('Sayfa: ${widget.dosya.sayfalar.first.ad}'),
        if (_hata != null)
          Text(
            _hata!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );

  Widget _ogrenciHucresi(BireyselFotoOgrenciHucresi hucre) {
    final secili = _seciliHucreler.contains(hucre.id);
    final sinif = _sinifAtamalari[hucre.id];
    final scheme = Theme.of(context).colorScheme;
    final renkler = [
      Colors.teal,
      Colors.blue,
      Colors.purple,
      Colors.orange,
      Colors.pink,
    ];
    final renk = sinif == null
        ? null
        : renkler[widget.siniflar.indexOf(sinif) % renkler.length];
    return Semantics(
      button: true,
      selected: secili,
      label:
          '${_sutunAdi(hucre.sutun)}${hucre.satir + 1}, '
          '${hucre.adSoyad}, okul no ${hucre.okulNo}, '
          '${sinif == null ? 'sınıf atanmadı' : 'atanan sınıf $sinif'}',
      child: Material(
        color: secili
            ? scheme.primaryContainer
            : renk?.withAlpha(35) ?? scheme.surface,
        child: InkWell(
          key: ValueKey('foto-hucre:${hucre.id}'),
          onTap: _mesgul ? null : () => _hucreyiSec(hucre),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(
                color: secili ? scheme.primary : scheme.outlineVariant,
                width: secili ? 2 : .5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hucre.fotoVerisi != null) ...[
                      Image.memory(
                        hucre.fotoVerisi!,
                        width: 32,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image, size: 32),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        hucre.adSoyad,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (secili) const Icon(Icons.check_circle, size: 16),
                  ],
                ),
                Text(
                  'No: ${hucre.okulNo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  sinif == null ? 'Sınıf atanmadı' : 'Sınıf: $sinif',
                  key: ValueKey('foto-atama:${hucre.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: renk ?? scheme.onSurfaceVariant,
                    fontWeight: sinif == null
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _excelIzgarasi() {
    if (widget.dosya.sayfalar.isEmpty) {
      return const Center(child: Text('Excel sayfası bulunamadı.'));
    }
    final rows = widget.dosya.sayfalar[_sayfa].satirlar;
    final adaylar = widget.dosya.hucreler
        .where((h) => h.sayfa == _sayfa)
        .toList();
    final satirSayisi = math.max(
      rows.length,
      adaylar.fold<int>(0, (n, h) => math.max(n, h.satir + 1)),
    );
    final sutunSayisi = math.max(
      rows.fold<int>(0, (n, r) => math.max(n, r.length)),
      adaylar.fold<int>(0, (n, h) => math.max(n, h.sutun + 1)),
    );
    final olcek = MediaQuery.textScalerOf(context).scale(14) / 14;
    final ogrenciSatirlari = adaylar.map((h) => h.satir).toSet();
    double yukseklik(int r) {
      if (ogrenciSatirlari.contains(r)) return 128 * olcek;
      final dolu = r < rows.length && rows[r].any((v) => _metin(v).isNotEmpty);
      return (dolu ? 56 : 28) * olcek;
    }

    final doluSutunlar = adaylar.map((h) => h.sutun).toSet();
    for (final row in rows) {
      for (var c = 0; c < row.length; c++) {
        if (_metin(row[c]).isNotEmpty) doluSutunlar.add(c);
      }
    }
    final ogrenciGenisligi = ((MediaQuery.sizeOf(context).width - 44 - 28) / 2)
        .clamp(120.0, 172.0)
        .toDouble();
    final genislikler = [
      for (var c = 0; c < sutunSayisi; c++)
        doluSutunlar.contains(c) ? ogrenciGenisligi : 28.0,
    ];
    final scheme = Theme.of(context).colorScheme;
    Widget baslik(String metin, double genislik) => Container(
      width: genislik,
      height: 32 * olcek,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant, width: .5),
      ),
      child: Text(metin, maxLines: 1),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                baslik('', 44),
                Expanded(
                  child: ListView.builder(
                    controller: _satirNumaralari,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: satirSayisi,
                    itemBuilder: (_, r) => Container(
                      height: yukseklik(r),
                      alignment: Alignment.topCenter,
                      color: scheme.surfaceContainerHighest,
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${r + 1}', maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _yatay,
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                key: const ValueKey('foto-excel-yatay'),
                controller: _yatay,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: genislikler.fold<double>(0, (n, w) => n + w),
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (var c = 0; c < sutunSayisi; c++)
                            baslik(_sutunAdi(c), genislikler[c]),
                        ],
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _dikey,
                          child: ListView.builder(
                            key: const ValueKey('foto-excel-dikey'),
                            controller: _dikey,
                            itemCount: satirSayisi,
                            itemBuilder: (_, r) => SizedBox(
                              height: yukseklik(r),
                              child: Row(
                                children: [
                                  for (var c = 0; c < sutunSayisi; c++)
                                    SizedBox(
                                      width: genislikler[c],
                                      height: yukseklik(r),
                                      child: _hucreler['$_sayfa:$r:$c'] != null
                                          ? _ogrenciHucresi(
                                              _hucreler['$_sayfa:$r:$c']!,
                                            )
                                          : Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: scheme.outlineVariant,
                                                  width: .5,
                                                ),
                                              ),
                                              child: Text(
                                                r < rows.length &&
                                                        c < rows[r].length
                                                    ? _metin(rows[r][c])
                                                    : '',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_mesgul,
    child: OrtakSayfa(
      appBar: const ModulUstBar(
        title: Text(
          'Hücrelerden Sınıf Ata',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Yeni öğrenci kaydedilmez.'),
              FilledButton.icon(
                key: const ValueKey('foto-hucre-onizle'),
                onPressed: _mesgul || _sinifAtamalari.isEmpty ? null : _onIzle,
                icon: const Icon(Icons.preview),
                label: Text('${_sinifAtamalari.length} Öğrenciyle Ön İzle'),
              ),
              TextButton(
                key: const ValueKey('foto-otomatik-onizle'),
                onPressed: _mesgul
                    ? null
                    : () => _onIzle(dosyadakiSiniflar: true),
                child: const Text('Otomatik Eşleştirmeye Dön'),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .48,
                    ),
                    child: SingleChildScrollView(child: _kontroller()),
                  ),
                  Expanded(child: _excelIzgarasi()),
                ],
              ),
            ),
            if (_mesgul)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x55000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
