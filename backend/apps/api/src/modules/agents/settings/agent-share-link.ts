/**
 * `referral.share_link_base_url`: the web address an agent's share link and
 * QR code start with. The link is `{base}/?ref={code}` (the code
 * URL-encoded) and the QR payload is that same link; the member web app
 * reads `?ref=` and fills in its referral code box.
 *
 * Seeded as JSON `null` (20261104090000_agent_share_link_setting) so a Super
 * Admin can find it and set it in the admin settings; nothing in code or SQL
 * sets a value. Null, missing, or a value this file's rule refuses means NO
 * link: `link` and `qrPayload` are both null and the share messages drop the
 * link line. It never makes a route fail.
 *
 * The rule (also the validator registered for the key, so a bad value is
 * refused at admin entry): an https origin and nothing else, written exactly
 * as the browser writes it (`https://host`, lower case, no trailing slash,
 * no port 443, no user, no path, query or fragment), and never containing
 * "agent" in any case. The same "agent" check is made on the finished link,
 * because a code's letters could spell it too.
 */
export const REFERRAL_SHARE_LINK_BASE_URL_KEY = 'referral.share_link_base_url';

const AGENT_WORD = /agent/i;

/** The validator registered for the key (refused values answer 400 at admin entry). */
export function referralShareLinkBaseUrlProblem(value: unknown): string | null {
  if (value === null) return null;
  const problem = `Setting ${REFERRAL_SHARE_LINK_BASE_URL_KEY} must be null or an https web address with no path, query or fragment (for example https://app.example.com), and must not contain "agent".`;
  if (typeof value !== 'string' || AGENT_WORD.test(value)) return problem;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return problem;
  }
  return url.protocol === 'https:' && url.origin === value ? null : problem;
}

/**
 * The share link for [code] from the stored settings, or null when there is
 * no usable base (see the rule above) or the link would contain "agent".
 */
export function referralShareLink(
  raw: Record<string, unknown>,
  code: string,
): string | null {
  const base = Object.prototype.hasOwnProperty.call(
    raw,
    REFERRAL_SHARE_LINK_BASE_URL_KEY,
  )
    ? raw[REFERRAL_SHARE_LINK_BASE_URL_KEY]
    : undefined;
  if (typeof base !== 'string' || referralShareLinkBaseUrlProblem(base)) {
    return null;
  }
  const link = `${base}/?ref=${encodeURIComponent(code)}`;
  return AGENT_WORD.test(link) ? null : link;
}
