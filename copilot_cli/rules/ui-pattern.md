# UI コンポーネントの編集ルール

## インポート元
1. UI コンポーネントは @front/components/ からインポートすること
   - antd, Headless UI, React Aria を直接インポートしてはならない
   - Why: ライブラリの差し替え・ラップ時の影響範囲を限定するため

## ローカルコンポーネントへの切り出し
1. 下記条件のいずれかに合致する JSX 部分はローカルコンポーネントに切り出すこと
   a. 条件付きレンダリング（三項演算子・&& 等）で **5行以上** のブロックを表示している部分
   b. 同一の構造で2回以上表示している部分
   - Why: render 関数の肥大化を防ぎ、差分レビューの単位を小さくするため

## 命名ルール
1. @front/features/mypage/resources/ もしくは @front/features/pre-mypage/resources/ 内に
   作成するコンポーネントの名前は [resource名]〇〇.tsx とすること
   - 例: bill/ 配下なら BillPaymentDetail.tsx
