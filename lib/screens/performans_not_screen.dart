import '../widgets/ortak_ui.dart';
import 'package:flutter/material.dart';
import '../widgets/odev_puan_dialog.dart';
import '../widgets/odev_gorunum.dart';
import '../models/odev_kontrol.dart';
import '../models/performans_notu.dart';
import '../services/bireysel_liste_service.dart';
import '../services/bireysel_odev_kontrol_service.dart';

class PerformansNotScreen extends StatefulWidget {
  const PerformansNotScreen({super.key, required this.oturum});
  final BireyselListeOturumu oturum;
  @override
  State<PerformansNotScreen> createState() => _PerformansState();
}

class _PerformansState extends State<PerformansNotScreen> {
  int? _sinif, _ders;
  late String _yil = widget.oturum.yil;
  List<String> _yillar = [];
  Map<int, String> _siniflar = {};
  bool get _saltOkunur => _yil != widget.oturum.yil;
  int _filtreSurumu = 0;
  int _donem = 1, _sekme = 1;
  List<OdevDersSecenegi> _dersler = [];
  final _veriler = <int, PerformansVerisi>{};
  final _taslaklar = <int, Map<int, int?>>{};
  bool _busy = false;
  String? _hata;
  bool get _degisti => _taslaklar.values.any((m) => m.isNotEmpty);
  @override
  void initState() {
    super.initState();
    _siniflar = {
      for (final s in widget.oturum.siniflar) s.sinifSubeId: s.sinif,
    };
    _sinif = _siniflar.keys.firstOrNull;
    _yukle();
  }

  Future<void> _islem(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'İşlem tamamlanamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _veriOku() async {
    if (_sinif == null || _ders == null) {
      if (mounted) setState(_veriler.clear);
      return;
    }
    final a = await PerformansNotService.oku(
      widget.oturum,
      _sinif!,
      _ders!,
      _donem,
      1,
      yil: _yil,
    );
    final b = await PerformansNotService.oku(
      widget.oturum,
      _sinif!,
      _ders!,
      _donem,
      2,
      yil: _yil,
    );
    if (mounted) {
      setState(() {
        _veriler[1] = a;
        _veriler[2] = b;
      });
    }
  }

  Future<void> _yukle() => _islem(() async {
    final yillar = await PerformansNotService.yillar(widget.oturum);
    List<OdevDersSecenegi> dersler;
    if (_saltOkunur) {
      final rows = await PerformansNotService.gecmisDersler(
        widget.oturum,
        _yil,
      );
      _siniflar = {
        for (final r in rows) r['SinifSubeId'] as int: r['SinifKodu'] as String,
      };
      if (!_siniflar.containsKey(_sinif)) _sinif = _siniflar.keys.firstOrNull;
      dersler = rows
          .where((r) => r['SinifSubeId'] == _sinif)
          .map(OdevDersSecenegi.fromMap)
          .toList();
    } else {
      _siniflar = {
        for (final s in widget.oturum.siniflar) s.sinifSubeId: s.sinif,
      };
      if (!_siniflar.containsKey(_sinif)) _sinif = _siniflar.keys.firstOrNull;
      dersler = await BireyselOdevKontrolService.dersler(widget.oturum, _sinif);
    }
    _yillar = yillar;

    if (!mounted) return;
    setState(() {
      _dersler = dersler;
      if (!dersler.any((d) => d.dersId == _ders)) {
        _ders = dersler.firstOrNull?.dersId;
      }
    });
    await _veriOku();
  });
  Future<bool> _vazgec() async {
    if (!_degisti) return true;
    return await odevDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Notlar kaydedilmedi'),
            content: const Text(
              'Kaydedilmemiş nihai notlardan vazgeçilsin mi?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Devam et'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _filtre(VoidCallback f) async {
    if (_busy) return;
    if (!await _vazgec() || !mounted) {
      if (mounted) setState(() => _filtreSurumu++);
      return;
    }
    setState(() {
      _taslaklar.clear();
      f();
    });
    await _yukle();
  }

  Future<void> _kaydet() => _islem(() async {
    final giris = <({PerformansVerisi veri, Map<int, int?> notlar})>[
      for (final e in _taslaklar.entries)
        if (e.value.isNotEmpty)
          (veri: _veriler[e.key]!, notlar: Map.of(e.value)),
    ];
    if (giris.isEmpty) return;
    await PerformansNotService.topluNotKaydet(widget.oturum, giris);
    if (mounted) setState(_taslaklar.clear);
    await _veriOku();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Performans notları kaydedildi.')),
      );
    }
  });
  Future<void> _odevSec(PerformansVerisi p) async {
    if (_busy || !await _vazgec() || !mounted) return;
    final secilen = Set<int>.of(p.secilenler);
    final onay = await odevDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => OdevFormSayfasi(
          title: Text('Performans ${p.tanim['Grup']} – Ödev seçimi'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p.odevler.isEmpty)
                    const Text('Bu ders/sınıf için ödev yok.'),
                  for (final g in p.odevler)
                    CheckboxListTile(
                      value: secilen.contains(g.odevId),
                      title: Text(g.baslik),
                      subtitle: Text(
                        '${odevTarihYaz(g.baslangicTarihi)}${g.donem == null ? ' • Dönemi belirtilmemiş' : ''}${g.aktif ? '' : ' • Pasif'}',
                      ),
                      onChanged: (v) => yenile(() {
                        if (v == true) {
                          secilen.add(g.odevId);
                        } else {
                          secilen.remove(g.odevId);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Seçilenleri kaydet (${secilen.length})'),
            ),
          ],
        ),
      ),
    );
    if (onay == true && mounted) {
      await _islem(() async {
        await PerformansNotService.odevleriSec(widget.oturum, p, secilen);
        _taslaklar.clear();
        await _veriOku();
      });
    }
  }

  Future<void> _agirlik(PerformansVerisi p) async {
    if (_busy || !await _vazgec() || !mounted) return;
    final controller = TextEditingController(
      text: p.tanim['OdevAgirligi']?.toString() ?? '',
    );
    try {
      final onay = await odevDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Hesaplama ağırlığı'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('performans-agirlik'),
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ödev ağırlığı (%0–100)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
      if (onay != true || !mounted || _saltOkunur) return;
      final raw = controller.text.trim(),
          agirlik = int.tryParse(controller.text.trim());
      await _islem(() async {
        if (raw.isNotEmpty && agirlik == null) {
          throw ArgumentError('Yüzdeyi tam sayı girin.');
        }
        await PerformansNotService.agirlikKaydet(widget.oturum, p, agirlik);
        _taslaklar.clear();
        await _veriOku();
      });
    } finally {
      controller.dispose();
    }
  }

  Future<void> _kriter(PerformansVerisi p, {int index = 0}) async {
    if (_busy || _saltOkunur || p.ogrenciler.isEmpty) return;
    if (_degisti) {
      setState(
        () => _hata = 'Kriterleri değiştirmeden önce nihai notları kaydedin.',
      );
      return;
    }
    while (mounted && index >= 0 && index < p.ogrenciler.length) {
      final s = p.ogrenciler[index];
      final controllers = {
        for (final k in p.kriterler)
          k.id: TextEditingController(
            text: s.kriterPuanlari[k.id]?.toString() ?? '',
          ),
      };
      try {
        if (!mounted) return;
        final yon = await odevDialog<int>(
          context: context,
          barrierDismissible: false,
          builder: (c) => _KriterDialog(
            baslik:
                '${s.ogrenci['OkulNo']} • ${s.ogrenci['Ad']} ${s.ogrenci['Soyad']}',
            kriterler: p.kriterler,
            controllers: controllers,
            onceki: index > 0,
            sonraki: index < p.ogrenciler.length - 1,
            kaydet: () async {
              final puanlar = <String, int?>{};
              for (final k in p.kriterler) {
                final raw = controllers[k.id]!.text.trim();
                final n = int.tryParse(raw);
                if (raw.isNotEmpty && (n == null || n < 0 || n > k.azami)) {
                  throw ArgumentError(
                    '${k.baslik}: 0–${k.azami} arasında puan girin.',
                  );
                }
                puanlar[k.id] = n;
              }
              await PerformansNotService.kriterKaydet(
                widget.oturum,
                p,
                s,
                puanlar,
              );
            },
          ),
        );
        if (yon == null) return;
        await _islem(_veriOku);
        p = _veriler[p.tanim['Grup']]!;
        if (yon == 0) return;
        index += yon;
      } finally {
        for (final c in controllers.values) {
          c.dispose();
        }
      }
    }
  }

  Widget _puanKarti(String baslik, String deger, Color zemin, Color renk) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: zemin,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: odevCizgi),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              baslik,
              style: TextStyle(fontWeight: FontWeight.w600, color: renk),
            ),
            const SizedBox(height: 12),
            Text(
              '$deger / 100',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: renk,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ],
        ),
      );

  Future<void> _sonuc(PerformansVerisi p, PerformansOgrenciSonucu s) async {
    if (_busy) return;
    final grup = p.tanim['Grup'] as int, id = s.ogrenci['OgrenciId'] as int;
    final controller = TextEditingController(
      text:
          (_taslaklar[grup]?.containsKey(id) == true
                  ? _taslaklar[grup]![id]
                  : s.nihai)
              ?.toString() ??
          '',
    );
    String? hata;
    try {
      final onay = await odevDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, yenile) => OdevFormSayfasi(
            title: Text('Hesaplama Sonucu (P$grup)'),
            subtitle: '${s.ogrenci['Ad']} ${s.ogrenci['Soyad']}',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _puanKarti(
                  'Ödevlerden Gelen Puan',
                  s.odev.puan?.round().toString() ?? '—',
                  const Color(0xfff1faee),
                  const Color(0xff237e2f),
                ),
                Text(
                  '${s.odev.dahil} ödev • ${s.odev.bos} boş • ${s.odev.disarida} G/M',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                _puanKarti(
                  'Kriter Puanı',
                  s.kriterPuani?.toString() ?? '—',
                  const Color(0xfff2f4ff),
                  odevMavi,
                ),
                _puanKarti(
                  'Önerilen Performans $grup Notu',
                  s.oneri?.toString() ?? '—',
                  const Color(0xffeeebff),
                  const Color(0xff5820f5),
                ),
                if (p.tanim['OdevAgirligi'] == null)
                  const TextButton(
                    onPressed: null,
                    child: Text('Hesaplama ağırlığı seçilmedi'),
                  ),
                if (!s.guncel && s.nihai != null)
                  const Text(
                    'Kaynak değişti • Notu kontrol edin',
                    style: TextStyle(color: Colors.deepOrange),
                  ),
                const SizedBox(height: 16),
                const Text('Öğretmen Notu (Düzenlenebilir)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton.outlined(
                      onPressed: _saltOkunur
                          ? null
                          : () => yenile(() {
                              final n =
                                  (int.tryParse(controller.text) ?? 0) - 1;
                              if (n >= 0) controller.text = '$n';
                            }),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('nihai-performans-puani'),
                        readOnly: _saltOkunur,
                        controller: controller,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '0–100',
                          errorText: hata,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      onPressed: _saltOkunur
                          ? null
                          : () => yenile(() {
                              final n =
                                  (int.tryParse(controller.text) ?? -1) + 1;
                              if (n <= 100) controller.text = '$n';
                            }),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (s.oneri != null && !_saltOkunur)
                  TextButton(
                    onPressed: () =>
                        yenile(() => controller.text = '${s.oneri}'),
                    child: const Text('Öneriyi kullan'),
                  ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Geri'),
              ),
              FilledButton(
                onPressed: _saltOkunur
                    ? null
                    : () {
                        final raw = controller.text.trim(),
                            n = int.tryParse(controller.text.trim());
                        if (raw.isNotEmpty && (n == null || n < 0 || n > 100)) {
                          yenile(() => hata = '0–100 tam sayı girin.');
                          return;
                        }
                        Navigator.pop(c, true);
                      },
                child: const Text('Uygula'),
              ),
            ],
          ),
        ),
      );
      if (onay != true || !mounted || _saltOkunur) return;
      setState(
        () => (_taslaklar[grup] ??= {})[id] = int.tryParse(
          controller.text.trim(),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Widget _performans(PerformansVerisi p) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Text(
        'Performans ${p.tanim['Grup']}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      Text(
        'Seçilen ödev: ${p.secilenler.length} • Ödev ağırlığı: ${p.tanim['OdevAgirligi'] ?? 'Seçilmedi'}',
      ),
      FilledButton(
        onPressed: _busy || _saltOkunur ? null : () => _odevSec(p),
        child: const Text('Ödev Seçimi ve Hesaplama'),
      ),
      OutlinedButton(
        onPressed: _busy || _saltOkunur || p.ogrenciler.isEmpty
            ? null
            : () => _kriter(p),
        child: const Text('Kriterleri Değerlendir'),
      ),
      TextButton(
        onPressed: _busy || _saltOkunur ? null : () => _agirlik(p),
        child: const Text('Hesaplama ağırlığını belirle'),
      ),
      for (var i = 0; i < p.ogrenciler.length; i++)
        Card(
          child: ListTile(
            title: Text(
              '${p.ogrenciler[i].ogrenci['OkulNo']} • ${p.ogrenciler[i].ogrenci['Ad']} ${p.ogrenciler[i].ogrenci['Soyad']}',
            ),
            subtitle: Text(
              'Ödev: ${p.ogrenciler[i].odev.puan?.round() ?? '—'} • Kriter: ${p.ogrenciler[i].kriterPuani ?? '—'} • Öneri: ${p.ogrenciler[i].oneri ?? '—'}',
            ),
            onTap: _busy ? null : () => _sonuc(p, p.ogrenciler[i]),
            trailing: IconButton(
              tooltip: 'Kriterleri değerlendir',
              onPressed: _busy ? null : () => _kriter(p, index: i),
              icon: const Icon(Icons.fact_check_outlined),
            ),
          ),
        ),
    ],
  );
  Widget _ozet() {
    final a = _veriler[1]!, b = _veriler[2]!;
    final ids = {
      ...a.ogrenciler.map((s) => s.ogrenci['OgrenciId']),
      ...b.ogrenciler.map((s) => s.ogrenci['OgrenciId']),
    };
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2.2),
            1: FlexColumnWidth(.7),
            2: FlexColumnWidth(.7),
            3: FlexColumnWidth(1.2),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
            horizontalInside: BorderSide(color: odevCizgi),
          ),
          children: [
            const TableRow(
              decoration: BoxDecoration(color: Color(0xffeef2f7)),
              children: [
                Padding(padding: EdgeInsets.all(10), child: Text('Öğrenci')),
                Text('P1'),
                Text('P2'),
                Text('Durum'),
              ],
            ),
            for (final id in ids) _ozetSatiri(id, a, b),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy || _degisti
              ? null
              : () => _islem(() async {
                  await PerformansNotService.excelAktar(
                    widget.oturum,
                    _sinif!,
                    _ders!,
                    _donem,
                    yil: _yil,
                  );
                }),
          icon: const Icon(Icons.download),
          label: const Text('Excel’e Aktar'),
        ),
      ],
    );
  }

  TableRow _ozetSatiri(Object? id, PerformansVerisi a, PerformansVerisi b) {
    final x = a.ogrenciler
        .where((s) => s.ogrenci['OgrenciId'] == id)
        .firstOrNull;
    final y = b.ogrenciler
        .where((s) => s.ogrenci['OgrenciId'] == id)
        .firstOrNull;
    final o = x?.ogrenci ?? y!.ogrenci;
    final taslak = _taslaklar.values.any((m) => m.containsKey(id));
    final tamam =
        x?.nihai != null && y?.nihai != null && x!.guncel && y!.guncel;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Text(
            '${o['Ad']} ${o['Soyad']}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        for (final (grup, s) in [(1, x), (2, y)])
          s == null
              ? const Text('—')
              : TextButton(
                  onPressed: _busy ? null : () => _sonuc(_veriler[grup]!, s),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(30, 40),
                  ),
                  child: Text(
                    '${_taslaklar[grup]?.containsKey(id) == true ? _taslaklar[grup]![id] : s.nihai ?? '—'}',
                  ),
                ),
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: tamam && !taslak
                ? const Color(0xffe2f7e6)
                : const Color(0xfffff0da),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            taslak
                ? 'Taslak'
                : tamam
                ? 'Tamam'
                : 'Eksik',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: tamam && !taslak ? Colors.green : Colors.deepOrange,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => OdevTema(
    child: PopScope(
      canPop: !_busy && !_degisti,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !_busy && await _vazgec() && mounted) {
          setState(_taslaklar.clear);
          await WidgetsBinding.instance.endOfFrame;
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: OrtakSayfa(
        appBar: OdevBaslik(
          title: const Text('Not Hesaplama'),
          actions: [
            IconButton(
              tooltip: 'Yenile',
              onPressed: _busy ? null : () => _filtre(() {}),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('performans-yil-$_yil-$_filtreSurumu'),
                      initialValue: _yil,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Eğitim yılı',
                      ),
                      items: [
                        for (final y in _yillar.isEmpty ? [_yil] : _yillar)
                          DropdownMenuItem(value: y, child: Text(y)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v != null) {
                                _filtre(() {
                                  _yil = v;
                                  _sinif = null;
                                  _ders = null;
                                });
                              }
                            },
                    ),
                    if (_saltOkunur)
                      const Text('Geçmiş eğitim yılı: salt okunur.'),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(
                              'performans-donem-$_donem-$_filtreSurumu',
                            ),
                            initialValue: _donem,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Dönem',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 1,
                                child: Text('1. dönem'),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text('2. dönem'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) {
                                    if (v != null) _filtre(() => _donem = v);
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(
                              'performans-sinif-$_sinif-$_filtreSurumu',
                            ),
                            initialValue: _sinif,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Sınıf / şube',
                            ),
                            items: [
                              for (final s in _siniflar.entries)
                                DropdownMenuItem(
                                  value: s.key,
                                  child: Text(s.value),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => _filtre(() {
                                    _sinif = v;
                                    _ders = null;
                                  }),
                          ),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<int>(
                      key: ValueKey(
                        'performans-ders-$_sinif-$_ders-$_filtreSurumu',
                      ),
                      initialValue: _ders,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Ders'),
                      items: [
                        for (final d in _dersler)
                          DropdownMenuItem(
                            value: d.dersId,
                            child: Text(
                              d.dersAdi,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy ? null : (v) => _filtre(() => _ders = v),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (id, ad) in [
                          (1, 'Performans 1'),
                          (2, 'Performans 2'),
                          (3, 'Özet'),
                        ])
                          ChoiceChip(
                            label: Text(ad),
                            selected: _sekme == id,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() => _sekme = id),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_hata != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _hata!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: _veriler.length < 2
                    ? Center(
                        child: Text(
                          _busy ? 'Yükleniyor…' : 'Önce sınıf ve ders seçin.',
                        ),
                      )
                    : _sekme == 3
                    ? _ozet()
                    : _performans(_veriler[_sekme]!),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _busy || !_degisti ? null : _kaydet,
                  child: const Text('Notları Kaydet'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _KriterDialog extends StatefulWidget {
  const _KriterDialog({
    required this.baslik,
    required this.kriterler,
    required this.controllers,
    required this.onceki,
    required this.sonraki,
    required this.kaydet,
  });
  final String baslik;
  final List<PerformansKriteri> kriterler;
  final Map<String, TextEditingController> controllers;
  final bool onceki, sonraki;
  final Future<void> Function() kaydet;
  @override
  State<_KriterDialog> createState() => _KriterState();
}

class _KriterState extends State<_KriterDialog> {
  bool _busy = false;
  String? _hata;
  Future<void> _save(int yon) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.kaydet();
      if (mounted) {
        setState(() => _busy = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, yon);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Kriterler kaydedilemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OdevFormSayfasi(
      title: const Text('Kriter Değerlendirme'),
      subtitle: widget.baslik,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2.7),
              1: FlexColumnWidth(.7),
              2: FlexColumnWidth(1),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: const TableBorder(
              horizontalInside: BorderSide(color: odevCizgi),
            ),
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Color(0xffedf2f7)),
                children: [
                  Padding(padding: EdgeInsets.all(10), child: Text('Kriter')),
                  Text('En Fazla'),
                  Text('Puan'),
                ],
              ),
              for (final k in widget.kriterler)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 8,
                      ),
                      child: Text(k.baslik),
                    ),
                    Text('${k.azami}', textAlign: TextAlign.center),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        key: ValueKey('kriter-${k.id}'),
                        controller: widget.controllers[k.id],
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ],
                ),
              TableRow(
                decoration: const BoxDecoration(color: Color(0xffedf2f7)),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'Toplam',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Text('100', textAlign: TextAlign.center),
                  Text(
                    '${widget.controllers.values.fold<int>(0, (v, c) => v + (int.tryParse(c.text) ?? 0))}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          if (_hata != null)
            Text(_hata!, style: const TextStyle(color: Colors.red)),
        ],
      ),
      actions: [
        if (widget.onceki)
          OutlinedButton(
            onPressed: _busy ? null : () => _save(-1),
            child: const Text('Önceki'),
          ),
        FilledButton(
          onPressed: _busy ? null : () => _save(0),
          child: const Text('Kaydet'),
        ),
        if (widget.sonraki)
          OutlinedButton(
            onPressed: _busy ? null : () => _save(1),
            child: const Text('Sonraki'),
          ),
      ],
    ),
  );
}
