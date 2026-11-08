import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'bireysel_ana_sayfa_screen.dart';
import '../database/local_database.dart';
import '../services/bireysel_profil_service.dart';
import '../services/bireysel_yillik_plan_service.dart';
import '../services/yillik_plan_import_tanimi.dart';
import '../models/ortak_import.dart';
import 'ortak_import_screen.dart';
import '../services/ortak_import_service.dart';
import '../services/ders_belgeleri_service.dart';
import '../services/yillik_plan_belge_oneri_service.dart';
import 'yillik_plan_belge_oneri_dialog.dart';

class BireyselYillikPlanImportScreen extends StatefulWidget {
  const BireyselYillikPlanImportScreen({
    super.key,
    this.baslangicDosyasi,
    this.baslangicDersId,
    this.baslangicSinifSeviyesi,
    this.kaydedinceDon = false,
  });

  final ImportDosya? baslangicDosyasi;
  final int? baslangicDersId;
  final int? baslangicSinifSeviyesi;
  final bool kaydedinceDon;

  @override
  State<BireyselYillikPlanImportScreen> createState() =>
      _BireyselYillikPlanImportScreenState();
}

class _DersSecenegi {
  const _DersSecenegi({
    required this.dersId,
    required this.dersAdi,
    required this.sinifSeviyesi,
    required this.planYuklu,
  });

  final int dersId;
  final String dersAdi;
  final int sinifSeviyesi;
  final bool planYuklu;

  String get etiket => '$sinifSeviyesi. Sınıf - $dersAdi';
}

class _BireyselYillikPlanImportScreenState
    extends State<BireyselYillikPlanImportScreen> {
  Map<String, dynamic>? _profil;
  List<_DersSecenegi> _dersSecenekleri = const <_DersSecenegi>[];

  ImportDosya? _seciliDosya;
  _DersSecenegi? _seciliDers;
  String? _sonucMesaji;

  bool _ilkYukleniyor = true;
  bool _baslangicKullanildi = false;
  bool _onIzlemeHazirlaniyor = false;
  bool _kaydedildi = false;
  bool _yuklenenleriGoster = false;

  bool _dersAdiFarkli(
    _DersSecenegi ders,
    BireyselYillikPlanOnIzleme plan,
  ) {
    final secilen = _normalize(ders.dersAdi);
    final bulunan = _normalize(plan.tespitEdilenDersAdi);
    return bulunan.isNotEmpty && secilen != bulunan &&
        !secilen.contains(bulunan) && !bulunan.contains(secilen);
  }

  bool get _dersDisaridanSecili =>
      widget.baslangicDersId != null &&
      widget.baslangicSinifSeviyesi != null;

  @override
  void initState() {
    super.initState();
    _ilkVerileriYukle();
  }

  Future<void> _ilkVerileriYukle() async {
    try {
      final profil = await BireyselProfilService.getir();

      if (profil == null) {
        throw Exception(
          'Bireysel öğretmen profili bulunamadı.',
        );
      }

      final profilId = profil['OgretmenProfilId'] as int?;
      final yil = (profil['EgitimOgretimYili'] ?? '').toString().trim();

      if (profilId == null || profilId <= 0) {
        throw Exception(
          'Geçerli öğretmen profil kimliği bulunamadı.',
        );
      }

      if (yil.isEmpty) {
        throw Exception(
          'Öğretmen profilinde eğitim öğretim yılı bulunamadı.',
        );
      }

      final dersler = await _dersSecenekleriniGetir(
        ogretmenProfilId: profilId,
        egitimOgretimYili: yil,
      );

      _DersSecenegi? baslangicDersi;

      if (_dersDisaridanSecili) {
        for (final ders in dersler) {
          if (ders.dersId == widget.baslangicDersId &&
              ders.sinifSeviyesi == widget.baslangicSinifSeviyesi) {
            baslangicDersi = ders;
            break;
          }
        }

        if (baslangicDersi == null) {
          throw Exception(
            'Yıllık plan kartından seçilen ders, mevcut ders programında '
            'bulunamadı. DersId: ${widget.baslangicDersId}, '
            'Sınıf: ${widget.baslangicSinifSeviyesi}',
          );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _profil = profil;
        _dersSecenekleri = dersler;
        _seciliDers = baslangicDersi;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mesajGoster(
        'Bireysel yıllık plan ekranı hazırlanırken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _ilkYukleniyor = false;
        });
      }
    }
  }

  Future<List<_DersSecenegi>> _dersSecenekleriniGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
  }) async {
    try {
      final db = await LocalDatabase.instance.database;

      final sonuc = await db.rawQuery(
        '''
        SELECT DISTINCT
          d.DersId,
          d.DersAdi,
          s.SinifSeviyesi,
          EXISTS (
            SELECT 1 FROM YillikPlan yp
            WHERE yp.YillikPlanId = (
              SELECT MAX(yp2.YillikPlanId) FROM YillikPlan yp2
              WHERE yp2.OgretmenProfilId = dp.OgretmenProfilId
                AND yp2.EgitimOgretimYili IN (?, ?)
                AND yp2.DersId = d.DersId
                AND yp2.SinifSeviyesi = s.SinifSeviyesi
                AND yp2.Aktif = 1
            )
              AND EXISTS (
                SELECT 1 FROM YillikPlanDetay ypd
                WHERE ypd.YillikPlanId = yp.YillikPlanId AND ypd.Aktif = 1
              )
          ) AS PlanYuklu
        FROM ${widget.kaydedinceDon ? 'DersProgrami' : 'GecerliDersProgrami'} dp
        LEFT JOIN DersProgramiSurum ps ON ps.ProgramSurumId = dp.ProgramSurumId
        INNER JOIN Ders d
          ON d.DersId = dp.DersId
        INNER JOIN SinifSube s
          ON s.SinifSubeId = dp.SinifSubeId
        WHERE dp.OgretmenProfilId = ?
          AND dp.EgitimOgretimYili = ?
          AND dp.Aktif = 1
          AND d.Aktif = 1
          AND s.Aktif = 1
          AND s.SinifSeviyesi > 0
          AND (dp.ProgramSurumId IS NULL OR ps.Aktif = 1)
        ORDER BY s.SinifSeviyesi, d.DersAdi
        ''',
        [
          egitimOgretimYili,
          _egitimOgretimYiliniNormalizeEt(egitimOgretimYili),
          ogretmenProfilId,
          egitimOgretimYili,
        ],
      );

      return sonuc
          .map(
            (satir) => _DersSecenegi(
              dersId: satir['DersId'] as int,
              dersAdi: (satir['DersAdi'] ?? '').toString().trim(),
              sinifSeviyesi: satir['SinifSeviyesi'] as int,
              planYuklu: satir['PlanYuklu'] == 1,
            ),
          )
          .where((e) => e.dersAdi.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      throw Exception(
        'Öğretmenin dersleri SQLite veritabanından okunurken '
        'hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  Future<ImportOnIzleme?> _konuSutunluOnIzleme(
    BuildContext ekranContext,
    ImportDosya dosya,
    String yil,
  ) async {
    int? konuKolonu;
    if (dosya.uzanti == 'xls' || dosya.uzanti == 'xlsx') {
      final tablolar = await OrtakImportService.oku(dosya);
      List<List<String>>? satirlar;
      int baslik = -1;
      for (final tablo in tablolar) {
        for (var i = 0; i < tablo.satirlar.length; i++) {
          final basliklar = tablo.satirlar[i]
              .map((s) => s.toLowerCase().trim())
              .toList();
          if (basliklar.any((s) => s.contains('hafta')) &&
              basliklar.any((s) =>
                  s.contains('konu') ||
                  s.contains('içerik') ||
                  s.contains('icerik') ||
                  s.contains('kazanım') ||
                  s.contains('kazanim') ||
                  s.contains('öğrenme') ||
                  s.contains('ogrenme') ||
                  s.contains('etkinlik'))) {
            satirlar = tablo.satirlar;
            baslik = i;
            break;
          }
        }
        if (satirlar != null) break;
      }
      if (satirlar != null && baslik >= 0) {
        final rows = satirlar;
        final headers = rows[baslik];
        final konuVar = headers.any((s) =>
            s.toLowerCase().trim() == 'konu' ||
            s.toLowerCase().trim() == 'konular');
        if (!konuVar) {
          final etkinlikKolonu = headers.indexWhere((s) =>
              importNormalize(s) == 'etkinlik');
          if (etkinlikKolonu >= 0) {
            konuKolonu = etkinlikKolonu;
          } else {
          final secenekler = <int, String>{};
          for (var c = 0; c < headers.length; c++) {
            final ornekler = <String>[];
            for (var i = baslik + 1;
                i < rows.length && ornekler.length < 2;
                i++) {
              if (c < rows[i].length && rows[i][c].trim().isNotEmpty) {
                ornekler.add(rows[i][c].trim());
              }
            }
            if (ornekler.isNotEmpty) {
              secenekler[c] =
                  '${c + 1}. ${headers[c].trim().isEmpty ? "(Başlıksız)" : headers[c]}'
                  ' — Örnek: ${ornekler.join(" / ")}';
            }
          }
          int? secim;
          konuKolonu = await showDialog<int>(
            context: ekranContext,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('Konu sütununu seçin'),
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Dosyada KONU başlığı bulunamadı. Ana ekranda ve sınıf '
                        'defterinde konu olarak gösterilecek sütunu seçin.',
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: secim,
                        decoration: const InputDecoration(
                          labelText: 'Konu olarak kullanılacak sütun',
                        ),
                        items: [
                          for (final e in secenekler.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => secim = value),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('İptal'),
                  ),
                  FilledButton(
                    onPressed: secim == null
                        ? null
                        : () => Navigator.pop(dialogContext, secim),
                    child: const Text('Önizlemeye geç'),
                  ),
                ],
              ),
            ),
          );
          if (konuKolonu == null) return null;
          }
        }
      }
    }
    final plan = await BireyselYillikPlanService.onIzlemeHazirla(
      dosyaBytes: dosya.bytes,
      dosyaAdi: dosya.ad,
      dosyaUzantisi: dosya.uzanti,
      egitimOgretimYili: yil,
      konuKolonu: konuKolonu,
    );
    return YillikPlanImportTanimi.onIzlemeyeCevir(plan);
  }

  Future<void> _dosyaSecVeOnIzle() async {
    final profil = _profil;
    final seciliDers = _seciliDers;
    if (profil == null || seciliDers == null) {
      _mesajGoster('Önce yıllık planını yükleyeceğiniz dersi seçin.');
      return;
    }

    ImportSecimi? onaylananSecim;
    try {
      setState(() {
        _seciliDosya = null;
        _sonucMesaji = null;
        _kaydedildi = false;
        _onIzlemeHazirlaniyor = true;
      });
      final yil = (profil['EgitimOgretimYili'] ?? '').toString().trim();
      var ilkDosya = _baslangicKullanildi ? null : widget.baslangicDosyasi;
      _baslangicKullanildi = true;
      final profilId = profil['OgretmenProfilId'] as int;
      if (Platform.isAndroid && ilkDosya == null) {
        final service = YillikPlanBelgeOneriService();
        try {
          final adaylar = await service.ara(profilId: profilId,
            ders: seciliDers.dersAdi, seviye: seciliDers.sinifSeviyesi,
            yil: _egitimOgretimYiliniNormalizeEt(yil),
            okul: '${profil['OkulAdi'] ?? ''}')
            .timeout(const Duration(seconds: 15));
          if (!mounted) return;
          if (adaylar.isNotEmpty) {
            final secim = await yillikPlanBelgeOnerisiniGoster(context, adaylar);
            if (!mounted || secim == null) return;
            if (secim >= 0) ilkDosya = adaylar[secim].dosya;
          }
        } catch (_) {
          if (!mounted) return;
          _mesajGoster('Drive önerileri kontrol edilemedi. Dosyayı kendiniz seçebilirsiniz.');
        } finally {
          service.dispose();
        }
      }
      if (!mounted) return;
      final sonuc = await Navigator.of(context).push<ImportOzet>(
        MaterialPageRoute(
          builder: (_) => OrtakImportScreen(
            tanim: YillikPlanImportTanimi.olustur(yil),
            birlesikKaynakSecimi: true,
            driveDosyasiSec: () async {
              final service = YillikPlanBelgeOneriService();
              try {
                return await service.sec(profilId,
                  YillikPlanImportTanimi.olustur(yil).uzantilar);
              } finally {
                service.dispose();
              }
            },
            ozelOnIzlemeyiHazirla: (ctx, file) =>
                _konuSutunluOnIzleme(ctx, file, yil),
            baslangicDosyasi: ilkDosya,
            secimOnayi: (ortakContext, secim, ortakOzet) async {
              onaylananSecim = null;
              final onay = await _secimiOnayla(
                ortakContext, secim, ortakOzet, seciliDers, yil,
              );
              if (onay) onaylananSecim = secim;
              return onay;
            },
            secimiKaydet: (secim) {
              if (!identical(secim, onaylananSecim)) {
                throw StateError('Seçim değişti. Kayıtları yeniden onaylayın.');
              }
              return _secimiKaydet(secim, profil, seciliDers);
            },
          ),
        ),
      );
      if (!mounted || sonuc == null) return;
      setState(() {
        _seciliDosya = onaylananSecim?.dosya;
        _sonucMesaji = sonuc.mesaj;
        _kaydedildi = true;
        _onIzlemeHazirlaniyor = false;
      });
      if (widget.kaydedinceDon) {
        Navigator.of(context).pop();
      } else {
        await _kayitSonrasiSecimSor();
      }
    } catch (e) {
      if (mounted) {
        _mesajGoster(
          'Yıllık plan import işlemi tamamlanamadı.\nOrijinal hata: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _onIzlemeHazirlaniyor = false);
    }
  }

  List<String> _uygunlukHatalariniOlustur({
    required _DersSecenegi seciliDers,
    required BireyselYillikPlanOnIzleme onIzleme,
  }) {
    final hatalar = <String>[];
    final tespitSinif = onIzleme.tespitEdilenSinifSeviyesi;

    if (tespitSinif != null &&
        tespitSinif != seciliDers.sinifSeviyesi) {
      hatalar.add(
        'Seçilen ders ${seciliDers.sinifSeviyesi}. sınıfa ait, '
        'ancak dosyada $tespitSinif. sınıf tespit edildi.',
      );
    }

    return List<String>.unmodifiable(hatalar);
  }

  Future<bool> _secimiOnayla(
    BuildContext ortakContext,
    ImportSecimi secim,
    String ortakOzet,
    _DersSecenegi ders,
    String yil,
  ) async {
    final plan = YillikPlanImportTanimi.secimiUygula(secim);
    final hatalar = [
      ...plan.hatalar,
      ..._uygunlukHatalariniOlustur(seciliDers: ders, onIzleme: plan),
      if (!plan.basarili && plan.hatalar.isEmpty)
        'Seçili planın çalışma takvimi hazırlanamadı.',
    ];
    final adFarkli = _dersAdiFarkli(ders, plan);
    var dersAdiKabulEdildi = false;
    final onay = await showDialog<bool>(
      context: ortakContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          title: const Text('Yıllık Planı Onayla ve Kaydet'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Aktarılacak ders: ${ders.etiket}'),
              Text('Eğitim öğretim yılı: $yil'),
              const SizedBox(height: 12),
              Text('Plan kaydı: ${plan.kayitlar.length}\n'
                  'Çalışma takvimi kaydı: ${plan.calismaTakvimi.length}'),
              Text('Dosyadaki sınıf: ${plan.tespitEdilenSinifSeviyesi == null ? 'Otomatik tespit edilemedi' : '${plan.tespitEdilenSinifSeviyesi}. sınıf'}'),
              Text('Dosyadaki ders: ${plan.tespitEdilenDersAdi.isEmpty ? 'Otomatik tespit edilemedi' : plan.tespitEdilenDersAdi}'),
              const SizedBox(height: 12),
              Text(ortakOzet),
              const SizedBox(height: 12),
              const Text(
                'Aynı hafta ve tarih aralığındaki önceki plan satırları '
                'güncellenir. Seçilmeyen mevcut plan kayıtları korunur.',
              ),
              for (final hata in hatalar)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(hata, style: const TextStyle(color: Colors.red)),
                ),
              if (adFarkli) ...[
                const SizedBox(height: 8),
                const Text('Ders adı farklı; seçtiğiniz derse aktarabilirsiniz.'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: dersAdiKabulEdildi,
                  title: const Text('Ders adını kabul et; seçtiğim derse aktar.'),
                  onChanged: (deger) => dialogSetState(
                    () => dersAdiKabulEdildi = deger == true,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: hatalar.isNotEmpty || (adFarkli && !dersAdiKabulEdildi)
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Onayla ve Kaydet'),
            ),
          ],
        ),
      ),
    );
    return onay == true;
  }

  Future<ImportOzet> _secimiKaydet(
    ImportSecimi secim,
    Map<String, dynamic> profil,
    _DersSecenegi ders,
  ) async {
    final plan = YillikPlanImportTanimi.secimiUygula(secim);
    if (_uygunlukHatalariniOlustur(seciliDers: ders, onIzleme: plan).isNotEmpty) {
      throw StateError('Seçilen dersin sınıfı ile yıllık plan uyuşmuyor.');
    }
    final profilId = profil['OgretmenProfilId'] as int?;
    final yil = (profil['EgitimOgretimYili'] ?? '').toString().trim();
    if (profilId == null || profilId <= 0 || yil.isEmpty) {
      throw StateError('Öğretmen profil bilgileri geçerli değil.');
    }

    final db = await LocalDatabase.instance.database;
    // Kayıt servisi aynı kapsamın ilk planını günceller.
    final mevcutPlan = await db.query(
      'YillikPlan',
      columns: ['YillikPlanId'],
      where: 'DersId = ? AND SinifSeviyesi = ? '
          'AND OgretmenProfilId = ? AND EgitimOgretimYili = ?',
      whereArgs: [ders.dersId, ders.sinifSeviyesi, profilId,
        _egitimOgretimYiliniNormalizeEt(yil)],
      orderBy: 'YillikPlanId ASC',
      limit: 1,
    );
    final mevcutAnahtarlar = <(int?, String)>{};
    if (mevcutPlan.isNotEmpty) {
      final detaylar = await db.query(
        'YillikPlanDetay',
        columns: ['HaftaNo', 'TarihAraligi'],
        where: 'YillikPlanId = ?',
        whereArgs: [mevcutPlan.single['YillikPlanId']],
      );
      mevcutAnahtarlar.addAll(detaylar.map(
        (satir) => (satir['HaftaNo'] as int?,
          (satir['TarihAraligi'] ?? '').toString()),
      ));
    }
    var guncellenen = 0;
    for (final satir in plan.kayitlar) {
      if (!mevcutAnahtarlar.add((satir.haftaNo, satir.tarihAraligi))) {
        guncellenen++;
      }
    }
    final kayitSayisi = await BireyselYillikPlanService.kaydet(
      dersId: ders.dersId,
      sinifSeviyesi: ders.sinifSeviyesi,
      ogretmenProfilId: profilId,
      egitimOgretimYili: yil,
      onIzleme: plan,
      mevcutKayitlariKoru: true,
    );
    var arsivMesaji = 'Kaynak dosya Ders Belgelerim’e eklendi.';
    try {
      await DersBelgeleriService.instance.yillikKaynakKaydet(
        profilId: profilId, egitimYili: yil, dersId: ders.dersId,
        seviye: ders.sinifSeviyesi, dosya: secim.dosya,
      );
    } catch (e) {
      arsivMesaji = 'Plan verileri kaydedildi; kaynak dosya arşivlenemedi. '
          'Orijinal hata: $e';
    }
    return ImportOzet(
      eklenen: kayitSayisi - guncellenen,
      guncellenen: guncellenen,
      atlanan: secim.onIzleme.onceAtlanan +
          secim.onIzleme.kayitlar.length - secim.secimler.length,
      hatali: 0,
      mesaj: 'Yıllık plan ve çalışma takvimi başarıyla kaydedildi.\n'
          '$kayitSayisi plan kaydı: ${kayitSayisi - guncellenen} yeni, '
          '$guncellenen güncellenen.\n'
          '${plan.calismaTakvimi.length} çalışma takvimi kaydı işlendi.\n$arsivMesaji',
    );
  }

  Future<void> _kayitSonrasiSecimSor() async {
    final secim = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Yıllık Plan Kaydedildi'),
          scrollable: true,
          content: Text(
            '${_sonucMesaji ?? 'Yıllık plan ve çalışma takvimi başarıyla kaydedildi.'}\n\n'
            'Şimdi ne yapmak istiyorsunuz?',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop('yeniPlan');
              },
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Başka Yıllık Plan Yükle'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop('anaSayfa');
              },
              icon: const Icon(Icons.home_outlined),
              label: const Text('Ana Sayfaya Git'),
            ),
          ],
        );
      },
    );

    if (!mounted || secim == null) {
      return;
    }

    if (secim == 'yeniPlan') {
      if (_dersDisaridanSecili) {
        Navigator.of(context).pop();
        return;
      }

      setState(() {
        _seciliDosya = null;
        _seciliDers = null;
        _sonucMesaji = null;
        _kaydedildi = false;
        _ilkYukleniyor = true;
      });

      await _ilkVerileriYukle();
      if (!mounted) return;

      _mesajGoster(
        'Yeni yıllık plan için önce dersi seçin.',
      );
      return;
    }

    if (secim == 'anaSayfa') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const BireyselAnaSayfaScreen(),
        ),
        (route) => false,
      );
    }
  }

  void _dersDegisti(_DersSecenegi? ders) {
    setState(() {
      _seciliDers = ders;
      _seciliDosya = null;
      _sonucMesaji = null;
      _kaydedildi = false;
    });
  }

  void _yuklenenleriGosterDegisti(bool goster) {
    setState(() {
      _yuklenenleriGoster = goster;
    });
    if (!goster && _seciliDers?.planYuklu == true) {
      _dersDegisti(null);
    }
  }

  void _mesajGoster(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mesaj),
      ),
    );
  }


  String _egitimOgretimYiliniNormalizeEt(String deger) {
    final temiz = deger.trim();
    final eslesme = RegExp(r'(\d{4})\s*[-/]\s*(\d{4})').firstMatch(temiz);
    if (eslesme != null) {
      return '${eslesme.group(1)}-${eslesme.group(2)}';
    }
    final baslangic = int.tryParse(temiz);
    return baslangic == null ? temiz : '$baslangic-${baslangic + 1}';
  }

  String _normalize(String deger) {
    var sonuc = deger.trim();

    const buyukDonusumler = <String, String>{
      'Ç': 'c',
      'Ğ': 'g',
      'İ': 'i',
      'I': 'i',
      'Ö': 'o',
      'Ş': 's',
      'Ü': 'u',
    };

    buyukDonusumler.forEach((eski, yeni) {
      sonuc = sonuc.replaceAll(eski, yeni);
    });

    sonuc = sonuc.toLowerCase();

    const kucukDonusumler = <String, String>{
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
      'â': 'a',
      'î': 'i',
      'û': 'u',
    };

    kucukDonusumler.forEach((eski, yeni) {
      sonuc = sonuc.replaceAll(eski, yeni);
    });

    return sonuc
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return OrtakSayfa(
      appBar: const ModulUstBar(
        title: Text('Bireysel Yıllık Plan Import'),
        centerTitle: true,
      ),
      body: _ilkYukleniyor
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.kaydedinceDon)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('Günlük plan için bu dersin yıllık planı eksik. '
                            'Yükleyip onayladıktan sonra belge kontrolüne devam edilecek.'),
                        ),
                      _akisKarti(),
                      const SizedBox(height: 16),
                      _profilKarti(),
                      const SizedBox(height: 16),
                      if (_dersDisaridanSecili)
                        _sabitDersKarti()
                      else
                        _dersSecimKarti(),
                      const SizedBox(height: 16),
                      _dosyaSecimKarti(),
                      if (_onIzlemeHazirlaniyor) ...[
                        const SizedBox(height: 16),
                        const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ],
                      if (_kaydedildi) ...[
                        const SizedBox(height: 16),
                        _basariKarti(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _akisKarti() {
    final adimlar = _dersDisaridanSecili
        ? const <String>[
            '1. Dosya Seç',
            '2. Ön İzleme',
            '3. Onayla ve Kaydet',
          ]
        : const <String>[
            '1. Ders Seç',
            '2. Dosya Seç',
            '3. Ön İzleme',
            '4. Onayla ve Kaydet',
          ];

    final akistakiWidgetlar = <Widget>[];

    for (int i = 0; i < adimlar.length; i++) {
      if (i > 0) {
        akistakiWidgetlar.add(
          const Icon(Icons.arrow_forward, size: 18),
        );
      }
      akistakiWidgetlar.add(Chip(label: Text(adimlar[i])));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Yıllık Plan Import Akışı',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: akistakiWidgetlar,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profilKarti() {
    final profil = _profil;

    if (profil == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Bireysel öğretmen profili bulunamadı.',
          ),
        ),
      );
    }

    final adSoyad = (profil['AdSoyad'] ?? '').toString().trim();
    final yil =
        (profil['EgitimOgretimYili'] ?? '').toString().trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              child: Icon(Icons.person_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adSoyad,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Eğitim Öğretim Yılı: $yil',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sabitDersKarti() {
    final ders = _seciliDers;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.indigo.withValues(alpha: 0.10),
              child: const Icon(
                Icons.menu_book_outlined,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seçili Ders',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ders?.etiket ?? 'Ders bilgisi yüklenemedi',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ders, Yıllık Planlarım ekranından seçildi. '
                    'Tekrar ders seçmenize gerek yok.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dersSecimKarti() {
    final gorunenDersler = _dersSecenekleri
        .where((ders) => _yuklenenleriGoster || !ders.planYuklu)
        .toList(growable: false);
    final islemSuruyor = _onIzlemeHazirlaniyor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1. Ders Seç',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Yıllık planını yükleyeceğiniz dersi, daha önce '
              'kaydettiğiniz ders programındaki derslerden seçin.',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('yillik-plan-yuklenenleri-goster'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Yüklenenleri de göster'),
              value: _yuklenenleriGoster,
              onChanged: islemSuruyor || _dersSecenekleri.isEmpty
                  ? null
                  : _yuklenenleriGosterDegisti,
            ),
            const SizedBox(height: 8),
            if (_dersSecenekleri.isEmpty)
              const Text(
                'Ders programınızda yıllık plan yüklenecek ders bulunamadı. '
                'Önce ders programınızı yükleyin.',
              )
            else if (gorunenDersler.isEmpty)
              const Text(
                'Ders programınızdaki tüm dersler için yıllık plan yüklendi. '
                'Güncellemek için "Yüklenenleri de göster" seçeneğini açın.',
              )
            else
              DropdownButtonFormField<_DersSecenegi>(
                key: ValueKey(_seciliDers),
                initialValue: _seciliDers,
                isExpanded: true,
                isDense: false,
                itemHeight: null,
                decoration: const InputDecoration(
                  labelText: 'Ders / Sınıf',
                  border: OutlineInputBorder(),
                ),
                items: gorunenDersler
                    .map(
                      (ders) => DropdownMenuItem<_DersSecenegi>(
                        value: ders,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              ders.etiket,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (ders.planYuklu)
                              Text(
                                '✓ Yüklendi',
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: islemSuruyor ? null : _dersDegisti,
              ),
          ],
        ),
      ),
    );
  }

  Widget _dosyaSecimKarti() {
    final dosya = _seciliDosya;
    final dersSecildi = _seciliDers != null;
    final adimNo = _dersDisaridanSecili ? 1 : 2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$adimNo. Dosya Seç',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              dersSecildi
                  ? 'Seçilen ders: ${_seciliDers!.etiket}'
                  : 'Önce 1. adımda dersi seçin.',
              style: TextStyle(
                fontWeight: dersSecildi ? FontWeight.w600 : FontWeight.normal,
                color: dersSecildi ? null : Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Desteklenen dosyalar: XLS, XLSX, CSV, DOC ve DOCX',
            ),
            if (dosya != null) ...[
              const SizedBox(height: 10),
              Text(
                'Seçilen dosya: ${dosya.ad}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: !dersSecildi || _onIzlemeHazirlaniyor
                  ? null
                  : _dosyaSecVeOnIzle,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(
                dosya == null
                    ? 'Seçilen Derse Ait Yıllık Planı Seç'
                    : 'Başka Dosya Seç',
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _basariKarti() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _sonucMesaji ?? 'Yıllık plan ve çalışma takvimi başarıyla kaydedildi.',
                style: TextStyle(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
