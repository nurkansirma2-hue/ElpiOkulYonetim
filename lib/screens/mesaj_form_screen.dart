import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/mesajlasma.dart';
import '../services/mesajlasma_service.dart';
import 'mesajlasma_screen.dart';

/// Bütün modüller aynı talep, gönderim ve cevap aktarım ekranını kullanır.
class MesajFormScreen extends StatefulWidget {
  const MesajFormScreen({
    super.key,
    required this.kaynakModul,
    required this.kaynakKayit,
    required this.ogrenciIdleri,
    this.baslik = '',
    this.baslangicSoru = '',
    this.aliciTuru = 'Ogretmen',
    this.service,
    this.egitimOgretimYili,
    this.saltOkunur = false,
  });
  final String kaynakModul, kaynakKayit, baslik;
  final String baslangicSoru, aliciTuru;
  final Set<int> ogrenciIdleri;
  final MesajlasmaService? service;
  final String? egitimOgretimYili;
  final bool saltOkunur;
  @override
  State<MesajFormScreen> createState() => _MesajFormState();
}

class _MesajFormState extends State<MesajFormScreen> {
  late final _service = widget.service ?? MesajlasmaService.instance;
  MesajBaglami? _b;
  List<Map<String, Object?>> _formlar = [];
  List<MesajOgrencisi> _ogrenciler = [];
  final _secili = <int>{};
  late final _baslik = TextEditingController(text: widget.baslik);
  late final _soru = TextEditingController(text: widget.baslangicSoru);
  late String _tur = widget.aliciTuru;
  String? _hata;
  bool _genel = true, _islem = false;
  bool get _saltOkunur =>
      widget.saltOkunur ||
      (widget.egitimOgretimYili != null && widget.egitimOgretimYili != _b?.yil);
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _baslik.dispose();
    _soru.dispose();
    super.dispose();
  }

  Future<void> _calistir(Future<void> Function() f) async {
    if (_islem) return;
    setState(() {
      _islem = true;
      _hata = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(
          () => _hata = 'Mesajlaşma işlemi tamamlanamadı.\nOrijinal hata: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _yukle() => _calistir(() async {
    final b = await _service.hazirla();
    final o =
        widget.saltOkunur ||
            (widget.egitimOgretimYili != null &&
                widget.egitimOgretimYili != b.yil)
        ? <MesajOgrencisi>[]
        : await _service.ogrenciler(b);
    final f = await _service.formlariGetir(
      b,
      widget.kaynakModul,
      widget.kaynakKayit,
      egitimOgretimYili: widget.egitimOgretimYili,
    );
    if (mounted) {
      setState(() {
        _b = b;
        _ogrenciler = o
            .where((s) => widget.ogrenciIdleri.contains(s.id))
            .toList();
        _formlar = f;
      });
    }
  });
  Future<void> _cevap(Map<String, Object?> f) async {
    final ad = TextEditingController(), genel = TextEditingController();
    final os = (jsonDecode(f['Ogrenciler'] as String) as List);
    final controllers = {
      for (final o in os) o['id'].toString(): TextEditingController(),
    };
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Gelen cevabı aktar'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Yanıtı kontrol ederek aktarın. Yanıtlayan kimliği beyana dayalıdır.',
              ),
              TextField(
                controller: ad,
                decoration: const InputDecoration(labelText: 'Yanıtlayan'),
              ),
              if (f['SinifGeneli'] == 1)
                TextField(
                  controller: genel,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Sınıf geneli görüşü',
                  ),
                ),
              for (final o in os)
                TextField(
                  controller: controllers[o['id'].toString()],
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '${o['no']} • ${o['ad']}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla ve aktar'),
          ),
        ],
      ),
    );
    if (onay == true && mounted) {
      await _calistir(() async {
        await _service.cevapKaydet(
          _b!,
          f['Id'] as String,
          ad.text,
          genel.text,
          controllers.map((k, v) => MapEntry(k, v.text)),
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Cevap aktarıldı.')));
        }
      });
    }
    ad.dispose();
    genel.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> _cevaplar(Map<String, Object?> f) => _calistir(() async {
    final rows = await _service.cevaplariGetir(
      _b!,
      f['Id'] as String,
      egitimOgretimYili: widget.egitimOgretimYili,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Görüşler'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rows.isEmpty) const Text('Henüz cevap aktarılmadı.'),
                for (final r in rows) ...[
                  Text('${r['Yanitlayan']} • ${r['OlusturmaTarihi']}'),
                  Text('${r['SinifGorusu']}'),
                  for (final o in jsonDecode(f['Ogrenciler'] as String) as List)
                    Text(
                      '${o['ad']}: ${(jsonDecode(r['OgrenciGorusleri'] as String) as Map)[o['id'].toString()] ?? ''}',
                    ),
                  const Divider(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  });
  Future<void> _gonder(Map<String, Object?> f) => _calistir(() async {
    if (f['AliciTuru'] != 'Ogretmen' &&
        (jsonDecode(f['Ogrenciler'] as String) as List).length > 1) {
      throw StateError(
        'Veli veya öğrenciye başka öğrencilerin görüş bilgileri gönderilemez. Ayrı talepler hazırlayın.',
      );
    }
    final metin = await _service.formMetni(_b!, f['Id'] as String);
    if (!mounted) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Gönderim ön izlemesi'),
        content: SingleChildScrollView(child: Text(metin)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              f['AliciTuru'] == 'Veli' ? 'Mesajlaşmayı aç' : 'Metni kopyala',
            ),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    await _service.formMetni(_b!, f['Id'] as String);
    if (!mounted) return;
    if (f['AliciTuru'] == 'Veli') {
      // Her veliye çok sayıda öğrencinin adını göndermeyiz. Bireysel talep ayrı iletilir.
      final os = jsonDecode(f['Ogrenciler'] as String) as List;
      if (os.length > 1) {
        throw StateError(
          'Birden fazla öğrenci içeren talep velilere toplu gönderilemez. Her veli için ayrı talep hazırlayın.',
        );
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MesajlasmaScreen(
            kaynakModul: widget.kaynakModul,
            kaynakKayit: f['Id'] as String,
            baslangicMetni: metin,
            baslangicOgrenciIdleri: os.map((o) => o['id'] as int).toSet(),
            izinliOgrenciIdleri: os.isEmpty
                ? widget.ogrenciIdleri
                : os.map((o) => o['id'] as int).toSet(),
          ),
        ),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: metin));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Talep kopyalandı. İlgili kişiyle paylaşabilirsiniz.',
            ),
          ),
        );
      }
    }
  });

  Future<void> _dosyaAktar(Map<String, Object?> f) => _calistir(() async {
    final secim = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (secim == null) return;
    final bytes = secim.files.single.bytes;
    if (bytes == null || bytes.length > 100000) {
      throw const FormatException('Cevap dosyası okunamadı veya çok büyük.');
    }
    final veri = MesajFormIslemleri.cevapDosyasiOku(
      utf8.decode(bytes),
      f['Id'] as String,
    );
    if (!mounted) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cevap ön izlemesi'),
        content: SingleChildScrollView(
          child: Text(const JsonEncoder.withIndent('  ').convert(veri)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla ve aktar'),
          ),
        ],
      ),
    );
    if (onay == true) {
      await _service.cevapKaydet(
        _b!,
        f['Id'] as String,
        veri['yanitlayan'] as String,
        veri['sinifGorusu'] as String,
        Map<String, String>.from(veri['ogrenciGorusleri'] as Map),
        cevapId: veri['cevapId'] as String,
      );
    }
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_islem,
    child: OrtakSayfa(
      appBar: ModulUstBar(
        title: const Text('Ortak Mesajlaşma • Görüşler'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _islem ? null : _yukle,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_hata != null) Text(_hata!),
          if (_saltOkunur) const Text('Geçmiş görüşler: salt okunur.'),
          if (!_saltOkunur) ...[
            const Text(
              'Tek talep, sınıf geneli ve seçilen öğrenciler için ayrı değerlendirmeler içerir. Öğretmen/öğrenciye talep metni kopyalanır; gelen yanıtlar burada kontrol edilerek aktarılır.',
            ),
            TextField(
              controller: _baslik,
              decoration: const InputDecoration(labelText: 'Talep başlığı'),
              maxLength: 300,
            ),
            TextField(
              controller: _soru,
              maxLines: 3,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Değerlendirme sorusu',
              ),
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _tur,
              decoration: const InputDecoration(
                labelText: 'Görüş alınacak kişi',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Ogretmen',
                  child: Text(
                    'Sınıfa ders veren öğretmen',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(value: 'Ogrenci', child: Text('Öğrenci')),
                DropdownMenuItem(value: 'Veli', child: Text('Veli')),
              ],
              onChanged: _islem ? null : (v) => setState(() => _tur = v!),
            ),
            CheckboxListTile(
              title: const Text('Sınıf genelini de değerlendir'),
              value: _genel,
              onChanged: _islem ? null : (v) => setState(() => _genel = v!),
            ),
            for (final o in _ogrenciler)
              CheckboxListTile(
                title: Text('${o.okulNo} • ${o.ad}'),
                value: _secili.contains(o.id),
                onChanged: _islem
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          _secili.add(o.id);
                        } else {
                          _secili.remove(o.id);
                        }
                      }),
              ),
            FilledButton(
              onPressed: _islem || _b == null
                  ? null
                  : () async {
                      await _calistir(() async {
                        await _service.formOlustur(
                          _b!,
                          kaynakModul: widget.kaynakModul,
                          kaynakKayit: widget.kaynakKayit,
                          baslik: _baslik.text,
                          aliciTuru: _tur,
                          ogrenciIdleri: _secili,
                          sinifGeneli: _genel,
                          soru: _soru.text,
                        );
                      });
                      if (mounted) await _yukle();
                    },
              child: const Text('Görüş talebini kaydet'),
            ),
          ],
          for (final f in _formlar)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${f['Baslik']}'),
                    Text('${f['Soru']}'),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (!_saltOkunur)
                          TextButton(
                            onPressed: _islem ? null : () => _gonder(f),
                            child: const Text('Gönder / kopyala'),
                          ),
                        if (!_saltOkunur)
                          TextButton(
                            onPressed: _islem ? null : () => _cevap(f),
                            child: const Text('Cevap aktar'),
                          ),
                        TextButton(
                          onPressed: _islem ? null : () => _cevaplar(f),
                          child: const Text('Cevapları gör'),
                        ),
                        if (!_saltOkunur)
                          TextButton(
                            onPressed: _islem ? null : () => _dosyaAktar(f),
                            child: const Text('Cevap dosyası aktar'),
                          ),
                        if (!_saltOkunur)
                          TextButton(
                            onPressed: _islem
                                ? null
                                : () => _calistir(() async {
                                    await Clipboard.setData(
                                      ClipboardData(
                                        text: await _service.cevapSablonu(
                                          _b!,
                                          f['Id'] as String,
                                        ),
                                      ),
                                    );
                                  }),
                            child: const Text('Yanıt şablonunu kopyala'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
