/**
 * Fills a share-message template with an agent's details.
 *
 * Plain string replacement only: the template is never evaluated or
 * interpreted. Placeholders are replaced in a single pass, so a value that
 * itself looks like a placeholder (an agent named "{code}") is inserted as
 * text and not expanded again. Unknown placeholders are left untouched.
 */

export interface ShareMessageValues {
  agentName: string;
  code: string;
  discountPercent: number | string;
  /** Null or empty while the public web address is not decided. */
  link: string | null;
}

const PLACEHOLDER = /\{(agent_name|code|discount_percent|link)\}/g;
const LINK_PLACEHOLDER = '{link}';

export function renderShareMessage(
  template: string,
  values: ShareMessageValues,
): string {
  const link = values.link?.trim() ? values.link : null;

  let text = template;
  if (link === null) {
    // No link yet: drop every line that would carry it, and do not leave a
    // blank line behind at the end.
    const lines = template.split('\n');
    const kept = lines.filter((line) => !line.includes(LINK_PLACEHOLDER));
    if (kept.length !== lines.length) {
      while (kept.length > 0 && kept[kept.length - 1].trim() === '') {
        kept.pop();
      }
      text = kept.join('\n');
    }
  }

  const replacements: Record<string, string> = {
    agent_name: values.agentName,
    code: values.code,
    discount_percent: String(values.discountPercent),
    link: link ?? '',
  };

  return text.replace(
    PLACEHOLDER,
    (_match, name: string) => replacements[name],
  );
}
