/// Title-based preference, shared by collection and display. Unknown topics
/// remain fallback candidates; view counts break ties within each priority.
int draftVideoPriority(Map<String, dynamic> video) {
  final title = '${video['title'] ?? ''}';
  final focused = RegExp(
    r'密着|特集|インタビュー|対談|素顔|私生活|日常|休日|家族|ルーティン|生い立ち|成長|ドキュメンタリー|能力|プレー?スタイル|プレイスタイル|スカウト評|フォーム|球種|球速|変化球|制球|打撃|バッティング|スイング|守備|走塁|奪三振|投球|全打席|全投球|好プレー|ファインプレー|ホームラン|本塁打|ハイライト|練習|トレーニング|ブルペン|ピッチング|ストレート|直球|変化球|安打|ヒット|登板|投手戦',
    caseSensitive: false,
  ).hasMatch(title);
  final roundup = RegExp(r'指名予想|ドラフト予想|ドラフト会議|指名結果|指名速報|獲得予想|候補一覧|ランキング|候補まとめ|候補総まとめ').hasMatch(title);
  if (roundup) return focused ? 1 : 0;
  return focused ? 3 : 2;
}

int compareDraftVideos(Map<String, dynamic> a, Map<String, dynamic> b) {
  final priority = draftVideoPriority(b).compareTo(draftVideoPriority(a));
  if (priority != 0) return priority;
  return ((b['view_count'] as num?) ?? 0).compareTo((a['view_count'] as num?) ?? 0);
}
