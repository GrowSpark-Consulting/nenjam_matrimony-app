import {
  AGENT_CONTENT,
  AGENT_SHARE_MESSAGE_EN,
  AGENT_SHARE_MESSAGE_TA,
  AGENT_TAMIL_LABEL_PENDING,
  StaticAgentContent,
} from './agent-content';

describe('AGENT_CONTENT', () => {
  it('has a label for every agent status, stage, commission status and payout status', () => {
    expect(Object.keys(AGENT_CONTENT.statusLabels).sort()).toEqual([
      'ACTIVE',
      'PENDING_APPROVAL',
      'REJECTED',
      'SUSPENDED',
      'TERMINATED',
    ]);
    expect(Object.keys(AGENT_CONTENT.stageLabels).sort()).toEqual([
      'PROFILE_COMPLETE',
      'PURCHASED',
      'REGISTERED',
    ]);
    expect(Object.keys(AGENT_CONTENT.commissionStatusLabels).sort()).toEqual([
      'APPROVED',
      'CANCELLED',
      'ON_HOLD',
      'PAID',
    ]);
    expect(Object.keys(AGENT_CONTENT.payoutStatusLabels).sort()).toEqual([
      'CANCELLED',
      'CREATED',
      'PAID',
    ]);
  });

  it('uses the English words the API contract names', () => {
    expect(AGENT_CONTENT.statusLabels.PENDING_APPROVAL.en).toBe('Under review');
    expect(AGENT_CONTENT.statusLabels.SUSPENDED.en).toBe('Paused');
    expect(AGENT_CONTENT.payoutStatusLabels.CREATED.en).toBe('Processing');
  });

  it('leaves every Tamil label as the single pending placeholder', () => {
    const groups = [
      AGENT_CONTENT.statusLabels,
      AGENT_CONTENT.stageLabels,
      AGENT_CONTENT.commissionStatusLabels,
      AGENT_CONTENT.payoutStatusLabels,
    ];
    for (const group of groups) {
      for (const label of Object.values(group)) {
        expect(label.ta).toBe(AGENT_TAMIL_LABEL_PENDING);
        expect(label.en).not.toBe('');
      }
    }
    expect(AGENT_TAMIL_LABEL_PENDING).toBe('<to be supplied>');
  });
});

describe('approved share-message wording (Raja, 28 Oct)', () => {
  it('English is exactly the approved text, link on its own last line', () => {
    expect(AGENT_SHARE_MESSAGE_EN).toBe(
      "Hi! I'm {agent_name}. Join Nenjam, a trusted matrimony app, and use my referral code {code} when you sign up to get {discount_percent}% off your first plan.\n{link}",
    );
  });

  it('Tamil is exactly the approved text, link on its own last line', () => {
    expect(AGENT_SHARE_MESSAGE_TA).toBe(
      'வணக்கம்! நான் {agent_name}. நம்பகமான திருமண வரன் தேடல் செயலியான "நெஞ்சம்" (Nenjam)-இல் இணையுங்கள். பதிவு செய்யும்போது என் பரிந்துரைக் குறியீடு {code} பயன்படுத்தினால், உங்கள் முதல் திட்டத்தில் {discount_percent}% தள்ளுபடி கிடைக்கும்.\n{link}',
    );
  });

  it('both use exactly the four placeholders, each as needed', () => {
    for (const text of [AGENT_SHARE_MESSAGE_EN, AGENT_SHARE_MESSAGE_TA]) {
      const found = [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();
      expect(found).toEqual(['agent_name', 'code', 'discount_percent', 'link']);
      expect(text.endsWith('\n{link}')).toBe(true);
    }
  });

  it('is served as one template with id "default"', () => {
    expect(AGENT_CONTENT.shareMessageTemplates).toEqual([
      {
        id: 'default',
        text: { en: AGENT_SHARE_MESSAGE_EN, ta: AGENT_SHARE_MESSAGE_TA },
      },
    ]);
  });
});

describe('StaticAgentContent', () => {
  it('returns the content, and editing the result does not change it', async () => {
    const port = new StaticAgentContent();
    const first = await port.getContent();
    expect(first).toEqual(AGENT_CONTENT);
    first.statusLabels.ACTIVE.en = 'changed';
    first.shareMessageTemplates[0].text.ta = 'changed';
    const second = await port.getContent();
    expect(second.statusLabels.ACTIVE.en).toBe('Active');
    expect(second).toEqual(AGENT_CONTENT);
  });
});
