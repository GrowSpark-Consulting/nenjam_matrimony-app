import { PushDispatchService } from '../services/push-dispatch.service';

function build() {
  const repo = {
    findActiveTokens: jest.fn().mockResolvedValue([{ fcmToken: 't-peer' }]),
    findActiveTokensExcludingUser: jest
      .fn()
      .mockResolvedValue([{ fcmToken: 't-peer' }]),
    deactivateTokens: jest.fn().mockResolvedValue(undefined),
    findLatestActiveToken: jest.fn(),
    upsertDeviceToken: jest.fn(),
    deactivateOwnToken: jest.fn(),
  };
  const firebase = {
    sendMulticastPush: jest.fn().mockResolvedValue({ invalidTokens: [] }),
  };
  const service = new PushDispatchService(repo as never, firebase as never);
  return { service, repo, firebase };
}

const payload = { title: 'Asha Patel', body: 'hi there' };

describe('PushDispatchService.dispatchToUser', () => {
  it('sends to every active device of the recipient when nothing is excluded', async () => {
    const { service, repo, firebase } = build();
    await service.dispatchToUser('peer', payload);

    expect(repo.findActiveTokens).toHaveBeenCalledWith('peer');
    expect(repo.findActiveTokensExcludingUser).not.toHaveBeenCalled();
    expect(firebase.sendMulticastPush).toHaveBeenCalledWith(
      ['t-peer'],
      payload,
      undefined,
    );
  });

  it('excludes the excluded user devices from the recipient token list', async () => {
    const { service, repo, firebase } = build();
    await service.dispatchToUser('peer', payload, { excludeUserId: 'me' });

    expect(repo.findActiveTokens).not.toHaveBeenCalled();
    expect(repo.findActiveTokensExcludingUser).toHaveBeenCalledWith(
      'peer',
      'me',
    );
    expect(firebase.sendMulticastPush).toHaveBeenCalledWith(
      ['t-peer'],
      payload,
      undefined,
    );
  });

  it('sends nothing when every recipient token belongs to the excluded user', async () => {
    const { service, repo, firebase } = build();
    repo.findActiveTokensExcludingUser.mockResolvedValue([]);

    await service.dispatchToUser('peer', payload, { excludeUserId: 'me' });

    expect(firebase.sendMulticastPush).not.toHaveBeenCalled();
  });

  it('suppresses the send entirely when the recipient is the excluded user', async () => {
    const { service, repo, firebase } = build();
    await service.dispatchToUser('me', payload, { excludeUserId: 'me' });

    expect(repo.findActiveTokens).not.toHaveBeenCalled();
    expect(repo.findActiveTokensExcludingUser).not.toHaveBeenCalled();
    expect(firebase.sendMulticastPush).not.toHaveBeenCalled();
  });

  it('deactivates tokens FCM reports as permanently dead', async () => {
    const { service, repo, firebase } = build();
    firebase.sendMulticastPush.mockResolvedValue({
      invalidTokens: ['t-peer'],
    });

    await service.dispatchToUser('peer', payload, { excludeUserId: 'me' });

    expect(repo.deactivateTokens).toHaveBeenCalledWith(['t-peer']);
  });

  it('never throws back at the domain write that triggered it', async () => {
    const { service, firebase } = build();
    firebase.sendMulticastPush.mockRejectedValue(new Error('FCM down'));

    await expect(
      service.dispatchToUser('peer', payload, { excludeUserId: 'me' }),
    ).resolves.toBeUndefined();
  });
});
