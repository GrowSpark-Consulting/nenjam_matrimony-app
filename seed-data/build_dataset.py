"""One-off preprocessing: GeoNames + ISO 3166 -> committed seed files.

Run by hand, never at runtime. The seeder reads only the three files this
emits; GeoNames is a build-time source and is never called by the API.

Inputs (downloaded alongside this script):
  cities15000.txt        GeoNames, CC BY 4.0   cities with population > 15,000
  admin1CodesASCII.txt   GeoNames, CC BY 4.0   subdivision names per country
  countryInfo.txt        GeoNames, CC BY 4.0   ISO 3166-1
  iso3166.min.js         iso-3166-2 npm 1.0.0  ISO 3166-2 subdivision codes

The join that matters: GeoNames codes subdivisions inconsistently - US.AR is
already ISO-shaped, IN.25 and AE.03 are not - so cities are matched to ISO
3166-2 by subdivision NAME within the country, never by GeoNames' own code.
Anything that fails to match is dropped and COUNTED, never guessed at.
"""
import io, json, os, re, sys, unicodedata
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
os.makedirs(OUT, exist_ok=True)

SCOPE = ['IN', 'US', 'GB', 'SG', 'AE', 'MY', 'AU', 'CA']
POPULATION_FLOOR = 15000


def norm(s):
    """Casefold + strip accents + collapse punctuation, for name matching only.
    Never used to produce a stored value."""
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    return re.sub(r'[^a-z0-9]+', '', s.lower())


# GeoNames uses common English names; ISO 3166-2 uses official transliterations.
# Each line asserts "these two name the same subdivision" - a reviewable claim,
# not a guess. Anything not listed here stays unmatched and is reported.
ALIASES = {
    'AE': {'dubai': 'Dubayy', 'abudhabi': 'Abū Z̧aby', 'sharjah': 'Ash Shāriqah',
           'fujairah': 'Al Fujayrah', 'ajman': "'Ajmān",
           'rasalkhaimah': "Ra's al Khaymah", 'ummalquwain': 'Umm al Qaywayn'},
    'MY': {'penang': 'Pulau Pinang', 'malacca': 'Melaka',
           'kualalumpur': 'Wilayah Persekutuan Kuala Lumpur',
           'labuan': 'Wilayah Persekutuan Labuan',
           'putrajaya': 'Wilayah Persekutuan Putrajaya'},
    'IN': {'andamanandnicobar': 'Andaman and Nicobar Islands',
           'dadraandnagarhavelianddamananddiu':
               'Dadra and Nagar Haveli and Daman and Diu'},
}

# ── Deliberate, approved deviations from the ISO source ──────────────────
#
# SG-SG is NOT an ISO 3166-2 code. ISO defines SG-01..SG-05, but GeoNames
# publishes no subdivision names for Singapore at all, so no city can be
# attributed to one of those five without guessing. Singapore is modelled as a
# single city-state subdivision instead, which is also how members describe
# living there. Approved decision, documented in the README.
SG_CITY_STATE = {'code': 'SG-SG', 'countryCode': 'SG', 'label': 'Singapore',
                 'type': 'City-state', 'isActive': True}

# iso-3166-2@1.0.0 predates Ladakh (2019) and the DNH+DD merger (2020). These
# are published ISO facts the package is simply too old to carry.
ISO_SUPPLEMENT = [
    {'code': 'IN-LA', 'countryCode': 'IN', 'label': 'Ladakh',
     'type': 'Union territory', 'isActive': True},
    {'code': 'IN-DH', 'countryCode': 'IN',
     'label': 'Dadra and Nagar Haveli and Daman and Diu',
     'type': 'Union territory', 'isActive': True},
]

# Superseded by IN-DH in 2020. Retained so legacy profile values stay
# resolvable, but inactive so they never appear in a dropdown.
RETIRED = {'IN-DD', 'IN-DN'}

# Same treatment, different reason: ISO's five Singapore regions are real codes,
# but no city can be attributed to one of them (see SG_CITY_STATE), so leaving
# them active would put five empty options in the registration dropdown. They
# stay in the table - resolvable, never selectable. Called out in the README.
EMPTY_BY_DESIGN = {'SG-01', 'SG-02', 'SG-03', 'SG-04', 'SG-05'}
INACTIVE = RETIRED | EMPTY_BY_DESIGN


# ── ISO 3166-1: countries ────────────────────────────────────────────────
countries = []
for line in io.open(os.path.join(HERE, 'countryInfo.txt'), encoding='utf-8'):
    if line.startswith('#'):
        continue
    f = line.rstrip('\n').split('\t')
    if len(f) > 4 and f[0] in SCOPE:
        countries.append({'code': f[0], 'label': f[4], 'isActive': True})
countries.sort(key=lambda c: c['label'])

# ── ISO 3166-2: subdivisions ─────────────────────────────────────────────
js = io.open(os.path.join(HERE, 'iso3166.min.js'), encoding='utf-8').read()
states = []
for code, typ, name in re.findall(
        r'"([A-Z]{2}-[A-Z0-9]{1,3})":\{type:"([^"]*)",name:"([^"]*)"\}', js):
    cc = code.split('-')[0]
    if cc in SCOPE:
        states.append({'code': code, 'countryCode': cc, 'label': name,
                       'type': typ, 'isActive': code not in INACTIVE})
states.extend(ISO_SUPPLEMENT)
states.append(SG_CITY_STATE)
states.sort(key=lambda s: (s['countryCode'], s['label']))

# Only ACTIVE subdivisions can be a city's parent.
iso_by_name = defaultdict(dict)
for s in states:
    if s['isActive']:
        iso_by_name[s['countryCode']][norm(s['label'])] = s['code']

# ── GeoNames admin1 code -> subdivision name ─────────────────────────────
admin1_name = {}
for line in io.open(os.path.join(HERE, 'admin1CodesASCII.txt'), encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    if len(f) >= 2:
        admin1_name[f[0]] = f[1]

# ── Cities ───────────────────────────────────────────────────────────────
candidates = defaultdict(list)
dropped = defaultdict(int)
source_rows = 0
for line in io.open(os.path.join(HERE, 'cities15000.txt'), encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    if len(f) < 15:
        continue
    gid, name, cc, a1, pop = f[0], f[1], f[8], f[10], f[14]
    if cc not in SCOPE:
        continue
    source_rows += 1

    # cities15000.txt is not strictly what its name says - a few entries fall
    # under the threshold. Enforce it here so the documented floor is a real
    # guarantee rather than an assumption about the source file.
    if int(pop or 0) < POPULATION_FLOOR:
        dropped[f'{cc}: below the {POPULATION_FLOOR:,} population floor'] += 1
        continue

    if cc == 'SG':
        iso = SG_CITY_STATE['code']     # approved city-state exception
    else:
        sub_name = admin1_name.get(f'{cc}.{a1}')
        if not sub_name:
            dropped[f'{cc}: GeoNames has no subdivision name for admin1 {a1!r}'] += 1
            continue
        iso = iso_by_name[cc].get(norm(sub_name))
        if not iso:
            aliased = ALIASES.get(cc, {}).get(norm(sub_name))
            iso = iso_by_name[cc].get(norm(aliased)) if aliased else None
        if not iso:
            dropped[f'{cc}: no active ISO 3166-2 match for {sub_name!r}'] += 1
            continue

    slug = re.sub(r'-+', '-', re.sub(r'[^A-Z0-9]+', '-',
                                     norm(name).upper())).strip('-')
    candidates[f'{iso}-{slug}'].append(
        {'stateCode': iso, 'countryCode': cc, 'label': name,
         'population': int(pop or 0), 'geonameId': int(gid)})

# Distinct places can collide on one code - two towns called Ashford in England,
# two called Vanier in Ontario. The code has to stay unique and deterministic,
# so the largest wins (geonameId breaks a population tie). Input file order
# never decides; a re-run of this script reproduces the file byte for byte.
cities, collisions = [], []
for code, group in candidates.items():
    group.sort(key=lambda c: (-c['population'], c['geonameId']))
    winner, losers = group[0], group[1:]
    cities.append({'code': code, **{k: winner[k] for k in
                                    ('stateCode', 'countryCode', 'label', 'population')}})
    for lost in losers:
        dropped[f'{lost["countryCode"]}: name collides with a larger place of the '
                f'same name in the same subdivision'] += 1
        collisions.append((code, winner, lost))

cities.sort(key=lambda c: (c['countryCode'], c['stateCode'], c['label']))
seen = {c['code'] for c in cities}

# A subdivision with no city behind it is a dead end in the registration form:
# the member picks it and the city dropdown is empty. So the invariant is
# "active <=> has at least one city", which the API and the seeder can both
# rely on. Two things land here, for quite different reasons:
#   - ISO codes GB to 239 councils and boroughs; GeoNames codes it to the four
#     countries. All 862 GB cities therefore sit under ENG/SCT/WLS/NIR and the
#     other 235 are empty. Reuniting them would mean guessing which borough each
#     town belongs to - exactly what we are not doing.
#   - CA-NU (Nunavut) genuinely has no settlement above the 15,000 floor.
# Nothing is deleted: the rows stay, so a legacy value still resolves.
childless = {s['code'] for s in states} - {c['stateCode'] for c in cities}
deactivated = []
for s in states:
    if s['isActive'] and s['code'] in childless:
        s['isActive'] = False
        deactivated.append(s)

# ── Validation — every check the brief asks for ──────────────────────────
errors, notes = [], []
country_codes = {c['code'] for c in countries}
active_states = {s['code'] for s in states if s['isActive']}
all_states = {s['code'] for s in states}

if len(country_codes) != len(countries):
    errors.append('duplicate country codes')
if len(all_states) != len(states):
    errors.append('duplicate subdivision codes')
if len(seen) != len(cities):
    errors.append('duplicate city codes')
for s in states:
    if s['countryCode'] not in country_codes:
        errors.append(f"subdivision {s['code']} has no valid country")
for c in cities:
    if c['countryCode'] not in country_codes:
        errors.append(f"city {c['code']} has no valid country")
    if c['stateCode'] not in active_states:
        errors.append(f"city {c['code']} parent {c['stateCode']} is not an active subdivision")
for code in INACTIVE:
    st = next((s for s in states if s['code'] == code), None)
    if st is None:
        errors.append(f'inactive-by-design code {code} missing entirely')
    elif st['isActive']:
        errors.append(f'{code} should be inactive but is active')
for code in ('IN-LA', 'IN-DH'):
    st = next((s for s in states if s['code'] == code), None)
    if not st or not st['isActive']:
        errors.append(f'{code} must be present and active')
sg = [c for c in cities if c['countryCode'] == 'SG']
if not sg:
    errors.append('SG-SG has no cities')
if any(c['stateCode'] != 'SG-SG' for c in sg):
    errors.append('a Singapore city was assigned outside SG-SG')
# Every active subdivision a member can pick must have at least one city.
for s in states:
    if s['isActive'] and not any(c['stateCode'] == s['code'] for c in cities):
        errors.append(f"active subdivision {s['code']} ({s['label']}) has no cities")
if any(c['population'] < POPULATION_FLOOR for c in cities):
    errors.append(f'a city falls below the {POPULATION_FLOOR} population floor')
if not all(re.fullmatch(r'[A-Z]{2}-[A-Z0-9]{1,3}-[A-Z0-9-]+', c['code']) for c in cities):
    errors.append('a city code is not well formed')

# newline='\n' throughout: the committed files must be byte-identical whichever
# platform rebuilds them.
def write_json(name, payload):
    with io.open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(payload, fh, indent=2, ensure_ascii=False)
        fh.write('\n')


write_json('iso-3166-1-countries.json', countries)
write_json('iso-3166-2-subdivisions.json', states)
with io.open(os.path.join(OUT, 'cities.csv'), 'w', encoding='utf-8', newline='\n') as fh:
    fh.write('city_code,state_code,country_code,label,population\n')
    for c in cities:
        fh.write(f'{c["code"]},{c["stateCode"]},{c["countryCode"]},'
                 f'"{c["label"].replace(chr(34), chr(34) * 2)}",{c["population"]}\n')

# ── Report ───────────────────────────────────────────────────────────────
print(f'  countries     {len(countries)}')
print(f'  subdivisions  {len(states)}  ({len(active_states)} active, '
      f'{len(states) - len(active_states)} inactive)')
print(f'  cities        {len(cities)}\n')
by_c, sub_c = defaultdict(int), defaultdict(int)
for c in cities:
    by_c[c['countryCode']] += 1
for s in states:
    if s['isActive']:
        sub_c[s['countryCode']] += 1
print('  per country:')
for cc in SCOPE:
    print(f'    {cc}  {by_c[cc]:>5} cities   {sub_c[cc]:>3} active subdivisions')

print(f'\n  source rows in scope: {source_rows}')
print(f'  kept:                 {len(cities)}')
print(f'  dropped:              {sum(dropped.values())}')
if dropped:
    print('\n  every dropped record, explained:')
    for k, v in sorted(dropped.items(), key=lambda x: -x[1]):
        print(f'    {v:>4}  {k}')
if collisions:
    print(f'\n  name collisions resolved by population ({len(collisions)}):')
    for code, win, lost in collisions:
        print(f'    {code:<28} kept pop {win["population"]:>8,}  '
              f'dropped pop {lost["population"]:>8,}  (geonameId {lost["geonameId"]})')

by_reason = defaultdict(list)
for s in deactivated:
    by_reason[s['countryCode']].append(s['code'])
if by_reason:
    print(f'\n  subdivisions deactivated for having no city ({len(deactivated)}):')
    for cc, codes in sorted(by_reason.items()):
        shown = ', '.join(codes[:6]) + (f', +{len(codes) - 6} more' if len(codes) > 6 else '')
        print(f'    {cc}  {len(codes):>3}   {shown}')
    print('    (rows retained and resolvable; excluded from active dropdowns)')

print()
if notes:
    for n in notes:
        print(f'  NOTE: {n}')
if errors:
    print('\n  VALIDATION FAILED:')
    for e in errors[:20]:
        print(f'    - {e}')
    sys.exit(1)
print('  VALIDATION PASSED - all checks green')
