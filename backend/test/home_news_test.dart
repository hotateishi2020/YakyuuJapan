import 'package:test/test.dart';
import '../app/HomeNews.dart';

void main() {
  test('野球記事を抽出し記事リンクだけを重複なく返す', () {
    final rows = HomeNews.parse('''<rss><channel>
      <item><title><![CDATA[大谷が本塁打 & 快勝]]></title><link>https://news.yahoo.co.jp/articles/abc?source=rss</link></item>
      <item><title>大谷が本塁打</title><link>https://news.yahoo.co.jp/articles/abc</link></item>
      <item><title>高校野球 秋季大会</title><link>https://news.yahoo.co.jp/articles/def</link></item>
      <item><title>阪神が勝利</title><link>https://news.yahoo.co.jp/articles/ghi</link></item>
      <item><title>サッカー代表が勝利</title><link>https://news.yahoo.co.jp/articles/jkl</link></item>
      <item><title>野球ニュース一覧</title><link>https://news.yahoo.co.jp/categories/sports</link></item>
      <item><title>野球</title><link>javascript:alert(1)</link></item>
      <item><title>野球</title><link>https://other.example/articles/mno</link></item>
    </channel></rss>''');
    expect(rows.map((r) => r['category']), ['MLB', '高校野球', 'NPB']);
    expect(rows.first['title'], '大谷が本塁打 & 快勝');
    expect(rows.first['url'], 'https://news.yahoo.co.jp/articles/abc?source=rss');
  });
  test('競馬などの中日スポーツ記事を球団記事と誤認しない', () {
    expect(HomeNews.category('【競馬】新馬戦を勝利(中日スポーツ)'), isNull);
    expect(HomeNews.category('会見で指名に驚き(Full-Count)'), '野球');
    expect(() => HomeNews.parse('<html>error</html>'), throwsFormatException);
  });
}
