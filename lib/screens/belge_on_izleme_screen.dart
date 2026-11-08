import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:pdfx/pdfx.dart';

import '../models/ortak_import.dart';
import '../services/belge_analiz_service.dart';
import '../services/ortak_import_service.dart';

class BelgeOnIzlemeScreen extends StatefulWidget {
  const BelgeOnIzlemeScreen({
    super.key,
    required this.yol,
    required this.ad,
    required this.uzanti,
  });
  final String yol, ad, uzanti;
  static const uzantilar = {
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'txt',
    'csv',
    'xls',
    'xlsx',
    'docx',
  };
  @override
  State<BelgeOnIzlemeScreen> createState() => _BelgeOnIzlemeScreenState();
}

class _BelgeOnIzlemeScreenState extends State<BelgeOnIzlemeScreen> {
  PdfController? _pdf;
  List<ImportTablosu>? _tablolar;
  int _sayfa = 0;
  String? _metin, _hata;
  bool _yukleniyor = true, _kirpildi = false;
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _pdf?.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      if (widget.uzanti == 'pdf') {
        _pdf = PdfController(document: PdfDocument.openFile(widget.yol));
      } else if (const {'xls', 'xlsx', 'csv'}.contains(widget.uzanti)) {
        final bytes = await File(widget.yol).readAsBytes();
        final dosya = ImportDosya(widget.ad, bytes);
        await BelgeAnalizService.bicimiDogrulaAsync(dosya);
        final tablolar = await OrtakImportService.oku(dosya);
        if (tablolar.isEmpty) throw StateError('Dosyada tablo bulunamadı.');
        _tablolar = tablolar;
      } else if (widget.uzanti == 'docx') {
        final text = await BelgeAnalizService.docxMetni(
          await File(widget.yol).readAsBytes(),
        );
        _kirpildi = text.length > 500000;
        _metin = text.substring(0, _kirpildi ? 500000 : text.length);
      } else if (widget.uzanti == 'txt') {
        final file = File(widget.yol);
        _kirpildi = await file.length() > 512000;
        final bytes = await file
            .openRead(0, _kirpildi ? 512000 : null)
            .fold<List<int>>([], (sum, b) => sum..addAll(b));
        _metin = utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      _hata =
          'Ön izleme hazırlanamadı. Dış uygulamada açmayı deneyebilirsiniz.\nOrijinal hata: $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _disaridaAc() async {
    final sonuc = await OpenFile.open(widget.yol);
    if (sonuc.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dosya açılamadı. Orijinal hata: ${sonuc.message}'),
        ),
      );
    }
  }

  Widget _tablo() {
    final table = _tablolar![_sayfa];
    final rows = table.satirlar.take(100).toList();
    var columns = rows.fold<int>(0, (n, r) => r.length > n ? r.length : n);
    if (columns > 20) columns = 20;
    if (columns == 0) {
      return const Center(child: Text('Sayfada dolu hücre yok.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<int>(
            initialValue: _sayfa,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sayfa'),
            items: [
              for (var i = 0; i < _tablolar!.length; i++)
                DropdownMenuItem(value: i, child: Text(_tablolar![i].ad)),
            ],
            onChanged: (i) {
              if (i != null) setState(() => _sayfa = i);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Salt okunur ön izleme • İlk 100 satır ve 20 sütun. Yatay kaydırabilirsiniz.',
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: columns * 160 + 48,
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, r) => Container(
                  color: r.isEven
                      ? Theme.of(context).colorScheme.surfaceContainerLow
                      : Theme.of(context).colorScheme.surface,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 48,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('${r + 1}'),
                        ),
                      ),
                      for (var c = 0; c < columns; c++)
                        SizedBox(
                          width: 160,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              c < rows[r].length ? rows[r][c] : '',
                              maxLines: 6,
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: ModulUstBar(
      title: Text(widget.ad),
      actions: [
        IconButton(
          tooltip: 'Dış Uygulamada Aç',
          onPressed: _disaridaAc,
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
    body: _yukleniyor
        ? const Center(child: CircularProgressIndicator())
        : _hata != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_hata!),
            ),
          )
        : _pdf != null
        ? PdfView(
            controller: _pdf!,
            onDocumentError: (e) {
              if (mounted) {
                setState(() => _hata = 'PDF açılamadı. Orijinal hata: $e');
              }
            },
          )
        : _tablolar != null
        ? _tablo()
        : _metin != null
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.uzanti == 'docx')
                  const Text(
                    'Word metin görünümü. Sayfa düzeni için Dış Uygulamada Aç seçeneğini kullanın.\n',
                  ),
                if (_kirpildi)
                  const Text(
                    'Uzun belgenin başlangıcı gösteriliyor; tam içerik dosyada korunuyor.\n',
                  ),
                SelectableText(_metin!),
              ],
            ),
          )
        : Center(
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 5,
              child: Image.file(
                File(widget.yol),
                cacheWidth: 1600,
                errorBuilder: (_, error, _) =>
                    Text('Görsel açılamadı. Orijinal hata: $error'),
              ),
            ),
          ),
  );
}
