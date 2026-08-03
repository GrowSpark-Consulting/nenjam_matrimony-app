import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import * as Handlebars from 'handlebars';
import { AppConfigService } from '@app/config';
import type { EmailPayload } from './interfaces/email.interface';

/**
 * Compiles the Handlebars templates and wraps each in the shared layout.
 *
 * This file sits at the root of libs/mail/src on purpose. Templates live in
 * `<this file's dir>/templates`, and that single expression resolves in both
 * layouts we actually run in:
 *
 *   ts-node / jest : libs/mail/src            -> libs/mail/src/templates      ✔
 *   webpack bundle : dist/apps/worker         -> dist/apps/worker/templates   ✔
 *
 * The second only works because nest-cli.json copies *.hbs to
 * dist/apps/worker/templates for the worker build — webpack inlines .ts but
 * knows nothing about .hbs. Moving this file breaks the dist case silently, so
 * TemplateRenderer.onModuleInit fails fast at boot rather than at first send.
 */
@Injectable()
export class TemplateRenderer implements OnModuleInit {
  private readonly logger = new Logger(TemplateRenderer.name);
  private readonly cache = new Map<string, HandlebarsTemplateDelegate>();
  private layout?: HandlebarsTemplateDelegate;

  /** Overridable for tests and unusual deployment layouts. */
  private readonly templateDir =
    process.env.MAIL_TEMPLATE_DIR?.trim() || join(__dirname, 'templates');

  constructor(private readonly configService: AppConfigService) {
    registerHelpers();
  }

  /**
   * Compiles every template at boot.
   *
   * Eager on purpose: a syntax error or a missing file otherwise surfaces as a
   * failed job in a worker at 3am. Paying ~10ms at startup turns that into a
   * refused boot with the filename in the message.
   */
  onModuleInit(): void {
    if (!existsSync(this.templateDir)) {
      throw new Error(
        `Email template directory not found at "${this.templateDir}". ` +
          'For a bundled build, check the "assets" entry for the worker in nest-cli.json.',
      );
    }

    const files = readdirSync(this.templateDir).filter((f) =>
      f.endsWith('.hbs'),
    );
    for (const file of files) {
      const name = file.replace(/\.hbs$/, '');
      const source = readFileSync(join(this.templateDir, file), 'utf8');
      try {
        const compiled = Handlebars.compile(source, { strict: false });
        if (name === 'layout') {
          this.layout = compiled;
        } else {
          this.cache.set(name, compiled);
        }
      } catch (error) {
        throw new Error(
          `Failed to compile email template "${file}": ${(error as Error).message}`,
        );
      }
    }

    if (!this.layout) {
      throw new Error(`layout.hbs is missing from "${this.templateDir}".`);
    }
    this.logger.log(
      `Compiled ${this.cache.size} email template(s) from ${this.templateDir}.`,
    );
  }

  /**
   * Renders a template body and wraps it in the layout.
   *
   * Every value interpolated from `payload` goes through `{{ }}`, so
   * Handlebars HTML-escapes it. A display name of `<script>…` renders as
   * inert text. The one unescaped insertion is the layout's `{{{body}}}`,
   * which receives renderer-produced markup whose own substitutions were
   * already escaped by this same call — never raw caller input.
   */
  render(templateName: string, payload: EmailPayload): string {
    const template = this.cache.get(templateName);
    if (!template) {
      throw new Error(
        `Unknown email template "${templateName}". Available: ${[...this.cache.keys()].sort().join(', ')}.`,
      );
    }

    const brand = this.brandContext();
    const body = template({ ...payload, ...brand });
    return this.layout!({ ...payload, ...brand, body });
  }

  /** Values every template's layout needs. Config-driven so a deployment can
   *  rebrand without touching the templates. */
  private brandContext(): Record<string, unknown> {
    const { appUrl, supportEmail, logoUrl } = this.configService.mail;
    return { appUrl, supportEmail, logoUrl, year: new Date().getFullYear() };
  }

  /** Compiled template names, excluding the layout. Used by tests. */
  availableTemplates(): string[] {
    return [...this.cache.keys()].sort();
  }
}

let helpersRegistered = false;

/** Handlebars' registry is module-global, so guard against re-registering
 *  when several Nest test modules construct a renderer in one process. */
function registerHelpers(): void {
  if (helpersRegistered) return;
  helpersRegistered = true;

  // Pluralisation for digest copy: {{plural count "match" "matches"}}
  Handlebars.registerHelper(
    'plural',
    (count: number, singular: string, plural: string) =>
      Number(count) === 1 ? singular : plural,
  );

  // {{#if (gt count 0)}} — Handlebars has no built-in comparison.
  Handlebars.registerHelper(
    'gt',
    (a: number, b: number) => Number(a) > Number(b),
  );
}

/**
 * Derives the plaintext alternative from the rendered HTML.
 *
 * Not cosmetic: an HTML-only message scores worse with spam filters, and some
 * clients (watches, screen readers, plaintext-preferring users) show this
 * instead. Link targets are kept inline as "text (url)" so a text reader can
 * still act on the CTA.
 */
export function htmlToPlainText(html: string): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<head[\s\S]*?<\/head>/gi, '')
    .replace(
      /<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi,
      (_m: string, href: string, text: string) => {
        const label = text.replace(/<[^>]+>/g, '').trim();
        return label && label !== href ? `${label} (${href})` : href;
      },
    )
    .replace(/<(br|\/p|\/div|\/tr|\/h[1-6])\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_m, code) => String.fromCharCode(Number(code)))
    .replace(/[ \t]+/g, ' ')
    .replace(/\n\s*\n\s*\n+/g, '\n\n')
    .split('\n')
    .map((line) => line.trim())
    .join('\n')
    .trim();
}
