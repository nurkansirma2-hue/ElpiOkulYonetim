import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import '../services/bireysel_bakim_service.dart';

class BireyselSifirlamaScreen extends StatefulWidget {
  const BireyselSifirlamaScreen({
    super.key,
    this.service,
    required this.yedekle,
  });
  final BireyselBakimService? service;
  final Future<void> Function() yedekle;
  @override
  State<BireyselSifirlamaScreen> createState() => _BireyselSifirlamaState();
}

class _BireyselSifirlamaState extends State<BireyselSifirlamaScreen> {
  late final _service = widget.service ?? BireyselBakimService.instance;
  SifirlamaEnvanteri? _envanter;
  final _secim = <String>{};
  bool _mesgul = false, _siliniyor = false;
  String? _hata;
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _mesgul = true);
    try {
      final e = await _service.sifirlamaEnvanteri();
      if (mounted) {
        setState(() {
          _envanter = e;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Modüller okunamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _siliniyor = false;
        });
      }
    }
  }

  Future<void> _sifirla(SifirlamaPlani plan) async {
    if (_mesgul || plan.secilen.isEmpty) return;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final yedek = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('Sıfırlamadan önce yedekle'),
          content: Text(
            '${plan.kapsam.length} modüldeki ${plan.kayitSayisi} veritabanı kaydı tüm eğitim yılları için silinecek. Önceden alınmış yedek olmadan geri alınamaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Yedek almadan devam et'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Önce Yedekle'),
            ),
          ],
        ),
      );
      if (!mounted || yedek == null) return;
      if (yedek) {
        await widget.yedekle();
        await _yukle();
        return;
      }
      final onay = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SifirlamaOnayi(plan: plan),
      );
      if (!mounted || onay != true) return;
      setState(() => _siliniyor = true);
      await _service.seciliModulleriSifirla(plan, onayMetni: 'SIFIRLA');
      if (!mounted) return;
      setState(() => _siliniyor = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Sıfırlama tamamlandı'),
          content: Text(
            '${plan.kapsam.length} modül sıfırlandı.${plan.kapsam.contains('profil') ? ' Öğretmen kurulumuna dönülecek.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _mesgul = false);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Sıfırlama tamamlanamadı. Orijinal hata: $e');
      }
      if (mounted) await _yukle();
    } finally {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _siliniyor = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _envanter, moduller = BireyselSifirlama.moduller;
    final plan = e?.planla(_secim);
    return PopScope(
      canPop: !_mesgul,
      child: OrtakSayfa(
        appBar: ModulUstBar(
          title: const Text('Sıfırlanacak modüller'),
          automaticallyImplyLeading: !_mesgul,
        ),
        body: SafeArea(
          child: e == null
              ? Center(
                  child: _mesgul
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_hata ?? ''),
                            TextButton(
                              onPressed: _yukle,
                              child: const Text('Yeniden dene'),
                            ),
                          ],
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Tüm eğitim yılları için sıfırlanacak modülleri seçin. Seçimin gerektirdiği bağlı modüller de işaretlenir; bunları son onayda kontrol edebilirsiniz.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _mesgul
                              ? null
                              : () => setState(
                                  () =>
                                      _secim.addAll(moduller.map((m) => m.id)),
                                ),
                          icon: const Icon(Icons.select_all),
                          label: const Text('Tümünü seç'),
                        ),
                        TextButton(
                          onPressed: _mesgul || _secim.isEmpty
                              ? null
                              : () => setState(_secim.clear),
                          child: const Text('Seçimi temizle'),
                        ),
                      ],
                    ),
                    for (final m in moduller)
                      Card(
                        child: CheckboxListTile(
                          key: ValueKey('sifirla-modul-${m.id}'),
                          isThreeLine: false,
                          title: Text(m.ad),
                          subtitle: Text(
                            '${m.aciklama}\n${e.kayitSayisi(m)} veritabanı kaydı${plan!.nedenler.containsKey(m.id) ? '\n${plan.nedenler[m.id]} seçimi nedeniyle dahil edildi.' : ''}',
                          ),
                          value: plan.kapsam.contains(m.id),
                          onChanged:
                              _mesgul ||
                                  (plan.kapsam.contains(m.id) &&
                                      !_secim.contains(m.id))
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _secim.add(m.id);
                                  } else {
                                    _secim.remove(m.id);
                                  }
                                }),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '${plan!.kapsam.length} modül • ${plan.kayitSayisi} veritabanı kaydı',
                    ),
                    const Text(
                      'Belgelerim, klasörler, import geçmişi, yedekler ve cihazdaki kaynak dosyalar korunur. Google’daki form ve yanıtlar bu işlemle silinmez.',
                    ),
                    if (_hata != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _hata!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('secili-modulleri-sifirla'),
                      onPressed: _mesgul || plan.secilen.isEmpty
                          ? null
                          : () => _sifirla(plan),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: _siliniyor
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_forever_outlined),
                      label: Text(
                        _siliniyor
                            ? 'İşlem sürüyor…'
                            : 'Seçilen modülleri sıfırla',
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SifirlamaOnayi extends StatefulWidget {
  const _SifirlamaOnayi({required this.plan});
  final SifirlamaPlani plan;
  @override
  State<_SifirlamaOnayi> createState() => _SifirlamaOnayiState();
}

class _SifirlamaOnayiState extends State<_SifirlamaOnayi> {
  final _onay = TextEditingController();
  @override
  void dispose() {
    _onay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Seçilen modüller silinsin mi?'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final m in BireyselSifirlama.moduller.where(
          (m) => widget.plan.kapsam.contains(m.id),
        ))
          Text('• ${m.ad} (${widget.plan.envanter.kayitSayisi(m)} kayıt)'),
        const SizedBox(height: 12),
        const Text(
          'Bu modüllerin tüm eğitim yıllarındaki kayıtları kalıcı olarak silinecek. Onaylamak için SIFIRLA yazın.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('sifirlama-onay-metni'),
          controller: _onay,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Onay metni',
            hintText: 'SIFIRLA',
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
        onPressed: _onay.text == 'SIFIRLA'
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('Onayla ve Sıfırla'),
      ),
    ],
  );
}
