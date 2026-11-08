import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import '../services/bireysel_seflik_yillik_plan_service.dart';
import '../services/seflik_aylik_disari_aktar_service.dart';

/// Onaylı yıllık plandan oluşturulan salt okunur aylık çalışma formu.
/// Ayrı kayıt oluşturmaz; yıllık plan tek veri kaynağıdır.
class BireyselSeflikAylikFormScreen extends StatefulWidget {
  const BireyselSeflikAylikFormScreen({
    super.key,
    required this.egitimOgretimYili,
    required this.faaliyetler,
    required this.ogretmenAdi,
    required this.okulAdi,
    this.ilkAy,
    this.taslak = false,
  });

  final String egitimOgretimYili;
  final List<SeflikYillikFaaliyet> faaliyetler;
  final String ogretmenAdi;
  final String okulAdi;
  final DateTime? ilkAy;
  final bool taslak;

  @override
  State<BireyselSeflikAylikFormScreen> createState() =>
      _BireyselSeflikAylikFormScreenState();
}

class _BireyselSeflikAylikFormScreenState
    extends State<BireyselSeflikAylikFormScreen> {
  static const _aylar = <String>[
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  late final List<DateTime> _donemAylar;
  late DateTime _seciliAy;
  bool _aktariliyor = false;

  @override
  void initState() {
    super.initState();
    final ilkYil = int.parse(widget.egitimOgretimYili.substring(0, 4));
    _donemAylar = <DateTime>[
      for (var ay = 9; ay <= 12; ay++) DateTime(ilkYil, ay),
      for (var ay = 1; ay <= 6; ay++) DateTime(ilkYil + 1, ay),
    ];
    final dolu = _donemAylar.where((ay) => widget.faaliyetler.any(
      (f) => f.tarih.year == ay.year && f.tarih.month == ay.month,
    ));
    _seciliAy = widget.ilkAy ?? (dolu.isEmpty ? _donemAylar.first : dolu.first);
  }

  Future<void> _aktar(String uzanti, {required bool belgelerime}) async {
    if (_aktariliyor) return;
    setState(() => _aktariliyor = true);
    try {
      final faaliyetler = SeflikAylikDisariAktarService.ayFaaliyetleri(
        widget.faaliyetler, _seciliAy);
      final bytes = uzanti == 'pdf'
          ? await SeflikAylikDisariAktarService.pdfOlustur(
              ay: _seciliAy, yil: widget.egitimOgretimYili,
              okul: widget.okulAdi, ogretmen: widget.ogretmenAdi,
              faaliyetler: faaliyetler)
          : SeflikAylikDisariAktarService.excelOlustur(
              ay: _seciliAy, yil: widget.egitimOgretimYili,
              okul: widget.okulAdi, ogretmen: widget.ogretmenAdi,
              faaliyetler: faaliyetler);
      if (belgelerime) {
        await SeflikAylikDisariAktarService.belgelerimeKaydet(
          ay: _seciliAy, yil: widget.egitimOgretimYili,
          bytes: bytes, uzanti: uzanti);
        if (mounted) _mesaj('Form Belgelerim arşivine kaydedildi.');
      } else {
        final yol = await SeflikAylikDisariAktarService.dosyayaAktar(
          ay: _seciliAy, uzanti: uzanti, bytes: bytes);
        if (mounted && yol != null) _mesaj('Dosya dışa aktarıldı.');
      }
    } catch (e) {
      if (mounted) _mesaj('Form aktarımı başarısız. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _aktariliyor = false);
    }
  }

  void _mesaj(String mesaj) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj)));

  Widget _altIslem(IconData simge, String baslik, VoidCallback islem) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _aktariliyor ? null : islem,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(simge, size: 21,
              color: _aktariliyor ? Theme.of(context).disabledColor
                : Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final satirlar = widget.faaliyetler.where((f) =>
      f.tarih.year == _seciliAy.year && f.tarih.month == _seciliAy.month,
    ).toList()
      ..sort((a, b) {
        final gun = a.tarih.compareTo(b.tarih);
        return gun != 0 ? gun : a.dersSaatiNo.compareTo(b.dersSaatiNo);
      });
    final haftalar = <String, int>{};
    for (final f in satirlar) {
      final pazartesi = f.tarih.subtract(Duration(days: f.tarih.weekday - 1));
      final anahtar = '${pazartesi.year}-${pazartesi.month}-${pazartesi.day}';
      haftalar.update(anahtar, (s) => s + 1, ifAbsent: () => 1);
    }

    return Scaffold(
      appBar: const ModulUstBar(title: Text('Aylık Şeflik Çalışma Formu')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(children: [
            _altIslem(Icons.picture_as_pdf_outlined, 'PDF indir',
              () => _aktar('pdf', belgelerime: false)),
            _altIslem(Icons.table_chart_outlined, 'Excel indir',
              () => _aktar('xlsx', belgelerime: false)),
            _altIslem(Icons.folder_copy_outlined, 'PDF kaydet',
              () => _aktar('pdf', belgelerime: true)),
            _altIslem(Icons.create_new_folder_outlined, 'Excel kaydet',
              () => _aktar('xlsx', belgelerime: true)),
          ]),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.description_outlined,
                  color: Theme.of(context).colorScheme.primary, size: 30),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Aylık Şeflik Çalışma Formu',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '${_aylar[_seciliAy.month]} ${_seciliAy.year} • ${satirlar.length} ders saati',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 3),
                    const Text('Önizleyin veya PDF / Excel olarak dışa aktarın.',
                      style: TextStyle(fontSize: 11)),
                  ],
                )),
              ]),
            ),
          ),
        ),
        if (widget.taslak)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Taslak ön izleme',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('Bu ekran, seçilen aya ait atölye şefliği '
                          'aylık çalışma formunun ön izlemesidir. '
                          'Yıllık plan henüz onaylanmamıştır.'),
                      ],
                    )),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Ay seçimi',
                    style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    key: ValueKey('${_seciliAy.year}-${_seciliAy.month}'),
                    initialValue: _donemAylar.indexWhere((a) =>
                      a.year == _seciliAy.year && a.month == _seciliAy.month),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                      border: OutlineInputBorder()),
                    items: [
                      for (var i = 0; i < _donemAylar.length; i++)
                        DropdownMenuItem(value: i,
                          child: Text('${_aylar[_donemAylar[i].month]} ${_donemAylar[i].year}')),
                    ],
                    onChanged: (i) {
                      if (i != null) setState(() => _seciliAy = _donemAylar[i]);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_aktariliyor) const LinearProgressIndicator(),
        Expanded(child: ListView(children: [
          Card(margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.okulAdi.isEmpty ? 'Okul adı belirtilmemiş' : widget.okulAdi,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text('${widget.egitimOgretimYili} EĞİTİM ÖĞRETİM YILI',
                textAlign: TextAlign.center),
              const Text('ATÖLYE ŞEFLİĞİ AYLIK ÇALIŞMA FORMU',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
              const Divider(height: 28),
              Text('Atölye şefi: ${widget.ogretmenAdi.isEmpty ? "Belirtilmemiş" : widget.ogretmenAdi}'),
              Text('Dönem: ${_aylar[_seciliAy.month]} ${_seciliAy.year}'),
              Text('Planlanan toplam: ${satirlar.length} ders saati'),
              const Divider(height: 28),
              if (satirlar.isEmpty)
                const Padding(padding: EdgeInsets.all(16),
                  child: Text('Bu ay için yıllık planda faaliyet yok. '
                    'Form boş gösteriliyor; çalışma saati eklenmiyor.')),
              if (satirlar.isNotEmpty) SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Tarih')),
                    DataColumn(label: Text('Gün')),
                    DataColumn(label: Text('Ders')),
                    DataColumn(label: Text('Saat')),
                    DataColumn(label: Text('Çalışma / Faaliyet')),
                  ],
                  rows: [
                    for (final f in satirlar)
                      DataRow(cells: [
                        DataCell(Text('${f.tarih.day.toString().padLeft(2, "0")}.${f.tarih.month.toString().padLeft(2, "0")}.${f.tarih.year}')),
                        DataCell(Text(f.gun)),
                        DataCell(Text('${f.dersSaatiNo}. ders')),
                        const DataCell(Text('1')),
                        DataCell(SizedBox(width: 280, child: Text(f.faaliyet))),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Haftalık saat dağılımı: ${haftalar.values.join(" / ")}'),
              const SizedBox(height: 28),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [
                  Text(widget.ogretmenAdi.isEmpty ? 'Atölye Şefi' : widget.ogretmenAdi,
                    textAlign: TextAlign.center),
                  const Text('Atölye Şefi'),
                  const SizedBox(height: 28),
                  const Text('İmza'),
                ])),
                const Expanded(child: Column(children: [
                  Text('UYGUNDUR', textAlign: TextAlign.center),
                  Text('Okul Müdürü', textAlign: TextAlign.center),
                  SizedBox(height: 28),
                  Text('İmza', textAlign: TextAlign.center),
                ])),
              ]),
              const SizedBox(height: 12),
              Text(widget.taslak
                ? 'Bu form onaylanmamış yıllık plan taslağından oluşturulmuştur. '
                : 'Bu form onaylı yıllık plandan otomatik oluşturulmuştur. '
                    'Gerçekleşen çalışma veya imza onayı anlamına gelmez.',
                style: const TextStyle(fontSize: 12)),
            ],
          ))),
        ])),
      ]),
    );
  }
}
