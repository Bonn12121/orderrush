-- Run against a disposable database or within a transaction; this script rolls back.
begin;
do $$
declare u1 uuid:=gen_random_uuid();u2 uuid:=gen_random_uuid();cid uuid;ord uuid[];wrong uuid[];a jsonb;b jsonb;n integer;
begin
 insert into auth.users(instance_id,id,aud,role,created_at,updated_at) values
 ('00000000-0000-0000-0000-000000000000',u1,'authenticated','authenticated',now(),now()),
 ('00000000-0000-0000-0000-000000000000',u2,'authenticated','authenticated',now(),now());
 select id into cid from public.challenges where status='active';
 select array_agg(item_id order by correct_position) into ord from public.challenge_answers where challenge_id=cid;
 wrong:=array[ord[2],ord[1],ord[3],ord[4]];
 perform set_config('request.jwt.claim.sub',u1::text,true);
 perform public.join_game('Same Name');
 update public.player_challenge_sessions set started_at=now()-interval '5 seconds' where player_id=u1 and challenge_id=cid;
 a:=public.submit_order(cid,ord);
 if (a->>'is_correct')::boolean is not true or (a->>'score')::integer<1000 then raise exception 'Correct scoring failed: %',a;end if;
 begin
  perform public.submit_order(cid,ord);
  raise exception 'Duplicate submission accepted';
 exception when others then if sqlerrm='Duplicate submission accepted' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',u2::text,true);
 perform public.join_game('Same Name');
 update public.player_challenge_sessions set started_at=now()-interval '5 seconds' where player_id=u2 and challenge_id=cid;
 b:=public.submit_order(cid,wrong);
 if (b->>'is_correct')::boolean is not false or (b->>'score')::integer<>0 then raise exception 'Incorrect scoring failed: %',b;end if;
 select count(*) into n from public.submissions where challenge_id=cid and player_id in(u1,u2);
 if n<>2 then raise exception 'Distinct players with same name were not retained';end if;
 raise notice 'PASS: correct scoring, incorrect scoring, duplicate rejection, distinct player identity';
end$$;
rollback;
