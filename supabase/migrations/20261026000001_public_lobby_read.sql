-- Visitors need the active question and leaderboard before anonymous sign-in.
-- Answer keys and submissions remain protected.
grant select on public.challenges,public.challenge_items to anon;
drop policy challenge_read on public.challenges;
create policy challenge_read on public.challenges for select to anon,authenticated
using(status in ('active','published'));
drop policy item_read on public.challenge_items;
create policy item_read on public.challenge_items for select to anon,authenticated
using(exists(select 1 from public.challenges c where c.id=challenge_id and c.status in ('active','published')));
grant execute on function public.live_leaderboard(uuid) to anon;
