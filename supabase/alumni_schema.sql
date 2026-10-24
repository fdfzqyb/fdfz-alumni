-- FDFZ 校友提問牆 資料庫結構（alumni.fdfz.click）
-- 前提：同一個 Supabase 專案已執行過 fdfz-wall 的 supabase/schema.sql
--       （需要 profiles、verify_status、is_approved()、is_admin()）。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。
--
-- 原則：
--   * 在校同學提問，校友工作部（也是在校同學）請教校友後代為回答。校友本人不註冊。
--   * 所有內容都要登入且校園卡已審核才看得到，未登入什麼都讀不到。
--   * 新問題是「未公開」，校友工作部公開後才讓其他同學看到；「暫無法回答」只有提問者和校友工作部看得到。
--   * 匿名提問時，其他同學看不到提問者；校友工作部一律看得到。
--   * 寫入一律走下面的 security definer 函數，前端不能直接改表。
--   * 不動權益牆的 profiles.role；校友工作部是本站自己的名單（alumni_staff）。

-------------------------------------------------------------------------------
-- 1. 類型
-------------------------------------------------------------------------------

-- 未公開、待回答、聯繫校友中、已回答、暫無法回答
create type alumni_q_status as enum ('hidden', 'open', 'contacting', 'answered', 'unable');
create type alumni_req_kind as enum ('edit', 'delete');
create type alumni_req_status as enum ('pending', 'approved', 'rejected', 'withdrawn');

-------------------------------------------------------------------------------
-- 2. 資料表
-------------------------------------------------------------------------------

-- 校友工作部名單
create table alumni_staff (
  user_id uuid primary key references profiles(id) on delete cascade,
  added_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- 分類。校友工作部在後台增減；停用的分類不能再選，舊問題保留原分類
create table alumni_categories (
  id bigint generated always as identity primary key,
  name text not null unique check (char_length(btrim(name)) between 1 and 20),
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into alumni_categories (name, sort) values ('其它', 100);

create table alumni_questions (
  id bigint generated always as identity primary key,
  author_id uuid not null references profiles(id) on delete cascade,
  category_id bigint not null references alumni_categories,
  title text not null check (char_length(btrim(title)) between 1 and 60),
  body text not null check (char_length(btrim(body)) between 1 and 3000),
  wish text not null default '' check (char_length(wish) <= 60), -- 希望哪類校友回答（選填）
  anonymous boolean not null default true,
  status alumni_q_status not null default 'hidden',
  status_note text check (char_length(status_note) <= 200),    -- 暫無法回答的原因，給提問者看
  published_at timestamptz,                                    -- 第一次公開的時間
  edited_at timestamptz,
  created_at timestamptz not null default now()
);
create index on alumni_questions (author_id);
create index on alumni_questions (status, created_at);

-- 代答。校友資訊由校友工作部填寫：屆別、大學或工作單位、真名（選填，校友同意才寫）
create table alumni_answers (
  id bigint generated always as identity primary key,
  question_id bigint not null references alumni_questions on delete cascade,
  cohort smallint not null check (cohort between 1950 and 2100),
  affiliation text not null check (char_length(btrim(affiliation)) between 1 and 60),
  alumni_name text check (char_length(btrim(alumni_name)) between 1 and 30),
  body text not null check (char_length(btrim(body)) between 1 and 5000),
  posted_by uuid references profiles(id) on delete set null,
  poster_name text,              -- 發布代答的校友工作部成員（profiles 讀不到別人，所以存一份）
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
create index on alumni_answers (question_id);

-- 我也想問
create table alumni_metoo (
  question_id bigint not null references alumni_questions on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (question_id, user_id)
);
create index on alumni_metoo (user_id);

-- 有幫助
create table alumni_helpful (
  answer_id bigint not null references alumni_answers on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (answer_id, user_id)
);
create index on alumni_helpful (user_id);

-- 已有代答後，提問者改或刪自己的問題要校友工作部同意
create table alumni_change_requests (
  id bigint generated always as identity primary key,
  question_id bigint not null references alumni_questions on delete cascade,
  requester uuid not null references profiles(id) on delete cascade,
  kind alumni_req_kind not null,
  new_category_id bigint references alumni_categories,
  new_title text check (char_length(btrim(new_title)) between 1 and 60),
  new_body text check (char_length(btrim(new_body)) between 1 and 3000),
  new_wish text check (char_length(new_wish) <= 60),
  new_anonymous boolean,
  reason text not null default '' check (char_length(reason) <= 200), -- 提問者寫的原因
  status alumni_req_status not null default 'pending',
  reviewed_by uuid references profiles(id) on delete set null,
  reviewer_name text,
  reject_reason text check (char_length(reject_reason) <= 200),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (kind = 'delete' or (new_category_id is not null and new_title is not null and new_body is not null
                             and new_wish is not null and new_anonymous is not null))
);
create index on alumni_change_requests (status, created_at);
-- 一個問題同時只能有一份待處理的申請
create unique index on alumni_change_requests (question_id) where status = 'pending';

-- 通知。question_id 在問題刪除後變成空的，通知保留
create table alumni_notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  question_id bigint references alumni_questions on delete set null,
  message text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index on alumni_notifications (user_id, created_at desc);

-------------------------------------------------------------------------------
-- 3. 權限判斷
-------------------------------------------------------------------------------

create function alumni_is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select is_approved() and exists (select 1 from alumni_staff where user_id = auth.uid());
$$;

-- 這個問題自己看不看得到：校友工作部全部看得到；提問者看得到自己的；
-- 其他已審核同學只看得到待回答、聯繫校友中、已回答
create function alumni_can_see(qid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select is_approved() and exists (
    select 1 from alumni_questions q where q.id = qid
      and (q.author_id = auth.uid() or q.status in ('open', 'contacting', 'answered') or alumni_is_staff()));
$$;

alter table alumni_staff           enable row level security;
alter table alumni_categories      enable row level security;
alter table alumni_questions       enable row level security;
alter table alumni_answers         enable row level security;
alter table alumni_metoo           enable row level security;
alter table alumni_helpful         enable row level security;
alter table alumni_change_requests enable row level security;
alter table alumni_notifications   enable row level security;

-- 只開讀取規則；新增、修改、刪除都要透過下面的函數
create policy "校友工作部可看名單" on alumni_staff for select using (alumni_is_staff() or is_admin());
create policy "已審核同學可看分類" on alumni_categories for select using (is_approved());
create policy "看得到的問題" on alumni_questions for select using (alumni_can_see(id));
create policy "看得到問題的代答" on alumni_answers for select using (alumni_can_see(question_id));
create policy "看自己的我也想問" on alumni_metoo for select using (user_id = auth.uid());
create policy "看自己的有幫助" on alumni_helpful for select using (user_id = auth.uid());
create policy "申請人本人或校友工作部" on alumni_change_requests for select
  using (requester = auth.uid() or alumni_is_staff());
create policy "看自己的通知" on alumni_notifications for select using (user_id = auth.uid());

-------------------------------------------------------------------------------
-- 4. 讀取用的視圖
-------------------------------------------------------------------------------

-- 問題牆、問題詳情。視圖以建立者身份執行（繞過 RLS），所以條件寫在 where 裡。
-- 提問者姓名：不匿名時大家看得到；匿名時只有校友工作部看得到。學號只給校友工作部。
create view alumni_question_feed as
select q.id, q.category_id, c.name as category_name, q.title, q.body, q.wish, q.anonymous,
       q.status, q.status_note, q.published_at, q.edited_at, q.created_at,
       q.author_id = auth.uid() as is_mine,
       case when not q.anonymous or q.author_id = auth.uid() or alumni_is_staff() then p.full_name end as author_name,
       case when alumni_is_staff() then p.student_id end as author_student_id,
       (select count(*) from alumni_metoo m where m.question_id = q.id)::int as metoo_count,
       exists (select 1 from alumni_metoo m where m.question_id = q.id and m.user_id = auth.uid()) as metoo_mine,
       (select count(*) from alumni_answers a where a.question_id = q.id)::int as answer_count,
       (select r.kind from alumni_change_requests r where r.question_id = q.id and r.status = 'pending') as pending_request
from alumni_questions q
join alumni_categories c on c.id = q.category_id
join profiles p on p.id = q.author_id
where is_approved()
  and (q.author_id = auth.uid() or q.status in ('open', 'contacting', 'answered') or alumni_is_staff());

-- 代答，附有幫助人數。發布的人只有校友工作部看得到
create view alumni_answer_feed as
select a.id, a.question_id, a.cohort, a.affiliation, a.alumni_name, a.body, a.created_at, a.updated_at,
       case when alumni_is_staff() then a.poster_name end as poster_name,
       (select count(*) from alumni_helpful h where h.answer_id = a.id)::int as helpful_count,
       exists (select 1 from alumni_helpful h where h.answer_id = a.id and h.user_id = auth.uid()) as helpful_mine
from alumni_answers a
where alumni_can_see(a.question_id);

revoke all on alumni_question_feed, alumni_answer_feed from anon;
grant select on alumni_question_feed, alumni_answer_feed to authenticated;

-------------------------------------------------------------------------------
-- 5. 同學的操作
-------------------------------------------------------------------------------

create function alumni_notify(p_user uuid, p_question bigint, p_message text) returns void
language sql security definer set search_path = public as $$
  insert into alumni_notifications (user_id, question_id, message) values (p_user, p_question, p_message);
$$;

-- 檢查並整理提問表單；p 是 {category_id, title, body, wish, anonymous}
create function alumni_check_form(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cat bigint := nullif(p->>'category_id', '')::bigint;
begin
  if btrim(coalesce(p->>'title', '')) = '' then raise exception '請填標題'; end if;
  if btrim(coalesce(p->>'body', '')) = '' then raise exception '請填問題內容'; end if;
  if char_length(btrim(p->>'title')) > 60 then raise exception '標題最多 60 字'; end if;
  if char_length(btrim(p->>'body')) > 3000 then raise exception '問題內容最多 3000 字'; end if;
  if char_length(btrim(coalesce(p->>'wish', ''))) > 60 then raise exception '「希望哪類校友回答」最多 60 字'; end if;
  if not exists (select 1 from alumni_categories where id = cat and active) then raise exception '請選分類'; end if;
  return jsonb_build_object('category_id', cat, 'title', btrim(p->>'title'), 'body', btrim(p->>'body'),
                            'wish', btrim(coalesce(p->>'wish', '')), 'anonymous', coalesce((p->>'anonymous')::boolean, true));
end $$;

-- 提問。送出後是「未公開」，等校友工作部公開
create function alumni_ask(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  f jsonb;
  qid bigint;
begin
  if not is_approved() then raise exception '校園卡審核通過後才能提問'; end if;
  f := alumni_check_form(p);
  insert into alumni_questions (author_id, category_id, title, body, wish, anonymous)
  values (auth.uid(), (f->>'category_id')::bigint, f->>'title', f->>'body', f->>'wish', (f->>'anonymous')::boolean)
  returning id into qid;
  return qid;
end $$;

-- 改或刪自己的問題。還沒有代答時直接生效，回傳 'done'；
-- 已有代答時送出申請等校友工作部同意，回傳 'requested'。p 是新的表單內容（刪除時可以只放 reason）
create function alumni_change_my_question(p_id bigint, p_kind alumni_req_kind, p jsonb default '{}')
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
        wish = f->>'wish', anonymous = (f->>'anonymous')::boolean, edited_at = now()
      where id = p_id;
    end if;
    return 'done';
  end if;

  insert into alumni_change_requests (question_id, requester, kind, new_category_id, new_title, new_body,
                                      new_wish, new_anonymous, reason)
  values (p_id, auth.uid(), p_kind, (f->>'category_id')::bigint, f->>'title', f->>'body',
          f->>'wish', (f->>'anonymous')::boolean, left(btrim(coalesce(p->>'reason', '')), 200));
  return 'requested';
end $$;

create function alumni_withdraw_request(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update alumni_change_requests set status = 'withdrawn'
  where id = p_id and requester = auth.uid() and status = 'pending';
  if not found then raise exception '找不到這份申請，可能已經處理了'; end if;
end $$;

-- 我也想問：只有公開的問題能按，不能按自己的。回傳按完後是不是「想問」
create function alumni_toggle_metoo(p_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not is_approved() then raise exception '校園卡審核通過後才能按'; end if;
  if not exists (select 1 from alumni_questions where id = p_id
                 and status in ('open', 'contacting', 'answered') and author_id <> auth.uid()) then
    raise exception '這個問題現在不能按「我也想問」';
  end if;
  delete from alumni_metoo where question_id = p_id and user_id = auth.uid();
  if found then return false; end if;
  insert into alumni_metoo (question_id, user_id) values (p_id, auth.uid());
  return true;
end $$;

-- 有幫助
create function alumni_toggle_helpful(p_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  qid bigint;
begin
  select question_id into qid from alumni_answers where id = p_id;
  if qid is null or not alumni_can_see(qid) then raise exception '找不到這則回答'; end if;
  delete from alumni_helpful where answer_id = p_id and user_id = auth.uid();
  if found then return false; end if;
  insert into alumni_helpful (answer_id, user_id) values (p_id, auth.uid());
  return true;
end $$;

create function alumni_mark_read(p_id bigint default null) returns void
language sql security definer set search_path = public as $$
  update alumni_notifications set read = true
  where user_id = auth.uid() and not read and (p_id is null or id = p_id);
$$;

-------------------------------------------------------------------------------
-- 6. 校友工作部的操作
-------------------------------------------------------------------------------

create function alumni_status_label(s alumni_q_status) returns text
language sql immutable as $$
  select case s when 'hidden' then '未公開' when 'open' then '待回答' when 'contacting' then '聯繫校友中'
                when 'answered' then '已回答' else '暫無法回答' end;
$$;

-- 改狀態。p_note 是暫無法回答的原因（選填），改成其他狀態時清掉
create function alumni_set_status(p_id bigint, p_status alumni_q_status, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  q alumni_questions;
  note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not alumni_is_staff() then raise exception '只有校友工作部可以改狀態'; end if;
  select * into q from alumni_questions where id = p_id for update;
  if q.id is null then raise exception '找不到這個問題'; end if;
  if p_status <> 'unable' then note := null; end if;
  if char_length(note) > 200 then raise exception '原因最多 200 字'; end if;
  if q.status = p_status and q.status_note is not distinct from note then return; end if;
  update alumni_questions set status = p_status, status_note = note,
    published_at = case when p_status in ('open', 'contacting', 'answered') then coalesce(published_at, now()) else published_at end
  where id = p_id;
  perform alumni_notify(q.author_id, p_id,
    case when q.status = 'hidden' and p_status in ('open', 'contacting', 'answered')
           then '你的問題「' || q.title || '」已公開，狀態：' || alumni_status_label(p_status)
         else '你的問題「' || q.title || '」狀態改為：' || alumni_status_label(p_status) end
    || coalesce('。原因：' || note, ''));
end $$;

-- 新增或修改代答。p_id 空的是新增；p 是 {cohort, affiliation, alumni_name, body}。
-- 新增後問題自動變成「已回答」並通知提問者。回傳代答 id
create function alumni_save_answer(p_question bigint, p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  q alumni_questions;
  aid bigint;
  yr int := nullif(p->>'cohort', '')::int;
  aff text := btrim(coalesce(p->>'affiliation', ''));
  nm text := nullif(btrim(coalesce(p->>'alumni_name', '')), '');
  txt text := btrim(coalesce(p->>'body', ''));
begin
  if not alumni_is_staff() then raise exception '只有校友工作部可以代答'; end if;
  select * into q from alumni_questions where id = p_question for update;
  if q.id is null then raise exception '找不到這個問題'; end if;
  if yr is null or yr < 1950 or yr > 2100 then raise exception '請填校友的屆別（畢業年份，例如 2019）'; end if;
  if aff = '' then raise exception '請填校友的大學或工作單位'; end if;
  if char_length(aff) > 60 then raise exception '大學或工作單位最多 60 字'; end if;
  if char_length(nm) > 30 then raise exception '校友姓名最多 30 字'; end if;
  if txt = '' then raise exception '請填回答內容'; end if;
  if char_length(txt) > 5000 then raise exception '回答內容最多 5000 字'; end if;

  if p_id is null then
    insert into alumni_answers (question_id, cohort, affiliation, alumni_name, body, posted_by, poster_name)
    values (p_question, yr, aff, nm, txt, auth.uid(), (select full_name from profiles where id = auth.uid()))
    returning id into aid;
    update alumni_questions set status = 'answered', status_note = null, published_at = coalesce(published_at, now())
    where id = p_question;
    perform alumni_notify(q.author_id, p_question, '你的問題「' || q.title || '」有新的校友回答');
  else
    update alumni_answers set cohort = yr, affiliation = aff, alumni_name = nm, body = txt, updated_at = now()
    where id = p_id and question_id = p_question
    returning id into aid;
    if aid is null then raise exception '找不到這則回答'; end if;
  end if;
  return aid;
end $$;

-- 刪除代答。刪到一則都不剩、問題還是「已回答」時，改回「待回答」
create function alumni_delete_answer(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  qid bigint;
begin
  if not alumni_is_staff() then raise exception '只有校友工作部可以刪除回答'; end if;
  delete from alumni_answers where id = p_id returning question_id into qid;
  if qid is null then raise exception '找不到這則回答'; end if;
  update alumni_questions set status = 'open'
  where id = qid and status = 'answered' and not exists (select 1 from alumni_answers where question_id = qid);
end $$;

-- 校友工作部直接刪除問題（例如廣告、重複的問題），會通知提問者
create function alumni_staff_delete_question(p_id bigint, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  q alumni_questions;
begin
  if not alumni_is_staff() then raise exception '只有校友工作部可以刪除問題'; end if;
  delete from alumni_questions where id = p_id returning * into q;
  if q.id is null then raise exception '找不到這個問題'; end if;
  perform alumni_notify(q.author_id, null, '你的問題「' || q.title || '」已被校友工作部刪除'
    || coalesce('。原因：' || nullif(btrim(p_reason), ''), ''));
end $$;

-- 同意或退回修改、刪除申請，結果通知申請人
create function alumni_review_request(p_id bigint, p_approve boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  r alumni_change_requests;
  q alumni_questions;
  what text;
begin
  if not alumni_is_staff() then raise exception '只有校友工作部可以處理申請'; end if;
  select * into r from alumni_change_requests where id = p_id and status = 'pending' for update;
  if r.id is null then raise exception '找不到這份申請，可能已經處理了'; end if;
  select * into q from alumni_questions where id = r.question_id;
  what := case r.kind when 'edit' then '修改' else '刪除' end;

  update alumni_change_requests set status = case when p_approve then 'approved' else 'rejected' end::alumni_req_status,
    reviewed_by = auth.uid(), reviewer_name = (select full_name from profiles where id = auth.uid()),
    reject_reason = case when p_approve then null else left(nullif(btrim(p_reason), ''), 200) end,
    reviewed_at = now()
  where id = p_id;

  if p_approve then
    if r.kind = 'delete' then
      delete from alumni_questions where id = r.question_id;
    else
      if not exists (select 1 from alumni_categories where id = r.new_category_id and active) then
        raise exception '申請裡的分類已停用，請退回讓同學重新選';
      end if;
      update alumni_questions set category_id = r.new_category_id, title = r.new_title, body = r.new_body,
        wish = r.new_wish, anonymous = r.new_anonymous, edited_at = now()
      where id = r.question_id;
    end if;
  end if;

  perform alumni_notify(r.requester, case when p_approve and r.kind = 'delete' then null else r.question_id end,
    '你對「' || q.title || '」的' || what || '申請' || case when p_approve then '已通過' else '被退回' end
    || coalesce('。原因：' || case when p_approve then null else nullif(btrim(p_reason), '') end, ''));
end $$;

-- 分類：p_id 空的是新增
create function alumni_save_category(p_id bigint, p_name text, p_sort int default 0, p_active boolean default true)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  cid bigint;
  nm text := btrim(coalesce(p_name, ''));
begin
  if not alumni_is_staff() then raise exception '只有校友工作部可以管理分類'; end if;
  if nm = '' or char_length(nm) > 20 then raise exception '分類名稱要 1～20 字'; end if;
  if exists (select 1 from alumni_categories where name = nm and id is distinct from p_id) then
    raise exception '已經有同名的分類';
  end if;
  if p_id is null then
    insert into alumni_categories (name, sort, active) values (nm, coalesce(p_sort, 0), coalesce(p_active, true))
    returning id into cid;
  else
    update alumni_categories set name = nm, sort = coalesce(p_sort, 0), active = coalesce(p_active, true)
    where id = p_id returning id into cid;
    if cid is null then raise exception '找不到這個分類'; end if;
  end if;
  if not exists (select 1 from alumni_categories where active) then raise exception '至少要留一個啟用的分類'; end if;
  return cid;
end $$;

create function alumni_staff_list()
returns table (user_id uuid, full_name text, student_id text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (alumni_is_staff() or is_admin()) then raise exception '只有校友工作部可以看'; end if;
  return query select s.user_id, p.full_name, p.student_id, s.created_at
  from alumni_staff s join profiles p on p.id = s.user_id order by s.created_at;
end $$;

-- 加人：校友工作部成員或權益牆的最高管理員（第一位由最高管理員加）
create function alumni_add_staff(p_student_id text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid;
begin
  if not (alumni_is_staff() or is_admin()) then raise exception '只有校友工作部可以加人'; end if;
  select id into uid from profiles where student_id = btrim(p_student_id) and verify_status = 'approved';
  if uid is null then raise exception '找不到這個學號，或校園卡還沒通過審核'; end if;
  insert into alumni_staff (user_id, added_by) values (uid, auth.uid()) on conflict do nothing;
end $$;

create function alumni_remove_staff(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (alumni_is_staff() or is_admin()) then raise exception '只有校友工作部可以移除成員'; end if;
  if (select count(*) from alumni_staff) <= 1 then raise exception '至少要留一位校友工作部成員'; end if;
  delete from alumni_staff where user_id = p_user;
end $$;

-- 內部用，不給前端直接呼叫
revoke execute on function alumni_notify(uuid, bigint, text) from public, anon, authenticated;
revoke execute on function alumni_check_form(jsonb) from public, anon, authenticated;
