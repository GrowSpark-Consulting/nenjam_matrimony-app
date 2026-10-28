/**
 * Whether a `users` row is a staff identity: any role but USER.
 *
 * Staff rows are never re-linked to a different Firebase account by the
 * member sign-in paths — FirebaseAuthGuard's email/phone reconciliation and
 * the dummy-OTP session exchange both refuse. Those paths match on an email or
 * phone the caller supplies, which is fine for a member recovering their own
 * account and catastrophic for an admin: whoever could claim the admin's
 * address or number would inherit the admin row. Only the operator-run
 * provisioning script (`pnpm admin:provision`) may link a staff row to a
 * Firebase account.
 *
 * A row loaded without its role (`undefined`) is not staff.
 */
export function isStaffRole(role: unknown): boolean {
  return typeof role === 'string' && role !== 'USER';
}
