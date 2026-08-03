import { JOB_PRIORITY, type JobPriority } from '@app/queue';

/**
 * Every email the platform can send. This is the only thing business logic
 * names — it never names a template file, a subject line, or a provider.
 */
export enum EmailType {
  WELCOME = 'WELCOME',
  OTP = 'OTP',
  VERIFY_EMAIL = 'VERIFY_EMAIL',
  FORGOT_PASSWORD = 'FORGOT_PASSWORD',
  MATCH_FOUND = 'MATCH_FOUND',
  PROFILE_VIEWED = 'PROFILE_VIEWED',
  NEW_MESSAGE = 'NEW_MESSAGE',
  SUBSCRIPTION = 'SUBSCRIPTION',
  PAYMENT_SUCCESS = 'PAYMENT_SUCCESS',
  PAYMENT_FAILED = 'PAYMENT_FAILED',
  WEEKLY_DIGEST = 'WEEKLY_DIGEST',
  ACCOUNT_SECURITY = 'ACCOUNT_SECURITY',
}

export interface EmailTypeDefinition {
  /** Basename of the .hbs file in libs/mail/src/templates. */
  template: string;
  /** Handlebars expression evaluated against the payload. */
  subject: string;
  priority: JobPriority;
  /**
   * Transactional mail is a direct response to a user action (OTP, receipt)
   * and must ignore notification preferences. Non-transactional mail is
   * engagement and is suppressible — see MailService.isSuppressed.
   */
  transactional: boolean;
}

/**
 * The single mapping from "what happened" to "what gets sent".
 *
 * Centralised so adding an email is one entry plus one .hbs file, and so the
 * subject line lives beside the template it belongs to rather than being
 * passed in from a call site that shouldn't know it.
 */
export const EMAIL_TYPE_DEFINITIONS: Record<EmailType, EmailTypeDefinition> = {
  [EmailType.WELCOME]: {
    template: 'welcome',
    subject: 'Welcome to Nenjam Matrimony, {{firstName}}',
    priority: JOB_PRIORITY.HIGH,
    transactional: true,
  },
  [EmailType.OTP]: {
    template: 'otp',
    subject: '{{code}} is your Nenjam Matrimony verification code',
    priority: JOB_PRIORITY.CRITICAL,
    transactional: true,
  },
  [EmailType.VERIFY_EMAIL]: {
    template: 'verify-email',
    subject: 'Confirm your email address',
    priority: JOB_PRIORITY.CRITICAL,
    transactional: true,
  },
  [EmailType.FORGOT_PASSWORD]: {
    template: 'forgot-password',
    subject: 'Reset your Nenjam Matrimony password',
    priority: JOB_PRIORITY.CRITICAL,
    transactional: true,
  },
  [EmailType.MATCH_FOUND]: {
    template: 'new-match',
    subject: 'You have a new match on Nenjam Matrimony',
    priority: JOB_PRIORITY.NORMAL,
    transactional: false,
  },
  [EmailType.PROFILE_VIEWED]: {
    template: 'profile-viewed',
    subject: 'Someone viewed your profile',
    priority: JOB_PRIORITY.NORMAL,
    transactional: false,
  },
  [EmailType.NEW_MESSAGE]: {
    template: 'new-message',
    subject: 'New message from {{senderName}}',
    priority: JOB_PRIORITY.NORMAL,
    transactional: false,
  },
  [EmailType.SUBSCRIPTION]: {
    template: 'subscription-renewal',
    subject: 'Your {{planName}} plan renews on {{renewalDate}}',
    priority: JOB_PRIORITY.HIGH,
    transactional: true,
  },
  [EmailType.PAYMENT_SUCCESS]: {
    template: 'premium-activated',
    subject: '{{planName}} is now active',
    priority: JOB_PRIORITY.HIGH,
    transactional: true,
  },
  [EmailType.PAYMENT_FAILED]: {
    template: 'payment-failed',
    subject: 'Payment failed for your {{planName}} plan',
    priority: JOB_PRIORITY.HIGH,
    transactional: true,
  },
  [EmailType.WEEKLY_DIGEST]: {
    template: 'weekly-digest',
    subject: '{{matchCount}} new matches for you this week',
    priority: JOB_PRIORITY.LOW,
    transactional: false,
  },
  [EmailType.ACCOUNT_SECURITY]: {
    template: 'account-security',
    subject: 'Security alert on your account',
    priority: JOB_PRIORITY.CRITICAL,
    transactional: true,
  },
};
