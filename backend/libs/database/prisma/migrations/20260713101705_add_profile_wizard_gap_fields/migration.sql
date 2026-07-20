-- AlterTable
ALTER TABLE "astrology_profiles" ADD COLUMN     "horoscope_available" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "partner_preferences" ADD COLUMN     "preferred_mother_tongues" JSONB NOT NULL DEFAULT '[]',
ADD COLUMN     "preferred_occupations" JSONB NOT NULL DEFAULT '[]';

-- AlterTable
ALTER TABLE "user_profiles" ADD COLUMN     "area" TEXT,
ADD COLUMN     "community" TEXT,
ADD COLUMN     "country" TEXT,
ADD COLUMN     "denomination" TEXT,
ADD COLUMN     "family_values" TEXT,
ADD COLUMN     "fitness" TEXT,
ADD COLUMN     "hobbies" JSONB NOT NULL DEFAULT '[]',
ADD COLUMN     "languages_known" JSONB NOT NULL DEFAULT '[]',
ADD COLUMN     "pin_code" TEXT;
