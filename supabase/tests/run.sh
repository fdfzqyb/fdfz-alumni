#!/bin/sh
# 在本機 Postgres 16 上跑情境測試：./run.sh 權益牆的schema.sql路徑
# 用 stub.sql 模擬 Supabase 的 auth、storage 和角色，再依序載入權益牆和校友提問牆的結構。
set -e
WALL=${1:?請給權益牆 supabase/schema.sql 的路徑}
DIR=$(dirname "$0")
dropdb --if-exists alumni_test && createdb alumni_test
psql -q -v ON_ERROR_STOP=1 -d alumni_test -f "$DIR/stub.sql" -f "$WALL" -f "$DIR/../alumni_schema.sql" >/dev/null
for t in "$DIR"/test*.sql; do
  echo "=== $t"
  psql -q -v ON_ERROR_STOP=1 -d alumni_test -f "$t"
done
