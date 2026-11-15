# Test ve regresyon



## 27. HATA GELDİĞİNDE ÖNCELİK DEĞİŞİR

Kullanıcı hata veya Exception gönderdiğinde önce ilgili hata ele alınır. Aynı anda başka özellik geliştirilmez.

Hata mesajlarında mümkün olduğunca Türkçe açıklama ve orijinal hata/Exception bilgisi birlikte sunulur.

Komut, build veya test hatası gizlenmez. Onaylı kapsam ve mevcut yetki içinde güvenle çözülebilen teknik hata araştırılır ve giderilir; her teknik hatada gereksiz onay beklenmez.

Çözüm yeni yetki, kapsam genişlemesi, kullanıcı tercihi veya veri kaybı riski gerektiriyorsa durulur ve kullanıcıya bildirilir.

Parola, token, private key, gizli bağlantı bilgisi ve benzeri hassas veriler kaynak koda/Git’e eklenmez; hata çıktılarında veya raporlarda gereksiz gösterilmez.

## 29. TEST MATRİSİ

Değişikliğin türüne göre build, açılış, navigasyon, kayıt, okuma, güncelleme, silme, boş/yanlış/tekrar veri, yetki, mod farkı, ekran taşması, veri büyüklüğü ve regresyon değerlendirilir.

Her değişiklikte bütün testler zorunlu değildir. Etkilenebilecek alanlar için anlamlı testler seçilir.

Testler izin verilen ortamda güvenli biçimde çalıştırılır. Veri silen veya dış sistemleri değiştiren testler ayrıca gerekli yetkiye tabidir.

Yapılmayan test yapılmış gibi gösterilmez.

Test bahanesiyle kapsam dışı kaynak değişikliği yapılmaz. `bin/`, `obj/`, `.vs/`, build çıktıları, generated plugin dosyaları ve makineye özel `local.properties` gibi dosyalar gerekmedikçe commit edilmez.

Mevcut `.gitignore` kuralları korunur.

## 30. REGRESYON KONTROLÜ

Yeni özelliğin çalışması tek başına yeterli değildir.

“Bu değişiklik daha önce çalışan neyi bozabilir?” sorusu değerlendirilir.

Riskli alanlar gerekli ölçüde kontrol edilir. Kontrol edilemeyen önemli risk veya eksik test açıkça bildirilir.
