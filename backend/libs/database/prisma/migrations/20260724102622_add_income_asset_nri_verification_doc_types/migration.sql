-- Adds the doc types needed to represent Income/Asset/NRI verification on
-- the existing KycVerification table, so ProfileCompletionService's five
-- verification slices (mobile/income/asset/aadhaar/nri) can all be scored
-- from the same table instead of three new ones. Additive only — no
-- existing rows/columns are affected.
ALTER TYPE "kyc_doc_type" ADD VALUE 'INCOME_PROOF';
ALTER TYPE "kyc_doc_type" ADD VALUE 'ASSET_PROOF';
ALTER TYPE "kyc_doc_type" ADD VALUE 'NRI_PROOF';
