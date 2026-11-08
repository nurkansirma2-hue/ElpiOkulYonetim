import 'widgets/ana_sayfa_gorunumu.dart';
import 'widgets/modul_ust_bar.dart';
import 'widgets/ortak_ui.dart';
import 'package:flutter/material.dart';

import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_kurulum_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'package:elpi_okul_yonetim/services/calisma_modu_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _yenilemeSayaci = 0;
  late Future<Widget> _baslangic = _baslangicEkraniniGetir();

  Widget _bireyselKurulumEkrani() {
    return BireyselKurulumScreen(
      onTamamlandi: () async {
        if (!mounted) {
          return;
        }

        setState(() {
          _yenilemeSayaci++;
          _baslangic = _baslangicEkraniniGetir();
        });
      },
    );
  }

  Future<Widget> _baslangicEkraniniGetir() async {
    await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
    final profilBilgileriTam =
        await BireyselProfilService.profilBilgileriTamMi();
    return profilBilgileriTam
        ? const BireyselAnaSayfaScreen()
        : _bireyselKurulumEkrani();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OrtakGorunumTercihi.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Elpi Okul Yönetim',
        theme: OrtakGorunumTercihi.instance.tema.olustur(Brightness.light),
        darkTheme: OrtakGorunumTercihi.instance.tema.olustur(Brightness.dark),
        themeMode: OrtakGorunumTercihi.instance.ekranModu,
        home: FutureBuilder<Widget>(
          key: ValueKey(_yenilemeSayaci),
          future: _baslangic,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const OrtakSayfa(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return OrtakSayfa(
                appBar: const ModulUstBar(
                  title: Text('Başlangıç Hatası'),
                  centerTitle: true,
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Uygulama başlatılırken hata oluştu.\n'
                      'Orijinal hata: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            return snapshot.data ??
                const OrtakSayfa(
                  body: Center(child: Text('Başlangıç ekranı oluşturulamadı.')),
                );
          },
        ),
      ),
    );
  }
}
