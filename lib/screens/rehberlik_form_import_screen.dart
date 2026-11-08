import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/ortak_import.dart';
import '../services/rehberlik_form_import.dart';
import '../services/bireysel_rehberlik_service.dart';
import '../services/rehberlik_toplu_form_import.dart';
import 'ortak_import_screen.dart';
import 'rehberlik_form_hizalama_screen.dart';

class RehberlikFormImportScreen extends StatefulWidget {
  const RehberlikFormImportScreen({
    super.key,
    required String this.okulNo,
    required String this.adSoyad,
  }) : service = null,
       baglam = null,
       atamaId = null;
  const RehberlikFormImportScreen.toplu({
    super.key,
    required BireyselRehberlikService this.service,
    required BireyselRehberlikBaglami this.baglam,
    required int this.atamaId,
  }) : okulNo = null,
       adSoyad = null;
  final String? okulNo, adSoyad;
  final BireyselRehberlikService? service;
  final BireyselRehberlikBaglami? baglam;
  final int? atamaId;
  @override
  State<RehberlikFormImportScreen> createState() => _FormImportState();
}

class _FormImportState extends State<RehberlikFormImportScreen>
    with WidgetsBindingObserver {
  late final _import = RehberlikFormImport(
    okulNo: widget.okulNo!,
    adSoyad: widget.adSoyad!,
  );
  bool get _topluMu => widget.service != null;
  late final _toplu = RehberlikTopluFormImport(
    service: widget.service!,
    baglam: widget.baglam!,
    atamaId: widget.atamaId!,
  );
  ImportDosya? _resim;
  final _topluResimler = <String, ImportDosya>{};
  String? _ilerleme;
  bool _durdur = false;
  bool _kilit = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused || !mounted || _kilit) return;
    _kilit = true;
    // Fotoğraf/ön izleme ve varsa açık düzenleme diyaloğu aynı örtü altında.
    Navigator.of(context, rootNavigator: true)
        .push<void>(
          RawDialogRoute<void>(
            barrierColor: Colors.black,
            barrierDismissible: false,
            pageBuilder: (ctx, _, __) => PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('Hassas öğrenci formu'),
                content: const Text(
                  'Uygulama arka plana geçti. Form ön izlemesini yeniden görüntüleyin.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Ön izlemeyi görüntüle'),
                  ),
                ],
              ),
            ),
            transitionDuration: Duration.zero,
          ),
        )
        .whenComplete(() => _kilit = false);
  }

  Future<ImportOnIzleme> _oku(ImportDosya dosya) async {
    final result = await _resimOku(dosya);
    if (result == null) {
      throw StateError(
        'Hizalama iptal edildi. Ön izlemeyi yeniden hazırlayabilirsiniz.',
      );
    }
    if (mounted) setState(() => _resim = result.resim);
    return _import.hazirla([
      for (var i = 0; i < _import.sorular.length; i++)
        ImportKaynakSatiri('$i', _import.sorular[i], {
          'alan': _import.sorular[i],
          'deger': result.cevaplar[_import.sorular[i]] ?? '',
        }),
    ]);
  }

  Future<({ImportDosya resim, Map<String, String> cevaplar})?> _resimOku(
    ImportDosya dosya,
  ) async {
    if (!RehberlikFormImport.uzantilar.contains(dosya.uzanti) ||
        dosya.bytes.length > 20 * 1024 * 1024) {
      throw const FormatException(
        'JPG, PNG veya WEBP biçiminde, en fazla 20 MB bir resim seçin.',
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(dosya.bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 64000000) {
        throw const FormatException('Görsel 64 megapiksel sınırını aşıyor.');
      }
      final ratio =
          1800 /
          (descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height);
      final scale = ratio < 1 ? ratio : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final bytes = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (bytes == null) throw StateError('Görsel hazırlanamadı.');
          final normal = ImportDosya('form.png', bytes.buffer.asUint8List());
          if (!mounted) throw StateError('Form ekranı kapandı.');
          final corners = await Navigator.push<List<double>>(
            context,
            MaterialPageRoute(
              builder: (_) => RehberlikFormHizalamaScreen(
                bytes: normal.bytes,
                dosyaAdi: dosya.ad,
                kalanlariAtla: _topluMu ? () => _durdur = true : null,
                boyut: Size(
                  frame.image.width.toDouble(),
                  frame.image.height.toDouble(),
                ),
              ),
            ),
          );
          if (corners == null) return null;
          final result = await RehberlikFormImport.resimDegerleriniOku(
            normal,
            corners,
          );
          return (resim: normal, cevaplar: result);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<ImportOnIzleme?> _topluOku(List<ImportDosya> dosyalar) async {
    await widget.service!.formImportOgrencileri(
      widget.baglam!,
      widget.atamaId!,
      hassasOnay: true,
    );
    if (!mounted) return null;
    _topluResimler.clear();
    _durdur = false;
    final sources = <ImportKaynakSatiri>[];
    try {
      for (var i = 0; i < dosyalar.length; i++) {
        if (!mounted) return null;
        final file = dosyalar[i], id = 'form-$i';
        _topluResimler[id] = file;
        if (_durdur) {
          final source = _toplu.kaynak(id, file.ad, {});
          sources.add(
            ImportKaynakSatiri(id, file.ad, {
              ...source.degerler,
              'islem': 'Atla',
            }),
          );
          continue;
        }
        setState(() => _ilerleme = '${i + 1}/${dosyalar.length} • ${file.ad}');
        try {
          final result = await _resimOku(file);
          if (result == null) {
            final source = _toplu.kaynak(id, file.ad, {});
            sources.add(
              ImportKaynakSatiri(id, file.ad, {
                ...source.degerler,
                'islem': 'Atla',
              }),
            );
          } else {
            _topluResimler[id] = result.resim;
            sources.add(_toplu.kaynak(id, file.ad, result.cevaplar));
          }
        } catch (e) {
          sources.add(_toplu.kaynak(id, file.ad, {}, hata: e.toString()));
        }
      }
      return await _toplu.hazirla(sources);
    } finally {
      if (mounted) setState(() => _ilerleme = null);
    }
  }

  Future<bool> _topluOnay(
    BuildContext context,
    ImportSecimi secim,
    String ozet,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Seçilen öğrenci formlarını kaydet'),
          content: SingleChildScrollView(
            child: Text(
              '${secim.secimler.length} öğrenci formu yeni sürüm olarak kaydedilecek. Dolu okunan cevaplar mevcut formdaki aynı alanı günceller; boş cevaplar ve eski sürümler korunur.\n\n$ozet',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Onayla ve Kaydet'),
            ),
          ],
        ),
      ) ??
      false;

  Widget? _kaynakGorseli(ImportOnIzleme preview, ImportKaydi row) {
    final image = _topluMu ? _topluResimler[row.id] : _resim;
    if (image == null) return null;
    return IconButton(
      tooltip: 'Kaynak resmi görüntüle',
      icon: Image.memory(
        image.bytes,
        width: 48,
        height: 56,
        fit: BoxFit.contain,
        cacheWidth: 96,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 8,
                  child: Image.memory(
                    image.bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Text('Kaynak resim görüntülenemedi.'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      OrtakImportScreen(
        tanim: _topluMu ? _toplu.tanim : _import.tanim(_oku),
        secimleDon: !_topluMu,
        sonucIleDon: false,
        cokluOnIzlemeyiHazirla: _topluMu
            ? (_, files) => _topluOku(files)
            : null,
        secimOnayi: _topluMu ? _topluOnay : null,
        secimiKaydet: _topluMu
            ? (s) => _toplu.kaydet(s.onIzleme, s.secimler)
            : null,
        kayitGorseli: _kaynakGorseli,
      ),
      if (_ilerleme != null)
        Positioned(
          top: 80,
          left: 12,
          right: 12,
          child: Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _ilerleme!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const LinearProgressIndicator(),
                  TextButton(
                    onPressed: () => setState(() => _durdur = true),
                    child: Text(
                      _durdur
                          ? 'Mevcut resimden sonra duracak'
                          : 'Kalan Resimleri Atla',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
