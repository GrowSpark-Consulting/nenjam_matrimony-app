-- AlterTable
ALTER TABLE "admin_accounts" ADD COLUMN     "is_active" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "last_login_at" TIMESTAMP(3),
ADD COLUMN     "mfa_enrolled_at" TIMESTAMP(3),
ADD COLUMN     "mfa_enrollment_code_hash" TEXT,
ADD COLUMN     "mfa_enrollment_expires_at" TIMESTAMP(3),
ADD COLUMN     "mfa_failed_attempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "mfa_last_used_step" INTEGER,
ADD COLUMN     "mfa_locked_until" TIMESTAMP(3),
ADD COLUMN     "mfa_secret_encrypted" TEXT;

-- AlterTable
ALTER TABLE "audit_logs" ADD COLUMN     "actor_type" TEXT,
ADD COLUMN     "after" JSONB,
ADD COLUMN     "before" JSONB,
ADD COLUMN     "reason" TEXT,
ADD COLUMN     "request_id" TEXT,
ADD COLUMN     "user_agent" TEXT;

-- CreateTable
CREATE TABLE "roles" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "is_system" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "roles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "permissions" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "is_sensitive" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "permissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "role_permissions" (
    "role_id" TEXT NOT NULL,
    "permission_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("role_id","permission_id")
);

-- CreateTable
CREATE TABLE "admin_user_roles" (
    "admin_account_id" TEXT NOT NULL,
    "role_id" TEXT NOT NULL,
    "assigned_by_id" TEXT,
    "assigned_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "admin_user_roles_pkey" PRIMARY KEY ("admin_account_id","role_id")
);

-- CreateTable
CREATE TABLE "admin_sessions" (
    "id" TEXT NOT NULL,
    "admin_account_id" TEXT NOT NULL,
    "token_hash" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMP(3) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "mfa_verified_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "revoke_reason" TEXT,
    "ip_address" TEXT,
    "user_agent" TEXT,

    CONSTRAINT "admin_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "roles_key_key" ON "roles"("key");

-- CreateIndex
CREATE UNIQUE INDEX "permissions_key_key" ON "permissions"("key");

-- CreateIndex
CREATE INDEX "role_permissions_permission_id_idx" ON "role_permissions"("permission_id");

-- CreateIndex
CREATE INDEX "admin_user_roles_role_id_idx" ON "admin_user_roles"("role_id");

-- CreateIndex
CREATE UNIQUE INDEX "admin_sessions_token_hash_key" ON "admin_sessions"("token_hash");

-- CreateIndex
CREATE INDEX "admin_sessions_admin_account_id_idx" ON "admin_sessions"("admin_account_id");

-- CreateIndex
CREATE INDEX "admin_sessions_expires_at_idx" ON "admin_sessions"("expires_at");

-- CreateIndex
CREATE INDEX "audit_logs_action_created_at_idx" ON "audit_logs"("action", "created_at");

-- AddForeignKey
ALTER TABLE "role_permissions" ADD CONSTRAINT "role_permissions_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "roles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_permissions" ADD CONSTRAINT "role_permissions_permission_id_fkey" FOREIGN KEY ("permission_id") REFERENCES "permissions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "admin_user_roles" ADD CONSTRAINT "admin_user_roles_admin_account_id_fkey" FOREIGN KEY ("admin_account_id") REFERENCES "admin_accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "admin_user_roles" ADD CONSTRAINT "admin_user_roles_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "roles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "admin_sessions" ADD CONSTRAINT "admin_sessions_admin_account_id_fkey" FOREIGN KEY ("admin_account_id") REFERENCES "admin_accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Hand-written: constraints Prisma cannot express, and the RBAC seed.
-- Additive only. Nothing existing is modified except the new admin_accounts
-- columns above; `is_active` defaults to false, so every admin account that
-- exists before this migration (the old seeder's placeholder included) has no
-- access until it is provisioned with `pnpm admin:provision`.
-- ---------------------------------------------------------------------------

ALTER TABLE "permissions" ADD CONSTRAINT "permissions_key_format"
  CHECK ("key" ~ '^[a-z]+(\.[a-z_]+)+$');
ALTER TABLE "roles" ADD CONSTRAINT "roles_key_format"
  CHECK ("key" ~ '^[A-Z][A-Z0-9_]*$');
ALTER TABLE "admin_sessions" ADD CONSTRAINT "admin_sessions_expiry_after_creation"
  CHECK ("expires_at" > "created_at");
ALTER TABLE "admin_accounts" ADD CONSTRAINT "admin_accounts_mfa_failed_attempts_non_negative"
  CHECK ("mfa_failed_attempts" >= 0);
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actor_type_known"
  CHECK ("actor_type" IS NULL OR "actor_type" IN ('STAFF', 'MEMBER', 'AGENT', 'SYSTEM'));

-- Permission keys (Nenjam Admin Architecture v3, section 13). Must match
-- PERMISSIONS in apps/api/src/modules/admin/rbac/permissions.ts.
INSERT INTO "permissions" ("id", "key", "description", "is_sensitive") VALUES
  (gen_random_uuid()::text, 'dashboard.view', 'View the admin dashboard', false),
  (gen_random_uuid()::text, 'finance.view', 'View revenue figures', false),
  (gen_random_uuid()::text, 'member.view', 'View members (contact details masked)', false),
  (gen_random_uuid()::text, 'member.pii.reveal', 'Reveal a member''s unmasked phone and email', true),
  (gen_random_uuid()::text, 'member.suspend', 'Suspend, ban or restore a member', false),
  (gen_random_uuid()::text, 'member.session.revoke', 'Sign a member out everywhere', false),
  (gen_random_uuid()::text, 'verification.decide', 'Decide KYC and face verification reviews', false),
  (gen_random_uuid()::text, 'photo.moderate', 'Remove or approve member photos', false),
  (gen_random_uuid()::text, 'report.resolve', 'Resolve member reports', false),
  (gen_random_uuid()::text, 'support.ticket.respond', 'Reply to and close support tickets', false),
  (gen_random_uuid()::text, 'support.ticket.assign', 'Assign support tickets', false),
  (gen_random_uuid()::text, 'subscription.view', 'View member subscriptions', false),
  (gen_random_uuid()::text, 'subscription.extend', 'Extend a member''s subscription', false),
  (gen_random_uuid()::text, 'subscription.cancel', 'Cancel or revoke a member''s subscription', false),
  (gen_random_uuid()::text, 'subscription.grant', 'Grant a complimentary plan', false),
  (gen_random_uuid()::text, 'plan.view', 'View plans, versions and prices', false),
  (gen_random_uuid()::text, 'plan.edit', 'Edit plan drafts and display details', false),
  (gen_random_uuid()::text, 'plan.publish', 'Publish plan versions, prices and availability', false),
  (gen_random_uuid()::text, 'feature.registry.edit', 'Add feature definitions', false),
  (gen_random_uuid()::text, 'coupon.manage', 'Create and disable coupons', false),
  (gen_random_uuid()::text, 'payment.view', 'View payments', false),
  (gen_random_uuid()::text, 'payment.reconcile', 'Re-fetch a payment''s status from the gateway', false),
  (gen_random_uuid()::text, 'payment.record_offline', 'Record a cash or offline UPI payment', false),
  (gen_random_uuid()::text, 'refund.request', 'Request a refund', false),
  (gen_random_uuid()::text, 'refund.approve', 'Approve a refund', true),
  (gen_random_uuid()::text, 'agent.view', 'View agents and applications', false),
  (gen_random_uuid()::text, 'agent.approve', 'Approve or reject agent applications', false),
  (gen_random_uuid()::text, 'agent.manage', 'Pause, resume, terminate agents and replace codes', false),
  (gen_random_uuid()::text, 'agent.payout_details.verify', 'Verify an agent''s payout details', false),
  (gen_random_uuid()::text, 'agent.pii.reveal', 'Reveal an agent''s full PAN or payout details (e.g. for a first payout)', true),
  (gen_random_uuid()::text, 'attribution.view', 'View referral attributions', false),
  (gen_random_uuid()::text, 'attribution.override', 'Set or correct a referral attribution', false),
  (gen_random_uuid()::text, 'commission.view', 'View commissions', false),
  (gen_random_uuid()::text, 'commission.approve', 'Approve commissions', false),
  (gen_random_uuid()::text, 'commission.cancel', 'Cancel commissions before approval', false),
  (gen_random_uuid()::text, 'commission.override', 'Override a commission amount', false),
  (gen_random_uuid()::text, 'commission.policy.edit', 'Edit commission policies', false),
  (gen_random_uuid()::text, 'commission.adjust', 'Post commission ledger adjustments', false),
  (gen_random_uuid()::text, 'payout.view', 'View agent payouts', false),
  (gen_random_uuid()::text, 'payout.execute', 'Create and mark agent payouts paid', true),
  (gen_random_uuid()::text, 'report.view', 'View reports', false),
  (gen_random_uuid()::text, 'report.export', 'Export reports', false),
  (gen_random_uuid()::text, 'flag.toggle', 'Turn feature flags on and off', false),
  (gen_random_uuid()::text, 'config.edit', 'Change platform settings', false),
  (gen_random_uuid()::text, 'rbac.manage', 'Manage admin users, roles and permissions', true),
  (gen_random_uuid()::text, 'audit.view', 'View the audit log', false),
  (gen_random_uuid()::text, 'system.view', 'View system health', false),
  (gen_random_uuid()::text, 'system.job.retry', 'Retry failed background jobs', false)
ON CONFLICT ("key") DO NOTHING;

-- Roles decided by Raja (28 Oct). Anything not granted below — pausing or
-- terminating agents, code replacement, PAN/phone reveal, commissions,
-- attribution — stays Super Admin only until decided. Further roles
-- (Operations, Finance, Support, ...) are added in later migrations once their
-- permission matrix is confirmed.
INSERT INTO "roles" ("id", "key", "name", "description", "is_system", "updated_at") VALUES
  (gen_random_uuid()::text, 'SUPER_ADMIN', 'Super Admin',
   'Every permission. Assign to one or two founders only.', true, CURRENT_TIMESTAMP),
  (gen_random_uuid()::text, 'PARTNER_MANAGER', 'Partner Manager',
   'Reviews agent applications: view agents, approve or reject them.', true, CURRENT_TIMESTAMP),
  (gen_random_uuid()::text, 'PAYOUT_MANAGER', 'Payout Manager',
   'Pays agents: views payouts, creates them and marks them paid. Sees the payout destination when paying; never PAN.', true, CURRENT_TIMESTAMP)
ON CONFLICT ("key") DO NOTHING;

INSERT INTO "role_permissions" ("role_id", "permission_id")
SELECT r."id", p."id"
FROM "roles" r CROSS JOIN "permissions" p
WHERE r."key" = 'SUPER_ADMIN'
ON CONFLICT DO NOTHING;

INSERT INTO "role_permissions" ("role_id", "permission_id")
SELECT r."id", p."id"
FROM "roles" r
JOIN "permissions" p
  ON (r."key" = 'PARTNER_MANAGER' AND p."key" IN ('agent.view', 'agent.approve'))
  OR (r."key" = 'PAYOUT_MANAGER' AND p."key" IN ('payout.view', 'payout.execute'))
ON CONFLICT DO NOTHING;
