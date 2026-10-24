# 列出程式裡所有要翻成簡體的繁體文案，產生 locales/zh-Hans.js 缺的那幾行（用 OpenCC 轉換，再人工校對）。
# 用法：pip install opencc-python-reimplemented && python3 scripts/extract-strings.py
import re, pathlib, sys
import opencc

root = pathlib.Path(__file__).resolve().parent.parent
keys = []
def add(k):
    if k and re.search(r'[一-鿿]', k) and '.replace(' not in k and k not in keys:
        keys.append(k)

for f in sorted((root / 'src').rglob('*')):
    if f.suffix not in ('.vue', '.js') or 'locales' in f.parts:
        continue
    text = f.read_text(encoding='utf8')
    # t('…') 和 toast('…')、error.value = '…'、throw new Error('…') 這類會經過 t() 顯示的字串
    for m in re.finditer(r"\b(?:t|toast)\(\s*'((?:[^'\\]|\\.)*)'", text):
        add(m.group(1))
    for m in re.finditer(r"(?:label|text|error|auth\.error)\s*[:=]\s*'((?:[^'\\]|\\.)*)'", text):
        add(m.group(1))
    for line in re.findall(r"toast\(.*", text):
        for m in re.finditer(r"'([^']*)'", line):
            add(m.group(1))
    for m in re.finditer(r"new Error\('((?:[^'\\]|\\.)*)'\)", text):
        add(m.group(1))
    for m in re.finditer(r"return '((?:[^'\\]|\\.)*)'", text):
        add(m.group(1))
    for m in re.finditer(r"\[\s*'([^']+)',\s*'st-", text):
        add(m.group(1))
    for m in re.finditer(r"'(週[日一二三四五六])'", text):
        add(m.group(1))
    if f.name in ('constants.js', 'AdminView.vue'):
        for m in re.finditer(r"'([^'\n]*[一-鿿][^'\n]*)'", text):
            add(m.group(1))

# 資料庫函數 raise 的訊息也會顯示給同學看
schema = (root / 'supabase' / 'alumni_schema.sql').read_text(encoding='utf8')
for m in re.finditer(r"raise exception '([^']+)'", schema):
    add(m.group(1))

# 通知文字也是資料庫產生的，NotificationsView 會拆成「固定文字「標題」固定文字」分別翻譯
STATUS_LABELS = ['未公開', '待回答', '聯繫校友中', '已回答', '暫無法回答']
for k in ['你的問題', '你對', '。原因：', '有新的校友回答', '已被校友工作部刪除',
          '的修改申請已通過', '的修改申請被退回', '的刪除申請已通過', '的刪除申請被退回']:
    add(k)
for s in STATUS_LABELS:
    add('已公開，狀態：' + s)
    add('狀態改為：' + s)

existing = {}
loc = root / 'src' / 'locales' / 'zh-Hans.js'
if loc.exists():
    for m in re.finditer(r"^  '((?:[^'\\]|\\.)*)': '((?:[^'\\]|\\.)*)',$", loc.read_text(encoding='utf8'), re.M):
        existing[m.group(1)] = m.group(2)

cc = opencc.OpenCC('tw2sp')
FIX = [('注销', '退出登录'), ('拷贝', '复制'), ('帐号', '账号'), ('行事历', '日历'), ('缺省', '默认'), ('信箱', '邮箱'), ('设定', '设置'),
       ('帐户', '账户'), ('数据', '资料'), ('激活', '启用')]
missing = [k for k in keys if k not in existing]
unused = [k for k in existing if k not in keys]
for k in missing:
    v = cc.convert(k)
    for a, b in FIX:
        v = v.replace(a, b)
    print(f"  '{k}': '{v}',")
if unused:
    print('// 沒用到的：', unused, file=sys.stderr)
