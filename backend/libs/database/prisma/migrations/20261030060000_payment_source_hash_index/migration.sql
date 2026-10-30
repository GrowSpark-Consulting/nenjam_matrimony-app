-- Speeds up "has this UPI id paid before?" (the agent program's abuse check on
-- payment_source_hash). Index only: no data or column changes. The table is
-- small (empty in production on 30 Oct), so a plain CREATE INDEX is instant.

-- CreateIndex
CREATE INDEX "payment_transactions_payment_source_hash_idx" ON "payment_transactions"("payment_source_hash");

