import type { PrismaClient } from '@app/database';
import type { AgentClientMemberProfilePort } from '../ports/agent-client-ports';
import { buildAgentProgram, type AgentProgramDeps } from './agent-program';

/**
 * The factory gives the client invitations a member-profile writer that
 * goes through the ProfileService it was given (the member side's own),
 * and reads the profile row from the same database.
 */
describe('buildAgentProgram: an accepted client gets her member profile', () => {
  const findUnique = jest.fn<Promise<{ userId: string } | null>, [unknown]>();
  const profiles = {
    syncMatchableFromDraft: jest.fn<Promise<void>, [string]>(() =>
      Promise.resolve(),
    ),
  };
  const deps: AgentProgramDeps = {
    prisma: { userProfile: { findUnique } } as unknown as PrismaClient,
    platformSettings: {} as AgentProgramDeps['platformSettings'],
    otp: {} as AgentProgramDeps['otp'],
    hashing: {} as AgentProgramDeps['hashing'],
    adminAudit: {} as AgentProgramDeps['adminAudit'],
    firebase: {} as AgentProgramDeps['firebase'],
    agentOtp: { dummyEnabled: false, dummyPhones: [] },
    locations: { resolve: () => Promise.resolve(null) },
    religions: { resolve: () => Promise.resolve(null) },
    profiles,
    env: {},
    logger: { warn: jest.fn() },
  };

  /** The writer the client invitations were built with (a private dependency). */
  const writerOf = (program: ReturnType<typeof buildAgentProgram>) =>
    (
      program.clientInvites as unknown as {
        deps: { memberProfiles: AgentClientMemberProfilePort };
      }
    ).deps.memberProfiles;

  it('makes the profile through the given ProfileService', async () => {
    const writer = writerOf(buildAgentProgram(deps));
    await writer.createFromDraft('member-1');
    expect(profiles.syncMatchableFromDraft).toHaveBeenCalledWith('member-1');
  });

  it('looks for her profile row by her user id', async () => {
    const writer = writerOf(buildAgentProgram(deps));
    findUnique.mockResolvedValueOnce({ userId: 'member-1' });
    await expect(writer.exists('member-1')).resolves.toBe(true);
    findUnique.mockResolvedValueOnce(null);
    await expect(writer.exists('member-2')).resolves.toBe(false);
    expect(findUnique.mock.calls.map((c) => c[0])).toEqual([
      { where: { userId: 'member-1' }, select: { userId: true } },
      { where: { userId: 'member-2' }, select: { userId: true } },
    ]);
  });
});
