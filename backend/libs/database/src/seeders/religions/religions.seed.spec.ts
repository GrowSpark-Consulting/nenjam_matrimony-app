import { resolve } from 'node:path';
import { communityCode, loadReligionDataset } from './index';

/**
 * Guards the committed dataset itself.
 *
 * This data was migrated verbatim from `ProfileOptions` in the Flutter app, so
 * the values below are asserted against what that file shipped. If someone
 * edits seed-data/religions.json and drops or renames an entry, an existing
 * member's stored `religion` / `community` string stops matching the list they
 * are shown — which is the failure this catches.
 */
const SEED = resolve(__dirname, '../../../../../../seed-data/religions.json');

describe('committed religion dataset', () => {
  const dataset = loadReligionDataset(SEED);

  it('carries every religion the app already shipped, in order', () => {
    // ProfileOptions.religions, verbatim.
    expect(dataset.religions.map((r) => r.label)).toEqual([
      'Hindu',
      'Christian',
      'Muslim',
      'Jain',
      'Sikh',
      'Buddhist',
      'Inter-Religion',
    ]);
  });

  it('keeps each religion\'s communities exactly as ProfileOptions had them', () => {
    const communitiesOf = (code: string) =>
      dataset.religions.find((r) => r.code === code)?.communities;

    expect(communitiesOf('HINDU')).toEqual([
      'Vellalar', 'Nadar', 'Chettiar', 'Mudaliar', 'Iyer', 'Iyengar',
      'Naidu', 'Reddy', 'Tamil', 'Telugu', 'Malayalam', 'Kannada',
    ]);
    expect(communitiesOf('MUSLIM')).toEqual([
      'Urdu', 'Tamil', 'Malayalam', 'Rowther', 'Lebbai', 'Marakayar',
    ]);
    expect(communitiesOf('CHRISTIAN')).toEqual([
      'Tamil', 'Malayalam', 'Telugu', 'Roman Catholic', 'Protestant',
    ]);
    expect(communitiesOf('JAIN')).toEqual([
      'Digambar', 'Shwetambar', 'Gujarati', 'Marwari',
    ]);
    expect(communitiesOf('SIKH')).toEqual([
      'Jat', 'Khatri', 'Ramgarhia', 'Punjabi',
    ]);
    expect(communitiesOf('BUDDHIST')).toEqual(['Tamil', 'Marathi', 'Other']);
  });

  it('gives Inter-Religion the union, matching communitiesFor()\'s fallback', () => {
    // ProfileOptions.communitiesFor() falls back to the full union for any
    // religion absent from its map, and Inter-Religion is absent. Seeding an
    // empty list here would silently empty that dropdown for those members.
    const union = new Set(
      dataset.religions
        .filter((r) => r.code !== 'INTER-RELIGION')
        .flatMap((r) => r.communities),
    );
    const inter = communitiesOf(dataset, 'INTER-RELIGION');
    expect(new Set(inter)).toEqual(union);
  });

  it('derives community codes deterministically from their parts', () => {
    expect(communityCode('HINDU', 'Vellalar')).toBe('HINDU-VELLALAR');
    expect(communityCode('CHRISTIAN', 'Roman Catholic')).toBe('CHRISTIAN-ROMAN-CATHOLIC');
    // Every generated code must start with its religion, which is what makes
    // a community impossible to attach to the wrong parent.
    for (const community of dataset.communities) {
      expect(community.code.startsWith(`${community.religionCode}-`)).toBe(true);
    }
  });

  it('has no duplicate codes at either level', () => {
    expect(new Set(dataset.religions.map((r) => r.code)).size).toBe(
      dataset.religions.length,
    );
    expect(new Set(dataset.communities.map((c) => c.code)).size).toBe(
      dataset.communities.length,
    );
  });

  it('points every community at a religion that exists', () => {
    const codes = new Set(dataset.religions.map((r) => r.code));
    for (const community of dataset.communities) {
      expect(codes.has(community.religionCode)).toBe(true);
    }
  });
});

function communitiesOf(
  dataset: ReturnType<typeof loadReligionDataset>,
  code: string,
): string[] {
  return dataset.religions.find((r) => r.code === code)?.communities ?? [];
}
