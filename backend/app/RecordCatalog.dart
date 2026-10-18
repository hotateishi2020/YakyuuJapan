class RecordMetric {
  const RecordMetric(this.key, this.label, this.statId, this.npb, this.mlb,
      this.group, this.unit,
      {this.lower = false});
  final String key, label, npb, mlb, group, unit;
  final int statId;
  final bool lower;
}

const recordMetrics = [
  RecordMetric('avg', '打率', 1, 'b_avg', 'avg', 'hitting', ''),
  RecordMetric('hits', '安打', 2, 'b_h', 'hits', 'hitting', '安打'),
  RecordMetric('hr', '本塁打', 3, 'b_hr', 'homeRuns', 'hitting', '本'),
  RecordMetric('rbi', '打点', 4, 'b_rbi', 'rbi', 'hitting', '打点'),
  RecordMetric('sb', '盗塁', 5, 'b_sb', 'stolenBases', 'hitting', '盗塁'),
  RecordMetric('obp', '出塁率', 6, 'b_obp', 'obp', 'hitting', ''),
  RecordMetric('slg', '長打率', 7, 'b_slg', 'slg', 'hitting', ''),
  RecordMetric('era', '防御率', 9, 'p_era', 'era', 'pitching', '', lower: true),
  RecordMetric('wins', '勝利', 10, 'p_w', 'wins', 'pitching', '勝'),
  RecordMetric('so', '奪三振', 11, 'p_so', 'strikeOuts', 'pitching', '奪三振'),
  RecordMetric('holds', 'ホールド', 17, 'p_hld', 'holds', 'pitching', 'ホールド'),
  RecordMetric('hp', 'ホールドポイント', 18, 'p_hldp', '', 'pitching', 'HP'),
  RecordMetric('saves', 'セーブ', 19, 'p_sv', 'saves', 'pitching', 'セーブ'),
];
const streakDefinitions = [
  ('wins', '連続勝利', '勝', '勝敗が付いた登板のみ。勝敗なしの登板は継続。'),
  ('saves', '連続セーブ', '試合', '登板ごとの連続セーブ。セーブの付かない登板で中断。連続セーブ機会成功とは別集計。'),
  ('holds', '連続ホールド', '試合', '登板ごとの連続ホールド。ホールドポイントとは別集計。'),
  ('scoreless_games', '連続無失点（登板）', '試合', '失点ゼロの登板が続いた回数。自責点ゼロとは区別。'),
  ('scoreless_innings', '連続無失点（投球回）', '回', '公式に認定された連続無失点イニング。'),
  ('outs', '連続アウト', '人', '走者を出さずに連続して退けた打者数。'),
  ('hit_pa', '連続安打（打席）', '打席', '安打が続いた打席数。四死球などの打席で終了。'),
  ('hit_games', '連続安打（試合）', '試合', '四死球・犠打のみの試合は継続。犠飛は中断。'),
  ('onbase_pa', '連続出塁（打席）', '打席', '安打・四球・死球による連続出塁。失策出塁は含まない。'),
  ('onbase_games', '連続出塁（試合）', '試合', '安打・四球・死球による連続試合出塁。'),
  ('steals', '連続盗塁成功', '回', '盗塁企図の成功が続いた回数。盗塁刺で中断。'),
  ('appearances', '連続出場', '試合', '所属チームの公式戦で欠場せず出場した回数。'),
  ('hr_pa', '連続本塁打（打席）', '打席', '本塁打が続いた打席数。四死球を含む本塁打以外の打席で中断。試合をまたいで集計。'),
  ('hr_games', '連続本塁打（試合）', '試合', '本塁打を記録した連続出場試合数。'),
  ('strikeouts', '連続奪三振', '人', '連続する対戦打者から奪った三振数。'),
];
