-- Religion -> Community master data.
--
-- Additive in the strict sense: two new tables and nothing else. No existing
-- row is read, updated or deleted; no column is dropped, renamed or retyped;
-- no default backfills anything. user_profiles is NOT touched — `religion`,
-- `community`, `caste` and `sub_caste` keep their current free-text values and
-- remain the source of truth for every profile already written.
--
-- These tables back the fields that already exist rather than introducing a
-- new "caste" vocabulary. The app uses the three words inconsistently today
-- ('Iyer' is a community in ProfileOptions, a caste in the profile seeder, and
-- a sub-community in ProfileOptions.subCommunities), so renaming anything here
-- would mean picking a winner and migrating live profile data to match.
--
-- There is deliberately no sub_communities table: no community -> sub-community
-- relationship exists anywhere in the project, and inventing one is not an
-- option. That field stays free text until a sourced dataset is supplied.

CREATE TABLE "religions" (
    "code"       VARCHAR(20) NOT NULL,
    "label"      TEXT NOT NULL,
    "is_active"  BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "religions_pkey" PRIMARY KEY ("code")
);

CREATE TABLE "communities" (
    "code"          VARCHAR(60) NOT NULL,
    "religion_code" VARCHAR(20) NOT NULL,
    "label"         TEXT NOT NULL,
    "is_active"     BOOLEAN NOT NULL DEFAULT true,
    "created_at"    TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"    TIMESTAMP(3) NOT NULL,

    CONSTRAINT "communities_pkey" PRIMARY KEY ("code")
);

-- One index per query the reference-data API actually issues, rather than
-- indexing every column on principle.
CREATE INDEX "religions_is_active_idx" ON "religions"("is_active");
CREATE INDEX "communities_religion_code_is_active_label_idx"
    ON "communities"("religion_code", "is_active", "label");

-- Parent/child integrity is the database's job, not only the API's.
-- ON DELETE RESTRICT, not CASCADE: retiring a religion must never silently
-- delete the communities beneath it. A row that is no longer offered is
-- deactivated (is_active = false), never deleted.
ALTER TABLE "communities" ADD CONSTRAINT "communities_religion_code_fkey"
    FOREIGN KEY ("religion_code") REFERENCES "religions"("code")
    ON DELETE RESTRICT ON UPDATE CASCADE;
