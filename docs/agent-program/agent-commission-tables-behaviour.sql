-- Behaviour tests for 20261029110000_agent_commission_tables (+ the seed).
-- Everything runs in one transaction that is rolled back. Fake data only.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE results (n serial, name text, expected text, got text, ok boolean);

-- expect: 'ok' or a SQLSTATE
CREATE FUNCTION pg_temp.t(p_name text, p_sql text, p_expected text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_got text := 'ok';
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v_got := SQLSTATE;
  END;
  INSERT INTO results(name, expected, got, ok) VALUES (p_name, p_expected, v_got, v_got = p_expected);
END $f$;

-- Setup (fake values only)
INSERT INTO agents (id, phone, phone_hash, name, city, state, status, updated_at)
VALUES ('a1','+919000000001','h1','Ravi','Madurai','TN','ACTIVE', now()),
       ('a2','+919000000002','h2','Mala','Madurai','TN','ACTIVE', now());
INSERT INTO referral_attributions (id, phone_hash, agent_id, source, window_ends_at, updated_at)
VALUES ('at1','mh1','a1','CODE_AT_SIGNUP', now(), now()),
       ('at2','mh2','a1','CODE_AT_SIGNUP', now(), now()),
       ('at3','mh3','a1','CODE_AT_SIGNUP', now(), now()),
       ('at4','mh4','a1','CODE_AT_SIGNUP', now(), now()),
       ('at5','mh5','a1','CODE_AT_SIGNUP', now(), now());

-- Seed (the second migration)
SELECT pg_temp.t('seed: policy v1 exists (PERCENTAGE 1000 bps, 14 days)',
  $$SELECT 1/(SELECT count(*)::int FROM commission_policy_versions WHERE version=1 AND calc_type='PERCENTAGE' AND value=1000 AND hold_days=14)$$, 'ok');
SELECT pg_temp.t('seed: exactly one policy row', $$SELECT 1/(SELECT (count(*)=1)::int FROM commission_policy_versions)$$, 'ok');

-- Policy versions
SELECT pg_temp.t('policy: v2 valid (control)', $$INSERT INTO commission_policy_versions (id,version,calc_type,value,hold_days,effective_from) VALUES ('p2',2,'PERCENTAGE',1500,7,now())$$, 'ok');
SELECT pg_temp.t('policy: duplicate version', $$INSERT INTO commission_policy_versions (id,version,calc_type,value,hold_days,effective_from) VALUES ('p3',2,'PERCENTAGE',1500,7,now())$$, '23505');
SELECT pg_temp.t('policy: over 100%', $$INSERT INTO commission_policy_versions (id,version,calc_type,value,hold_days,effective_from) VALUES ('p4',4,'PERCENTAGE',10001,7,now())$$, '23514');
SELECT pg_temp.t('policy: 100% allowed (boundary)', $$INSERT INTO commission_policy_versions (id,version,calc_type,value,hold_days,effective_from) VALUES ('p5',5,'PERCENTAGE',10000,0,now())$$, 'ok');
SELECT pg_temp.t('policy: negative hold', $$INSERT INTO commission_policy_versions (id,version,calc_type,value,hold_days,effective_from) VALUES ('p6',6,'PERCENTAGE',100,-1,now())$$, '23514');
SELECT pg_temp.t('policy: version 0', $$INSERT INTO commission_policy_versions (id,version,calc_type,value,hold_days,effective_from) VALUES ('p7',0,'PERCENTAGE',100,1,now())$$, '23514');
SELECT pg_temp.t('agent: optional policy id set', $$UPDATE agents SET commission_policy_id=(SELECT id FROM commission_policy_versions WHERE version=2) WHERE id='a2'$$, 'ok');
SELECT pg_temp.t('agent: unknown policy id refused', $$UPDATE agents SET commission_policy_id='nope' WHERE id='a1'$$, '23503');

-- Commissions
CREATE FUNCTION pg_temp.c(p_id text, p_att text, p_pay text, p_hash text, p_amount text, p_paid int, p_extra text DEFAULT '') RETURNS text LANGUAGE sql AS $f$
  SELECT format('INSERT INTO commissions (id,agent_id,attribution_id,payment_id,phone_hash,policy_version_id,calc_type,rule_value,amount_paise,amount_paid_paise,taxable_amount_paise,hold_until,updated_at %s) VALUES (%L,''a1'',%L,%L,%L,(SELECT id FROM commission_policy_versions WHERE version=1),''PERCENTAGE'',1000,%s,%s,0,now(),now() %s)',
    CASE WHEN p_extra='' THEN '' ELSE split_part(p_extra,'|',1) END, p_id, p_att, p_pay, p_hash, p_amount, p_paid,
    CASE WHEN p_extra='' THEN '' ELSE split_part(p_extra,'|',2) END)
$f$;
SELECT pg_temp.t('commission: valid (control)', pg_temp.c('c1','at1','pay1','mh1','8475',9999), 'ok');
SELECT pg_temp.t('commission: amount null allowed', pg_temp.c('c2','at2','pay2','mh2','NULL',9999), 'ok');
SELECT pg_temp.t('commission: amount equals paid (boundary)', pg_temp.c('c3','at3','pay3','mh3','9999',9999), 'ok');
SELECT pg_temp.t('commission: amount over paid', pg_temp.c('cx1','at4','pay4','mh4','10000',9999), '23514');
SELECT pg_temp.t('commission: amount negative', pg_temp.c('cx2','at4','pay4','mh4','-1',9999), '23514');
SELECT pg_temp.t('commission: taxable part over what was paid', $$INSERT INTO commissions (id,agent_id,attribution_id,payment_id,phone_hash,policy_version_id,calc_type,rule_value,amount_paid_paise,taxable_amount_paise,hold_until,updated_at) VALUES ('cx3b','a1','at4','pay4x','mh4x',(SELECT id FROM commission_policy_versions WHERE version=1),'PERCENTAGE',1000,100,101,now(),now())$$, '23514');
SELECT pg_temp.t('commission: paid negative', pg_temp.c('cx3','at4','pay4','mh4','NULL',-1), '23514');
SELECT pg_temp.t('commission: one per attribution', pg_temp.c('cx4','at1','payN1','mhN1','10',9999), '23505');
SELECT pg_temp.t('commission: one per payment', pg_temp.c('cx5','at4','pay1','mhN2','10',9999), '23505');
SELECT pg_temp.t('commission: one per phone hash', pg_temp.c('cx6','at4','payN3','mh1','10',9999), '23505');
SELECT pg_temp.t('commission: unknown attribution', pg_temp.c('cx7','nope','payN4','mhN4','10',9999), '23503');
SELECT pg_temp.t('commission: credited over amount', pg_temp.c('cx8','at4','payN5','mhN5','100',9999,',credited_paise|,101'), '23514');
SELECT pg_temp.t('commission: credited with null amount', pg_temp.c('cx9','at4','payN6','mhN6','NULL',9999,',credited_paise|,1'), '23514');
SELECT pg_temp.t('commission: credited = amount ok (boundary)', pg_temp.c('c4','at4','pay4','mh4','100',9999,',credited_paise|,100'), 'ok');
SELECT pg_temp.t('commission: reversed over credited', $$UPDATE commissions SET reversed_paise=101 WHERE id='c4'$$, '23514');
SELECT pg_temp.t('commission: reversed = credited ok', $$UPDATE commissions SET reversed_paise=100 WHERE id='c4'$$, 'ok');
SELECT pg_temp.t('commission: APPROVED without amount', $$UPDATE commissions SET status='APPROVED' WHERE id='c2'$$, '23514');
SELECT pg_temp.t('commission: APPROVED with amount (control)', $$UPDATE commissions SET status='APPROVED' WHERE id='c1'$$, 'ok');
SELECT pg_temp.t('commission: PAID without paid_at', $$UPDATE commissions SET status='PAID' WHERE id='c1'$$, '23514');
SELECT pg_temp.t('commission: PAID with paid_at (control)', $$UPDATE commissions SET status='PAID', paid_at=now() WHERE id='c1'$$, 'ok');
SELECT pg_temp.t('commission: bad review reason', $$UPDATE commissions SET review_reasons=ARRAY['SOMETHING_ELSE'] WHERE id='c1'$$, '23514');
SELECT pg_temp.t('commission: known review reasons ok', $$UPDATE commissions SET review_reasons=ARRAY['SELF_MATCH','PAID_BY_AGENT'] WHERE id='c1'$$, 'ok');
SELECT pg_temp.t('commission: NULL review reasons', $$UPDATE commissions SET review_reasons=NULL WHERE id='c1'$$, '23514');
SELECT pg_temp.t('delete: agent with commissions refused', $$DELETE FROM agents WHERE id='a1'$$, '23503');
SELECT pg_temp.t('delete: attribution with commission refused', $$DELETE FROM referral_attributions WHERE id='at1'$$, '23503');
SELECT pg_temp.t('delete: policy version used by a commission refused', $$DELETE FROM commission_policy_versions WHERE version=1$$, '23503');
SELECT pg_temp.t('delete: policy version used by an agent refused', $$DELETE FROM commission_policy_versions WHERE version=2$$, '23503');

-- Payouts
CREATE FUNCTION pg_temp.p(p_id text, p_agent text, p_period text, p_amount int, p_tax int, p_net int, p_status text, p_ref text, p_paid text, p_reason text, p_cancelled text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('INSERT INTO agent_payouts (id,agent_id,period,amount_paise,tax_withheld_paise,net_paise,status,reference,paid_at,cancel_reason,cancelled_at,created_by,updated_at) VALUES (%L,%L,%L,%s,%s,%s,%L,%s,%s,%s,%s,''staff-1'',now())',
    p_id, p_agent, p_period, p_amount, p_tax, p_net, p_status, p_ref, p_paid, p_reason, p_cancelled)
$f$;
SELECT pg_temp.t('payout: valid CREATED (control)', pg_temp.p('po1','a1','2026-11',60000,0,60000,'CREATED','NULL','NULL','NULL','NULL'), 'ok');
SELECT pg_temp.t('payout: second non-cancelled for the same period', pg_temp.p('po2','a1','2026-11',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), '23505');
SELECT pg_temp.t('payout: other agent same period ok', pg_temp.p('po3','a2','2026-11',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), 'ok');
SELECT pg_temp.t('payout: same agent other period ok', pg_temp.p('po4','a1','2026-12',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), 'ok');
SELECT pg_temp.t('payout: cancel the first', $$UPDATE agent_payouts SET status='CANCELLED', cancel_reason='wrong account', cancelled_at=now() WHERE id='po1'$$, 'ok');
SELECT pg_temp.t('payout: period is free again after a cancel', pg_temp.p('po5','a1','2026-11',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), 'ok');
SELECT pg_temp.t('payout: PAID with reference (control)', $$UPDATE agent_payouts SET status='PAID', reference='UTR0001', paid_at=now() WHERE id='po3'$$, 'ok');
SELECT pg_temp.t('payout: duplicate reference', $$UPDATE agent_payouts SET status='PAID', reference='UTR0001', paid_at=now() WHERE id='po4'$$, '23505');
SELECT pg_temp.t('payout: several null references ok', pg_temp.p('po6','a1','2027-01',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), 'ok');
SELECT pg_temp.t('payout: PAID without reference', $$UPDATE agent_payouts SET status='PAID', paid_at=now() WHERE id='po6'$$, '23514');
SELECT pg_temp.t('payout: PAID with blank reference', $$UPDATE agent_payouts SET status='PAID', reference='  ', paid_at=now() WHERE id='po6'$$, '23514');
SELECT pg_temp.t('payout: CANCELLED without reason', $$UPDATE agent_payouts SET status='CANCELLED', cancelled_at=now() WHERE id='po6'$$, '23514');
SELECT pg_temp.t('payout: net must equal amount minus tax', pg_temp.p('pox1','a1','2027-02',100,10,91,'CREATED','NULL','NULL','NULL','NULL'), '23514');
SELECT pg_temp.t('payout: amount zero', pg_temp.p('pox2','a1','2027-02',0,0,0,'CREATED','NULL','NULL','NULL','NULL'), '23514');
SELECT pg_temp.t('payout: tax over amount', pg_temp.p('pox3','a1','2027-02',100,101,-1,'CREATED','NULL','NULL','NULL','NULL'), '23514');
SELECT pg_temp.t('payout: bad period (month 13)', pg_temp.p('pox4','a1','2026-13',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), '23514');
SELECT pg_temp.t('payout: bad period (text)', pg_temp.p('pox5','a1','Nov-2026',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), '23514');
SELECT pg_temp.t('payout: unknown agent', pg_temp.p('pox6','nope','2027-02',100,0,100,'CREATED','NULL','NULL','NULL','NULL'), '23503');
SELECT pg_temp.t('commission: attach to a payout (control)', $$UPDATE commissions SET payout_id='po3' WHERE id='c3'$$, 'ok');
SELECT pg_temp.t('delete: payout used by a commission refused', $$DELETE FROM agent_payouts WHERE id='po3'$$, '23503');
SELECT pg_temp.t('delete: agent with payouts refused', $$DELETE FROM agents WHERE id='a2'$$, '23503');

-- Ledger
CREATE FUNCTION pg_temp.l(p_id text, p_type text, p_amount int, p_key text, p_commission text DEFAULT 'NULL', p_refund text DEFAULT 'NULL', p_payout text DEFAULT 'NULL', p_reason text DEFAULT 'NULL') RETURNS text LANGUAGE sql AS $f$
  SELECT format('INSERT INTO agent_ledger_entries (id,agent_id,type,amount_paise,idempotency_key,commission_id,refund_id,payout_id,reason) VALUES (%L,''a1'',%L,%s,%L,%s,%s,%s,%s)',
    p_id, p_type, p_amount, p_key, p_commission, p_refund, p_payout, p_reason)
$f$;
SELECT pg_temp.t('ledger: credit (control)', pg_temp.l('l1','CREDIT',8475,'credit:c1','''c1'''), 'ok');
SELECT pg_temp.t('ledger: duplicate idempotency key', pg_temp.l('l2','CREDIT',8475,'credit:c1','''c1'''), '23505');
SELECT pg_temp.t('ledger: credit must be positive', pg_temp.l('lx1','CREDIT',-5,'k1','''c1'''), '23514');
SELECT pg_temp.t('ledger: zero amount', pg_temp.l('lx2','ADJUSTMENT',0,'k2','NULL','NULL','NULL','''fix'''), '23514');
SELECT pg_temp.t('ledger: reversal must be negative', pg_temp.l('lx3','REVERSAL',5,'k3','''c1''','''rf1'''), '23514');
SELECT pg_temp.t('ledger: reversal ok (control)', pg_temp.l('l3','REVERSAL',-100,'reversal:rf1','''c1''','''rf1'''), 'ok');
SELECT pg_temp.t('ledger: reversal needs a refund id', pg_temp.l('lx4','REVERSAL',-5,'k4','''c1'''), '23514');
SELECT pg_temp.t('ledger: credit needs a commission', pg_temp.l('lx5','CREDIT',5,'k5'), '23514');
SELECT pg_temp.t('ledger: payout debit must be negative', pg_temp.l('lx6','PAYOUT_DEBIT',5,'k6','NULL','NULL','''po3'''), '23514');
SELECT pg_temp.t('ledger: payout debit needs a payout', pg_temp.l('lx7','PAYOUT_DEBIT',-5,'k7'), '23514');
SELECT pg_temp.t('ledger: payout debit ok (control)', pg_temp.l('l4','PAYOUT_DEBIT',-60000,'payout:po3','NULL','NULL','''po3'''), 'ok');
SELECT pg_temp.t('ledger: payout release must be positive', pg_temp.l('lx8','PAYOUT_RELEASE',-5,'k8','NULL','NULL','''po3'''), '23514');
SELECT pg_temp.t('ledger: payout release ok (control)', pg_temp.l('l5','PAYOUT_RELEASE',60000,'payout-release:po3','NULL','NULL','''po3'''), 'ok');
SELECT pg_temp.t('ledger: adjustment without reason', pg_temp.l('lx9','ADJUSTMENT',50,'k9'), '23514');
SELECT pg_temp.t('ledger: adjustment with blank reason', pg_temp.l('lx10','ADJUSTMENT',50,'k10','NULL','NULL','NULL','''   '''), '23514');
SELECT pg_temp.t('ledger: adjustment + (control)', pg_temp.l('l6','ADJUSTMENT',50,'adj1','NULL','NULL','NULL','''goodwill'''), 'ok');
SELECT pg_temp.t('ledger: adjustment - (control)', pg_temp.l('l7','ADJUSTMENT',-50,'adj2','NULL','NULL','NULL','''correction'''), 'ok');
SELECT pg_temp.t('ledger: unknown commission', pg_temp.l('lx11','CREDIT',5,'k11','''nope'''), '23503');
SELECT pg_temp.t('ledger: UPDATE rejected by the trigger', $$UPDATE agent_ledger_entries SET amount_paise=1 WHERE id='l1'$$, '23001');
SELECT pg_temp.t('ledger: DELETE rejected by the trigger', $$DELETE FROM agent_ledger_entries WHERE id='l1'$$, '23001');
SELECT pg_temp.t('ledger: the row is unchanged', $$SELECT 1/(SELECT (amount_paise=8475)::int FROM agent_ledger_entries WHERE id='l1')$$, 'ok');
SELECT pg_temp.t('delete: agent with ledger entries refused', $$DELETE FROM agents WHERE id='a1'$$, '23503');
-- CONTROL for the trigger: with it disabled the same UPDATE succeeds, so the
-- rejection above really is the trigger and not another rule.
ALTER TABLE agent_ledger_entries DISABLE TRIGGER agent_ledger_entries_append_only_trg;
SELECT pg_temp.t('control: UPDATE succeeds with the trigger disabled', $$UPDATE agent_ledger_entries SET amount_paise=8476 WHERE id='l1'$$, 'ok');
ALTER TABLE agent_ledger_entries ENABLE TRIGGER agent_ledger_entries_append_only_trg;
SELECT pg_temp.t('trigger re-enabled: UPDATE rejected again', $$UPDATE agent_ledger_entries SET amount_paise=1 WHERE id='l1'$$, '23001');

-- Balance is the sum of the signed rows
SELECT pg_temp.t('ledger: balance = sum of entries', $$SELECT 1/(SELECT (sum(amount_paise)=8476-100-60000+60000+50-50)::int FROM agent_ledger_entries WHERE agent_id='a1')$$, 'ok');

\echo
SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, name, expected, got FROM results ORDER BY n;
\echo
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM results;
ROLLBACK;
