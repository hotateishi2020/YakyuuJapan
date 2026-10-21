/// Display only the municipality; retain the original address in catalog data.
String stadiumLocation(Object? value) {
  final address = '${value ?? ''}'.trim();
  if (address.isEmpty) return '未収録';
  // MLB catalog addresses end in city, state/province, postal code, country.
  final parts = address.split(',').map((s) => s.trim()).toList();
  if (parts.length >= 5 && const ['USA', 'Canada'].contains(parts.last)) {
    return [parts[parts.length - 4], parts[parts.length - 3], parts.last]
        .join(', ');
  }
  final prefecture =
      RegExp(r'^(北海道|東京都|京都府|大阪府|.{2,3}県|海外)').firstMatch(address);
  if (prefecture == null) return address;
  final prefix = prefecture[0]!;
  final rest = address.substring(prefix.length);
  final city = RegExp(r'^.+?市市?').firstMatch(rest);
  if (city != null) {
    final name = city[0]!;
    const wardCities = {
      '札幌市',
      '仙台市',
      'さいたま市',
      '千葉市',
      '横浜市',
      '川崎市',
      '相模原市',
      '新潟市',
      '静岡市',
      '浜松市',
      '名古屋市',
      '京都市',
      '大阪市',
      '堺市',
      '神戸市',
      '岡山市',
      '広島市',
      '北九州市',
      '福岡市',
      '熊本市'
    };
    final ward = wardCities.contains(name)
        ? RegExp(r'^[^0-9０-９]+?区')
            .firstMatch(rest.substring(name.length))
            ?.group(0)
        : null;
    return '$prefix$name${ward ?? ''}';
  }
  final district = RegExp(r'^.+?郡').firstMatch(rest)?.group(0) ?? '';
  final municipality = district.isNotEmpty
      ? RegExp(r'^.+?[町村](?:町|村)?')
          .firstMatch(rest.substring(district.length))
          ?.group(0)
      : RegExp(r'^.+?[区町村](?:町|村)?').firstMatch(rest)?.group(0);
  return municipality == null ? address : '$prefix$district$municipality';
}
