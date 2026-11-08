import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import '../models/import_ilerleme.dart';
import '../models/mesajlasma.dart';
import '../models/ortak_import.dart';
import '../services/mesajlasma_service.dart';
import '../services/ogretmen_programi_import_tanimi.dart';
import '../widgets/program_import_kapsam_dialog.dart';
import 'ortak_import_screen.dart';

class OgretmenDersImportScreen extends StatefulWidget {
  const OgretmenDersImportScreen({super.key, this.service, this.sinifId});
  final MesajlasmaService? service;
  final int? sinifId;
  @override
  State<OgretmenDersImportScreen> createState() => _State();
}

class _State extends State<OgretmenDersImportScreen> {
  late final _service = widget.service ?? MesajlasmaService.instance;
  final _ilerleme = ValueNotifier<ImportIlerleme?>(null);
  MesajBaglami? _baglam;
  Map<int, String> _siniflar = {};
  int? _sinif;
  bool _busy = true;
  String? _hata;
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _ilerleme.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final b = await _service.hazirla();
      final ss = await _service.mesajSiniflari(b);
      if (!mounted) return;
      setState(() {
        _baglam = b;
        _siniflar = {
          for (final s in ss) s['SinifSubeId'] as int: s['SinifKodu'] as String,
        };
        _sinif = _siniflar.containsKey(widget.sinifId) ? widget.sinifId : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Import hazırlanamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ac() async {
    if (_busy || _baglam == null || _sinif == null) return;
    setState(() => _busy = true);
    try {
      final b = _baglam!, id = _sinif!;
      final sonuc = await Navigator.of(context).push<ImportOzet>(
        MaterialPageRoute(
          builder: (_) => OrtakImportScreen(
            tanim: OgretmenProgramiImportTanimi.olustur(_service, b, id),
            birlesikKaynakSecimi: true,
            ilerleme: _ilerleme,
            ozelOnIzlemeyiHazirla: (c, d) => ProgramImportKapsamDialog.hazirla(
              c,
              _service,
              b,
              id,
              d,
              ilerleme: (v) {
                if (mounted) _ilerleme.value = v;
              },
            ),
            secimOnayi: (c, s, ozet) async =>
                await showDialog<bool>(
                  context: c,
                  builder: (d) => AlertDialog(
                    scrollable: true,
                    title: const Text('Öğretmen ve ders ilişkilerini onayla'),
                    content: Text(ozet),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('Vazgeç'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('Onayla ve Kaydet'),
                      ),
                    ],
                  ),
                ) ==
                true,
            secimiKaydet: (s) =>
                _service.ogretmenProgramiAktar(b, s.onIzleme, s.secimler),
          ),
        ),
      );
      if (mounted && sonuc != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(sonuc.mesaj)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Import tamamlanamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: const ModulUstBar(title: Text('Sınıf öğretmenleri ve dersleri')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Program belgesindeki öğretmenleri, sınıflarını ve derslerini buradan aktarabilirsiniz. PDF, Word ve Excel desteklenir. Belgedeki diğer ders sınıflarınızı da dahil etmek isteyip istemediğiniz sorulur.',
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_hata != null)
          Text(
            _hata!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!_busy && _siniflar.isEmpty)
          const Text(
            'Önce Import Merkezi > Ders programım ile ders sınıflarınızı hazırlayın.',
          ),
        DropdownButtonFormField<int>(
          key: ValueKey(_sinif),
          initialValue: _sinif,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Başlangıç sınıfı'),
          items: [
            for (final s in _siniflar.entries)
              DropdownMenuItem(value: s.key, child: Text(s.value)),
          ],
          onChanged: _busy ? null : (v) => setState(() => _sinif = v),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy || _sinif == null ? null : _ac,
          icon: const Icon(Icons.upload_file),
          label: const Text('Dosya seç ve aktar'),
        ),
      ],
    ),
  );
}
