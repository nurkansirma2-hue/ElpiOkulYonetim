/// Uygulamanın tek veri kaynağı cihazdaki bireysel SQLite veritabanıdır.
enum CalismaModu { bireyselOgretmen }

extension CalismaModuExtension on CalismaModu {
  String get kayitDegeri => 'bireysel';
  String get baslik => 'Bireysel Öğretmen';
  bool get bireyselMi => true;
}

CalismaModu? calismaModuFromString(String? deger) =>
    deger?.trim().toLowerCase() == 'bireysel'
    ? CalismaModu.bireyselOgretmen
    : null;
