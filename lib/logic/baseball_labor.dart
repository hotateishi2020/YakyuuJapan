/// Calendar years containing an actual work stoppage; future risk is separate.
({String label, String note})? baseballLaborLabel(int year, {required bool mlb}) {
  if (!mlb) return year == 2004 ? (label: 'ストライキ', note: '2004年9月18～19日。選手会ストライキ。出典：NPBセ・リーグ略史 https://www.npb.or.jp/cl/history.html') : null;
  if ([1972, 1980, 1981, 1985, 1994, 1995].contains(year)) {
    return (label: 'ストライキ', note: 'この暦年に選手会のストライキが発生。1994～1995年は年をまたぐ同一のストライキ。出典：https://www.bls.gov/opub/mlr/1997/03/art4full.pdf');
  }
  if ([1973, 1976, 1990, 2021, 2022].contains(year)) {
    return (label: 'ロックアウト', note: 'この暦年にオーナー側のロックアウトが発生。2021年12月～2022年3月は同一のロックアウト。出典：https://www.mlb.com/news/mlb-cba-negotiations-update');
  }
  // Attribute the 2026–2027 offseason to the following season only.
  if (year == 2027) {
    return (label: '労使交渉・未確定', note: '2026年10月19日時点：現労使協定は2026年12月1日満了。2026年オフ～2027年のロックアウト発生は未確定。出典：https://www.mlbplayers.com/es/frequently-asked-questions');
  }
  return null;
}
