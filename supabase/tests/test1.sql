\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- 學號：20240101 校友工作部、20240102 提問者、20240103～04 一般同學、20240106 未審核、20220202 權益牆超級管理員
insert into auth.users (email, raw_user_meta_data) select s||'@x.com', jsonb_build_object('full_name','U'||s,'student_id',s)
from unnest(array['20240101','20240102','20240103','20240104','20240106','20220202']) s;
update profiles set verify_status='approved' where student_id <> '20240106';
update profiles set role='admin' where student_id='20220202';
create function pg_temp.who(sid text) returns text language sql security definer as $$ select set_config('request.jwt.claim.sub', coalesce((select id::text from profiles where student_id=sid), ''), false) $$;
grant execute on function pg_temp.who(text) to anon, authenticated;
create function pg_temp.uid(sid text) returns uuid language sql security definer as $$ select id from profiles where student_id=sid $$;
grant execute on function pg_temp.uid(text) to anon, authenticated;
create function pg_temp.fails(q text) returns text language plpgsql as $$ begin execute q; return 'NOT FAILED: ' || q; exception when others then return 'ok: ' || sqlerrm; end $$;
grant execute on function pg_temp.fails(text) to anon, authenticated;
set role authenticated;

\echo '--- 一般同學不能加校友工作部；超級管理員加第一位'
select pg_temp.who('20240103'), pg_temp.fails($$select alumni_add_staff('20240101')$$);
select pg_temp.who('20220202'), alumni_add_staff('20240101');
select pg_temp.who('20240101'), alumni_is_staff();

\echo '--- 分類：只有校友工作部能加；新增「升學與選科」'
select pg_temp.who('20240103'), pg_temp.fails($$select alumni_save_category(null, '升學')$$);
select pg_temp.who('20240101'), alumni_save_category(null, '升學與選科', 1) > 0;
select pg_temp.fails($$select alumni_save_category(null, '其它')$$);

\echo '--- 提問：未審核不能問；欄位不全會擋；送出後是未公開'
select pg_temp.who('20240106'), pg_temp.fails($$select alumni_ask('{"title":"a","body":"b","category_id":1}')$$);
select pg_temp.who('20240102');
select pg_temp.fails($$select alumni_ask('{"title":"","body":"b","category_id":1}')$$);
select pg_temp.fails($$select alumni_ask('{"title":"a","body":"b","category_id":999}')$$);
select alumni_ask('{"title":"理科生選專業","body":"計算機還是生物？","wish":"讀計算機的","category_id":2}') as q1;
select alumni_ask('{"title":"不匿名的問題","body":"內容","category_id":1,"anonymous":false}') as q2;
select id, status, anonymous from alumni_questions order by id;

\echo '--- 未公開：其他同學看不到，提問者和校友工作部看得到；匿名者姓名只有校友工作部看得到'
select pg_temp.who('20240103'), (select count(*) from alumni_question_feed), (select count(*) from alumni_questions);
select pg_temp.who('20240102'), (select string_agg(id || ':' || coalesce(author_name, '-') || ':' || is_mine, ' ' order by id) from alumni_question_feed);
select pg_temp.who('20240101'), (select string_agg(id || ':' || coalesce(author_name, '-') || ':' || coalesce(author_student_id, '-'), ' ' order by id) from alumni_question_feed);
select pg_temp.who('20240106'), (select count(*) from alumni_question_feed);
reset role; set role anon; select pg_temp.who(''), pg_temp.fails($$select count(*) from alumni_question_feed$$); reset role; set role authenticated;

\echo '--- 未公開的問題不能按我也想問'
select pg_temp.who('20240103'), pg_temp.fails($$select alumni_toggle_metoo(1)$$);

\echo '--- 一般同學不能改狀態；校友工作部公開 1、2'
select pg_temp.who('20240103'), pg_temp.fails($$select alumni_set_status(1, 'open')$$);
select pg_temp.who('20240101'), alumni_set_status(1, 'open'), alumni_set_status(2, 'contacting');
select pg_temp.who('20240103'), (select string_agg(id || ':' || status || ':' || coalesce(author_name, '-') || ':' || coalesce(author_student_id, '-'), ' ' order by id) from alumni_question_feed);

\echo '--- 我也想問：不能按自己的；別人按兩次是取消'
select pg_temp.who('20240102'), pg_temp.fails($$select alumni_toggle_metoo(1)$$);
select pg_temp.who('20240103'), alumni_toggle_metoo(1), alumni_toggle_metoo(1), alumni_toggle_metoo(1);
select pg_temp.who('20240104'), alumni_toggle_metoo(1);
select metoo_count, metoo_mine from alumni_question_feed where id = 1;

\echo '--- 還沒有代答：提問者直接修改，公開的問題退回未公開（reopened）'
select pg_temp.who('20240103'), pg_temp.fails($$select alumni_change_my_question(1, 'edit', '{"title":"x","body":"y","category_id":1}')$$);
select pg_temp.who('20240102'), alumni_change_my_question(1, 'edit', '{"title":"理科生怎麼選專業","body":"計算機還是生物？","wish":"","category_id":2,"anonymous":true}');
select title, status, edited_at is not null from alumni_questions where id = 1;

\echo '--- 原始表：其他同學讀不到任何問題（匿名者不能被反推），提問者和校友工作部讀得到'
select pg_temp.who('20240103'), (select count(*) from alumni_questions);
select pg_temp.who('20240102'), (select count(*) from alumni_questions);
select pg_temp.who('20240101'), (select count(*) from alumni_questions);

\echo '--- 代答：一般同學不能貼；屆別錯會擋；貼上後變已回答並通知提問者'
select pg_temp.who('20240103'), pg_temp.fails($$select alumni_save_answer(1, null, '{"cohort":2019,"affiliation":"某大學","body":"先看課表"}')$$);
select pg_temp.who('20240101');
select pg_temp.fails($$select alumni_save_answer(1, null, '{"cohort":19,"affiliation":"某大學","body":"先看課表"}')$$);
select alumni_save_answer(1, null, '{"cohort":2019,"affiliation":"某某大學","body":"先去兩個學院的開放日看看課表"}') as a1;
select alumni_save_answer(1, null, '{"cohort":2015,"affiliation":"某醫院","alumni_name":"王同學","body":"生物也很好"}') as a2;
select status from alumni_questions where id = 1;
select pg_temp.who('20240102'), (select string_agg(message, ' | ' order by id) from alumni_notifications);
select pg_temp.who('20240103'), (select string_agg(id || ':' || cohort || ':' || coalesce(poster_name, '-'), ' ' order by id) from alumni_answer_feed);
select pg_temp.who('20240101'), (select string_agg(id || ':' || coalesce(poster_name, '-'), ' ' order by id) from alumni_answer_feed);

\echo '--- 有幫助'
select pg_temp.who('20240103'), alumni_toggle_helpful(2), alumni_toggle_helpful(1), alumni_toggle_helpful(1);
select pg_temp.who('20240104'), alumni_toggle_helpful(2);
select string_agg(id || ':' || helpful_count || ':' || helpful_mine, ' ' order by helpful_count desc) from alumni_answer_feed;

\echo '--- 已有代答：修改要申請；同時只能一份；別人看不到申請'
select pg_temp.who('20240102'), alumni_change_my_question(1, 'edit', '{"title":"改過的標題","body":"新內容","wish":"","category_id":2,"anonymous":false,"reason":"寫錯了"}');
select pg_temp.fails($$select alumni_change_my_question(1, 'delete', '{}')$$);
select title from alumni_questions where id = 1;
select pending_request from alumni_question_feed where id = 1;
select pg_temp.who('20240103'), (select count(*) from alumni_change_requests);

\echo '--- 一般同學不能審；校友工作部同意後生效並通知'
select pg_temp.fails($$select alumni_review_request(1, true)$$);
select pg_temp.who('20240101'), alumni_review_request(1, true);
select title, anonymous from alumni_questions where id = 1;
select pg_temp.who('20240102'), (select message from alumni_notifications order by id desc limit 1);

\echo '--- 刪除申請：退回、撤回、再同意'
select alumni_change_my_question(1, 'delete', '{"reason":"不想問了"}');
select pg_temp.who('20240101'), alumni_review_request(2, false, '已經有校友回答了');
select pg_temp.who('20240102'), (select message from alumni_notifications order by id desc limit 1);
select alumni_change_my_question(1, 'delete', '{}');
select alumni_withdraw_request(3);
select status from alumni_change_requests order by id;
select alumni_change_my_question(1, 'delete', '{}');
select pg_temp.who('20240101'), alumni_review_request(4, true);
select count(*) from alumni_questions where id = 1;
select pg_temp.who('20240102'), (select message || ':' || coalesce(question_id::text, 'null') from alumni_notifications order by id desc limit 1);

\echo '--- 暫無法回答：只有提問者和校友工作部看得到，原因會通知'
select pg_temp.who('20240101'), alumni_set_status(2, 'unable', '暫時找不到合適的校友');
select pg_temp.who('20240103'), (select count(*) from alumni_question_feed where id = 2), (select count(*) from alumni_questions where id = 2);
select pg_temp.fails($$select alumni_toggle_metoo(2)$$);
select pg_temp.who('20240102'), (select status || ':' || status_note from alumni_question_feed where id = 2);
select (select message from alumni_notifications order by id desc limit 1);

\echo '--- 刪光代答後退回待回答'
select pg_temp.who('20240102'), alumni_ask('{"title":"第三題","body":"內容","category_id":1}') as q3;
select pg_temp.who('20240101'), alumni_save_answer(3, null, '{"cohort":2020,"affiliation":"A","body":"B"}') as a3;
select status, published_at is not null from alumni_questions where id = 3;
select alumni_save_answer(3, 3, '{"cohort":2021,"affiliation":"A2","body":"B2"}');
select cohort, affiliation, updated_at is not null from alumni_answers where id = 3;
select alumni_delete_answer(3);
select status from alumni_questions where id = 3;

\echo '--- 校友工作部直接刪問題'
select pg_temp.who('20240103'), pg_temp.fails($$select alumni_staff_delete_question(3)$$);
select pg_temp.who('20240101'), alumni_staff_delete_question(3, '重複的問題');
select pg_temp.who('20240102'), (select message from alumni_notifications order by id desc limit 1);

\echo '--- 停用分類：不能再選；不能全部停用'
select pg_temp.who('20240101'), alumni_save_category(2, '升學與選科', 1, false);
select pg_temp.fails($$select alumni_save_category(1, '其它', 100, false)$$);
select pg_temp.who('20240102'), pg_temp.fails($$select alumni_ask('{"title":"a","body":"b","category_id":2}')$$);

\echo '--- 通知：只看得到自己的，標為已讀'
select pg_temp.who('20240103'), (select count(*) from alumni_notifications);
select pg_temp.who('20240102'), (select count(*) from alumni_notifications where not read);
select alumni_mark_read();
select count(*) from alumni_notifications where not read;

\echo '--- 成員：不能移除最後一位；不能直接寫表'
select pg_temp.who('20240101'), pg_temp.fails($$select alumni_remove_staff(pg_temp.uid('20240101'))$$);
select alumni_add_staff('20240103');
select count(*) from alumni_staff_list();
select alumni_remove_staff(pg_temp.uid('20240103'));
select count(*) from alumni_staff_list();
select pg_temp.who('20240102'), pg_temp.fails($$insert into alumni_questions (author_id, category_id, title, body) values (auth.uid(), 1, 'x', 'y')$$);
-- 沒有 update 規則：直接改表不會報錯，但一筆都改不到
update alumni_questions set status = 'answered';
select count(*) from alumni_questions where status = 'answered';
select pg_temp.fails($$select alumni_notify(auth.uid(), null, 'x')$$);
