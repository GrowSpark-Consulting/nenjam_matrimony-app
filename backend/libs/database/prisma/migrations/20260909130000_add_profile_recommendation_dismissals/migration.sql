-- Persistent "hide this recommendation" rows for the Home / Edit Profile
-- "Complete Your Profile" cards.
--
-- Hides a SUGGESTION only. Nothing here is read by any profile section, so a
-- dismissal can never remove a member's saved family, horoscope or
-- verification data — deleting a row simply makes the card eligible again.
--
-- card_key is a plain TEXT rather than an enum so a new recommendation card
-- never needs a migration; unknown keys are ignored by both the API and the
-- client.
CREATE TABLE "profile_recommendation_dismissals" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "card_key" TEXT NOT NULL,
    "dismissed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "profile_recommendation_dismissals_pkey" PRIMARY KEY ("id")
);

-- One dismissal per card per member — the upsert path relies on this.
CREATE UNIQUE INDEX "profile_recommendation_dismissals_user_id_card_key_key" ON "profile_recommendation_dismissals"("user_id", "card_key");

-- Every read is "all dismissals for this member".
CREATE INDEX "profile_recommendation_dismissals_user_id_idx" ON "profile_recommendation_dismissals"("user_id");

ALTER TABLE "profile_recommendation_dismissals" ADD CONSTRAINT "profile_recommendation_dismissals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
