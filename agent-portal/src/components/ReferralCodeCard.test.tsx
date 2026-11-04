import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReferralLink } from '../api/types';
import { ReferralCodeCard } from './ReferralCodeCard';

/** Share link + QR on the referral card. Test data only, no backend. */

const LINK = 'https://nenjammatrimony.test/?ref=NM7K2P9X';

function make(over: Partial<ReferralLink> = {}): ReferralLink {
  return {
    codeId: 'c1',
    code: 'NM7K2P9X',
    isPrimary: true,
    link: LINK,
    qrPayload: LINK,
    shareMessages: [],
    shareable: true,
    ...over,
  };
}

/** userEvent.setup() installs its own clipboard, so spy after calling it. */
function clipboard(user: ReturnType<typeof userEvent.setup>) {
  void user;
  return vi.spyOn(navigator.clipboard, 'writeText');
}

describe('share link', () => {
  it('shows the exact URL and copies exactly that', async () => {
    const user = userEvent.setup();
    const writeText = clipboard(user);
    render(<ReferralCodeCard link={make()} />);
    expect(screen.getByLabelText('Share link')).toHaveTextContent(LINK);
    await user.click(screen.getByRole('button', { name: 'Copy link' }));
    expect(writeText).toHaveBeenCalledExactlyOnceWith(LINK);
    expect(await screen.findByText('Link copied to your clipboard.')).toBeInTheDocument();
  });

  it('says so when copying fails', async () => {
    const user = userEvent.setup();
    clipboard(user).mockRejectedValue(new Error('denied'));
    render(<ReferralCodeCard link={make()} />);
    await user.click(screen.getByRole('button', { name: 'Copy link' }));
    expect(await screen.findByText(/Couldn't copy. Select the link/)).toBeInTheDocument();
  });

  it.each([null, '', '   '])('no link (%j): no link text and no Copy link button', (v) => {
    render(<ReferralCodeCard link={make({ link: v })} />);
    expect(screen.queryByLabelText('Share link')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Copy link' })).toBeNull();
    // The code itself is always there.
    expect(screen.getByRole('button', { name: 'Copy code' })).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(/undefined|null/);
  });
});

describe('QR code', () => {
  it('renders the QR and downloads an SVG of exactly that payload', async () => {
    const user = userEvent.setup();
    const blobs: Blob[] = [];
    URL.createObjectURL = vi.fn((b: Blob) => {
      blobs.push(b);
      return 'blob:qr';
    });
    URL.revokeObjectURL = vi.fn();
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    render(<ReferralCodeCard link={make()} />);
    expect(document.querySelector('.qr svg')).not.toBeNull();

    await user.click(screen.getByRole('button', { name: 'Download QR' }));

    expect(click).toHaveBeenCalledTimes(1);
    expect(blobs).toHaveLength(1);
    expect(blobs[0].type).toContain('image/svg+xml');
    const text = await blobs[0].text();
    expect(text).toContain('xmlns="http://www.w3.org/2000/svg"');
    // Same drawing as on screen (identical path data), not a regenerated QR.
    const shown = document.querySelector('.qr svg')!;
    const paths = (el: Element) => [...el.querySelectorAll('path')].map((p) => p.getAttribute('d'));
    const parsed = new DOMParser().parseFromString(text, 'image/svg+xml').documentElement;
    expect(paths(parsed)).toEqual(paths(shown));
    expect(screen.queryByRole('alert')).toBeNull();
    click.mockRestore();
  });

  it('shows a visible error when the download fails', async () => {
    const user = userEvent.setup();
    URL.createObjectURL = vi.fn(() => {
      throw new Error('boom');
    });
    render(<ReferralCodeCard link={make()} />);
    await user.click(screen.getByRole('button', { name: 'Download QR' }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(/Couldn't download the QR/));
  });

  it.each([null, '', '  '])('no QR data (%j): no QR and no Download button', (v) => {
    render(<ReferralCodeCard link={make({ qrPayload: v })} />);
    expect(document.querySelector('.qr')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Download QR' })).toBeNull();
  });
});
