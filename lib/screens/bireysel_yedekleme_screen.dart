import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../services/bireysel_bakim_service.dart';

class BireyselYedeklemeScreen extends StatefulWidget {
  const BireyselYedeklemeScreen({super.key, this.onGeriYuklendi, this.service});
  final Future<void> Function()? onGeriYuklendi;
  final BireyselBakimService? service;
  @override
  State<BireyselYedeklemeScreen> createState() =>
      _BireyselYedeklemeScreenState();
}

class _BireyselYedeklemeScreenState extends State<BireyselYedeklemeScreen> {
  late final _service = widget.service ?? BireyselBakimService.instance;
  bool _busy = false;
  String _durum = '', _mesaj = '';
  BakimYedegi? _sonYedek;
  bool _disariKaydedildi = false;
  Future<void> _calistir(String durum, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _durum = durum;
      _mesaj = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _mesaj = 'İşlem tamamlanamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _yedekle() => _calistir('Yedek hazırlanıyor...', () async {
    _sonYedek = await _service.yedekle();
    _disariKaydedildi = false;
    await _kaydet();
  });
  Future<void> _kaydet() async {
    final f = _sonYedek!.dosya;
    String? hedef;
    if (Platform.isAndroid) {
      hedef = await const MethodChannel(
        'elpi_okul_yonetim/dosya_secici',
      ).invokeMethod<String>('bakimYedegiKaydet', {'yol': f.path});
    } else {
      hedef = await FilePicker.platform.saveFile(
        dialogTitle: 'Yedek konumunu seç',
        fileName: p.basename(f.path),
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: Platform.isIOS ? await f.readAsBytes() : null,
      );
      if (hedef != null && !Platform.isIOS) await f.copy(hedef);
    }
    _disariKaydedildi = hedef != null;
    if (mounted) {
      setState(
        () => _mesaj = hedef == null
            ? 'Konum seçimi iptal edildi. Yedek yalnız bu uygulamada duruyor; dışarı kaydetmek için tekrar deneyin.'
            : 'Yedek seçilen konuma kaydedildi. Drive seçtiyseniz yükleme durumunu Drive uygulamasından kontrol edin.',
      );
    }
  }

  Future<void> _geriYukle({
    File? yerel,
  }) => _calistir('Yedek doğrulanıyor...', () async {
    var path = yerel?.path;
    if (path == null) {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Cihazdan veya Drive’dan yedek seç',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      if (picked == null) return;
      path = picked.files.single.path;
    }
    if (path == null) throw StateError('Seçilen yedek dosyasına erişilemedi.');
    final info = await _service.incele(File(path));
    try {
      if (!mounted) return;
      final onay = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _GeriYuklemeOnayi(info: info),
      );
      if (onay != 'GERİ YÜKLE' || !mounted) return;
      setState(
        () => _durum = 'Koruma yedeği alınıyor ve veriler geri yükleniyor...',
      );
      final koruma = await _service.geriYukle(info, onayMetni: onay!);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          scrollable: true,
          title: const Text('Geri yükleme tamamlandı'),
          content: Text(
            'Önceki durumun koruma yedeği cihazda tutuluyor.\n$koruma\n\n'
            'Bu yerel kopya uygulama kaldırılırsa silinir. Yönetim panelinden dışarı kaydedebilirsiniz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Devam Et'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onGeriYuklendi?.call();
    } finally {
      if (await info.dosya.exists()) await info.dosya.delete();
    }
  });
  Future<void> _yerelYedekSec() async {
    if (_busy) return;
    File? selected;
    String? action;
    await _calistir('Yerel yedekler okunuyor...', () async {
      final files = await _service.yerelYedekler();
      if (!mounted) return;
      if (files.isEmpty) {
        setState(() => _mesaj = 'Henüz cihazda yedek yok.');
        return;
      }
      selected = await showDialog<File>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cihazdaki yedekler'),
          content: SizedBox(
            width: 500,
            height: 350,
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(p.basename(files[i].path)),
                onTap: () => Navigator.pop(context, files[i]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      action = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Yedek işlemi'),
          content: Text(p.basename(selected!.path)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Yerel Kopyayı Sil'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'restore'),
              child: const Text('Geri Yükle'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Dışarı Kaydet'),
            ),
          ],
        ),
      );
    });
    if (!mounted || selected == null) return;
    if (action == 'restore') {
      await _geriYukle(yerel: selected);
    }
    if (action == 'delete') {
      await _calistir('Yerel yedek siliniyor...', () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            scrollable: true,
            title: const Text('Yerel yedek kopyası silinsin mi?'),
            content: const Text(
              'Bu yedek yalnız cihazınızdan kaldırılır. Canlı veriler ve dışarı '
              'kaydettiğiniz kopyalar korunur. Dışarı kaydetmediyseniz bu yedeği kaybedersiniz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yerel Kopyayı Sil'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await _service.yerelYedegiSil(selected!, onay: 'SİL');
        if (mounted) {
          setState(() {
            if (_sonYedek?.dosya.path == selected!.path) _sonYedek = null;
            _mesaj = 'Yerel yedek kopyası silindi. Canlı veriler korunuyor.';
          });
        }
      });
    }
    if (action == 'save') {
      await _calistir('Yedek doğrulanıyor...', () async {
        final info = await _service.incele(selected!);
        try {
          _sonYedek = BakimYedegi(
            selected!,
            info.tarih,
            info.ogretmen,
            info.sayilar,
          );
          _disariKaydedildi = false;
          await _kaydet();
        } finally {
          await info.dosya.delete();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OrtakSayfa(
      appBar: ModulUstBar(
        title: const Text('Yedekleme ve Geri Yükleme'),
        automaticallyImplyLeading: !_busy,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(
                  Icons.backup_outlined,
                  size: 48,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tüm bireysel verilerin bir arada',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Öğretmen ve okul bilgileri, öğrenciler ve fotoğrafları, ders programı, yıllık planlar, '
                  'çalışma takvimleri, ödev sonuçları ve tüm Belgelerim arşivleri tek ZIP yedeğe alınır. '
                  'Yedek bu cihazdaki bireysel kayıtları içerir.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Konumu kaydederken seçersiniz: cihaz klasörü veya dosya seçim ekranında Google Drive. '
                  'Drive için cihazınızda bağlı hesap ve internet gerekir. Drive görünmüyorsa cihazınıza kaydedebilirsiniz.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Yedek öğrenci bilgileri içerir; kendi hesabınızda veya güvenli bir klasörde saklayın. '
                  '512 MB toplam içerik sınırı vardır.',
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _yedekle,
                  icon: const Icon(Icons.backup),
                  label: const Text('Yedekle • Cihaz / Google Drive'),
                ),
                if (_sonYedek != null && !_disariKaydedildi) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _calistir('Yedek kaydediliyor...', _kaydet),
                    child: const Text('Hazır yedeği tekrar dışarı kaydet'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _yerelYedekSec,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Cihazdaki Yedekler / Koruma Yedekleri'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _geriYukle(),
                  icon: const Icon(Icons.restore),
                  label: const Text('Yedeği Geri Yükle'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Geri yükleme, bu cihazdaki tüm bireysel verilerin yerine yedekteki durumu getirir. '
                  'Önce doğrulama ve koruma yedeği yapılır; sonrasında açık onayınız istenir.',
                ),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_durum),
                ],
                if (_mesaj.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  SelectableText(_mesaj),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _GeriYuklemeOnayi extends StatefulWidget {
  const _GeriYuklemeOnayi({required this.info});
  final BakimYedegi info;
  @override
  State<_GeriYuklemeOnayi> createState() => _GeriYuklemeOnayiState();
}

class _GeriYuklemeOnayiState extends State<_GeriYuklemeOnayi> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Yedeği geri yükle'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Öğretmen: ${widget.info.ogretmen}\nTarih: ${widget.info.tarih}\n'
          'Öğrenci: ${widget.info.sayilar['Ogrenci'] ?? 0}\n'
          'Yıllık plan: ${widget.info.sayilar['YillikPlan'] ?? 0}\n'
          'Belge: ${widget.info.sayilar['BireyselBelge'] ?? 0}',
        ),
        const SizedBox(height: 16),
        const Text(
          'Mevcut tüm bireysel veriler bu yedekteki verilerle değiştirilecek. '
          'Belgelerim de yedekteki duruma dönecek. Önceki durumun koruma yedeği alınacak. '
          'Onaylamak için GERİ YÜKLE yazın.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          onChanged: (_) => setState(() {}),
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'GERİ YÜKLE',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('İptal'),
      ),
      FilledButton(
        onPressed: _text.text == 'GERİ YÜKLE'
            ? () => Navigator.pop(context, 'GERİ YÜKLE')
            : null,
        child: const Text('Onayla ve Geri Yükle'),
      ),
    ],
  );
}
