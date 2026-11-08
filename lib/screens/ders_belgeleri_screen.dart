import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../services/ders_belgeleri_service.dart';
import '../services/bireysel_belge_service.dart';
import 'belge_on_izleme_screen.dart';
import 'bireysel_dbf_import_screen.dart';
import 'bireysel_gunluk_plan_screen.dart';
import 'bireysel_yillik_planlarim_screen.dart';

class DersBelgeleriScreen extends StatefulWidget {
  const DersBelgeleriScreen({super.key});
  @override
  State<DersBelgeleriScreen> createState() => _DersBelgeleriScreenState();
}

class _DersBelgeleriScreenState extends State<DersBelgeleriScreen> {
  late Future<List<DersBelgeGrubu>> _gruplar;
  bool _aciliyor = false;
  @override
  void initState() {
    super.initState();
    _gruplar = DersBelgeleriService.instance.getir();
  }

  void _yenile() =>
      setState(() => _gruplar = DersBelgeleriService.instance.getir());

  Future<void> _ac(Future<void> Function() f) async {
    if (_aciliyor) return;
    setState(() => _aciliyor = true);
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Belge açılamadı.\nOrijinal hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _aciliyor = false);
        _yenile();
      }
    }
  }

  Future<void> _ekran(Widget screen) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InheritedTheme.captureAll(context, screen),
      ),
    );
  }

  Future<void> _pdf(String arsiv, String id) async {
    final service = BireyselBelgeService.instance;
    final belge = await service.belgeGetir(arsiv, id);
    if (belge.silinmeTarihi != null) {
      throw StateError('Belge çöp kutusunda. Belgelerim’den geri alın.');
    }
    final yol = await service.acmaYolunuGetir(arsivId: arsiv, belgeId: id);
    if (!mounted) return;
    if (!BelgeOnIzlemeScreen.uzantilar.contains(belge.uzanti)) {
      final sonuc = await OpenFile.open(yol);
      if (sonuc.type != ResultType.done) throw StateError(sonuc.message);
      return;
    }
    await _ekran(
      BelgeOnIzlemeScreen(yol: yol, ad: belge.dosyaAdi, uzanti: belge.uzanti),
    );
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: ModulUstBar(
      title: const Text('Ders Belgelerim'),
      actions: [
        IconButton(
          onPressed: _aciliyor ? null : _yenile,
          tooltip: 'Yenile',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<DersBelgeGrubu>>(
      future: _gruplar,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Ders belgeleri okunamadı.\nOrijinal hata: ${snapshot.error}',
              ),
              TextButton(onPressed: _yenile, child: const Text('Tekrar Dene')),
            ],
          );
        }
        final gruplar = snapshot.data!;
        if (gruplar.isEmpty) {
          return const Center(child: Text('Önce ders programınızı yükleyin.'));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Her ders için yıllık plan, günlük planlar ve ders bilgi formu sırasıyla gösterilir. '
                'Diğer belgeleriniz Belgelerim listesindedir.',
              ),
            ),
            if (_aciliyor) const LinearProgressIndicator(),
            for (final g in gruplar)
              Card(
                child: OrtakGenisleyenBolum(
                  key: ValueKey(
                    'ders-belgeleri-${g.dersId}-${g.sinifSeviyesi}',
                  ),
                  title: Text(g.dersAdi),
                  subtitle: Text('${g.sinifSeviyesi}. Sınıf • ${g.egitimYili}'),
                  children: [
                    ListTile(
                      title: const Text('Yıllık Plan'),
                      leading: const Icon(Icons.event_note_outlined),
                      subtitle: Text(
                        g.yillikPlanVar
                            ? 'Kayıtlı yıllık planı görüntüle'
                            : 'Henüz yıllık plan yüklenmedi',
                      ),
                      onTap: _aciliyor || !g.yillikPlanVar
                          ? null
                          : () => _ac(
                              () => bireyselHaftalikKazanimAc(
                                context,
                                ogretmenProfilId: g.profilId,
                                egitimOgretimYili: g.egitimYili,
                                dersId: g.dersId,
                                dersAdi: g.dersAdi,
                                sinifSeviyesi: g.sinifSeviyesi,
                              ),
                            ),
                    ),
                    if (g.yillikBelgeId != null && g.yillikArsivId != null)
                      TextButton(
                        onPressed: _aciliyor
                            ? null
                            : () => _ac(
                                () => _pdf(g.yillikArsivId!, g.yillikBelgeId!),
                              ),
                        child: const Text('Yıllık plan kaynak dosyasını aç'),
                      ),
                    OrtakGenisleyenBolum(
                      title: const Text('Günlük Plan'),
                      leading: const Icon(Icons.today_outlined),
                      subtitle: Text('${g.gunlukPlanlar.length} kayıt'),
                      children: [
                        if (g.gunlukPlanlar.isEmpty)
                          const ListTile(
                            title: Text('Henüz kaydedilmiş günlük plan yok.'),
                          ),
                        for (final plan in g.gunlukPlanlar)
                          ListTile(
                            title: Text(
                              '${plan.tarih.day.toString().padLeft(2, '0')}.'
                              '${plan.tarih.month.toString().padLeft(2, '0')}.${plan.tarih.year} • ${plan.sinifKodu}',
                            ),
                            subtitle: Text(
                              plan.konu.isEmpty
                                  ? 'Konu belirtilmedi'
                                  : plan.konu,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: _aciliyor
                                ? null
                                : () => _ac(
                                    () => _ekran(
                                      BireyselGunlukPlanScreen(
                                        ogretmenProfilId: g.profilId,
                                        egitimOgretimYili: g.egitimYili,
                                        dersId: g.dersId,
                                        dersAdi: g.dersAdi,
                                        sinifSeviyesi: g.sinifSeviyesi,
                                        tarih: plan.tarih,
                                        baslangicSinifKodu: plan.sinifKodu,
                                      ),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                    ListTile(
                      title: const Text('Ders Bilgi Formu'),
                      leading: const Icon(Icons.description_outlined),
                      subtitle: Text(
                        g.dbf == null
                            ? 'Henüz yüklenmedi'
                            : '${g.dbf!.dosyaAdi}\nProgram: ${g.dbf!.programSurumu}',
                      ),
                      onTap: _aciliyor
                          ? null
                          : () => _ac(
                              () => _ekran(
                                BireyselDbfImportScreen(
                                  profilId: g.profilId,
                                  egitimYili: g.egitimYili,
                                  dersId: g.dersId,
                                  dersAdi: g.dersAdi,
                                  sinifSeviyesi: g.sinifSeviyesi,
                                ),
                              ),
                            ),
                    ),
                    if (g.dbf?.belgeId != null && g.dbf?.arsivId != null)
                      TextButton(
                        onPressed: _aciliyor
                            ? null
                            : () => _ac(
                                () => _pdf(g.dbf!.arsivId!, g.dbf!.belgeId!),
                              ),
                        child: const Text('DBF kaynak PDF’sini aç'),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
