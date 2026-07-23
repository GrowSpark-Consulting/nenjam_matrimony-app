-- AlterTable
ALTER TABLE "user_profiles" ADD COLUMN     "father_age" INTEGER,
ADD COLUMN     "father_name" TEXT,
ADD COLUMN     "mother_age" INTEGER,
ADD COLUMN     "mother_name" TEXT,
ADD COLUMN     "sibling_details" JSONB NOT NULL DEFAULT '[]';
