// Approved Help & Support text for agents, copied verbatim from the
// `partnerHelp*` entries of Frontend/lib/l10n/app_en.arb (the same wording the
// app shows). Do not reword it here: change the approved source and re-copy.
// English only; no Tamil version has been supplied.

/** Shown until the support contact is confirmed. Never invent one. */
export const SUPPORT_CONTACT_PLACEHOLDER = '<support contact to be confirmed>';

export const help = {
  title: "Help & Support",
  welcome: "Welcome to the Nenjam Partner Program.",
  sections: [
    { title: "Getting started", body: "Sign in with your mobile number and the one-time code (OTP) we send you. Then fill in your application. Our team reviews it and either approves it or tells you why it was not approved. Once you are approved, you get your personal referral code." },
    { title: "Referring members", body: "Share your referral code, or the ready-made English or Tamil message in the portal. People can enter your code when they sign up, or at payment when they buy their first paid plan. A person stays linked to the first agent whose code they used." },
    { title: "Tracking referrals and earnings", body: "For privacy, you only see limited details about the people you referred: first name and last initial, age, city, their stage and a partly hidden phone number. You earn a commission only when someone you referred buys their first paid plan, and only once. Renewals and later plans do not earn commission. The commission is held for a short period, then approved, and paid by our team in the monthly payout." },
    { title: "Bank details", body: "Add your UPI ID or bank account details carefully and check them before saving. Your PAN is needed before your first payout. If you change your payment details, they are checked again and your next payout may wait a short while." },
  ],
  termsTitle: "Agent terms (main points)",
  terms: [
    "Never charge families any fee for joining.",
    "Never make false promises about matches.",
    "Never share information about the people you refer or your clients.",
    "Never create a profile for someone without their agreement.",
  ],
  termsConsequence: "Breaking these rules can lead to your account being paused.",
  needHelpTitle: "Need help?",
  /** Contains `{contact}`. */
  contact: "Contact the Nenjam team at {contact}.",
  otpWarning: "Never share your OTP or any login details with anyone.",
} as const;
