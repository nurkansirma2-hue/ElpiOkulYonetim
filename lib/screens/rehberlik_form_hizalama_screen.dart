import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Seçim öğrenci tablosunun üst köşelerinden aile tablosunun alt köşelerine
/// yapılır. Perspektif düzeltmesi alanların komşu hücreye kaymasını azaltır.
class RehberlikFormHizalamaScreen extends StatefulWidget {
  const RehberlikFormHizalamaScreen({
    super.key,
    required this.bytes,
    required this.boyut,
    this.dosyaAdi,
    this.kalanlariAtla,
  });
  final Uint8List bytes;
  final Size boyut;
  final String? dosyaAdi;
  final VoidCallback? kalanlariAtla;
  @override
  State<RehberlikFormHizalamaScreen> createState() => _HizalamaState();
}

class _HizalamaState extends State<RehberlikFormHizalamaScreen> {
  final _koseler = [
    const Offset(.08, .12),
    const Offset(.92, .12),
    const Offset(.92, .84),
    const Offset(.08, .84),
  ];
  bool get _gecerli {
    for (var i = 0; i < 4; i++) {
      final a = _koseler[i],
          b = _koseler[(i + 1) % 4],
          c = _koseler[(i + 2) % 4];
      if ((b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx) <=
          .015) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: const ModulUstBar(title: Text('Formun köşelerini hizala')),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.dosyaAdi != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                widget.dosyaAdi!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Resim dik olmalı. Dört noktayı ÖĞRENCİ BİLGİSİ başlığının üst köşeleri ile AİLE BİLGİSİ tablosunun en alt köşelerine sürükleyin. Üstteki logo ve alttaki teşekkür yazısı dışarıda kalsın.',
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = (constraints.maxWidth / widget.boyut.width).clamp(
                  0.0,
                  constraints.maxHeight / widget.boyut.height,
                );
                final size = Size(
                  widget.boyut.width * scale,
                  widget.boyut.height * scale,
                );
                return Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Image.memory(widget.bytes, fit: BoxFit.fill),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _KoseCizimi(_koseler)),
                          ),
                        ),
                        for (var i = 0; i < 4; i++)
                          Positioned(
                            left: _koseler[i].dx * size.width - 24,
                            top: _koseler[i].dy * size.height - 24,
                            child: GestureDetector(
                              onPanUpdate: (d) => setState(() {
                                _koseler[i] = Offset(
                                  (_koseler[i].dx + d.delta.dx / size.width)
                                      .clamp(0, 1),
                                  (_koseler[i].dy + d.delta.dy / size.height)
                                      .clamp(0, 1),
                                );
                              }),
                              child: Semantics(
                                label: '${i + 1}. köşe',
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withAlpha(110),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (!_gecerli)
            const Text('Köşeler kesişmemeli; 1–2 üstte, 4–3 altta olmalı.'),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _gecerli
                  ? () => Navigator.pop(
                      context,
                      _koseler.expand((p) => [p.dx, p.dy]).toList(),
                    )
                  : null,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Hizalamayı Onayla ve Resmi Oku'),
            ),
          ),
          if (widget.kalanlariAtla != null)
            TextButton(
              onPressed: () {
                widget.kalanlariAtla!();
                Navigator.pop(context);
              },
              child: const Text('Bu ve kalan resimleri atla'),
            ),
        ],
      ),
    ),
  );
}

class _KoseCizimi extends CustomPainter {
  _KoseCizimi(List<Offset> points) : points = List.of(points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_KoseCizimi oldDelegate) => true;
}
