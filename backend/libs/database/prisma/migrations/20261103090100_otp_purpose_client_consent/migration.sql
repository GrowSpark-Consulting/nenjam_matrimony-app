-- A one-time code purpose for agent-added clients (Way 2): a client proves her
-- phone before accepting or rejecting an agent's draft. Purpose-bound, so a
-- client code can never sign anyone in as an agent (AGENT_SIGN_IN).
--
-- Alone in its migration on purpose: Postgres does not let a value added by
-- ADD VALUE be used in the same transaction, and nothing here uses it.

-- AlterEnum
ALTER TYPE "otp_purpose" ADD VALUE 'AGENT_CLIENT_CONSENT';
