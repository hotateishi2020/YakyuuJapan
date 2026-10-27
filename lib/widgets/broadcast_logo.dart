import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

String? broadcastLogoAsset(Map<String,dynamic> row) {
  final name = '${row['name'] ?? ''}'.toLowerCase().replaceAll('ｎｈｋ', 'nhk').replaceAll('１', '1').replaceAll(RegExp(r'[\s－ー-]'), '');
  final kind = '${row['kind']}';
  final file = switch (name) {
    'tver' => 'tver.png',
    _ when kind == 'tv' && name.contains('テレビ信州') => 'tsb.jpg',
    _ when kind == 'tv' && name.contains('長野朝日放送') => 'abn.png',
    _ when kind == 'tv' && name.contains('長野放送') => 'nbs.png',
    _ when kind == 'tv' && (name.contains('nhk総合') || name.contains('nhkeテレ')) => 'nhk-tv.png',
    _ when kind == 'radio' && const {'nhkラジオ','nhkラジオ第1','nhkラジオ第一','nhk第1','nhk第一','nhkr1','nhkradio1'}.contains(name) => 'nhk-radio1.png',
    _ when kind == 'tv' && (name.contains('sbc') || name.contains('信越放送')) => 'sbc.png',
    'unext' => 'unext.svg',
    'tbsテレビ' => 'tbs.png',
    '日本テレビ' => 'ntv.svg',
    'テレビ東京' => 'tv-tokyo.svg',
    'hulu' => 'hulu.svg',
    _ when name.contains('rkb') => kind == 'radio' ? 'rkb-radio.png' : 'rkb.svg',
    _ when name.contains('kbc') && kind == 'radio' => 'kbc-radio.png',
    _ => null,
  };
  return file == null ? null : 'backend/assets/images/broadcasts/$file';
}

/// Bundled official logos avoid remote CORS/ICO failures in Flutter web.
class BroadcastLogo extends StatelessWidget {
  const BroadcastLogo({super.key,required this.row});
  final Map<String,dynamic> row;
  @override
  Widget build(BuildContext context) {
    final asset = broadcastLogoAsset(row);
    if (asset != null) {
      if (asset.endsWith('/nhk-tv.png')) {
        return Column(children:[Expanded(child:Image.asset(asset,fit:BoxFit.contain)),
          Text('${row['name']}'.contains('総合')?'総合':'Eテレ',style:const TextStyle(fontSize:8,height:1))]);
      }
      return asset.endsWith('.svg') ? SvgPicture.asset(asset,fit:BoxFit.contain)
          : Image.asset(asset,fit:BoxFit.contain);
    }
    final url = '${row['logo_url'] ?? ''}';
    final fallback = FittedBox(child: Text('${row['name'] ?? ''}',style:const TextStyle(fontSize:10)));
    if (Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') == true) {
      return SvgPicture.network(url,fit:BoxFit.contain,errorBuilder:(_,__,___)=>fallback);
    }
    return Image.network(url,webHtmlElementStrategy:WebHtmlElementStrategy.fallback,fit:BoxFit.contain,errorBuilder:(_,__,___)=>fallback);
  }
}
