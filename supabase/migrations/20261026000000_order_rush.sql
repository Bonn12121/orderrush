create extension if not exists pgcrypto;
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,display_name text not null check(char_length(display_name) between 1 and 30),created_at timestamptz not null default now(),last_seen_at timestamptz not null default now());
create table public.challenges(id uuid primary key default gen_random_uuid(),title text not null,description text not null default '',status text not null default 'draft' check(status in ('draft','published','active','archived')),created_at timestamptz not null default now(),activated_at timestamptz);
create unique index one_active_challenge on public.challenges(status) where status='active';
create table public.challenge_items(id uuid primary key default gen_random_uuid(),challenge_id uuid not null references public.challenges(id) on delete cascade,label text not null,content text not null,unique(id,challenge_id));
create table public.challenge_answers(challenge_id uuid not null references public.challenges(id) on delete cascade,item_id uuid not null,correct_position integer not null check(correct_position>0),primary key(challenge_id,item_id),unique(challenge_id,correct_position),foreign key(item_id,challenge_id) references public.challenge_items(id,challenge_id) on delete cascade);
create table public.player_challenge_sessions(id uuid primary key default gen_random_uuid(),challenge_id uuid not null references public.challenges(id),player_id uuid not null references auth.users(id),started_at timestamptz not null default now(),unique(challenge_id,player_id));
create table public.submissions(id uuid primary key default gen_random_uuid(),challenge_id uuid not null references public.challenges(id),player_id uuid not null references auth.users(id),submitted_order jsonb not null,is_correct boolean not null,score integer not null check(score between 0 and 1500),completion_ms integer not null check(completion_ms>=0),submitted_at timestamptz not null default now(),unique(challenge_id,player_id));
create table public.admin_users(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create table public.leaderboard_events(id bigint generated always as identity primary key,challenge_id uuid not null references public.challenges(id),created_at timestamptz not null default now());
create index submissions_rank_idx on public.submissions(challenge_id,score desc,completion_ms,submitted_at);
create index sessions_challenge_idx on public.player_challenge_sessions(challenge_id);
alter table public.profiles enable row level security;
alter table public.challenges enable row level security;
alter table public.challenge_items enable row level security;
alter table public.challenge_answers enable row level security;
alter table public.player_challenge_sessions enable row level security;
alter table public.submissions enable row level security;
alter table public.admin_users enable row level security;
alter table public.leaderboard_events enable row level security;
revoke all on all tables in schema public from anon,authenticated;
grant select on public.challenges,public.challenge_items,public.challenge_answers to authenticated;
grant select on public.profiles,public.player_challenge_sessions,public.submissions,public.admin_users to authenticated;
grant select on public.leaderboard_events to authenticated;
grant insert,update,delete on public.challenges,public.challenge_items,public.challenge_answers to authenticated;
create policy challenge_read on public.challenges for select to authenticated using(status in ('active','published') or exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create policy item_read on public.challenge_items for select to authenticated using(exists(select 1 from public.challenges c where c.id=challenge_id and (c.status in ('active','published') or exists(select 1 from public.admin_users where user_id=(select auth.uid())))));
create policy profile_self on public.profiles for select to authenticated using(id=(select auth.uid()) or exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create policy session_self on public.player_challenge_sessions for select to authenticated using(player_id=(select auth.uid()) or exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create policy submission_self on public.submissions for select to authenticated using(player_id=(select auth.uid()) or exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create policy admin_self on public.admin_users for select to authenticated using(user_id=(select auth.uid()));
create policy event_read on public.leaderboard_events for select to authenticated using(true);
create policy admin_challenge_write on public.challenges for all to authenticated using(exists(select 1 from public.admin_users where user_id=(select auth.uid()))) with check(exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create policy admin_item_write on public.challenge_items for all to authenticated using(exists(select 1 from public.admin_users where user_id=(select auth.uid()))) with check(exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create policy admin_answer_write on public.challenge_answers for all to authenticated using(exists(select 1 from public.admin_users where user_id=(select auth.uid()))) with check(exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create policy admin_answer_read on public.challenge_answers for select to authenticated using(exists(select 1 from public.admin_users where user_id=(select auth.uid())));
create or replace function public.join_game(p_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_challenge public.challenges;v_session public.player_challenge_sessions;
begin
 if v_user is null then raise exception 'Sign in first';end if;
 p_name:=trim(regexp_replace(p_name,'[[:cntrl:]]','','g'));
 if char_length(p_name)<1 or char_length(p_name)>30 then raise exception 'Name must be 1–30 characters';end if;
 select * into v_challenge from public.challenges where status='active' limit 1;
 if v_challenge.id is null then raise exception 'No active challenge';end if;
 insert into public.profiles(id,display_name) values(v_user,p_name) on conflict(id) do update set display_name=excluded.display_name,last_seen_at=now();
 insert into public.player_challenge_sessions(challenge_id,player_id) values(v_challenge.id,v_user) on conflict(challenge_id,player_id) do nothing;
 select * into v_session from public.player_challenge_sessions where challenge_id=v_challenge.id and player_id=v_user;
 return jsonb_build_object('challenge_id',v_challenge.id,'started_at',v_session.started_at);
end$$;
create function public.my_result(p_challenge uuid) returns jsonb language sql security definer set search_path='' as $$ select null::jsonb $$;
create or replace function public.submit_order(p_challenge uuid,p_order uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_started timestamptz;v_expected uuid[];v_ms integer;v_correct boolean;v_score integer;v_submission public.submissions;v_count integer;
begin
 if v_user is null then raise exception 'Sign in first';end if;
 if not exists(select 1 from public.challenges where id=p_challenge and status='active') then raise exception 'Challenge is not active';end if;
 select started_at into v_started from public.player_challenge_sessions where challenge_id=p_challenge and player_id=v_user for update;
 if v_started is null then raise exception 'Start the challenge first';end if;
 if exists(select 1 from public.submissions where challenge_id=p_challenge and player_id=v_user) then raise exception 'Already submitted';end if;
 if now()-v_started<interval '1 second' then raise exception 'Please take a moment to order the cards';end if;
 select array_agg(item_id order by correct_position) into v_expected from public.challenge_answers where challenge_id=p_challenge;
 v_count:=coalesce(array_length(v_expected,1),0);
 if v_count<2 or coalesce(array_length(p_order,1),0)<>v_count or (select count(distinct x) from unnest(p_order) x)<>v_count then raise exception 'Invalid item order';end if;
 if exists(select 1 from unnest(p_order) x where not exists(select 1 from public.challenge_items i where i.challenge_id=p_challenge and i.id=x)) then raise exception 'Invalid item order';end if;
 v_ms:=least(2147483647,greatest(0,floor(extract(epoch from (now()-v_started))*1000)::bigint))::integer;
 v_correct:=p_order=v_expected;
 v_score:=case when v_correct then 1000+greatest(0,500-ceil(v_ms/100.0)::integer) else 0 end;
 insert into public.submissions(challenge_id,player_id,submitted_order,is_correct,score,completion_ms) values(p_challenge,v_user,to_jsonb(p_order),v_correct,v_score,v_ms) returning * into v_submission;
 return public.my_result(p_challenge);
end$$;
create or replace function public.my_result(p_challenge uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_result jsonb;
begin
 if v_user is null then raise exception 'Sign in first';end if;
 if not exists(select 1 from public.submissions where challenge_id=p_challenge and player_id=v_user) then return null;end if;
 select jsonb_build_object('is_correct',s.is_correct,'score',s.score,'completion_ms',s.completion_ms,'rank',r.rank,'participants',(select count(*) from public.player_challenge_sessions where challenge_id=p_challenge),'correct_percent',(select coalesce(round(100.0*count(*) filter(where is_correct)/nullif(count(*),0)),0) from public.submissions where challenge_id=p_challenge),'correct_order',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'label',i.label,'content',i.content) order by a.correct_position),'[]'::jsonb) from public.challenge_answers a join public.challenge_items i on i.id=a.item_id where a.challenge_id=p_challenge)) into v_result
 from public.submissions s join (select player_id,row_number() over(order by score desc,completion_ms,submitted_at)::integer as rank from public.submissions where challenge_id=p_challenge) r on r.player_id=s.player_id where s.challenge_id=p_challenge and s.player_id=v_user;
 return v_result;
end$$;
create or replace function public.live_leaderboard(p_challenge uuid) returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('player_id',q.player_id,'display_name',q.display_name,'score',q.score,'completion_ms',q.completion_ms,'submitted_at',q.submitted_at,'status',q.status,'rank',q.rank) order by q.rank),'[]'::jsonb)
 from (select ps.player_id,p.display_name,coalesce(s.score,0) as score,s.completion_ms,s.submitted_at,case when s.id is null then 'playing' else 'submitted' end as status,row_number() over(order by (s.id is null),s.score desc nulls last,s.completion_ms nulls last,s.submitted_at nulls last,ps.started_at)::integer as rank from public.player_challenge_sessions ps join public.profiles p on p.id=ps.player_id left join public.submissions s on s.challenge_id=ps.challenge_id and s.player_id=ps.player_id where ps.challenge_id=p_challenge and exists(select 1 from public.challenges c where c.id=p_challenge and c.status in ('active','published'))) q;
$$;
create or replace function public.activate_challenge(p_challenge uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception 'Admin only';end if;
 if not exists(select 1 from public.challenges where id=p_challenge and status='published') then raise exception 'Publish the challenge first';end if;
 if (select count(*) from public.challenge_items where challenge_id=p_challenge)<2 or (select count(*) from public.challenge_items where challenge_id=p_challenge)<>(select count(*) from public.challenge_answers where challenge_id=p_challenge) then raise exception 'Every item needs a correct position';end if;
 update public.challenges set status='archived' where status='active';
 update public.challenges set status='active',activated_at=now() where id=p_challenge;
end$$;
create or replace function public.reset_challenge(p_challenge uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception 'Admin only';end if;
 delete from public.submissions where challenge_id=p_challenge;
 delete from public.player_challenge_sessions where challenge_id=p_challenge;
end$$;
create function public.announce_leaderboard() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.leaderboard_events(challenge_id) values(new.challenge_id);return new;end $$;
create trigger submission_announcement after insert on public.submissions for each row execute function public.announce_leaderboard();
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.join_game(text),public.submit_order(uuid,uuid[]),public.my_result(uuid),public.live_leaderboard(uuid),public.activate_challenge(uuid),public.reset_challenge(uuid) to authenticated;
alter publication supabase_realtime add table public.submissions;
alter publication supabase_realtime add table public.challenges;
alter publication supabase_realtime add table public.leaderboard_events;
insert into public.challenges(title,description,status,activated_at) values('Tìm kiếm thông tin trên Internet','Sắp xếp các bước đúng thứ tự để tìm thông tin nhanh và chính xác.','active',now());
insert into public.challenge_items(challenge_id,label,content) select c.id,v.label,v.content from public.challenges c cross join(values ('A','Truy cập vào máy tìm kiếm.'),('B','Gõ từ khóa vào ô tìm kiếm.'),('C','Xác định từ khóa.'),('D','Nháy chuột vào một siêu liên kết để mở trang web xem thông tin chi tiết.')) v(label,content) where c.status='active';
insert into public.challenge_answers(challenge_id,item_id,correct_position) select i.challenge_id,i.id,case i.label when 'C' then 1 when 'A' then 2 when 'B' then 3 else 4 end from public.challenge_items i join public.challenges c on c.id=i.challenge_id where c.status='active';
