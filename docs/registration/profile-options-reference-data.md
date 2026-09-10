# Profile Option Lists — Current State & Deferred Master-Data Work

**Status date:** 2026-09-10 (location master data built; superseding 2026-09-09)
**Scope:** the dropdown/selector reference data behind registration, Edit Profile
and partner preferences.

---

## 1. Task status

| Item | Status |
| --- | --- |
| Frontend dropdowns and cascades | **Complete** |
| Backend persistence of selected values | **Complete** |
| Backend master data — **location** (country/state/city) | **Complete** — see [location-master-data.md](../architecture/location-master-data.md) |
| Backend master data — religion, occupation, education, income | **Pending** — deferred, see §4 |
| Backend validation — **location** hierarchy | **Complete** |
| Backend validation — religion → community → sub-community | **Pending** — deferred, see §4 |

Location was signed off and built on 2026-09-10; §4 records what that covered
and what it did not. The remaining items in §4 are not approved or in progress,
and are recorded here so the gap is known rather than discovered.

> §2 and §3 below describe the **frontend-owned lists**, which are still how
> religion, community, occupation, education and income work. They no longer
> describe country/state/city — those now come from the backend.

---

## 2. What is true today

These are **frontend-owned option lists with backend persistence.** They are
explicitly **not** backend master-data dropdowns: Flutter does not fetch the
options from an API, and the backend does not validate what it is sent.

### Where the lists live

All of them are hardcoded `const` values in the client:

- `Frontend/lib/core/constants/profile_options.dart` — countries, states,
  cities, religions, communities, sub-communities, industries, occupations,
  qualifications, employment types, income ranges, diets, marital statuses,
  heights.
- `Frontend/lib/features/registration/presentation/widgets/step_language.dart`
  — the `_languages` list, private to that step.

There is **no** options / lookup / master-data endpoint on the API. The
complete controller list is `auth`, `chat/*`, `discover`, `interests`,
`matches`, `notifications`, `profiles`, `profiles/completion`,
`profiles/draft`, `profiles/me/photos`, `profiles/prompts`, `settings`,
`support/tickets`, `users`. There are no JSON option assets either.

### What is persisted

Everything, twice: verbatim into `registration_steps.draft_data` (JSON), then
copied by `writeProfileFromDraft` into `user_profiles` columns — `religion`,
`caste`, `sub_caste`, `community`, `mother_tongue`, `current_city`,
`current_state`, `country`, `highest_education`, `college`, `work_industry`,
`dietary_habits`, `smoking_habits`, `drinking_habits`, all plain
`String`/`String?`.

Two fields are stored as Postgres enums: `gender` (`Gender`) and
`marital_status` (`MaritalStatus`).

### What is validated server-side

Three fields, and only three:

| Field | Validation |
| --- | --- |
| `gender` | `@IsIn(['MALE','FEMALE'])` + Postgres `gender` enum |
| `maritalStatus` | `@IsIn(['NEVER_MARRIED','DIVORCED','WIDOWED','AWAITING_DIVORCE'])` + Postgres enum |
| sibling `relation` | `@IsIn(['BROTHER','SISTER'])` |

Every other dropdown field — religion, community, caste, subCaste, country,
state, city, motherTongue, qualification, occupation, employmentType,
workIndustry, annualIncome, height, eatingHabit, smoking, drinking, fitness,
hobbies, familyType, familyValues, familyStatus, rashi, nakshatra, star — is
`@IsOptional() @IsString()`. No enum, no whitelist, no format check, and no
CHECK constraint in any migration.

`registration-rules.ts` asks only whether a field is **present**
(`allPresent(religion, ['religion','community'])`,
`allPresent(location, ['country','state','city'])`) — never whether the value
is a real one.

### The cascades are Flutter-only

`ProfileOptions.statesFor` / `citiesFor` / `communitiesFor`, and the
`isStateInCountry` / `isCityInState` / `isCommunityInReligion` guards that drop
a stale answer when its parent changes, are called from `step_location.dart`,
`step_religion.dart`, `profile_basics_page.dart` and
`onboarding_religion_page.dart`.

NestJS has no equivalent. It stores country, state and city independently, and
religion and community independently, and never asks whether they agree.

**Known consequence:** a request made outside the app — a stale client, a
direct API call — can persist a city that is not in its state, or a community
that is not in its religion. Accepted for now; closing it is §4.

---

## 3. Working with the lists in the meantime

- Adding an option is a client-only change. It needs no backend change — and
  gets no backend guarantee.
- **Removing** an option does not migrate or re-validate profiles that already
  hold it. The stored string survives, the dropdown no longer offers it, and
  the member's saved value silently becomes unselectable on re-edit. Prefer
  adding over removing until §4 lands.
- Values are sent as-is. `gender` and `maritalStatus` are the exception: the
  client uppercases and underscores them (`BasicDetails._toEnumValue`) because
  those two really are whitelisted server-side.

Both ends carry a pointer to this arrangement in code: the `ProfileOptions`
class doc, and header comments on `LocationDetailsDto` and
`ReligionDetailsDto`.

---

## 4. Deferred: backend master data (separate future task)

**The location slice of this list has since been built and signed off** —
see [`docs/architecture/location-master-data.md`](../architecture/location-master-data.md).
Everything else below is still **not approved. Do not build it without explicit
sign-off.**

| # | Item | Status |
| --- | --- | --- |
| 1 | Backend reference-data tables / controlled master data | **Done for location.** Deferred for the rest |
| 2 | `GET /reference-data/profile-options` endpoint | **Done for location** as `/reference-data/countries \| states \| cities`. The single combined `profile-options` route was not built |
| 3 | Stable IDs for countries, states, cities, religions, communities, sub-communities, industries, occupations, qualifications, employment types and income ranges | **Done for countries/states/cities** (ISO 3166 codes, not surrogate IDs). Deferred for the rest |
| 4 | Flutter API-based option loading, with caching | **Done for location** (`features/location`). Deferred for the rest |
| 5 | Backend validation of all selected values against master data | **Done for location.** Deferred for the rest |
| 6 | Backend validation of the country → state → city dependency | **Done** — `LocationService.resolve()` |
| 7 | Backend validation of the religion → community → sub-community dependency | Deferred — no religion taxonomy change was made |
| 8 | A migration strategy that preserves existing string values and does not orphan current profiles | **Done for location** |

### How item 8 was answered for location

It was the item that decided whether the rest was safe, so it is worth
recording what was actually done rather than leaving it as a resolved
checkbox.

The answer was **not** to move to IDs. The new `country_code` / `state_code` /
`city_code` columns were added *beside* the existing free-text columns, not in
place of them:

- The new columns are nullable and start NULL for every existing profile.
- The free-text columns remain the source of truth for every profile written
  before the change, and everything that already reads them (search, feed
  cards, emails) still does.
- A write carrying no codes leaves the code columns untouched rather than
  nulling them, so an older client cannot wipe them.
- Values no list offers — `TN`, `chennai`, a Singapore address filed under
  Kerala — are left exactly as members typed them, and are never silently
  corrected.
- Backfilling the codes is a separate, reviewed step. `pnpm analyze:locations`
  reports, read-only, what a backfill *would* set and why the rest is not
  unambiguously resolvable. Nothing is written until that report is approved.

The same approach is the recommended starting point if items 3, 5 and 7 are
ever picked up for the religion and occupation taxonomies.
