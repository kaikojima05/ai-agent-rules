# import の編集ルール

## 禁止事項

1. dayjs を `"dayjs"` から直接 import すること
  - 必ず `"@/modules/dayjs"` に用意された関数を呼び出すこと
  - ただし、`"@/modules/dayjs"` の dayjs の使用は非推奨としているので、その他の適切な関数を使用する
