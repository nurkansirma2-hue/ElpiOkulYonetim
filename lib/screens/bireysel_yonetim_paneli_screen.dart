import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

import '../services/bireysel_profil_service.dart';
import 'bireysel_yedekleme_screen.dart';
import 'bireysel_sifirlama_screen.dart';

class BireyselYonetimPaneliScreen extends StatefulWidget {
  const BireyselYonetimPaneliScreen({super.key, required this.onSifirlandi});

  final VoidCallback onSifirlandi;

  @override
  State<BireyselYonetimPaneliScreen> createState() =>
      _BireyselYonetimPaneliScreenState();
}

class _BireyselYonetimPaneliScreenState
    extends State<BireyselYonetimPaneliScreen> {
  bool _islemSuruyor = false;
  bool _sifirlandi = false;
  String? _hata;

  Future<void> _geriYuklendi() async {
    final tamam = await BireyselProfilService.profilBilgileriTamMi();
    if (!mounted) return;
    if (tamam) {
      Navigator.of(context).pop();
    } else {
      widget.onSifirlandi();
    }
  }

  Future<void> _sifirla() async {
    if (_islemSuruyor || _sifirlandi) return;
    setState(() {
      _islemSuruyor = true;
      _hata = null;
    });

    try {
      final sonuc = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BireyselSifirlamaScreen(
            yedekle: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      BireyselYedeklemeScreen(onGeriYuklendi: _geriYuklendi),
                ),
              );
            },
          ),
        ),
      );
      if (!mounted || sonuc != true) return;
      final profilTam = await BireyselProfilService.profilBilgileriTamMi();
      if (!mounted) return;
      if (!profilTam) {
        setState(() => _sifirlandi = true);
        widget.onSifirlandi();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = _sifirlandi
            ? 'Veriler sıfırlandı ancak kurulum ekranı açılamadı.\n'
                  'Orijinal hata: $e'
            : 'Sıfırlama tamamlanamadı.\nOrijinal hata: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _islemSuruyor = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_islemSuruyor && !_sifirlandi,
      child: OrtakSayfa(
        appBar: ModulUstBar(
          title: const Text('Yönetim ve Bakım'),
          automaticallyImplyLeading: !_islemSuruyor && !_sifirlandi,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bireysel Öğretmen',
                  style: TextStyle(fontSize: 14, color: Colors.indigo),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.backup_outlined,
                      color: Colors.indigo,
                    ),
                    title: const Text('Yedekleme ve Geri Yükleme'),
                    subtitle: const Text(
                      'Tüm bireysel veriler ve belgeler • Cihaz / Google Drive',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _islemSuruyor || _sifirlandi
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BireyselYedeklemeScreen(
                                  onGeriYuklendi: _geriYuklendi,
                                ),
                              ),
                            );
                          },
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.delete_forever_outlined,
                          color: Colors.red,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Bireysel Verileri Sıfırla',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Sıfırlamak istediğiniz modülleri bir sonraki ekranda '
                          'seçebilirsiniz. Tümünü seç veya yalnız gerekli modülleri '
                          'işaretle seçenekleriyle devam edin.',
                          style: TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Silinecek modüller ve bağlı kayıtlar son onaydan önce '
                          'gösterilir. Belgelerim arşivi ve kaynak dosyalar korunur.',
                          style: TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        if (_hata != null) ...[
                          Text(
                            _hata!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_sifirlandi)
                          FilledButton(
                            onPressed: _islemSuruyor
                                ? null
                                : widget.onSifirlandi,
                            child: const Text('Kuruluma Devam Et'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _islemSuruyor ? null : _sifirla,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                            ),
                            icon: _islemSuruyor
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_forever_outlined),
                            label: Text(
                              _islemSuruyor
                                  ? 'İşlem sürüyor...'
                                  : 'Bireysel Verileri Sıfırla',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
