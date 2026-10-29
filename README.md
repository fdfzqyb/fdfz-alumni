# FDFZ 校友提問牆

在校同學向校友提問，校友工作部請教合適的校友後代為回答。網址 alumni.fdfz.click。規劃書在專案資料夾 `alumni/校友提問牆規劃書.pdf`。

- 前端：Vite + Vue，部署在 Cloudflare Workers（和權益牆、樹洞、社團活動一樣）
- 後端：和權益牆共用同一個 Supabase 專案與帳號，資料表都用 `alumni_` 開頭，不動權益牆的 `profiles.role`。資料庫結構在 [`supabase/alumni_schema.sql`](supabase/alumni_schema.sql)
- 登入、註冊、校園卡驗證、改密碼都在帳號中心 [account.fdfz.click](https://account.fdfz.click)。`src/supabase.js`、`src/fdfz.js` 和其他站放一模一樣的，改了要一起改
- 所有內容都要登入且校園卡已審核才看得到
- 配色和 logo 是本站自己的（靛紫＋金黃），設計稿在專案資料夾 `alumni/design/`

## 上線步驟

1. **資料庫**：Supabase → SQL Editor，整份貼上 [`supabase/alumni_schema.sql`](supabase/alumni_schema.sql) 按 Run（只需一次）。會順便建好一個「其它」分類。
2. **第一位校友工作部成員**：在 SQL Editor 執行下面這行（學號換成那位同學的，校園卡要已審核）。之後成員可以在網站的「帳號 → 校友工作部後台 → 成員」自己加人。
   ```sql
   insert into alumni_staff (user_id) select id from profiles where student_id = '學號' and verify_status = 'approved';
   ```
3. **Cloudflare**：Workers & Pages → 建立 → 連接 GitHub，選這個倉庫。Build command `npm run build`，Deploy command `npx wrangler deploy`，Worker 名稱 `fdfz-alumni`（要和 [`wrangler.jsonc`](wrangler.jsonc) 一致）。部署完到 Worker → Settings → Domains & Routes → Add → Custom domain，填 `alumni.fdfz.click`。之後每次推到 `main` 都會自動重新部署。
4. **Supabase → Authentication → URL Configuration → Redirect URLs** 加上 `https://alumni.fdfz.click/**`（Site URL 不要改）。
5. 上線後，在帳號中心 fdfz-click-account 的 `src/constants.js` 的 `SITES` 加一行校友提問牆，「我的帳號」才會出現入口。

`.env.production` 已經放好 Supabase 的網址和 publishable key（和其他站相同）。

## 頁面一覽

| 頁面 | 路徑 | 誰能看 |
| --- | --- | --- |
| 問題牆（全部／等待回答／已回答，篩分類、搜尋、排序） | `/` | 已驗證同學 |
| 問題詳情（我也想問、代答、有幫助；提問者修改刪除；校友工作部改狀態、發布代答） | `/q/:id` | 看得到這題的人 |
| 提問、修改問題 | `/ask`、`/q/:id/edit` | 已驗證同學 |
| 我的提問（含未公開、暫無法回答） | `/mine` | 已驗證同學 |
| 通知 | `/notifications` | 已驗證同學 |
| 帳號、語言 | `/account` | 已驗證同學 |
| 校友工作部後台（待公開、全部問題、修改刪除申請、分類、成員） | `/admin` | 校友工作部 |

## 幾個規則

- **狀態**：未公開 → 待回答 → 聯繫校友中 → 已回答，另有暫無法回答。新問題是「未公開」，校友工作部公開後其他同學才看得到；「暫無法回答」只有提問者和校友工作部看得到，可以附原因。狀態改變時提問者會收到通知。
- **代答**：只有校友工作部能發布，一題可以有好幾則。每則標示校友的屆別、大學或工作單位，真名選填（校友同意才寫）。發布第一則時問題自動變成「已回答」；刪到一則不剩時退回「待回答」。
- **匿名**：提問預設匿名，其他同學看不到是誰問的；校友工作部一律看得到姓名和學號。
- **修改和刪除**：還沒有代答時，提問者直接改或刪（已公開的問題改完會退回「未公開」，校友工作部重新看過才再公開）；已有代答後要送申請，任一位校友工作部成員同意才生效。校友工作部也可以直接刪除不適合的問題，會通知提問者。
- **我也想問、有幫助**：我也想問只能按公開的問題、不能按自己的；代答依「有幫助」人數排序。
- **分類**：校友工作部在後台新增、改名、排序、停用。停用的分類不能再選，舊問題保留原分類，至少要留一個啟用的。
- **不寄信**：所有結果都只在網站的通知頁顯示。

## 在自己電腦上執行

需要 [Node.js](https://nodejs.org)（LTS 版）。

```bash
npm install
cp .env.example .env   # 填上 Supabase 的網址和 publishable key
npm run dev
```

本機（localhost）的登入資訊只存在本機，不會和正式站共用。

### 資料庫測試

[`supabase/tests/`](supabase/tests) 在本機 Postgres 16 上模擬 Supabase（`stub.sql`），載入權益牆的 `supabase/schema.sql` 和本站的 SQL 後跑情境測試：

```bash
supabase/tests/run.sh ../fdfz-wall/supabase/schema.sql
```

## 文字與語言

和其他站一樣有簡體（預設）和繁體，在帳號頁切換，設定存在各站共用的 `fdfz-lang` cookie。程式裡的文字一律寫繁體，包在 `t('…')` 裡，再到 `src/locales/zh-Hans.js` 加一行「繁體: 簡體」。`python3 scripts/extract-strings.py` 會列出還沒有對照的文案（用 OpenCC 先轉好，貼進去前再校對一次）。問題、回答、分類名稱照原文顯示。

通知文字由資料庫產生（繁體），`NotificationsView.vue` 把固定的部分拆出來翻譯。改了 `alumni_schema.sql` 裡通知的寫法，要同步更新 `scripts/extract-strings.py` 裡的通知片段和對照表。
