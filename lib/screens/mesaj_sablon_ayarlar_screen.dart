import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import '../models/mesajlasma.dart';
import '../models/mesaj_sablonu.dart';
import '../services/mesajlasma_service.dart';

class MesajSablonAyarlarScreen extends StatefulWidget {
  const MesajSablonAyarlarScreen({
    super.key,
    required this.service,
    required this.baglam,
    this.baslangicTuru = MesajKisiTuru.veli,
  });
  final MesajlasmaService service;
  final MesajBaglami baglam;
  final MesajKisiTuru baslangicTuru;
  @override
  State<MesajSablonAyarlarScreen> createState() => _SablonAyarlarState();
}

class _SablonAyarlarState extends State<MesajSablonAyarlarScreen> {
  MesajSablonListesi? _liste;
  late MesajKisiTuru _tur = widget.baslangicTuru;
  String? _hata;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _yenile();
  }

  Future<void> _yenile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      final liste = await widget.service.hazirMesajlariGetir(widget.baglam);
      if (mounted) setState(() => _liste = liste);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Hazır mesajlar okunamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duzenle([MesajSablonu? eski]) async {
    if (_busy || _liste == null) return;
    final beklenen = _liste!;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SablonDuzenleDialog(
        eski: eski,
        tur: _tur,
        kaydet: (tur, baslik, metin) async {
          final liste = await widget.service.hazirMesajKaydet(
            widget.baglam,
            beklenen: beklenen,
            eski: eski,
            tur: tur,
            baslik: baslik,
            metin: metin,
          );
          if (mounted) {
            setState(() {
              _liste = liste;
              _tur = tur;
              _hata = null;
            });
          }
        },
      ),
    );
  }

  Future<void> _sil(MesajSablonu eski) async {
    if (_busy || _liste == null) return;
    final beklenen = _liste!;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hazır mesajı sil'),
        content: Text(
          '“${eski.baslik}” silinsin mi? Gönderim geçmişi etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (!mounted || onay != true) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      final liste = await widget.service.hazirMesajSil(
        widget.baglam,
        beklenen: beklenen,
        eski: eski,
      );
      if (mounted) setState(() => _liste = liste);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Hazır mesaj silinemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        _liste?.sablonlar.where((s) => s.tur == _tur).toList() ??
        <MesajSablonu>[];
    return PopScope(
      canPop: !_busy,
      child: OrtakSayfa(
        appBar: ModulUstBar(
          title: const Text('Hazır mesaj ayarları'),
          actions: [
            IconButton(
              tooltip: 'Yeni hazır mesaj',
              onPressed: _busy || _liste == null ? null : () => _duzenle(),
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Hazır mesajları yenile',
              onPressed: _busy ? null : _yenile,
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
                child: DropdownButtonFormField<MesajKisiTuru>(
                  key: ValueKey('sablon-grubu-${_tur.name}'),
                  initialValue: _tur,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Alıcı grubu',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in MesajKisiTuru.values)
                      DropdownMenuItem(value: t, child: Text(t.baslik)),
                  ],
                  onChanged: _busy
                      ? null
                      : (t) {
                          if (t != null) setState(() => _tur = t);
                        },
                ),
              ),
              if (_hata != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _hata!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: _liste == null
                    ? Center(
                        child: Text(
                          _busy
                              ? 'Hazır mesajlar yükleniyor…'
                              : 'Hazır mesajlar yüklenemedi. Yenile düğmesini kullanın.',
                        ),
                      )
                    : rows.isEmpty
                    ? const Center(
                        child: Text(
                          'Bu grup için hazır mesaj yok. + düğmesiyle ekleyebilirsiniz.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (c, i) {
                          final s = rows[i];
                          return ListTile(
                            key: ValueKey('sablon-${s.id}'),
                            title: Text(s.baslik),
                            subtitle: Text(
                              s.metin,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: _busy ? null : () => _duzenle(s),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Oku / düzenle',
                                  onPressed: _busy ? null : () => _duzenle(s),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Hazır mesajı sil',
                                  onPressed: _busy ? null : () => _sil(s),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SablonDuzenleDialog extends StatefulWidget {
  const _SablonDuzenleDialog({
    this.eski,
    required this.tur,
    required this.kaydet,
  });
  final MesajSablonu? eski;
  final MesajKisiTuru tur;
  final Future<void> Function(MesajKisiTuru, String, String) kaydet;
  @override
  State<_SablonDuzenleDialog> createState() => _SablonDuzenleState();
}

class _SablonDuzenleState extends State<_SablonDuzenleDialog> {
  late final _baslik = TextEditingController(text: widget.eski?.baslik ?? '');
  late final _metin = TextEditingController(text: widget.eski?.metin ?? '');
  late MesajKisiTuru _tur = widget.eski?.tur ?? widget.tur;
  bool _busy = false;
  String? _hata;
  @override
  void dispose() {
    _baslik.dispose();
    _metin.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await widget.kaydet(_tur, _baslik.text, _metin.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Kaydedilemedi. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.eski == null ? 'Yeni hazır mesaj' : 'Hazır mesajı düzenle',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<MesajKisiTuru>(
              initialValue: _tur,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Alıcı grubu'),
              items: [
                for (final t in MesajKisiTuru.values)
                  DropdownMenuItem(value: t, child: Text(t.baslik)),
              ],
              onChanged: _busy
                  ? null
                  : (t) {
                      if (t != null) setState(() => _tur = t);
                    },
            ),
            TextField(
              key: const ValueKey('sablon-baslik'),
              controller: _baslik,
              enabled: !_busy,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            TextField(
              key: const ValueKey('sablon-metin'),
              controller: _metin,
              enabled: !_busy,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Mesaj içeriği'),
            ),
            Text(
              _tur == MesajKisiTuru.ogretmen
                  ? 'Değişkenler: {Tarih}, {Sinif}.'
                  : 'Değişkenler: {Tarih}, {Sinif}, {OgrenciAdi}. Öğrenci adı yalnız bir öğrenci veya velisi seçildiğinde kullanılır.',
            ),
            if (_hata != null)
              Text(
                _hata!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _busy ? null : _kaydet,
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}
