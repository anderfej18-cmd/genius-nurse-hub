// Everything the landing page says, in one place. Each claim here is a fact about the product as
// built: numbers come from the same rules the server enforces (`exam-rules`), session choices come
// from `session-modes`, and level names come from `progress-view`. There are no statistics about
// students, no pass rates and no testimonials, and a test (`landing-content.test.ts`) keeps it so.
//
// British spelling: "practise" is the verb, "practice" the noun, "programme" not "program".

import {
  MAX_SESSION_MINUTES,
  MIN_SESSION_MINUTES,
  TIER_DAILY_LIMIT,
  TIER_LABEL,
  TIER_SESSION_LIMIT,
  type Tier,
} from "@/lib/exam-rules";
import { masteryLevelText } from "@/lib/progress-view";
import { SELECTION_CHOICES, SELECTION_LABELS } from "@/lib/session-modes";

export const SITE_NAME = "NurseGenius";

/** The sections the page scrolls between. Each is the `id` of a section element. */
export const LANDING_SECTIONS = [
  "how-it-works",
  "pathways",
  "practice",
  "progress",
  "ai",
  "plan",
  "plans",
  "faq",
] as const;
export type LandingSectionId = (typeof LANDING_SECTIONS)[number];

export interface LandingLink {
  label: string;
  /** A section anchor ("#faq") on this page. */
  href: `#${LandingSectionId}`;
}

/** The links in the top bar and the footer: five in the bar so it stays on one line. */
export const NAV_LINKS: readonly LandingLink[] = [
  { label: "How it works", href: "#how-it-works" },
  { label: "Practice", href: "#practice" },
  { label: "Progress", href: "#progress" },
  { label: "Plans", href: "#plans" },
  { label: "FAQ", href: "#faq" },
];

export const FOOTER_LINKS: readonly LandingLink[] = [
  { label: "How it works", href: "#how-it-works" },
  { label: "RN and RM pathways", href: "#pathways" },
  { label: "Practice tests", href: "#practice" },
  { label: "Progress and mastery", href: "#progress" },
  { label: "AI help", href: "#ai" },
  { label: "Study plans", href: "#plan" },
  { label: "Plans and limits", href: "#plans" },
  { label: "Questions", href: "#faq" },
];

const novice: Tier = "novice";
const novicePerDay = TIER_DAILY_LIMIT[novice];

export const HERO = {
  headline: "Know what to study next.",
  description:
    "Timed RN and RM practice with the reasoning behind every answer, and a study plan built from your own results.",
  primaryCta: "Get started",
  secondaryCta: "Explore features",
  /** Under the buttons: a fact from the tier rules, not a promise. */
  note: `Free to start. The ${TIER_LABEL[novice]} plan allows ${novicePerDay} questions a day.`,
  previewCaption: "The layout of a test. Questions come from the question bank when you start one.",
} as const;

export interface Step {
  title: string;
  body: string;
}

export const HOW_IT_WORKS = {
  title: "From the first question to exam day",
  intro: "Four steps, and each one feeds the next.",
  steps: [
    {
      title: "Choose RN or RM",
      body: "Say which programme you are preparing for, or both. You pick one each time you start a test.",
    },
    {
      title: "Practise by topic or mix everything",
      body: `Set how many questions and how many minutes, from ${MIN_SESSION_MINUTES} to ${MAX_SESSION_MINUTES}, then start.`,
    },
    {
      title: "Read the reasoning",
      body: "After you submit, see the correct answer and why it is correct, question by question.",
    },
    {
      title: "Follow the plan",
      body: "Your answers shape a weekly plan to your exam date and show which topics need work.",
    },
  ] satisfies readonly Step[],
} as const;

export interface Pathway {
  code: "RN" | "RM";
  name: string;
  summary: string;
  points: readonly string[];
}

export const PATHWAYS = {
  title: "Two programmes, kept apart",
  intro:
    "RN and RM have their own questions and their own topics, and your readiness is estimated for each on its own.",
  items: [
    {
      code: "RN",
      name: "Registered Nurse",
      summary: "Questions grouped by topic, from a single topic to every area at once.",
      points: [
        "Topics are listed with their question counts once you sign in",
        "Mastery is tracked topic by topic",
        "Readiness is estimated for RN on its own",
      ],
    },
    {
      code: "RM",
      name: "Registered Midwife",
      summary: "The same tools, applied to the midwifery question bank.",
      points: [
        "Practise one topic or mix all areas",
        "Mastery is tracked topic by topic",
        "Readiness is estimated for RM on its own",
      ],
    },
  ] satisfies readonly Pathway[],
} as const;

export interface ModeDescription {
  label: string;
  hint: string;
}

export const PRACTICE = {
  title: "A test that behaves like an exam",
  intro:
    "Every test has a timer, a question navigator and a flag for questions you want to revisit. The server keeps the time and scores the test, so the result cannot be edited on your phone.",
  modesTitle: "Four ways to choose your questions",
  /** From the product's own selection list, so the wording matches what the start screen offers. */
  modes: SELECTION_CHOICES.map(
    (mode): ModeDescription => ({
      label: SELECTION_LABELS[mode].label,
      hint: SELECTION_LABELS[mode].hint,
    }),
  ),
  rules: [
    `Tests run from ${MIN_SESSION_MINUTES} to ${MAX_SESSION_MINUTES} minutes, and finish by themselves when time is up.`,
    "Correct answers and rationales appear after you submit, in every mode.",
    "Questions come only from the NurseGenius question bank. The app never invents a question to fill a test.",
  ],
} as const;

export const PROGRESS = {
  title: "See where you stand, honestly",
  intro:
    "Each topic gets a level based on your own answers, weighted toward recent ones. A short lucky streak does not make a topic mastered.",
  levelsTitle: "The levels a topic can have",
  levels: [
    {
      level: "insufficient_data",
      description: "Too few answers to say anything fair yet, so no level is shown.",
    },
    { level: "weak", description: "Needs the most attention. Practise it first." },
    { level: "developing", description: "Getting there. Keep practising and review mistakes." },
    { level: "proficient", description: "Solid results on a fair number of answers." },
    {
      level: "mastered",
      description: "Strong results backed by plenty of answers, not a handful.",
    },
  ].map((entry) => ({ ...entry, label: masteryLevelText(entry.level) })),
  readiness:
    "Exam readiness is shown for RN and RM separately. When there is not enough evidence it says so instead of guessing a number.",
  extras: ["Confidence and pace", "Repeated mistakes", "Reviews that are overdue"],
} as const;

export const AI = {
  title: "AI that explains. The numbers come from your answers.",
  help: {
    title: "Ask about any question, after you finish",
    body: "Explain it, simplify it, compare the options, or ask why your answer was wrong. Help is available once a test is submitted, never during it.",
  },
  summaries: {
    title: "Study summaries that say where they came from",
    body: "Your scores, levels and plan are calculated by the app. A summary is marked AI-assisted only when the AI's wording checked out against those numbers. Otherwise you get a plain computed summary, labelled as one.",
    labels: ["AI-assisted", "Computed summary"],
  },
  boundary:
    "The AI does not choose your questions or change your scores. Selection is rule-based and the same every time.",
} as const;

export const PLAN = {
  title: "A plan that works back from your exam date",
  intro:
    "Set your exam date and NurseGenius builds a week-by-week plan. Every item says why it is there, and weeks you have finished are kept.",
  points: [
    {
      title: "Progress comes from real answers",
      body: "A plan item is complete when your answers show it, not when you tick a box.",
    },
    {
      title: "Insight beyond the score",
      body: "Trends, repeated mistakes, reviews that are overdue, and how fast you answer.",
    },
    {
      title: "Today's focus",
      body: "A short daily recommendation, a study streak and a daily challenge keep the next step obvious.",
    },
  ] satisfies readonly Step[],
  timeline: { start: "Today", end: "Your exam date" },
} as const;

export const PLANS_SECTION = {
  title: "Start free, upgrade when you need more",
  intro:
    "Limits are the same ones the app enforces. Prices are read live from NurseGenius and paid in naira by card through Paystack.",
  tiers: ["novice", "erudite", "scholar"] satisfies readonly Tier[],
  rows: {
    perDay: "Questions per day",
    perTest: "Most questions in one test",
    price: "Price",
    length: "Access",
  },
  featureColumn: "What the plan includes",
  free: "Free",
  noExpiry: "No expiry",
  signInForPrice: "Shown after you sign in",
  unlimited: "Unlimited",
  dailyLimit: (tier: Tier): string => {
    const limit = TIER_DAILY_LIMIT[tier];
    return limit === null ? "Unlimited" : String(limit);
  },
  testLimit: (tier: Tier): string => String(TIER_SESSION_LIMIT[tier]),
  tierLabel: (tier: Tier): string => TIER_LABEL[tier],
} as const;

export interface Question {
  question: string;
  answer: string;
}

export const FAQ = {
  title: "Questions people ask first",
  items: [
    {
      question: "Is NurseGenius free?",
      answer: `You can start free. The ${TIER_LABEL.novice} plan allows ${TIER_DAILY_LIMIT.novice} questions a day and ${TIER_SESSION_LIMIT.novice} in one test. ${TIER_LABEL.erudite} and ${TIER_LABEL.scholar} raise those limits.`,
    },
    {
      question: "What do RN and RM stand for?",
      answer:
        "RN is Registered Nurse and RM is Registered Midwife. You choose which one to practise each time you start a test.",
    },
    {
      question: "When do I see the correct answers?",
      answer:
        "After you submit the test, in every mode. The answer key is never sent to your phone while the test is running.",
    },
    {
      question: "Who scores my test?",
      answer:
        "The server does, from the answers it has saved. The timer is kept there too, so the test ends on time wherever you are.",
    },
    {
      question: "How are my questions chosen?",
      answer:
        "You pick: random, focused on your weak areas, your past mistakes, or revision that is due today. The choice follows fixed rules. AI does not pick questions.",
    },
    {
      question: "How do I pay for a bigger plan?",
      answer:
        "In naira by card through Paystack. Your plan starts after Paystack confirms the payment.",
    },
    {
      question: "Can I practise on my phone?",
      answer:
        "Yes. Every page, including the test itself, is laid out for a phone screen first and grows from there.",
    },
  ] satisfies readonly Question[],
} as const;

export const FINAL_CTA = {
  title: "Start with one test.",
  body: "Pick RN or RM, choose a topic and see how you do. Your first results already start shaping what to study next.",
  primary: "Get started",
  secondary: "Sign in",
} as const;

export const FOOTER = {
  tagline: "RN and RM exam practice, with a plan.",
  columns: { explore: "Explore", account: "Account" },
  signIn: "Sign in",
  create: "Create an account",
  dashboard: "Go to your dashboard",
} as const;

/** Every sentence above, flattened, so a test can read the whole page's copy at once. */
export function allLandingCopy(): string[] {
  const out: string[] = [];
  const visit = (value: unknown): void => {
    if (typeof value === "string") out.push(value);
    else if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === "object") Object.values(value).forEach(visit);
  };
  visit([
    HERO,
    HOW_IT_WORKS,
    PATHWAYS,
    PRACTICE,
    PROGRESS,
    AI,
    PLAN,
    {
      ...PLANS_SECTION,
      dailyLimit: undefined,
      testLimit: undefined,
      tierLabel: undefined,
      tiers: undefined,
    },
    FAQ,
    FINAL_CTA,
    FOOTER,
    NAV_LINKS,
    FOOTER_LINKS,
  ]);
  return out;
}

export const landingMeta = {
  title: "NurseGenius: RN and RM exam practice with a study plan",
  description:
    "Timed RN and RM practice with the reasoning behind every answer, a mistake bank, and a study plan built from your own results.",
} as const;

export const landingNav = {
  skip: "Skip to content",
  links: [
    { label: "How it works", href: "#how" },
    { label: "Practice", href: "#practice" },
    { label: "Progress", href: "#progress" },
    { label: "Plans", href: "#plans" },
    { label: "FAQ", href: "#faq" },
  ],
  signIn: "Sign in",
  getStarted: "Get started",
  dashboard: "Go to your dashboard",
  openMenu: "Open menu",
  menuHint: "Jump to a section.",
} as const;

export const landingHero = {
  title: "Know what to study next.",
  body: "Timed RN and RM practice with the reasoning behind every answer, and a study plan built from your own results.",
  primary: "Get started",
  secondary: "Explore features",
  note: "Free to start. The Novice plan allows 50 questions a day.",
  caption: "The layout of a test. Questions come from the question bank when you start one.",
  previewLabel:
    "Test preview with placeholder bars: RN, timer, flag, previous, next, and options A to D",
} as const;

export const landingHow = {
  title: "From the first question to exam day",
  lead: "Four steps, and each one feeds the next.",
  steps: [
    {
      title: "Choose RN or RM",
      body: "Say which programme you are preparing for, or both. You pick one each time you start a test.",
    },
    {
      title: "Practise by topic or mix everything",
      body: "Set how many questions and how many minutes, from 5 to 180, then start.",
    },
    {
      title: "Read the reasoning",
      body: "After you submit, see the correct answer and why it is correct, question by question.",
    },
    {
      title: "Follow the plan",
      body: "Your answers shape a weekly plan to your exam date and show which topics need work.",
    },
  ],
} as const;

export const landingPathways = {
  title: "Two programmes, kept apart",
  lead: "RN and RM have their own questions and their own topics, and your readiness is estimated for each on its own.",
  rn: {
    code: "RN",
    title: "RN – Registered Nurse",
    intro: "Questions grouped by topic, from a single topic to every area at once.",
    points: [
      "Topics are listed with their question counts once you sign in",
      "Mastery is tracked topic by topic",
      "Readiness is estimated for RN on its own",
    ],
  },
  rm: {
    code: "RM",
    title: "RM – Registered Midwife",
    intro: "The same tools, applied to the midwifery question bank.",
    points: [
      "Practise one topic or mix all areas",
      "Mastery is tracked topic by topic",
      "Readiness is estimated for RM on its own",
    ],
  },
} as const;

export const landingPractice = {
  title: "A test that behaves like an exam",
  lead: "Every test has a timer, a question navigator and a flag for questions you want to revisit. The server keeps the time and scores the test, so the result cannot be edited on your phone.",
  features: ["Timer", "Question navigator", "Flag"],
  points: [
    "Tests run from 5 to 180 minutes, and finish by themselves when time is up.",
    "Correct answers and rationales appear after you submit, in every mode.",
    "Questions come only from the NurseGenius question bank. The app never invents a question to fill a test.",
  ],
  modesTitle: "Four ways to choose your questions",
  modes: [
    { title: "Random", body: "A random draw from the bank." },
    {
      title: "Focus on my weak areas",
      body: "Weights weak topics, due reviews, past mistakes and unseen questions.",
    },
    {
      title: "Review my mistakes",
      body: "Questions you missed and have not got right since.",
    },
    {
      title: "Revision due today",
      body: "Questions whose review date has arrived.",
    },
  ],
} as const;

export const landingProgress = {
  title: "See where you stand, honestly",
  lead1:
    "Each topic gets a level based on your own answers, weighted toward recent ones. A short lucky streak does not make a topic mastered.",
  lead2:
    "Exam readiness is shown for RN and RM separately. When there is not enough evidence it says so instead of guessing a number.",
  tags: ["Confidence and pace", "Repeated mistakes", "Reviews that are overdue"],
  gaugeLabel: "Readiness for RN and for RM shown as two separate gauges",
  levelsTitle: "The levels a topic can have",
  levels: [
    {
      key: "none",
      title: "Not enough data yet",
      body: "Too few answers to say anything fair yet, so no level is shown.",
    },
    { key: "weak", title: "Weak", body: "Needs the most attention. Practise it first." },
    {
      key: "developing",
      title: "Developing",
      body: "Getting there. Keep practising and review mistakes.",
    },
    {
      key: "proficient",
      title: "Proficient",
      body: "Solid results on a fair number of answers.",
    },
    {
      key: "mastered",
      title: "Mastered",
      body: "Strong results backed by plenty of answers, not a handful.",
    },
  ],
} as const;

export const landingAi = {
  title: "AI that explains. The numbers come from your answers.",
  lead: "The AI does not choose your questions or change your scores. Selection is rule-based and the same every time.",
  ask: {
    title: "Ask about any question, after you finish",
    body: "Explain it, simplify it, compare the options, or ask why your answer was wrong. Help is available once a test is submitted, never during it.",
  },
  summaries: {
    title: "Study summaries that say where they came from",
    body: "Your scores, levels and plan are calculated by the app. A summary is marked AI-assisted only when the AI's wording checked out against those numbers. Otherwise you get a plain computed summary, labelled as one.",
    labelsAria: "The two labels a summary can carry",
    labels: ["AI-assisted", "Computed summary"],
  },
} as const;

export const landingPlan = {
  title: "A plan that works back from your exam date",
  lead: "Set your exam date and NurseGenius builds a week-by-week plan. Every item says why it is there, and weeks you have finished are kept.",
  timelineLabel: "Timeline from today to your exam date",
  today: "Today",
  exam: "Your exam date",
  items: [
    {
      title: "Progress comes from real answers",
      body: "A plan item is complete when your answers show it, not when you tick a box.",
    },
    {
      title: "Insight beyond the score",
      body: "Trends, repeated mistakes, reviews that are overdue, and how fast you answer.",
    },
    {
      title: "Today's focus",
      body: "A short daily recommendation, a study streak and a daily challenge keep the next step obvious.",
    },
  ],
} as const;

export const landingPlans = {
  title: "Start free, upgrade when you need more",
  lead: "Limits are the same ones the app enforces. Prices are read live from NurseGenius and paid in naira by card through Paystack.",
  caption: "What each plan allows and costs",
  firstColumn: "What the plan includes",
  fallback: "Shown after you sign in",
  rows: {
    perDay: { label: "Questions per day", novice: "50", erudite: "500", scholar: "Unlimited" },
    perTest: { label: "Most questions in one test", novice: "50", erudite: "150", scholar: "250" },
    price: { label: "Price", novice: "Free" },
    access: { label: "Access", novice: "No expiry" },
  },
} as const;

export const landingFaq = {
  title: "Questions people ask first",
  items: [
    {
      q: "Is NurseGenius free?",
      a: "You can start free. The Novice plan allows 50 questions a day and 50 in one test. Erudite and Scholar raise those limits.",
    },
    {
      q: "What do RN and RM stand for?",
      a: "RN is Registered Nurse and RM is Registered Midwife. You choose which one to practise each time you start a test.",
    },
    {
      q: "When do I see the correct answers?",
      a: "After you submit the test, in every mode. The answer key is never sent to your phone while the test is running.",
    },
    {
      q: "Who scores my test?",
      a: "The server does, from the answers it has saved. The timer is kept there too, so the test ends on time wherever you are.",
    },
    {
      q: "How are my questions chosen?",
      a: "You pick: random, focused on your weak areas, your past mistakes, or revision that is due today. The choice follows fixed rules. AI does not pick questions.",
    },
    {
      q: "How do I pay for a bigger plan?",
      a: "In naira by card through Paystack. Your plan starts after Paystack confirms the payment.",
    },
    {
      q: "Can I practise on my phone?",
      a: "Yes. Every page, including the test itself, is laid out for a phone screen first and grows from there.",
    },
  ],
} as const;

export const landingCta = {
  title: "Start with one test.",
  body: "Pick RN or RM, choose a topic and see how you do. Your first results already start shaping what to study next.",
  primary: "Get started",
  secondary: "Sign in",
} as const;

export const landingFooter = {
  tagline: "RN and RM exam practice, with a plan.",
  exploreTitle: "Explore",
  explore: [
    { label: "How it works", href: "#how" },
    { label: "Practice", href: "#practice" },
    { label: "Progress", href: "#progress" },
    { label: "Study plans", href: "#plan" },
  ],
  accountTitle: "Account",
  signIn: "Sign in",
  create: "Create an account",
} as const;
