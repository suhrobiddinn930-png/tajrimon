create or replace function public.get_allowance(p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare sub public.subscriptions; used bigint; quota integer; effective_plan text; cost numeric;
begin
 select * into sub from public.subscriptions where user_id=p_user;
 effective_plan := case when sub.status='active' and (sub.plan='free' or sub.current_period_end>now()) then sub.plan else 'free' end;
 quota := case effective_plan when 'business' then 36000 when 'pro' then 7200 else 600 end;
 select coalesce(sum(duration_seconds),0),coalesce(sum(estimated_cost),0) into used,cost
 from public.usage_records where user_id=p_user
 and created_at>=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
 return jsonb_build_object('plan',effective_plan,'status',sub.status,'used_seconds',used,
 'limit_seconds',quota,'remaining_seconds',greatest(0,quota-used),'estimated_cost_usd',cost,
 'billing_available',false,'period','UTC calendar month');
end $$;
revoke all on function public.get_allowance(uuid) from public,anon,authenticated;
grant execute on function public.get_allowance(uuid) to service_role;
