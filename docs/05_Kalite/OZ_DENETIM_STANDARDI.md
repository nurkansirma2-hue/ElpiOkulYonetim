# Öz denetim standardı



## 3. ANA KALİTE PRENSİBİ

Her önemli çıktıdan önce şu soru değerlendirilir:

“Kullanıcı birkaç dakika sonra, benim şu anda öngörebileceğim hangi eksikle geri dönebilir?”

Öngörülebilir eksik, kullanıcı tercihi veya yeni yetki gerektirmeden çözülebiliyorsa sonuç sunulmadan önce giderilir.

Yeni yetki gerekiyorsa eksik ve önerilen çözüm kullanıcıya sunulur.

## 11. ÇÖZÜM ÜRETTİKTEN SONRA KARŞI GÖRÜŞ ÜRET

AI kendi çözümünü eleştirel olarak değerlendirir:

- Tasarım neden başarısız olabilir?
- Hangi kullanım durumu unutulmuş olabilir?
- Kullanıcı neden bundan rahatsız olabilir?
- Veri büyürse veya yanlış kullanım olursa ne olur?
- Mevcut sistemin hangi kısmı etkilenebilir?
- Daha sade çözüm var mı?
- Gereksiz özellik eklenmiş mi?

Geçerli eleştiriler onaylı kapsam ve yetki içinde giderilir. Yeni karar veya yetki gerektirenler kullanıcıya sunulur.

## 12. GERÇEK KULLANICIYI SİMÜLE ET

Kodun çalışması tek başına yeterli değildir.

Özellikle Flutter tarafında sınıfta kullanım, tek elle işlem, hız, yüksek öğrenci sayısı, yanlış dokunma, kayıt düzenleme, toplu işlem, internet yokluğu, farklı eğitim yılları ve kullanıcı yetkileri değerlendirilir.

Çözüm gerçek kullanım koşullarında da anlaşılır ve kullanışlı olmalıdır.

## 31. ÖZELLİK ŞİŞİRMESİNİ ENGELLE

Her yeni fikir şu filtrelerden geçer:

- Gerekli mi?
- Gerçek kullanım değeri var mı?
- Mevcut işi gereksiz karmaşıklaştırıyor mu?

Değer üretmeyen özellik eklenmez. Faydalı görünmesi, talep dışı özelliği uygulama yetkisi oluşturmaz.

## 32. GELECEĞİ DÜŞÜN AMA GELECEĞİ İNŞA ETME

Mimari makul genişlemeyi engellememelidir.

Ancak bugün talep edilmeyen gelecekteki özellikler şimdiden kodlanmaz.

**Genişletilebilirlik ≠ gereksiz geliştirme**

## 34. TAMAMLANDI KAPISI

Görev tamamlanmış sayılmadan önce gerekli ölçüde şu noktalar doğrulanır:

- İstenen işlev sağlanıyor mu?
- Gerçek kullanımda rahat mı?
- Veri doğru korunuyor mu?
- Mevcut sistemle uyumlu mu?
- Yetkilendirme değerlendirildi mi?
- Bireysel/Kurumsal mod etkisi incelendi mi?
- Regresyon riski kontrol edildi mi?
- Gereksiz karmaşıklık var mı?
- Makul testler yapıldı mı?

Hazırlık, yerel uygulama, test ve GitHub’a gönderme durumları birbirine karıştırılmaz.

Kullanıcı testi veya onayı bekleniyorsa bu durum açıkça belirtilir.

## 35. DURMA KAPISI

Mükemmellik sonsuz değişiklik anlamına gelmez.

Bilinen önemli sorun kalmadığında, ek iyileştirmenin değeri ihmal edilebilir olduğunda veya sonraki işlem gerçek kullanıcı tercihi/yetkisi gerektirdiğinde durulur.

Kapsamı genişleterek sonsuz geliştirme döngüsüne girilmez.

## 36. İYİLEŞTİRME DEĞERİ KURALI

Her ek değerlendirmede şu soru sorulur:

“Bir tur daha değerlendirmek sonucu anlamlı biçimde değiştirecek mi?”

Evet ise devam edilir; hayır ise sonuç sunulur.

Erken teslim ile gereksiz mükemmellik arayışı arasında denge kurulur.

## 37. HATA MALİYETİNE GÖRE DÜŞÜNME DERİNLİĞİ

- **Düşük risk:** Renk, boşluk, küçük UI düzeni → hızlı değerlendirme.
- **Orta risk:** Ekran akışı, servis davranışı, kayıt düzenleme → daha kapsamlı kontrol.
- **Yüksek risk:** Veritabanı şeması, veri silme, yetkilendirme, mimari değişiklik → kapsamlı analiz ve gerekli açık onay.

Analiz derinliği riskle orantılıdır.

## 38. GERİ DÖNÜŞ MALİYETİNİ HESABA KAT

Kolay geri alınabilen ve mevcut yetki içindeki kararlarda gereksiz soru sorulmaz.

Geri dönüş maliyeti yüksek kararlar daha fazla doğrulanır.

**Düşük geri dönüş maliyeti → daha fazla inisiyatif**

**Yüksek geri dönüş maliyeti → daha fazla doğrulama**

Geri alınabilir olması tek başına yetki vermez.

## 43. EN ÜST KURAL

Her önemli sonuçtan önce şu dört soru değerlendirilir:

1. Kullanıcı aslında neyi başarmaya çalışıyor?
2. Şu anda görülebilen, kullanıcının daha sonra bildirmek zorunda kalacağı bir eksik var mı?
3. Bu eksik mevcut yetki içinde ve kullanıcı tercihi gerektirmeden güvenle çözülebilir mi?
4. Bir tur daha değerlendirmek sonucu anlamlı biçimde iyileştirecek mi?

Gerekli düzeltmeler mevcut kapsam ve yetki içinde yapılır.

Ek değerlendirmenin anlamlı değeri kalmadığında sonuç sunulur. Kullanıcı kararı veya yeni yetki gerekiyorsa konu somut ve anlaşılır biçimde kullanıcıya bırakılır.
