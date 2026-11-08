import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/services/bireysel_yillik_plan_service.dart';
void main(){test('Gerçek dosyaların tarih tanılaması',() async{
 final files=Directory('C:/Users/Nurkan SIRMA/Downloads').listSync().whereType<File>().where((f)=>f.path.contains('bilgisayarli-tasarim')&&(f.path.endsWith('.docx')||f.path.endsWith('.xlsx')));
 final result=[];
 for(final f in files){ final p=await BireyselYillikPlanService.onIzlemeHazirla(dosyaBytes:await f.readAsBytes(),dosyaAdi:f.uri.pathSegments.last,dosyaUzantisi:f.path.split('.').last,egitimOgretimYili:'2026-2027'); result.add({'file':f.uri.pathSegments.last,'errors':p.hatalar,'count':p.kayitlar.length,'rows':p.kayitlar.take(8).map((r)=>{'hafta':r.haftaNo,'tarih':r.tarihAraligi,'bas':r.baslangicTarihi,'bit':r.bitisTarihi,'konu':r.konu,'kazanim':r.kazanim}).toList()}); }
 File('../output/yillik_tarih_tanilama.json').writeAsStringSync(JsonEncoder.withIndent('  ').convert(result));
});}
