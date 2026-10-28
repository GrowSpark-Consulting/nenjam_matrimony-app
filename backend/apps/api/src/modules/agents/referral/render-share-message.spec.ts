import { renderShareMessage, ShareMessageValues } from './render-share-message';

const values = (
  overrides: Partial<ShareMessageValues> = {},
): ShareMessageValues => ({
  agentName: 'Ravi K.',
  code: 'NM7K2P9X',
  discountPercent: 5,
  link: 'https://example.invalid/r/NM7K2P9X',
  ...overrides,
});

const TEMPLATE = [
  'Join Nenjam Matrimony with my code {code}.',
  'You get {discount_percent}% off your first plan.',
  'Sign up here: {link}',
  '- {agent_name}',
].join('\n');

describe('renderShareMessage', () => {
  describe('each placeholder', () => {
    it('{agent_name}', () => {
      expect(renderShareMessage('Hi from {agent_name}', values())).toBe(
        'Hi from Ravi K.',
      );
    });

    it('{code}', () => {
      expect(renderShareMessage('Code: {code}', values())).toBe(
        'Code: NM7K2P9X',
      );
    });

    it('{discount_percent} as a number or a string', () => {
      expect(renderShareMessage('{discount_percent}% off', values())).toBe(
        '5% off',
      );
      expect(
        renderShareMessage(
          '{discount_percent}% off',
          values({ discountPercent: '7.5' }),
        ),
      ).toBe('7.5% off');
    });

    it('{link}', () => {
      expect(renderShareMessage('Go: {link}', values())).toBe(
        'Go: https://example.invalid/r/NM7K2P9X',
      );
    });

    it('all of them in a multi-line template', () => {
      expect(renderShareMessage(TEMPLATE, values())).toBe(
        [
          'Join Nenjam Matrimony with my code NM7K2P9X.',
          'You get 5% off your first plan.',
          'Sign up here: https://example.invalid/r/NM7K2P9X',
          '- Ravi K.',
        ].join('\n'),
      );
    });
  });

  describe('missing link', () => {
    it.each([null, '', '   '])(
      'removes the whole link line (link %p)',
      (link) => {
        expect(renderShareMessage(TEMPLATE, values({ link }))).toBe(
          [
            'Join Nenjam Matrimony with my code NM7K2P9X.',
            'You get 5% off your first plan.',
            '- Ravi K.',
          ].join('\n'),
        );
      },
    );

    it('does not leave a blank line at the end when the link line was last', () => {
      const template = 'Use code {code}.\n\nSign up: {link}\n';
      expect(renderShareMessage(template, values({ link: null }))).toBe(
        'Use code NM7K2P9X.',
      );
    });

    it('removes every line that carries {link}', () => {
      const template = 'A {link}\nB {code}\nC {link}';
      expect(renderShareMessage(template, values({ link: null }))).toBe(
        'B NM7K2P9X',
      );
    });

    it('keeps the rest of the text exactly when only a middle line goes', () => {
      const template = 'Line 1\n{link}\nLine 3';
      expect(renderShareMessage(template, values({ link: null }))).toBe(
        'Line 1\nLine 3',
      );
    });

    it('returns an empty string when the template was only the link', () => {
      expect(renderShareMessage('{link}', values({ link: null }))).toBe('');
    });
  });

  describe('templates without a link line', () => {
    it('are unchanged apart from the placeholders, trailing newline included', () => {
      const template = 'Use code {code}.\n';
      expect(renderShareMessage(template, values({ link: null }))).toBe(
        'Use code NM7K2P9X.\n',
      );
      expect(renderShareMessage(template, values())).toBe(
        'Use code NM7K2P9X.\n',
      );
    });
  });

  describe('repeated and unknown placeholders', () => {
    it('replaces every occurrence', () => {
      expect(renderShareMessage('{code} / {code} / {code}', values())).toBe(
        'NM7K2P9X / NM7K2P9X / NM7K2P9X',
      );
    });

    it('leaves unknown placeholders untouched', () => {
      expect(
        renderShareMessage('{code} {name} {Code} {{code}} {CODE}', values()),
      ).toBe('NM7K2P9X {name} {Code} {NM7K2P9X} {CODE}');
    });

    it('does not expand a value that looks like a placeholder', () => {
      expect(
        renderShareMessage(
          '{agent_name}: {code}',
          values({ agentName: '{code}{link}' }),
        ),
      ).toBe('{code}{link}: NM7K2P9X');
    });

    it('inserts special replacement sequences literally', () => {
      expect(
        renderShareMessage(
          '{agent_name}',
          values({ agentName: "$& $1 $$ $'" }),
        ),
      ).toBe("$& $1 $$ $'");
    });
  });

  describe('a full stop at the end of the agent name', () => {
    it('is not doubled when the template follows {agent_name} with a full stop', () => {
      expect(
        renderShareMessage(
          "I'm {agent_name}. Join us.",
          values({ agentName: 'Ravi K.' }),
        ),
      ).toBe("I'm Ravi K. Join us.");
    });

    it('strips only ONE trailing full stop', () => {
      expect(
        renderShareMessage('{agent_name}. Hi', values({ agentName: 'Ravi..' })),
      ).toBe('Ravi.. Hi');
    });

    it('leaves a name with no trailing full stop alone', () => {
      expect(
        renderShareMessage(
          "I'm {agent_name}. Join",
          values({ agentName: 'Ravi Kumar' }),
        ),
      ).toBe("I'm Ravi Kumar. Join");
    });

    it('keeps the full stop when the template does not add one', () => {
      expect(
        renderShareMessage('- {agent_name}', values({ agentName: 'Ravi K.' })),
      ).toBe('- Ravi K.');
    });

    it('works for Tamil names too', () => {
      expect(
        renderShareMessage(
          'நான் {agent_name}. இணையுங்கள்',
          values({
            agentName: 'ரவி கு.',
          }),
        ),
      ).toBe('நான் ரவி கு. இணையுங்கள்');
    });

    it('strips each occurrence followed by a full stop, not one followed by something else', () => {
      expect(
        renderShareMessage(
          '{agent_name}. / {agent_name}!',
          values({ agentName: 'Ravi K.' }),
        ),
      ).toBe('Ravi K. / Ravi K.!');
    });
  });

  describe('never evaluates the template', () => {
    it.each(['${1+1}', '{{constructor}}', '<%= code %>', '{__proto__}'])(
      'leaves %p as plain text',
      (template) => {
        expect(renderShareMessage(template, values())).toBe(template);
      },
    );
  });

  describe('Tamil text', () => {
    it('survives unchanged around the placeholders', () => {
      const template = [
        'என் குறியீடு {code} உடன் நெஞ்சம் மேட்ரிமோனியில் சேருங்கள்.',
        'முதல் திட்டத்தில் {discount_percent}% தள்ளுபடி.',
        'இங்கே பதிவு செய்யுங்கள்: {link}',
        '— {agent_name}',
      ].join('\n');
      expect(
        renderShareMessage(template, values({ agentName: 'ரவி கு.' })),
      ).toBe(
        [
          'என் குறியீடு NM7K2P9X உடன் நெஞ்சம் மேட்ரிமோனியில் சேருங்கள்.',
          'முதல் திட்டத்தில் 5% தள்ளுபடி.',
          'இங்கே பதிவு செய்யுங்கள்: https://example.invalid/r/NM7K2P9X',
          '— ரவி கு.',
        ].join('\n'),
      );
    });

    it('drops the Tamil link line when there is no link', () => {
      const template = 'குறியீடு: {code}\nஇணைப்பு: {link}';
      expect(renderShareMessage(template, values({ link: null }))).toBe(
        'குறியீடு: NM7K2P9X',
      );
    });
  });
});
