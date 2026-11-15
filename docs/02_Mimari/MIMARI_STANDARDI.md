# Mimari standardı



## 8. ETKİ HARİTASI ÇIKAR

Bir değişiklikten önce neyi etkilediği değerlendirilir.

Gerekirse şu zincir incelenir:

Veri → Veritabanı → API → Model → Service → State → UI → Yetki → Rapor → Import → Diğer modüller

Yalnızca gerçekten etkilenen ve onaylı kapsama giren katman değiştirilir.

## 9. GELİŞTİRME SIRASI

Birden fazla katman değişecekse sıra:

**Veritabanı → API/Web Server → Flutter**

Değişiklik gerekmeyen katmana dokunulmaz.

## 10. MEVCUT SİSTEMİ KORU

Yeni yapı oluşturmadan önce aynı işi yapan mevcut yapı araştırılır. Uygunsa yeniden kullanılır veya genişletilir.

Gereksiz refactor, dosya taşıma, isim değiştirme, formatlama, servis, model, tablo veya ekran oluşturulmaz.

**Minimum müdahale + maksimum uyumluluk** esas alınır.

Mevcut kaynak dosyanın silinmesi, taşınması veya yeniden adlandırılması açık kullanıcı onayı gerektirir. Kullanıcının ilgili işlemi açıkça istemesi onay sayılır.

NuGet, Flutter/Dart paketleri, SDK sürümleri, Gradle ayarları veya veritabanı bağımlılıkları açık gerekçe ve kullanıcı onayı olmadan değiştirilmez.

Teknik uyumluluk korunur:

- Visual Studio Enterprise 2022
- C# ve mevcut .NET projesi
- Android Studio
- Mevcut Flutter/Dart projesi
- SQL Server 2025
- SSMS 2022

Bu bilgiler sürüm yükseltme izni değildir.

## 22. ÇALIŞMA MODLARI

Tek Flutter uygulaması kullanılır. Ayrı öğretmen uygulaması oluşturulmaz.

- **Bireysel Öğretmen:** Flutter → SQLite
- **Okul/Kurumsal:** Flutter → API → SQL Server

Bireysel mod geliştirilirken mevcut okul/kurumsal sistem korunur.

Mod verileri otomatik karıştırılmaz. Mod değişimi veri silmez.

Mevcut ekranlar mümkün olduğunca ortak kullanılır; veri kaynağı moda göre değişir.

Bireysel öğretmen yalnızca kendisini ve ders verdiği öğrencileri ilgilendiren verileri tutar.

## 26. NGROK

Ngrok URL’leri büyük/küçük harf dahil birebir korunur.

Kullanıcı istemedikçe adres kendiliğinden değiştirilmez veya yeniden üretilmez.
