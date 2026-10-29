-- 升級：匿名提問不能被反推；已公開的問題修改後退回未公開重新審核
-- 適用：已經執行過 alumni_schema.sql 的資料庫。全新建立的資料庫直接用 alumni_schema.sql 即可。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（重跑也不會出錯）。

-- 1. alumni_questions 原始表只給提問者本人和校友工作部讀（其他同學讀 alumni_question_feed）
drop policy if exists "看得到的問題" on alumni_questions;
drop policy if exists "看自己的問題或校友工作部" on alumni_questions;
create policy "看自己的問題或校友工作部" on alumni_questions for select
  using (is_approved() and (author_id = auth.uid() or alumni_is_staff()));

-- 2. 已公開（待回答、聯繫校友中）且還沒有代答的問題，提問者直接修改後退回「未公開」
create or replace function alumni_change_my_question(p_id bigint, p_kind alumni_req_kind, p jsonb default '{}')
returns text
language plpgsql security definer set search_path = public as $$
declare
  q alumni_questions;
  f jsonb;
begin
  select * into q from alumni_questions where id = p_id for update;
  if q.id is null or q.author_id <> auth.uid() or not is_approved() then raise exception '只能改自己的問題'; end if;
  if exists (select 1 from alumni_change_requests where question_id = p_id and status = 'pending') then
    raise exception '這個問題已經有一份申請在等校友工作部處理';
  end if;
  if p_kind = 'edit' then f := alumni_check_form(p); end if;

  if not exists (select 1 from alumni_answers where question_id = p_id) then
    if p_kind = 'delete' then
      delete from alumni_questions where id = p_id;
    else
      update alumni_questions set category_id = (f->>'category_id')::bigint, title = f->>'title', body = f->>'body',
        wish = f->>'wish', anonymous = (f->>'anonymous')::boolean, edited_at = now(),
        status = case when status in ('open', 'contacting') then 'hidden'::alumni_q_status else status end
      where id = p_id;
      if q.status in ('open', 'contacting') then return 'reopened'; end if;
    end if;
    return 'done';
  end if;

  insert into alumni_change_requests (question_id, requester, kind, new_category_id, new_title, new_body,
                                      new_wish, new_anonymous, reason)
  values (p_id, auth.uid(), p_kind, (f->>'category_id')::bigint, f->>'title', f->>'body',
          f->>'wish', (f->>'anonymous')::boolean, left(btrim(coalesce(p->>'reason', '')), 200));
  return 'requested';
end $$;

