
create or replace function public.egypt_guard_reconciled_invoice_value()
returns trigger language plpgsql security invoker set search_path='' as $$
declare entry_key text; value_changed boolean; matched boolean;
begin
 if tg_table_name='egypt_expenses' then
  entry_key:='expense:'||old.id::text;
  value_changed:=coalesce(nullif(new.payload->>'amount','')::numeric,0) is distinct from coalesce(nullif(old.payload->>'amount','')::numeric,0)
    or coalesce(nullif(new.payload->>'currency',''),'EGP') is distinct from coalesce(nullif(old.payload->>'currency',''),'EGP');
 else
  entry_key:='sales:'||old.invoice_number;
  value_changed:=new.amount is distinct from old.amount
    or coalesce(nullif(new.data->>'total','')::numeric,new.amount,0) is distinct from coalesce(nullif(old.data->>'total','')::numeric,old.amount,0)
    or coalesce(nullif(new.data->>'currency',''),'EGP') is distinct from coalesce(nullif(old.data->>'currency',''),'EGP');
 end if;
 if not value_changed then return new; end if;
 select exists(select 1 from public.egypt_bank_reconciliation_links where system_key=entry_key) into matched;
 if tg_table_name='egypt_expenses' then
  matched:=matched or exists(select 1 from public.egypt_expense_matches where expense_id=old.id);
 else
  matched:=matched or exists(
   select 1 from public.egypt_sales_payments p join public.egypt_bank_reconciliation_links l on l.system_key='salespayment:'||p.id::text
   where p.invoice_number=old.invoice_number);
 end if;
 if matched then
  raise exception using errcode='P0001',
   message='Invoice conciliada: desconcilie antes de alterar o valor ou a moeda.',
   hint='Cash Closing / Bank Reconciliation > localizar a conciliação > Desconciliar. Depois edite a invoice e concilie novamente.';
 end if;
 return new;
end $$;
create trigger egypt_lock_reconciled_invoice_value before update on public.egypt_expenses
for each row execute function public.egypt_guard_reconciled_invoice_value();
create trigger egypt_lock_reconciled_invoice_value before update on public.egypt_sales_invoices
for each row execute function public.egypt_guard_reconciled_invoice_value();
