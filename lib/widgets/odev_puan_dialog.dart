import 'ortak_ui.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/odev_kontrol.dart';
import 'odev_gorunum.dart';
import 'ogrenci_foto_widget.dart';

/// Dışarıda tutulan form denetleyicileri kapanış animasyonu bitince bırakılır.
Future<T?> odevDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
  final sonuc = await Navigator.of(context).push(route);
  await route.completed;
  return sonuc;
}

class OdevPuanDialog extends StatefulWidget {
  const OdevPuanDialog({
    super.key,
    required this.ad,
    required this.durum,
    required this.notDegeri,
    required this.aciklama,
    required this.kaydet,
    this.onceki = false,
    this.sonraki = false,
    this.ekle,
    this.gecmis,
    this.ekleriGetir,
    this.sinif = '',
    this.sira = 1,
    this.toplam = 1,
    this.fotoVerisi,
    this.fotoYolu,
  });
  final String ad, aciklama, sinif;
  final Uint8List? fotoVerisi;
  final String? fotoYolu;
  final OdevKontrolDurumu durum;
  final int? notDegeri;
  final int sira, toplam;
  final bool onceki, sonraki;
  final Future<void> Function(int?, OdevKontrolDurumu, String) kaydet;
  final Future<void> Function()? ekle;
  final VoidCallback? gecmis;
  final Future<List<Map<String, Object?>>> Function()? ekleriGetir;
  @override
  State<OdevPuanDialog> createState() => _PuanState();
}

class _PuanState extends State<OdevPuanDialog> {
  late int? _not = widget.notDegeri ?? OdevKontrolSonuc.hizliNot(widget.durum);
  late OdevKontrolDurumu _durum = widget.durum;
  late final _puan = TextEditingController(
    text: _not != null && _not! >= 0 ? '$_not' : '',
  );
  late final _aciklama = TextEditingController(text: widget.aciklama);
  late Future<List<Map<String, Object?>>>? _ekler = widget.ekleriGetir?.call();
  bool _busy = false;
  String? _hata;
  @override
  void dispose() {
    _puan.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  void _sec(OdevKontrolDurumu d) => setState(() {
    _not = OdevKontrolSonuc.hizliNot(d);
    _durum = d;
    _puan.text = _not != null && _not! >= 0 ? '$_not' : '';
    _hata = null;
  });
  void _puanDegisti(String v) => setState(() {
    _hata = null;
    if (v.trim().isEmpty) {
      _not = null;
      _durum = OdevKontrolDurumu.kontrolEdilmedi;
    } else {
      final n = int.tryParse(v.trim());
      if (n != null && n >= 0 && n <= 10) {
        _not = n;
        _durum = OdevKontrolSonuc.notDurumu(n, null);
      }
    }
  });
  Future<void> _kaydet(int yon) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_puan.text.trim().isNotEmpty) {
        final puan = int.tryParse(_puan.text.trim());
        if (puan == null || puan < 0 || puan > 10) {
          throw ArgumentError('Tam sayı olarak 0–10 puan girin.');
        }
        _not = puan;
        _durum = OdevKontrolSonuc.notDurumu(puan, null);
      }
      await widget.kaydet(_not, _durum, _aciklama.text);
      if (!mounted) return;
      setState(() => _busy = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, yon);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Puan kaydedilemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ekle() async {
    setState(() => _busy = true);
    try {
      await widget.ekle!();
      if (mounted) setState(() => _ekler = widget.ekleriGetir?.call());
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Ek kaydedilemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: OdevTema(
      child: PopScope(
        canPop: !_busy,
        child: OrtakSayfa(
          appBar: const OdevBaslik(title: Text('Öğrenci Puanı'), actions: []),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        OgrenciFotoWidget(
                          fotoYolu: widget.fotoYolu,
                          fotoVerisi: widget.fotoVerisi,
                          yerel: true,
                          width: 52,
                          height: 64,
                          daire: false,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OrtakBaslik(
                                widget.ad.split(' • ').last,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${widget.sinif}${widget.sinif.isEmpty ? '' : ' • '}${widget.ad.split(' • ').first}',
                              ),
                            ],
                          ),
                        ),
                        if (_not != null)
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: odevDurumZemini(_durum),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _not! >= 0 ? '$_not / 10' : _durum.sembol,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Puan Seçimi (0 - 10)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                for (
                  var start = 0;
                  start < OdevKontrolDurumu.hizli.length;
                  start += 3
                ) ...[
                  Row(
                    children: [
                      for (var i = start; i < start + 3; i++) ...[
                        if (i > start) const SizedBox(width: 8),
                        if (i < OdevKontrolDurumu.hizli.length)
                          Expanded(
                            child: _durumKutusu(OdevKontrolDurumu.hizli[i]),
                          )
                        else
                          const Expanded(child: SizedBox.shrink()),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Manuel Puan',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Puanı azalt',
                      onPressed: _busy
                          ? null
                          : () {
                              final n = (int.tryParse(_puan.text) ?? 0) - 1;
                              if (n >= 0) {
                                _puan.text = '$n';
                                _puanDegisti('$n');
                              }
                            },
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('manuel-odev-puani'),
                        controller: _puan,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(hintText: '0–10'),
                        onChanged: _puanDegisti,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Puanı artır',
                      onPressed: _busy
                          ? null
                          : () {
                              final n = (int.tryParse(_puan.text) ?? -1) + 1;
                              if (n <= 10) {
                                _puan.text = '$n';
                                _puanDegisti('$n');
                              }
                            },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Açıklama (isteğe bağlı)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _aciklama,
                  enabled: !_busy,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Açıklama'),
                ),
                const SizedBox(height: 12),
                if (widget.ekle != null) ...[
                  const Text('Dosya / Fotoğraf (isteğe bağlı)'),
                  const SizedBox(height: 8),
                  if (_ekler != null)
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: _ekler,
                      builder: (c, s) {
                        if (s.hasError) return const Text('Ekler yüklenemedi.');
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final r in s.data ?? <Map<String, Object?>>[])
                              Container(
                                width: 130,
                                height: 108,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: odevCizgi),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: r['Veri'] is List<int>
                                    ? Image.memory(
                                        Uint8List.fromList(
                                          r['Veri'] as List<int>,
                                        ),
                                        cacheWidth: 260,
                                        fit: BoxFit.contain,
                                        errorBuilder: (c, e, st) => const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.attach_file,
                                            color: odevMavi,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              '${r['DosyaAdi']}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                          ],
                        );
                      },
                    ),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 145,
                      height: 110,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _ekle,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, size: 28),
                            SizedBox(height: 8),
                            Text('Fotoğraf Ekle'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (_hata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _hata!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('odev-puan-onceki'),
                    tooltip: 'Önceki öğrenci • Kaydet ve geç',
                    onPressed: _busy || !widget.onceki
                        ? null
                        : () => _kaydet(-1),
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  Text(
                    '${widget.sira} / ${widget.toplam}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _kaydet(0),
                      child: const Text('Kaydet'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    key: const ValueKey('odev-puan-sonraki'),
                    tooltip: 'Sonraki öğrenci • Kaydet ve geç',
                    onPressed: _busy || !widget.sonraki
                        ? null
                        : () => _kaydet(1),
                    icon: const Icon(Icons.chevron_right, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _durumKutusu(OdevKontrolDurumu d) {
    final selected = _durum == d;
    final n = OdevKontrolSonuc.hizliNot(d);
    return SizedBox(
      height: 92,
      child: OutlinedButton(
        key: ValueKey('detay-hizli-${d.name}'),
        onPressed: _busy ? null : () => _sec(d),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(4),
          backgroundColor: odevDurumZemini(d),
          foregroundColor: odevDurumRengi(d),
          side: BorderSide(
            color: selected ? odevDurumRengi(d) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              d.sembol,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '(${odevDurumAdi(d)})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                n == null
                    ? 'Ortalamaya katılmaz'
                    : n >= 0
                    ? '$n'
                    : n == -3
                    ? '0'
                    : 'Ortalamaya katılmaz',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
