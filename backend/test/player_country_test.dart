import 'package:test/test.dart';
import '../app/PlayerCountry.dart';

void main() {
  test(
      'WBC mark includes birth-country representatives but excludes Premier12 alone',
      () {
    expect(
        playerCountryDisplay(
            '🇯🇵',
            [
              {'tournament': 'WBC', 'year': 2023, 'country_code': 'JP'}
            ],
            year: 2026)['flg_wbc'],
        true);
    expect(
        playerCountryDisplay(
            '🇯🇵',
            [
              {'tournament': 'Premier12', 'year': 2024, 'country_code': 'JP'}
            ],
            year: 2026)['flg_wbc'],
        false);
    expect(
        playerCountryDisplay(
            '🇯🇵',
            [
              {'tournament': 'WBC', 'year': 2026, 'country_code': 'JP'}
            ],
            year: 2025)['flg_wbc'],
        false);
  });
  test('birth country is used without representative appearances', () {
    expect(
        playerCountryDisplay('🇺🇸', [], year: 2026)['emoji_display_country'],
        '🇺🇸');
  });
  test('WBC representation overrides birthplace without changing it', () {
    final result = playerCountryDisplay(
        '🇺🇸',
        [
          {
            'year': 2023,
            'tournament': 'WBC',
            'country_code': 'JP',
            'source': 'official'
          }
        ],
        year: 2026);
    expect(result['emoji_country'], '🇺🇸');
    expect(result['emoji_display_country'], '🇯🇵');
    expect(result['country_flag_basis'], 'WBC 2023');
  });
  test('latest different country wins across both tournaments', () {
    final result = playerCountryDisplay(
        '🇺🇸',
        [
          {'year': 2017, 'tournament': 'WBC', 'country_code': 'IT'},
          {'year': 2019, 'tournament': 'Premier12', 'country_code': 'MX'},
          {'year': 2023, 'tournament': 'WBC', 'country_code': 'US'},
          {'year': 2024, 'tournament': 'Olympics', 'country_code': 'CA'},
          {'year': 2026, 'tournament': 'WBC', 'country_code': 'GB'},
        ],
        year: 2025);
    expect(result['emoji_display_country'], '🇲🇽');
  });
  test('future appearances and invalid codes are not used', () {
    final result = playerCountryDisplay(
        '🇨🇦',
        [
          {'year': 2026, 'tournament': 'WBC', 'country_code': 'IT'},
          {'year': 2023, 'tournament': 'WBC', 'country_code': '??'},
        ],
        year: 2024);
    expect(result['emoji_display_country'], '🇨🇦');
    expect(countryFlag('JP'), '🇯🇵');
    expect(countryFlag('null'), '');
  });
}
