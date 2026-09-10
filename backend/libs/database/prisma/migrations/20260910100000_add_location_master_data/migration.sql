-- Location master data: Country -> Subdivision -> City, keyed by ISO 3166.
--
-- Additive in the strict sense. Three new tables, three new nullable columns on
-- user_profiles, and nothing else. No existing row is read, updated or deleted;
-- no column is dropped, renamed or retyped; no default backfills anything.
--
-- The three new profile columns start NULL for every existing member and STAY
-- NULL until a separate, reviewed backfill runs. That is deliberate: the legacy
-- free-text columns hold values like 'TN', 'chennai', and a Singapore address
-- filed under 'Kerala'. Those are what members typed, they remain untouched,
-- and they are never silently corrected. current_city / current_state / country
-- continue to be the source of truth for every profile written before this
-- migration; the code columns are populated only where the mapping is
-- unambiguous, and only with approval.
--
-- Note what is NOT here: no NOT NULL, no DEFAULT, no UPDATE, no data migration
-- of any kind. Applying this to production changes no member's data.

-- ── Countries (ISO 3166-1) ────────────────────────────────────────────────
CREATE TABLE "countries" (
    "code"       VARCHAR(2) NOT NULL,
    "label"      TEXT NOT NULL,
    "is_active"  BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "countries_pkey" PRIMARY KEY ("code")
);

-- ── Subdivisions (ISO 3166-2) ─────────────────────────────────────────────
CREATE TABLE "subdivisions" (
    "code"         VARCHAR(6) NOT NULL,
    "country_code" VARCHAR(2) NOT NULL,
    "label"        TEXT NOT NULL,
    "type"         TEXT NOT NULL,
    "is_active"    BOOLEAN NOT NULL DEFAULT true,
    "created_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"   TIMESTAMP(3) NOT NULL,

    CONSTRAINT "subdivisions_pkey" PRIMARY KEY ("code")
);

-- ── Cities ────────────────────────────────────────────────────────────────
CREATE TABLE "cities" (
    "code"         VARCHAR(80) NOT NULL,
    "state_code"   VARCHAR(6) NOT NULL,
    "country_code" VARCHAR(2) NOT NULL,
    "label"        TEXT NOT NULL,
    "population"   INTEGER NOT NULL,
    "is_active"    BOOLEAN NOT NULL DEFAULT true,
    "created_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"   TIMESTAMP(3) NOT NULL,

    CONSTRAINT "cities_pkey" PRIMARY KEY ("code")
);

-- Dropdown-shaped indexes: each one matches a query the reference-data API
-- actually issues, rather than indexing every column on principle.
CREATE INDEX "countries_is_active_idx" ON "countries"("is_active");
CREATE INDEX "subdivisions_country_code_is_active_label_idx"
    ON "subdivisions"("country_code", "is_active", "label");
CREATE INDEX "cities_state_code_is_active_population_idx"
    ON "cities"("state_code", "is_active", "population" DESC);
CREATE INDEX "cities_country_code_is_active_idx"
    ON "cities"("country_code", "is_active");
CREATE INDEX "cities_label_idx" ON "cities"("label");

-- Parent/child integrity is the database's job, not only the API's: a city can
-- never point at a subdivision that does not exist, and its denormalized
-- country_code can never point at a country that does not exist.
ALTER TABLE "subdivisions" ADD CONSTRAINT "subdivisions_country_code_fkey"
    FOREIGN KEY ("country_code") REFERENCES "countries"("code")
    ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "cities" ADD CONSTRAINT "cities_state_code_fkey"
    FOREIGN KEY ("state_code") REFERENCES "subdivisions"("code")
    ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "cities" ADD CONSTRAINT "cities_country_code_fkey"
    FOREIGN KEY ("country_code") REFERENCES "countries"("code")
    ON DELETE RESTRICT ON UPDATE CASCADE;

-- ── Structured location on the profile, beside the existing free text ─────
ALTER TABLE "user_profiles" ADD COLUMN "country_code" VARCHAR(2);
ALTER TABLE "user_profiles" ADD COLUMN "state_code"   VARCHAR(6);
ALTER TABLE "user_profiles" ADD COLUMN "city_code"    VARCHAR(80);

CREATE INDEX "user_profiles_city_code_idx"    ON "user_profiles"("city_code");
CREATE INDEX "user_profiles_state_code_idx"   ON "user_profiles"("state_code");
CREATE INDEX "user_profiles_country_code_idx" ON "user_profiles"("country_code");

-- ON DELETE RESTRICT, not CASCADE or SET NULL: retiring a city must never
-- silently blank a member's location. A row that profiles reference is
-- deactivated (is_active = false), never deleted.
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_country_code_fkey"
    FOREIGN KEY ("country_code") REFERENCES "countries"("code")
    ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_state_code_fkey"
    FOREIGN KEY ("state_code") REFERENCES "subdivisions"("code")
    ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_city_code_fkey"
    FOREIGN KEY ("city_code") REFERENCES "cities"("code")
    ON DELETE RESTRICT ON UPDATE CASCADE;
