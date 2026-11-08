import 'dart:async';
import 'package:flutter/material.dart';
import '../models/import_ilerleme.dart';

class ImportIlerlemeKarti extends StatefulWidget {
  const ImportIlerlemeKarti({super.key, required this.durum});
  final ImportIlerleme durum;
  @override
  State<ImportIlerlemeKarti> createState() => _ImportIlerlemeKartiState();
}

class _ImportIlerlemeKartiState extends State<ImportIlerlemeKarti> {
  final _sure = Stopwatch()..start();
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _sure.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.durum;
    final saniye = _sure.elapsed.inSeconds;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'İşlem devam ediyor',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Semantics(liveRegion: true, child: Text(d.aciklama)),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: d.oran),
                    if (d.oran != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${d.tamamlanan} / ${d.toplam} • %${(d.oran! * 100).round()} (bu aşama)',
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Geçen süre: ${saniye ~/ 60} dk ${saniye % 60} sn'),
                    if (saniye >= 30)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Bu aşama beklenenden uzun sürüyor. Google veya dosya seçimi ekranı açıldıysa oradaki işlemi tamamlayın ya da iptal edin. Bulut dosyalarında internet bağlantısını kontrol edin.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
