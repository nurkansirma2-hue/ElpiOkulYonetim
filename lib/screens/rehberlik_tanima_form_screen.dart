import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/bireysel_rehberlik_service.dart';
import '../models/ogrenci_bilgi_formu.dart';
import '../database/veli_iliskisi.dart';
import '../models/ortak_import.dart';
import '../services/rehberlik_form_import.dart';
import 'rehberlik_form_import_screen.dart';

class RehberlikTanimaFormScreen extends StatefulWidget {
  const RehberlikTanimaFormScreen({
    super.key,
    required this.service,
    required this.baglam,
    required this.atamaId,
    required this.ogrenci,
    required this.saltOkunur,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final int atamaId;
  final Map<String, Object?> ogrenci;
  final bool saltOkunur;
  @override
  State<RehberlikTanimaFormScreen> createState() => _TanimaState();
}

class _TanimaState extends State<RehberlikTanimaFormScreen>
    with WidgetsBindingObserver {
  final _ekSoru = TextEditingController();
  Map<String, TextEditingController> _cevaplar = {};
  List<Map<String, Object?>> _gecmis = [];
  String? _hata;
  bool _acik = false, _islem = false;
  int _istek = 0;
  Map<String, Object?> _veliBilgileri = {};
  String? _veliTuru;
  final _veliTaslaklari = <String, Map<String, String>>{};
  static const _veliAlanlari = [
    'Veli adı soyadı',
    'Veli telefon numarası',
    'Veli eğitim durumu',
    'Veli mesleği',
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ac();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ekSoru.dispose();
    for (final c in _cevaplar.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _ac();
    } else if (mounted) {
      _istek++;
      setState(() {
        _acik = false;
        _gecmis = [];
      });
    }
  }

  Future<void> _ac() async {
    final istek = ++_istek;
    setState(() {
      _islem = true;
      _hata = null;
    });
    try {
      final rows = await widget.service.formlar(
        widget.baglam,
        widget.atamaId,
        widget.ogrenci['OgrenciId'] as int,
        hassasOnay: true,
      );
      final veliBilgileri = await widget.service.formVeliBilgileri(
        widget.baglam,
        widget.atamaId,
        widget.ogrenci['OgrenciId'] as int,
        hassasOnay: true,
      );
      final sorular = await widget.service.formSorulari(
        widget.baglam,
        widget.atamaId,
      );
      if (!mounted || istek != _istek) return;
      // Taslak yalnız bu ekranın belleğinde kalır; kapsam
      // kontrolünden sonra gösterilir. Odak kaybında cevaplar silinmez.
      _veliBilgileri = veliBilgileri;
      if (_cevaplar.isEmpty) _doldur(rows.isEmpty ? null : rows.first);
      if (!widget.saltOkunur) {
        for (final s in sorular.where((s) => !mebTanimaSorulari.contains(s))) {
          _cevaplar.putIfAbsent(s, () => TextEditingController());
        }
      }
      setState(() {
        _gecmis = rows;
        _acik = true;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = 'Form okunamadı.\nOrijinal hata: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  void _doldur(Map<String, Object?>? row) {
    for (final c in _cevaplar.values) {
      c.dispose();
    }
    final sorular = row == null
        ? ogrenciBilgiFormuSorulari
        : List<String>.from(jsonDecode(row['Sorular'] as String) as List);
    final cevaplar = row == null
        ? <String, dynamic>{}
        : jsonDecode(row['Cevaplar'] as String) as Map;
    _cevaplar = {
      for (final s in {
        ...sorular,
        if (!widget.saltOkunur) ...ogrenciBilgiFormuSorulari,
      })
        s: TextEditingController(text: cevaplar[s]?.toString() ?? ''),
    };
    if (row == null) {
      final defaults = <String, String>{
        'Adınız Soyadınız':
            '${widget.ogrenci['Ad']} ${widget.ogrenci['Soyad']}',
        'Okul numaranız': '${widget.ogrenci['OkulNo']}',
        'Okulunuz': widget.baglam.okulAdi,
        'Cinsiyetiniz': '${widget.ogrenci['Cinsiyet'] ?? ''}',
        'Anne adı soyadı': '${_veliBilgileri['AnneAdi'] ?? ''}',
        'Baba adı soyadı': '${_veliBilgileri['BabaAdi'] ?? ''}',
      };
      for (final e in defaults.entries) {
        _cevaplar[e.key]?.text = e.value;
      }
    }
    _veliTaslaklari.clear();
    _veliTuru = _veliTurunuOku(_cevaplar['Veli yakınlığı']?.text ?? '');
    if (row == null) {
      _veliTuru = VeliIliskisi.tur(_veliBilgileri);
      _veliDoldur(_veliTuru!);
    }
  }

  String? _veliTurunuOku(String deger) => switch (deger.trim().toLowerCase()) {
    'anne' || 'annesi' => 'Anne',
    'baba' || 'babası' => 'Baba',
    'diger' || 'diğer' || 'diğer veli' => 'Diger',
    _ => null,
  };

  void _veliDoldur(String tur) {
    final taslak = _veliTaslaklari[tur];
    final ebeveyn = tur == 'Anne' || tur == 'Baba';
    final ad = ebeveyn
        ? (_cevaplar['$tur adı soyadı']?.text.trim().isNotEmpty == true
              ? _cevaplar['$tur adı soyadı']!.text
              : '${_veliBilgileri['${tur}Adi'] ?? ''}')
        : '${_veliBilgileri['VeliAdi'] ?? ''}';
    final degerler =
        taslak ??
        {
          'Veli adı soyadı': ad,
          'Veli telefon numarası':
              '${_veliBilgileri[ebeveyn ? '${tur}Telefon' : 'VeliTelefonu'] ?? ''}',
          'Veli eğitim durumu': ebeveyn
              ? _cevaplar['$tur eğitim durumu']?.text ?? ''
              : '',
          'Veli mesleği': ebeveyn ? _cevaplar['$tur mesleği']?.text ?? '' : '',
        };
    for (final e in degerler.entries) {
      _cevaplar[e.key]?.text = e.value;
    }
    _cevaplar['Veli yakınlığı']?.text = VeliIliskisi.turler[tur]!;
  }

  void _veliSec(String? tur) {
    if (tur == null || tur == _veliTuru || _islem || widget.saltOkunur) return;
    setState(() {
      if (_veliTuru != null) {
        _veliTaslaklari[_veliTuru!] = {
          for (final alan in _veliAlanlari) alan: _cevaplar[alan]?.text ?? '',
        };
      }
      _veliTuru = tur;
      _veliDoldur(tur);
    });
  }

  Future<void> _resimdenAktar() async {
    if (_islem || !_acik || widget.saltOkunur) return;
    try {
      final selection = await Navigator.push<ImportSecimi>(
        context,
        MaterialPageRoute(
          builder: (_) => RehberlikFormImportScreen(
            okulNo: '${widget.ogrenci['OkulNo']}',
            adSoyad: '${widget.ogrenci['Ad']} ${widget.ogrenci['Soyad']}',
          ),
        ),
      );
      if (!mounted || selection == null) return;
      // Dosya seçici arka plana geçirir; dönüşte hassas erişimi yeniden aç.
      if (!_acik) await _ac();
      if (!mounted || !_acik) return;
      final request = _istek;
      await widget.service.formlar(
        widget.baglam,
        widget.atamaId,
        widget.ogrenci['OgrenciId'] as int,
        hassasOnay: true,
      );
      if (!mounted || !_acik || request != _istek) return;
      final validator = RehberlikFormImport(
        okulNo: '${widget.ogrenci['OkulNo']}',
        adSoyad: '${widget.ogrenci['Ad']} ${widget.ogrenci['Soyad']}',
      );
      final checked = await validator.hazirla([
        for (final r in selection.onIzleme.kayitlar)
          ImportKaynakSatiri(r.id, r.konum, r.degerler),
      ]);
      if (checked.engeller.isNotEmpty) {
        throw StateError(checked.engeller.join('\n'));
      }
      if (!mounted || !_acik || request != _istek) return;
      final rows = checked.kayitlar
          .where((r) => selection.secimler.contains(r.id) && r.aktarilabilir)
          .toList();
      final overwritten = rows
          .where(
            (r) =>
                (_cevaplar[r.degerler['alan']]?.text ?? '').isNotEmpty &&
                _cevaplar[r.degerler['alan']]!.text != r.degerler['deger'],
          )
          .length;
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Form taslağına uygula'),
          content: Text(
            '${rows.length} alan taslağa alınacak. Dolu değeri değişecek alan: $overwritten. Boş ve seçilmeyen alanlar korunur. Henüz kalıcı kayıt yapılmaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Taslağa Uygula'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted || !_acik || request != _istek) return;
      setState(() {
        for (final r in rows) {
          _cevaplar
              .putIfAbsent(r.degerler['alan']!, () => TextEditingController())
              .text = r
              .degerler['deger']!;
        }
        _veliTaslaklari.clear();
        _veliTuru = _veliTurunuOku(_cevaplar['Veli yakınlığı']?.text ?? '');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Değerler taslağa alındı. Kontrol edip Yeni sürüm olarak kaydet düğmesine basın.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Resim aktarılamadı.\nOrijinal hata: $e');
      }
    }
  }

  Future<void> _kaydet() async {
    if (_islem || !_acik) return;
    setState(() {
      _islem = true;
      _hata = null;
    });
    try {
      await widget.service.formKaydet(
        widget.baglam,
        widget.atamaId,
        widget.ogrenci['OgrenciId'] as int,
        _cevaplar.keys.toList(),
        _cevaplar.map((k, v) => MapEntry(k, v.text)),
        hassasOnay: true,
      );
      final rows = await widget.service.formlar(
        widget.baglam,
        widget.atamaId,
        widget.ogrenci['OgrenciId'] as int,
        hassasOnay: true,
      );
      if (mounted && _acik) setState(() => _gecmis = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Form kaydedilemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _soruEkle() async {
    final soru = _ekSoru.text.trim();
    if (_islem || soru.isEmpty || _cevaplar.containsKey(soru)) return;
    setState(() => _islem = true);
    try {
      final sorular = await widget.service.formSorulari(
        widget.baglam,
        widget.atamaId,
      );
      await widget.service.formSorulariniKaydet(
        widget.baglam,
        widget.atamaId,
        {...sorular, soru}.toList(),
      );
      if (mounted && _acik) {
        setState(() {
          _cevaplar[soru] = TextEditingController();
          _ekSoru.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Soru eklenemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_islem,
    child: OrtakSayfa(
      appBar: ModulUstBar(
        title: const Text('Öğrenci Bilgi Formu'),
        actions: [
          if (_acik && !widget.saltOkunur)
            IconButton(
              tooltip: 'Yeni sürüm olarak kaydet',
              onPressed: _islem ? null : _kaydet,
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.ogrenci['OkulNo']} • ${widget.ogrenci['Ad']} ${widget.ogrenci['Soyad']}',
          ),
          Text('Veli: ${widget.ogrenci['VeliAdi'] ?? 'Kayıtlı değil'}'),
          Text('Telefon: ${widget.ogrenci['VeliTelefonu'] ?? 'Kayıtlı değil'}'),
          const Text(
            'Rehberlik servisinin Öğrenci Bilgi Formu: öğrenci, veli, anne–baba ve aile bilgileri. Ana öğrenci kaydı değiştirilmez.',
          ),
          if (_hata != null) Text(_hata!),
          if (_islem && !_acik)
            const Center(child: CircularProgressIndicator()),
          if (!_acik && !_islem)
            FilledButton(
              onPressed: _islem ? null : _ac,
              child: const Text('Yeniden dene'),
            ),
          if (_acik) ...[
            if (!widget.saltOkunur)
              OutlinedButton.icon(
                onPressed: _islem ? null : _resimdenAktar,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Resimden içe aktar'),
              ),
            for (final bolum in ogrenciBilgiFormuBolumleri.entries)
              if (bolum.value.any(_cevaplar.containsKey)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    bolum.key,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (bolum.key == 'Veli Bilgisi' &&
                    _cevaplar.containsKey('Veli yakınlığı'))
                  _veliSecimi(),
                for (final soru in bolum.value.where(
                  (s) => s != 'Veli yakınlığı',
                ))
                  if (_cevaplar.containsKey(soru)) _alan(soru),
              ],
            if (_cevaplar.keys.any(
              (s) => !ogrenciBilgiFormuSorulari.contains(s),
            )) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Önceki form alanları / ek sorular'),
              ),
              for (final soru in _cevaplar.keys.where(
                (s) => !ogrenciBilgiFormuSorulari.contains(s),
              ))
                _alan(soru),
            ],
            if (!widget.saltOkunur) ...[
              TextField(
                controller: _ekSoru,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Ek soru'),
              ),
              TextButton(
                onPressed: _islem ? null : _soruEkle,
                child: const Text('Soruyu sınıf formuna ekle'),
              ),
              FilledButton(
                onPressed: _islem ? null : _kaydet,
                child: const Text('Yeni sürüm olarak kaydet'),
              ),
            ],
            const Text('Form geçmişi (kayıtlar değiştirilmez)'),
            for (final row in _gecmis)
              ListTile(
                title: Text('Sürüm ${row['Id']} • ${row['OlusturmaTarihi']}'),
                onTap: _islem ? null : () => setState(() => _doldur(row)),
              ),
          ],
        ],
      ),
    ),
  );

  Widget _veliSecimi() {
    final eski = _cevaplar['Veli yakınlığı']?.text.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey('form-veli-turu-${_veliTuru ?? eski}'),
        initialValue: _veliTuru ?? (eski.isEmpty ? null : 'Eski'),
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Veli bilgisi',
          border: OutlineInputBorder(),
        ),
        items: [
          if (_veliTuru == null && eski.isNotEmpty)
            DropdownMenuItem(value: 'Eski', child: Text(eski)),
          for (final e in VeliIliskisi.turler.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: widget.saltOkunur || _islem
            ? null
            : (t) {
                if (t != 'Eski') _veliSec(t);
              },
      ),
    );
  }

  Widget _alan(String soru) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: ValueKey(soru),
      controller: _cevaplar[soru],
      readOnly: widget.saltOkunur || _islem,
      maxLines: null,
      maxLength: 5000,
      decoration: InputDecoration(
        label: Text(soru),
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
