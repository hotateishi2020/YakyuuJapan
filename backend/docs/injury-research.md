# 怪我人情報のAPI調査

`InjuryList.sync` は球団公式とスポーツ報道を OpenAI Responses API の
`web_search` で調査します。旧個人サイトを検索対象に含めず、返却URLと
記事のリダイレクト先も許可ドメインに限定します。旧サイト由来の詳細と負傷フラグは削除します。

サーバー環境に `OPENAI_API_KEY` と `OPENAI_INJURY_MODEL` を設定します。
モデルは `OPENAI_RESEARCH_MODEL` を代用できます。Web検索・Structured Outputs対応モデルを指定してください。
キーやモデルが未設定の場合、旧データの除去だけを行い、API調査を保留します。
キーをソースコードやフロントエンドへ記載しないでください。

手動実行（backendディレクトリ）：`dart run tool_sync_injuries.dart`
既存のNPB成績取得処理からも呼ばれます。成功済みの日はJST日付で再実行せず、
DBアドバイザリロックで多重実行を防ぎます。画面の再読み込みはDB参照のみです。

全12球団の検索完了、API応答の完了、許可URL、本文と引用の一致を確認してから
トランザクションで登録します。取得失敗・不完全調査では既存API登録を消しません。
一覧にないという理由で復帰扱いにせず、復帰の記述がある選手だけ解除します。
取得漏れを完全には防げないため、調査結果は最新の全選手一覧を保証しません。
怪我や全治期間の医学的推測は禁止し、報道からの状態推定は `estimated` を付けます。

出典・引用は検証用にDB内部へ保存します。公開APIと怪我人画面には出典を出しません。

API仕様: https://developers.openai.com/api/docs/guides/tools-web-search
