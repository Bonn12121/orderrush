create function public.replay_challenge(p_challenge uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_session public.player_challenge_sessions%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if not exists(select 1 from public.challenges where id=p_challenge and status='active') then
  raise exception 'Challenge is not active';
 end if;
 select * into v_session from public.player_challenge_sessions
 where challenge_id=p_challenge and player_id=auth.uid() for update;
 if not found then raise exception 'Join the game first'; end if;
 delete from public.submissions where challenge_id=p_challenge and player_id=auth.uid();
 update public.player_challenge_sessions set started_at=clock_timestamp()
 where challenge_id=p_challenge and player_id=auth.uid();
 insert into public.leaderboard_events(challenge_id,kind) values(p_challenge,'replay');
end$$;

revoke execute on function public.replay_challenge(uuid) from public,anon,authenticated;
grant execute on function public.replay_challenge(uuid) to authenticated;
drop function public.replay_as_admin(uuid);
