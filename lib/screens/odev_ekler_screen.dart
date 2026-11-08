import '../widgets/ortak_ui.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../services/bireysel_liste_service.dart';
import '../widgets/odev_gorunum.dart';
import '../services/bireysel_odev_kontrol_service.dart';

Future<void> odevEkiEkle(
  BuildContext context,
  BireyselListeOturumu oturum,
  int odevId, {
  int? sonucId,
}) async {
  final pick = await FilePicker.platform.pickFiles(withData: true);
  if (pick == null) return;
  final f = pick.files.single;
  if (f.size > 10 * 1024 * 1024) {
    throw StateError('Ek dosya en fazla 10 MB olabilir.');
  }
  final bytes =
      f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
  if (bytes == null) throw StateError('Dosya okunamadı.');
  await OdevDosyaService.ekle(oturum, odevId, f.name, bytes, sonucId: sonucId);
}

class OdevEklerScreen extends StatefulWidget {
  const OdevEklerScreen({
    super.key,
    required this.oturum,
    required this.odevId,
  });
  final BireyselListeOturumu oturum;
  final int odevId;
  @override
  State<OdevEklerScreen> createState() => _EklerState();
}

class _EklerState extends State<OdevEklerScreen> {
  List<Map<String, Object?>> _rows = [];
  bool _busy = false;
  String? _hata;
  @override
  void initState() {
    super.initState();
    _islem(_oku);
  }

  Future<void> _oku() async {
    final rows = await OdevDosyaService.liste(widget.oturum, widget.odevId);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _islem(Future<void> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Ek işlemi tamamlanamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ac(int id) async {
    final r = await OdevDosyaService.oku(widget.oturum, widget.odevId, id);
    final uzanti = p.extension(r['DosyaAdi'] as String).toLowerCase();
    const acilabilir = {
      '.pdf',
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
      '.txt',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.mp3',
      '.mp4',
    };
    if (!acilabilir.contains(uzanti)) {
      throw StateError('Bu dosya türü uygulamadan doğrudan açılamıyor.');
    }
    final bytes = Uint8List.fromList(r['Veri'] as List<int>);
    final d = await Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        'odev_ek_${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create();
    final f = File(p.join(d.path, p.basename(r['DosyaAdi'] as String)));
    await f.writeAsBytes(bytes, flush: true);
    final sonuc = await OpenFile.open(f.path);
    if (sonuc.type != ResultType.done) throw StateError(sonuc.message);
  }

  @override
  Widget build(BuildContext context) => OdevTema(
    child: PopScope(
      canPop: !_busy,
      child: OrtakSayfa(
        appBar: const OdevBaslik(title: Text('Ödev Detayı / Ekler')),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _islem(() async {
                      await odevEkiEkle(context, widget.oturum, widget.odevId);
                      await _oku();
                    }),
              icon: const Icon(Icons.attach_file),
              label: const Text('Dosya / Fotoğraf Ekle'),
            ),
          ),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_hata != null) Text(_hata!),
            Card(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.attach_file_outlined, color: odevBaslikMavi),
                  SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mevcut Ekler',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 3),
                      Text('Ödev dosyalarını açın, yeni dosya ekleyin veya silin.',
                        style: TextStyle(fontSize: 12)),
                    ],
                  )),
                ]),
              ),
            ),
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('Ek dosya yok.'))
                  : ListView(
                      children: [
                        for (final r in _rows)
                          Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.insert_drive_file_outlined),
                              title: Text('${r['DosyaAdi']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                r['OdevKontrolSonucId'] == null
                                    ? 'Ödev eki • Açmak için dokun'
                                    : 'Öğrenci değerlendirme eki • Açmak için dokun',
                              ),
                            onTap: _busy
                                ? null
                                : () => _islem(() => _ac(r['Id'] as int)),
                            trailing: IconButton(
                              tooltip: 'Eki sil',
                              onPressed: _busy
                                  ? null
                                  : () => _islem(() async {
                                      final onay = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Ek silinsin mi?'),
                                          content: Text('${r['DosyaAdi']}'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(c),
                                              child: const Text('Vazgeç'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text('Sil'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (onay != true) return;
                                      await OdevDosyaService.sil(
                                        widget.oturum,
                                        widget.odevId,
                                        r['Id'] as int,
                                      );
                                      await _oku();
                                    }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
