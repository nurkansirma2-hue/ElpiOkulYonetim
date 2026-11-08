import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/bireysel_rehberlik_service.dart';
import '../widgets/ogrenci_foto_widget.dart';
import 'rehberlik_form_import_screen.dart';

class BireyselRehberlikOgrencileriScreen extends StatefulWidget {
  const BireyselRehberlikOgrencileriScreen({
    super.key,
    required this.service,
    required this.baglam,
    required this.atamaId,
    required this.sinifKodu,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final int atamaId;
  final String sinifKodu;
  @override
  State<BireyselRehberlikOgrencileriScreen> createState() => _OgrencilerState();
}

class _OgrencilerState extends State<BireyselRehberlikOgrencileriScreen>
    with WidgetsBindingObserver {
  List<Map<String, Object?>> _ogrenciler = [];
  String? _hata;
  bool _yukleniyor = true;
  int _istek = 0;
  bool _importAcik = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _yukle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _yukle();
    } else if (state != AppLifecycleState.inactive) {
      _istek++;
      setState(() {
        _ogrenciler = [];
        _yukleniyor = true;
      });
    }
  }

  Future<void> _yukle() async {
    final istek = ++_istek;
    setState(() {
      _ogrenciler = [];
      _hata = null;
      _yukleniyor = true;
    });
    try {
      final rows = await widget.service.ogrencileriGetir(
        widget.baglam,
        atamaId: widget.atamaId,
      );
      if (mounted && istek == _istek) setState(() => _ogrenciler = rows);
    } catch (e) {
      if (mounted && istek == _istek) {
        setState(() => _hata = 'Öğrenciler okunamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted && istek == _istek) setState(() => _yukleniyor = false);
    }
  }

  String _bilgi(Object? value) =>
      value == null || value.toString().trim().isEmpty
      ? 'Kayıtlı değil'
      : value.toString();

  Future<void> _topluFormAc() async {
    if (_importAcik || _yukleniyor || _hata != null) return;
    _importAcik = true;
    try {
      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hassas öğrenci bilgileri'),
          content: const Text(
            'Öğrenci ve aile bilgilerini yalnız rehberlik amacıyla aktarın. Resimler cihazda okunur; onayladığınız cevaplar form geçmişine kaydedilir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Devam Et'),
            ),
          ],
        ),
      );
      if (!mounted || onay != true) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => RehberlikFormImportScreen.toplu(
            service: widget.service,
            baglam: widget.baglam,
            atamaId: widget.atamaId,
          ),
        ),
      );
      if (mounted) await _yukle();
    } finally {
      _importAcik = false;
    }
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: ModulUstBar(
      title: Text('${widget.sinifKodu} • Öğrencilerim'),
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: _yukleniyor ? null : _yukle,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : _hata != null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_hata!),
                TextButton(
                  onPressed: _yukle,
                  child: const Text('Yeniden dene'),
                ),
              ],
            )
          : _ogrenciler.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Bu sınıf ve eğitim yılında aktif öğrenci bulunmuyor.',
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _ogrenciler.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.baglam.egitimOgretimYili} • ${_ogrenciler.length} öğrenci',
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const ValueKey('rehberlik-toplu-form-import'),
                          onPressed: _topluFormAc,
                          icon: const Icon(Icons.collections_outlined),
                          label: const Text('Toplu form resmi import'),
                        ),
                      ],
                    ),
                  );
                }
                final o = _ogrenciler[index - 1];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OgrenciFotoWidget(
                          fotoYolu: o['DosyaYolu'] as String?,
                          fotoVerisi: o['FotoVerisi'] as Uint8List?,
                          yerel: true,
                          width: 48,
                          height: 48,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${o['Ad']} ${o['Soyad']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text('No: ${o['OkulNo']} • ${o['SinifKodu']}'),
                              Text('Veli: ${_bilgi(o['VeliAdi'])}'),
                              Text('Telefon: ${_bilgi(o['VeliTelefonu'])}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
