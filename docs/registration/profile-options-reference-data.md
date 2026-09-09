# Profile Option Lists — Current State & Deferred Master-Data Work

**Status date:** 2026-09-09
**Scope:** the dropdown/selector reference data behind registration, Edit Profile
and partner preferences.

---

## 1. Task status

| Item | Status |
| --- | --- |
| Frontend dropdowns and cascades | **Complete** |
| Backend persistence of selected values | **Complete** |
| Backend master data (reference tables / options endpoint) | **Pending** — deferred, see §4 |
| Backend validation of selected values and dependencies | **Pending** — deferred, see §4 |

Nothing in §4 is approved or in progress. It is recorded here so the gap is
known rather than discovered.

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

**Not approved. Do not build any of this without explicit sign-off.**

1. Backend reference-data tables / controlled master data.
2. `GET /reference-data/profile-options` endpoint.
3. Stable IDs for countries, states, cities, religions, communities,
   sub-communities, industries, occupations, qualifications, employment types
   and income ranges.
4. Flutter API-based option loading, with caching.
5. Backend validation of all selected values against that master data.
6. Backend validation of the country → state → city dependency.
7. Backend validation of the religion → community → sub-community dependency.
8. A migration strategy that preserves existing string values and does not
   orphan current profiles.

Item 8 is the one that decides whether the rest is safe. Today's columns hold
free text written over the life of the app, including values no current list
offers; any move to IDs has to keep those readable and keep the profiles
holding them matchable, rather than rejecting or blanking them on first write.
