# Veritabanı standardı

Bireysel mod SQLite, kurumsal mod SQL Server kullanır. USE/GO yalnız SQL Server betikleri içindir. Mod verileri karıştırılmaz; mod değişimi veri silmez. Şema veya veri değişikliğinde mevcut kayıtlar ve yedek uyumu doğrulanır.

## 25. SQL STANDARDI

SQL Server 2025 ve SSMS 2022 uyumluluğu korunur.

Hazırlanan SQL betikleri şu satırlarla başlar:

```sql
USE [OkulYonetimMini]
GO
```

SQL hazırlamak ile veritabanında çalıştırmak ayrı işlemlerdir.

Açık onay olmadan DROP, TRUNCATE, toplu DELETE, veri kaybı doğuran migration veya geri dönüşü zor şema değişikliği çalıştırılmaz.

## ZORUNLU VERİTABANI SÜREKLİLİĞİ VE YEDEK KORUMA KURALI

**Öncelik: Kritik — Veri kaybını önleme.** Temel ilke: Mevcut kayıtlar korunur; uygulama güncelleme ve geliştirmelerinden sonra kaldığı yerden devam eder.

1. **Otomatik sıfırlama yasaktır.** Uygulama güncellemesi, APK kurulumu, kod veya modül değişikliği, GitHub/Codex senkronizasyonu, yedekleme veya şema değişimi mevcut veritabanını otomatik silmez, boşaltmaz, yeniden oluşturup eskisinin yerine koymaz. Bu işlemler sırasında mevcut kullanıcı verisi korunur.
2. **Bireysel ve kurumsal veriler ayrıdır.** Bireysel Öğretmen modunun SQLite verileri ile kurumsal SQL Server verileri korunur ve birbirine karıştırılmaz. Mod değişimi mevcut kayıtları silmez.
3. **Açılış ve güncelleme güvenlidir.** Uygulama mevcut veritabanını tanıyarak kullanır. Açılış hatası veya uyumsuzluk durumunda sessizce boş veritabanına geçilmez; işlem güvenle durdurulur ve sorun bildirilir.
4. **Şema değişikliği kontrollüdür.** Sürümlü, veri koruyan migration kullanılır. Öncesinde doğrulanmış geri dönüş yedeği alınır; kayıtlar, ilişkiler ve eski yedek uyumluluğu kontrol edilir. Başarısız migration eski veritabanını bozmuş durumda bırakmamalıdır.
5. **Yedekleme kaynak veriyi değiştirmez.** Mevcut veritabanı üzerine yazılmadan, bütünlüğü doğrulanabilir ayrı yedek oluşturulur. Eski yedekler otomatik silinmez; mümkünse cihaz dışında da güvenli kopya tutulur.
6. **Geri yükleme mevcut verileri otomatik ezmez.** Önce çalışan veritabanının ayrı geri dönüş kopyası oluşturulur; yedeğin bütünlüğü ve sürüm uyumu doğrulanır. Eski yedek yeni sürüme uyarlanamıyorsa işlem durdurulur. Üzerine geri yükleme için ayrıca açık ve özel kullanıcı onayı gerekir.
7. **Gerçek ve test ortamları ayrıdır.** Test APK'sı farklı uygulama kimliği ve veri alanı kullanır; gerçek veritabanını değiştirmez. Uyumlu uygulama güncellemesi veri sürekliliğini korur. Uygulamanın kaldırılması veya cihaz kaybında veri kalıcılığı garanti sayılamaz; bağımsız yedek ve geri yükleme yolu gerekir.
8. **Kritik işlemler için ayrı yetki şarttır.** DROP, TRUNCATE, toplu DELETE, veri kaybettiren migration, sıfırlama, mevcut veri üzerine geri yükleme veya yedek silme yalnızca sonuç ve riskler açıkça gösterilerek alınan özel onayla değerlendirilir. Genel `YAZ` komutu bu işlemler için tek başına onay değildir.
9. **Her veri etkili işlemde kontrol zorunludur.** Önceki kayıtların devamı, sürüm yükseltme, migration, hata durumunda korunma, yedek bütünlüğü ve geri yükleme olanağı uygun testlerle doğrulanır. Yapılmayan test yapılmış veya başarılı sayılmaz.
10. **Kapsam geneldir.** Bu hükümler tüm modüllere, Flutter/SQLite, API/SQL Server, senkronizasyon BAT dosyalarına, Codex ve ChatGPT çalışmalarına uygulanır. Mevcut kurallardan veri kaybına daha az izin veren hüküm öncelikle korunur.
