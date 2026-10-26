alter table public.leaderboard_events add column kind text not null default 'submission'
  check(kind in ('submission','join','reset','replay'));
grant select on public.leaderboard_events to anon;
drop policy event_read on public.leaderboard_events;
create policy event_read on public.leaderboard_events for select to anon,authenticated using(true);

create function public.announce_join() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.leaderboard_events(challenge_id,kind) values(new.challenge_id,'join');
 return new;
end$$;
create trigger session_announcement after insert on public.player_challenge_sessions
for each row execute function public.announce_join();

create or replace function public.reset_challenge(p_challenge uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.admin_users where user_id=auth.uid()) then
  raise exception 'Admin only';
 end if;
 delete from public.submissions where challenge_id=p_challenge;
 delete from public.player_challenge_sessions where challenge_id=p_challenge;
 insert into public.leaderboard_events(challenge_id,kind) values(p_challenge,'reset');
end$$;

create function public.admin_live_players(p_challenge uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.admin_users where user_id=auth.uid()) then
  raise exception 'Admin only';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'player_id',ps.player_id,
  'display_name',p.display_name,
  'started_at',ps.started_at,
  'status',case when s.id is null then 'playing' else 'submitted' end,
  'score',coalesce(s.score,0),
  'completion_ms',s.completion_ms,
  'is_correct',s.is_correct
 ) order by ps.started_at desc),'[]'::jsonb) into v_result
 from public.player_challenge_sessions ps
 join public.profiles p on p.id=ps.player_id
 left join public.submissions s on s.challenge_id=ps.challenge_id and s.player_id=ps.player_id
 where ps.challenge_id=p_challenge;
 return v_result;
end$$;

create function public.replay_as_admin(p_challenge uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.admin_users where user_id=auth.uid()) then
  raise exception 'Admin only';
 end if;
 if not exists(select 1 from public.challenges where id=p_challenge and status='active') then
  raise exception 'Challenge is not active';
 end if;
 delete from public.submissions where challenge_id=p_challenge and player_id=auth.uid();
 delete from public.player_challenge_sessions where challenge_id=p_challenge and player_id=auth.uid();
 perform public.join_game('admin');
 insert into public.leaderboard_events(challenge_id,kind) values(p_challenge,'replay');
end$$;

revoke execute on function public.announce_join() from public,anon,authenticated;
revoke execute on function public.admin_live_players(uuid),public.replay_as_admin(uuid) from public,anon,authenticated;
grant execute on function public.admin_live_players(uuid),public.replay_as_admin(uuid) to authenticated;
