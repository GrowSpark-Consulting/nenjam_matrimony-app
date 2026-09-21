-- Face verification (AWS Face Liveness + CompareFaces), phase 1.
--
-- Non-destructive: creates three enums and one table, adds nullable/defaulted
-- columns to face_verifications, and relaxes selfie_s3_key to NULL-able (the
-- liveness flow stores no selfie). No column, row or constraint is dropped.

-- CreateEnum
CREATE TYPE "face_verification_status" AS ENUM ('UNVERIFIED', 'VERIFIED', 'REVOKED');

-- CreateEnum
CREATE TYPE "face_verification_provider" AS ENUM ('AWS_REKOGNITION');

-- CreateEnum
CREATE TYPE "face_verification_outcome" AS ENUM ('PENDING', 'PROCESSING', 'VERIFIED', 'FAILED_LIVENESS', 'FAILED_MATCH', 'NO_FACE_IN_PHOTO', 'MULTIPLE_FACES_IN_PHOTO', 'UNSUPPORTED_PHOTO', 'NO_REFERENCE_IMAGE', 'PHOTO_CHANGED', 'EXPIRED', 'CANCELLED', 'ERROR');

-- AlterTable
ALTER TABLE "face_verifications" ADD COLUMN     "latest_attempt_id" TEXT,
ADD COLUMN     "match_similarity" DECIMAL(5,2),
ADD COLUMN     "matched_photo_id" TEXT,
ADD COLUMN     "matched_photo_s3_key" TEXT,
ADD COLUMN     "provider" "face_verification_provider",
ADD COLUMN     "revocation_reason" TEXT,
ADD COLUMN     "revoked_at" TIMESTAMP(3),
ADD COLUMN     "status" "face_verification_status" NOT NULL DEFAULT 'UNVERIFIED',
ALTER COLUMN "selfie_s3_key" DROP NOT NULL;

-- CreateTable
CREATE TABLE "face_verification_attempts" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "provider" "face_verification_provider" NOT NULL DEFAULT 'AWS_REKOGNITION',
    "liveness_session_id" TEXT,
    "liveness_status" TEXT,
    "liveness_confidence" DECIMAL(5,2),
    "compared_photo_id" TEXT,
    "compared_photo_s3_key" TEXT,
    "match_similarity" DECIMAL(5,2),
    "target_face_count" INTEGER,
    "liveness_threshold" DECIMAL(5,2) NOT NULL,
    "similarity_threshold" DECIMAL(5,2) NOT NULL,
    "outcome" "face_verification_outcome" NOT NULL DEFAULT 'PENDING',
    "failure_reason" TEXT,
    "client_outcome" TEXT,
    "client_error_code" TEXT,
    "consent_at" TIMESTAMP(3) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "processing_started_at" TIMESTAMP(3),
    "completed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "face_verification_attempts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "face_verification_attempts_liveness_session_id_key" ON "face_verification_attempts"("liveness_session_id");

-- CreateIndex
CREATE INDEX "face_verification_attempts_user_id_created_at_idx" ON "face_verification_attempts"("user_id", "created_at");

-- CreateIndex
CREATE INDEX "face_verification_attempts_created_at_idx" ON "face_verification_attempts"("created_at");

-- CreateIndex
CREATE INDEX "face_verification_attempts_outcome_expires_at_idx" ON "face_verification_attempts"("outcome", "expires_at");

-- CreateIndex
CREATE INDEX "face_verification_attempts_compared_photo_id_idx" ON "face_verification_attempts"("compared_photo_id");

-- CreateIndex
CREATE UNIQUE INDEX "face_verifications_latest_attempt_id_key" ON "face_verifications"("latest_attempt_id");

-- CreateIndex
CREATE INDEX "face_verifications_matched_photo_id_idx" ON "face_verifications"("matched_photo_id");

-- AddForeignKey
ALTER TABLE "face_verifications" ADD CONSTRAINT "face_verifications_matched_photo_id_fkey" FOREIGN KEY ("matched_photo_id") REFERENCES "profile_photos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "face_verifications" ADD CONSTRAINT "face_verifications_latest_attempt_id_fkey" FOREIGN KEY ("latest_attempt_id") REFERENCES "face_verification_attempts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "face_verification_attempts" ADD CONSTRAINT "face_verification_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "face_verification_attempts" ADD CONSTRAINT "face_verification_attempts_compared_photo_id_fkey" FOREIGN KEY ("compared_photo_id") REFERENCES "profile_photos"("id") ON DELETE SET NULL ON UPDATE CASCADE;
