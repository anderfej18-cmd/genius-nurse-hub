import { useEffect, useId, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import {
  ArrowRight,
  CalendarCheck,
  Calculator,
  Check,
  CircleCheck,
  Crosshair,
  FileText,
  Flag,
  LayoutGrid,
  Menu,
  MessageCircleQuestion,
  Minus,
  Plus,
  RotateCcw,
  Shuffle,
  Sparkles,
  Target,
  Timer,
  TrendingUp,
  X,
} from "lucide-react";
import {
  landingAi,
  landingCta,
  landingFaq,
  landingFooter,
  landingHero,
  landingHow,
  landingNav,
  landingPathways,
  landingPlan,
  landingPlans,
  landingPractice,
  landingProgress,
} from "../../lib/landing-content";
import { listPublicPlans } from "../../functions/plans.functions";

export type LivePlan = {
  name: "Erudite" | "Scholar";
  priceNaira: number;
  accessDays: number;
};

export type LandingPageProps = {
  /** Erudite and Scholar rows from the plans table. Omit when they could not be loaded. */
  plans?: ReadonlyArray<LivePlan>;
  /** Signed-in visitors see "Go to your dashboard" instead of the sign-in buttons. */
  signedIn?: boolean;
  signInHref?: string;
  signUpHref?: string;
  dashboardHref?: string;
};

type Links = Required<Pick<LandingPageProps, "signInHref" | "signUpHref" | "dashboardHref">> & {
  signedIn: boolean;
};

const wrap = "mx-auto w-full max-w-[1232px] px-4 sm:px-6 lg:px-8";
const sec = "py-16 sm:py-24 lg:py-[120px]";

const cardTints = ["bg-ng-warn-bg", "bg-ng-rn-soft", "bg-ng-rm-soft", "bg-ng-info-bg"] as const;

const levelStyle: Record<string, { box: string; title: string; height: string }> = {
  none: {
    box: "bg-ng-sunken border-[1.5px] border-dashed border-ng-input",
    title: "text-ng-ink",
    height: "min-h-[190px]",
  },
  weak: { box: "bg-ng-err-bg", title: "text-ng-err", height: "min-h-[220px]" },
  developing: { box: "bg-ng-warn-bg", title: "text-ng-warn", height: "min-h-[250px]" },
  proficient: { box: "bg-ng-info-bg", title: "text-ng-info", height: "min-h-[280px]" },
  mastered: { box: "bg-ng-ok-bg", title: "text-ng-ok", height: "min-h-[310px]" },
};

const modeStyle = [
  { box: "bg-ng-warn-bg", icon: "text-ng-warn", Icon: Shuffle },
  { box: "bg-ng-rn-soft", icon: "text-ng-rn-text", Icon: Crosshair },
  { box: "bg-ng-rm-soft", icon: "text-ng-rm-text", Icon: RotateCcw },
  { box: "bg-ng-info-bg", icon: "text-ng-info", Icon: CalendarCheck },
] as const;

const planIcons = [
  { Icon: CircleCheck, color: "text-ng-ok" },
  { Icon: TrendingUp, color: "text-ng-info" },
  { Icon: Target, color: "text-ng-warn" },
] as const;

/** The logo has a white backdrop, so it is multiplied onto the sand page colour. */
function Brand({ className = "size-14 sm:size-16" }: { className?: string }) {
  return (
    <img
      src="/images/landing/logo.webp"
      alt="NurseGenius"
      width={384}
      height={384}
      decoding="async"
      className={`block shrink-0 object-contain mix-blend-multiply ${className}`}
    />
  );
}

function SectionHead({ id, title, lead }: { id: string; title: string; lead?: string }) {
  return (
    <div className="mb-10 grid items-end gap-6 md:grid-cols-2 md:gap-16" data-reveal>
      <h2 id={id} className="ng-h2">
        {title}
      </h2>
      {lead ? <p className="ng-lead">{lead}</p> : null}
    </div>
  );
}

function Header({ links }: { links: Links }) {
  const [open, setOpen] = useState(false);
  const headerRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const el = headerRef.current;
    if (!el) return;
    const onScroll = () => {
      el.classList.toggle("ng-header-scrolled", window.scrollY > 8);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      ref={headerRef}
      className="sticky top-0 z-40 border-b border-ng-border/40 bg-ng-bg transition-[box-shadow] duration-200"
    >
      <div className={wrap}>
        <nav className="flex min-h-[68px] items-center gap-6" aria-label="Main">
          <a href="#top" className="ng-focus" aria-label="NurseGenius home">
            <Brand />
          </a>
          <div className="ml-auto hidden gap-1 lg:flex">
            {landingNav.links.map((l) => (
              <a
                key={l.href}
                href={l.href}
                className="ng-focus ng-nav-link rounded-full px-4 py-2.5 text-[15px] font-semibold hover:bg-ng-sunken"
              >
                {l.label}
              </a>
            ))}
          </div>
          <div className="hidden items-center gap-2.5 lg:flex">
            {links.signedIn ? (
              <a
                href={links.dashboardHref}
                className="ng-btn ng-focus min-h-11 bg-ng-primary px-5 text-[15px] text-ng-on-primary hover:bg-ng-primary-strong"
              >
                {landingNav.dashboard}
              </a>
            ) : (
              <>
                <a
                  href={links.signInHref}
                  className="ng-focus ng-nav-link rounded-full px-4 py-2.5 text-[15px] font-semibold hover:bg-ng-sunken"
                >
                  {landingNav.signIn}
                </a>
                <a
                  href={links.signUpHref}
                  className="ng-btn ng-focus min-h-11 bg-ng-primary px-5 text-[15px] text-ng-on-primary hover:bg-ng-primary-strong"
                >
                  {landingNav.getStarted}
                </a>
              </>
            )}
          </div>

          <Dialog.Root open={open} onOpenChange={setOpen}>
            <Dialog.Trigger asChild>
              <button
                type="button"
                aria-label={landingNav.openMenu}
                className="ng-focus ml-auto inline-flex size-12 items-center justify-center rounded-full border-2 border-ng-border bg-ng-card lg:hidden"
              >
                <Menu size={22} aria-hidden="true" />
              </button>
            </Dialog.Trigger>
            <Dialog.Portal>
              <Dialog.Overlay className="fixed inset-0 z-40 bg-ng-ink/40" />
              <Dialog.Content className="ng-root fixed inset-x-4 top-4 z-50 rounded-[18px] border border-ng-border bg-ng-card p-5 shadow-ng">
                <div className="flex items-start justify-between">
                  <Dialog.Title asChild>
                    <span>
                      <Brand />
                    </span>
                  </Dialog.Title>
                  <Dialog.Close asChild>
                    <button
                      type="button"
                      aria-label="Close menu"
                      className="ng-focus inline-flex size-11 items-center justify-center rounded-full border-2 border-ng-border"
                    >
                      <X size={20} aria-hidden="true" />
                    </button>
                  </Dialog.Close>
                </div>
                <Dialog.Description className="mb-3 mt-2 text-[15px] text-ng-muted">
                  {landingNav.menuHint}
                </Dialog.Description>
                <ul>
                  {landingNav.links.map((l) => (
                    <li key={l.href}>
                      <a
                        href={l.href}
                        onClick={() => setOpen(false)}
                        className="ng-focus flex min-h-12 items-center border-t border-ng-divider font-semibold"
                      >
                        {l.label}
                      </a>
                    </li>
                  ))}
                  <li>
                    <a
                      href={links.signedIn ? links.dashboardHref : links.signInHref}
                      className="ng-focus flex min-h-12 items-center border-t border-ng-divider font-semibold"
                    >
                      {links.signedIn ? landingNav.dashboard : landingNav.signIn}
                    </a>
                  </li>
                </ul>
              </Dialog.Content>
            </Dialog.Portal>
          </Dialog.Root>
        </nav>
      </div>
    </header>
  );
}

function Hero({ links }: { links: Links }) {
  return (
    <section className={`${wrap} pt-2`} aria-labelledby="hero-h">
      <div className="ng-dark hero-content relative overflow-hidden rounded-[28px] bg-ng-primary p-7 pb-0 text-ng-on-primary sm:p-10 sm:pb-0 md:pl-10 md:pr-0 md:pt-10 md:pb-0 lg:pl-14 lg:pr-0 lg:pt-12 lg:pb-0 xl:pl-16 xl:pr-0 xl:pt-12 xl:pb-0">
        <div className="pointer-events-none absolute -bottom-64 -left-44 size-[520px] rounded-full bg-ng-on-primary/[0.06]" />
        <div className="pointer-events-none absolute -right-24 -top-36 size-[340px] rounded-full bg-ng-on-primary/[0.06]" />

        <div className="hero-copy z-10 flex flex-col items-start gap-6 pb-6 pt-2 md:py-6 lg:py-8 xl:py-10">
          <h1 id="hero-h" className="ng-display text-[clamp(44px,6.6vw,86px)]">
            {landingHero.title}
          </h1>
          <p className="max-w-[34ch] text-[clamp(18px,1.7vw,22px)] leading-normal text-ng-on-primary/90 [text-wrap:pretty]">
            {landingHero.body}
          </p>
          <div className="flex flex-wrap gap-3">
            <a
              href={links.signedIn ? links.dashboardHref : links.signUpHref}
              className="ng-btn ng-focus ng-arrow-nudge bg-ng-signal text-ng-on-signal hover:bg-ng-signal-hover"
            >
              {links.signedIn ? landingNav.dashboard : landingHero.primary}
              <span className="ng-arrow" aria-hidden="true">
                <ArrowRight size={18} />
              </span>
            </a>
            <a
              href="#how"
              className="ng-btn ng-focus border-ng-on-primary/45 text-ng-on-primary hover:bg-ng-on-primary/10"
            >
              {landingHero.secondary}
            </a>
          </div>
          <p className="text-[15px] text-ng-on-primary/85">{landingHero.note}</p>
        </div>

        <img
          src="/images/landing/hero-nurses-transparent.webp"
          alt="Three smiling nurses in blue scrubs with stethoscopes standing together"
          width={1024}
          height={853}
          fetchPriority="high"
          decoding="async"
          className="hero-image"
        />
      </div>
    </section>
  );
}

function How() {
  return (
    <section id="how" className="scroll-mt-20 py-12 sm:py-16 lg:py-20" aria-labelledby="how-h">
      <div className={wrap}>
        <div className="mb-10 flex flex-col gap-3.5" data-reveal>
          <h2 id="how-h" className="ng-h2">
            {landingHow.title}
          </h2>
          <p className="ng-lead">{landingHow.lead}</p>
        </div>
        <ol className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {landingHow.steps.map((s, i) => (
            <li
              key={s.title}
              className={`ng-lift relative flex min-h-[280px] flex-col overflow-hidden rounded-[18px] p-[26px] ${cardTints[i]}`}
            >
              <span
                aria-hidden="true"
                className="absolute right-5 top-3.5 font-display text-[56px] font-extrabold leading-none tracking-[-0.04em] opacity-20"
              >
                {i + 1}
              </span>
              <h3 className="ng-h3 pr-8">{s.title}</h3>
              <p className="mt-2.5 text-base leading-normal">{s.body}</p>
              <span
                aria-hidden="true"
                className="mt-auto inline-flex size-11 items-center justify-center rounded-full bg-ng-raised"
              >
                <ArrowRight size={18} />
              </span>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

function Pathway({
  data,
  box,
  badge,
  titleColor,
  tick,
  image,
}: {
  data: typeof landingPathways.rn | typeof landingPathways.rm;
  box: string;
  badge: string;
  titleColor: string;
  tick: string;
  image: { src: string; alt: string; width: number; height: number; position: string };
}) {
  return (
    <article className={`flex flex-col gap-[18px] rounded-[28px] p-7 sm:p-11 ${box}`}>
      <img
        src={image.src}
        alt={image.alt}
        width={image.width}
        height={image.height}
        loading="lazy"
        decoding="async"
        className={`mb-2 h-48 w-full rounded-[18px] object-cover sm:h-56 ${image.position}`}
      />
      <div className="flex items-center gap-[18px]">
        <span
          aria-hidden="true"
          className={`inline-flex size-[68px] items-center justify-center rounded-[20px] font-display text-[28px] font-extrabold tracking-[-0.02em] text-white ${badge}`}
        >
          {data.code}
        </span>
        <h3 className={`ng-h3 ${titleColor}`}>{data.title}</h3>
      </div>
      <p className="text-lg">{data.intro}</p>
      <ul className="mt-1.5 flex flex-col gap-3">
        {data.points.map((p) => (
          <li key={p} className="flex items-start gap-3 text-[16.5px]">
            <Check
              size={20}
              strokeWidth={2.4}
              className={`mt-[3px] shrink-0 ${tick}`}
              aria-hidden="true"
            />
            {p}
          </li>
        ))}
      </ul>
    </article>
  );
}

function Pathways() {
  return (
    <section
      id="pathways"
      className="scroll-mt-20 pb-16 sm:pb-24 lg:pb-[120px]"
      aria-labelledby="path-h"
    >
      <div className={wrap}>
        <SectionHead id="path-h" title={landingPathways.title} lead={landingPathways.lead} />
        <div className="grid gap-5 md:grid-cols-2">
          <Pathway
            data={landingPathways.rn}
            box="bg-ng-rn-soft"
            badge="bg-ng-rn"
            titleColor="text-ng-rn-text"
            tick="text-ng-rn-text"
            image={{
              src: "/images/landing/nurse-rn.webp",
              alt: "A nurse in a surgical cap, mask and gloves preparing an intravenous drip",
              width: 725,
              height: 725,
              position: "object-[50%_35%]",
            }}
          />
          <Pathway
            data={landingPathways.rm}
            box="bg-ng-rm-soft"
            badge="bg-ng-rm"
            titleColor="text-ng-rm-text"
            tick="text-ng-rm-text"
            image={{
              src: "/images/landing/nurse-rm.webp",
              alt: "A smiling nurse in blue scrubs sitting at a desk with a stethoscope around her neck",
              width: 736,
              height: 1104,
              position: "object-[50%_22%]",
            }}
          />
        </div>
      </div>
    </section>
  );
}

function Practice() {
  const featureIcons = [
    { Icon: Timer, cls: "bg-ng-accent text-ng-accent-text" },
    { Icon: LayoutGrid, cls: "bg-ng-info-bg text-ng-info" },
    { Icon: Flag, cls: "bg-ng-warn-bg text-ng-warn" },
  ] as const;
  return (
    <section
      id="practice"
      className="scroll-mt-20 pb-16 sm:pb-24 lg:pb-[120px]"
      aria-labelledby="prac-h"
    >
      <div className={wrap}>
        <div className="rounded-[28px] border border-ng-border bg-ng-card p-6 sm:p-10 lg:p-16">
          <div className="grid items-start gap-10 lg:grid-cols-2 lg:gap-[72px]">
            <div className="flex flex-col gap-[22px]">
              <h2 id="prac-h" className="ng-h2">
                {landingPractice.title}
              </h2>
              <p className="ng-lead">{landingPractice.lead}</p>
              <div className="flex flex-wrap gap-2.5" aria-hidden="true">
                {landingPractice.features.map((f, i) => {
                  const { Icon, cls } = featureIcons[i] ?? featureIcons[0];
                  return (
                    <span
                      key={f}
                      className={`inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-bold ${cls}`}
                    >
                      <Icon size={16} /> {f}
                    </span>
                  );
                })}
              </div>
              <ul className="mt-1.5 flex flex-col gap-3.5">
                {landingPractice.points.map((p) => (
                  <li key={p} className="flex gap-3">
                    <Check
                      size={20}
                      strokeWidth={2.4}
                      className="mt-[3px] shrink-0 text-ng-primary"
                      aria-hidden="true"
                    />
                    {p}
                  </li>
                ))}
              </ul>
            </div>
            <div className="flex flex-col gap-[18px]">
              <h3 className="ng-h3">{landingPractice.modesTitle}</h3>
              <ul className="grid gap-3.5 sm:grid-cols-2">
                {landingPractice.modes.map((m, i) => {
                  const s = modeStyle[i] ?? modeStyle[0];
                  return (
                    <li
                      key={m.title}
                      className={`ng-lift flex min-h-[190px] flex-col gap-2 rounded-[18px] p-[22px] ${s.box}`}
                    >
                      <s.Icon size={30} strokeWidth={1.9} className={s.icon} aria-hidden="true" />
                      <strong className="font-display text-xl tracking-[-0.015em]">
                        {m.title}
                      </strong>
                      <span className="text-[15.5px] leading-normal">{m.body}</span>
                    </li>
                  );
                })}
              </ul>
              <div className="flex h-[280px] items-start justify-center overflow-hidden rounded-[18px] bg-ng-accent pt-4 sm:h-[300px]">
                <img
                  src="/images/landing/nurse-practice.webp"
                  alt="A smiling nurse in light blue scrubs with her arms crossed and a stethoscope around her neck"
                  width={480}
                  height={783}
                  loading="lazy"
                  decoding="async"
                  className="h-auto w-[240px] max-w-none"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function Progress() {
  return (
    <section
      id="progress"
      className="scroll-mt-20 pb-16 sm:pb-24 lg:pb-[120px]"
      aria-labelledby="prog-h"
    >
      <div className={wrap}>
        <div className="ng-dark relative overflow-hidden rounded-[28px] bg-ng-primary p-7 text-ng-on-primary sm:p-12 lg:p-[72px]">
          <div className="pointer-events-none absolute -bottom-52 -right-36 size-[480px] rounded-full bg-ng-on-primary/5" />
          <div className="relative grid items-start gap-10 lg:grid-cols-2 lg:gap-[72px]">
            <div className="flex flex-col gap-[22px]">
              <h2 id="prog-h" className="ng-h2">
                {landingProgress.title}
              </h2>
              <p className="ng-lead !text-ng-on-primary/85">{landingProgress.lead1}</p>
              <p className="ng-lead !text-ng-on-primary/85">{landingProgress.lead2}</p>
            </div>
            <div className="flex flex-col gap-5">
              <ul className="flex flex-wrap gap-2.5">
                {landingProgress.tags.map((t) => (
                  <li
                    key={t}
                    className="rounded-full border-[1.5px] border-ng-on-primary/40 px-4 py-2 text-[15px] font-semibold"
                  >
                    {t}
                  </li>
                ))}
              </ul>
              <div
                role="img"
                aria-label={landingProgress.gaugeLabel}
                className="rounded-[18px] bg-ng-card p-6 text-ng-ink"
              >
                <div aria-hidden="true" className="grid grid-cols-2 gap-4">
                  <div className="flex flex-col gap-3 rounded-xl bg-ng-rn-soft p-[18px]">
                    <span className="self-start rounded-full bg-ng-rn px-3 py-1 text-[13px] font-bold text-white">
                      RN
                    </span>
                    <span className="block h-2.5 overflow-hidden rounded-[5px] bg-white">
                      <span className="block h-full w-[34%] rounded-[5px] bg-ng-rn" />
                    </span>
                  </div>
                  <div className="flex flex-col gap-3 rounded-xl bg-ng-rm-soft p-[18px]">
                    <span className="self-start rounded-full bg-ng-rm px-3 py-1 text-[13px] font-bold text-white">
                      RM
                    </span>
                    <span className="block h-2.5 overflow-hidden rounded-[5px] bg-white">
                      <span className="block h-full w-[58%] rounded-[5px] bg-ng-rm" />
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="mt-12 lg:mt-[72px]">
          <h3 className="ng-h2 mb-7 !text-[clamp(28px,3.4vw,42px)]">
            {landingProgress.levelsTitle}
          </h3>
          <ul className="grid items-end gap-3.5 sm:grid-cols-2 lg:grid-cols-5">
            {landingProgress.levels.map((l) => {
              const s = levelStyle[l.key] ?? levelStyle.none!;
              return (
                <li
                  key={l.key}
                  className={`flex flex-col justify-end gap-2.5 rounded-[18px] p-5 ${s.box} ${s.height}`}
                >
                  <strong className={`font-display text-[21px] tracking-[-0.015em] ${s.title}`}>
                    {l.title}
                  </strong>
                  <p
                    className={`text-[15px] leading-normal ${l.key === "none" ? "text-ng-muted" : ""}`}
                  >
                    {l.body}
                  </p>
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </section>
  );
}

function Ai() {
  return (
    <section id="ai" className="scroll-mt-20 pb-16 sm:pb-24 lg:pb-[120px]" aria-labelledby="ai-h">
      <div className={wrap}>
        <SectionHead id="ai-h" title={landingAi.title} lead={landingAi.lead} />
        <div className="grid gap-5 md:grid-cols-2">
          <article className="flex flex-col gap-3.5 overflow-hidden rounded-[28px] bg-ng-accent p-7 sm:p-11">
            <MessageCircleQuestion
              size={40}
              strokeWidth={1.7}
              className="text-ng-accent-text"
              aria-hidden="true"
            />
            <h3 className="ng-h3">{landingAi.ask.title}</h3>
            <p className="text-lg">{landingAi.ask.body}</p>
            <img
              src="/images/landing/nurse-ai.webp"
              alt="A nurse in teal scrubs smiling and pointing to the side"
              width={480}
              height={650}
              loading="lazy"
              decoding="async"
              className="-mb-7 mt-auto h-auto w-36 self-end sm:-mb-11 sm:w-40"
            />
          </article>
          <article className="flex flex-col gap-3.5 rounded-[28px] border border-ng-border bg-ng-card p-7 sm:p-11">
            <FileText size={40} strokeWidth={1.7} className="text-ng-primary" aria-hidden="true" />
            <h3 className="ng-h3">{landingAi.summaries.title}</h3>
            <p className="text-lg">{landingAi.summaries.body}</p>
            <ul className="mt-2 flex flex-wrap gap-2.5" aria-label={landingAi.summaries.labelsAria}>
              <li className="inline-flex items-center gap-1.5 rounded-full bg-ng-accent px-[18px] py-2 text-[15px] font-bold text-ng-accent-text">
                <Sparkles size={16} aria-hidden="true" /> {landingAi.summaries.labels[0]}
              </li>
              <li className="inline-flex items-center gap-1.5 rounded-full border-[1.5px] border-ng-border bg-ng-sunken px-[18px] py-2 text-[15px] font-bold">
                <Calculator size={16} aria-hidden="true" /> {landingAi.summaries.labels[1]}
              </li>
            </ul>
          </article>
        </div>
      </div>
    </section>
  );
}

function StudyPlan() {
  return (
    <section
      id="plan"
      className="scroll-mt-20 pb-16 sm:pb-24 lg:pb-[120px]"
      aria-labelledby="plan-h"
    >
      <div className={wrap}>
        <div className="rounded-[28px] bg-ng-sunken p-6 sm:p-10 lg:p-16">
          <SectionHead id="plan-h" title={landingPlan.title} lead={landingPlan.lead} />
          <div
            role="img"
            aria-label={landingPlan.timelineLabel}
            className="mb-5 rounded-[18px] border border-ng-border bg-ng-card p-5 sm:p-9"
          >
            <div aria-hidden="true" className="flex items-center gap-3.5">
              <span className="shrink-0 rounded-full bg-ng-primary px-[18px] py-2 text-[15px] font-bold text-ng-on-primary">
                {landingPlan.today}
              </span>
              <div className="flex min-w-6 flex-1 items-center gap-1.5">
                {[0, 1, 2, 3, 4, 5].map((n) => (
                  <span
                    key={n}
                    className={`h-2 flex-1 rounded ${
                      n < 2 ? "bg-ng-primary" : n === 2 ? "bg-ng-signal" : "bg-ng-border"
                    }`}
                  />
                ))}
              </div>
              <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-ng-rm-soft px-[18px] py-2 text-[15px] font-bold text-ng-rm-text">
                <Flag size={16} /> {landingPlan.exam}
              </span>
            </div>
          </div>
          <ul className="grid gap-4 md:grid-cols-3">
            {landingPlan.items.map((it, i) => {
              const { Icon, color } = planIcons[i] ?? planIcons[0];
              return (
                <li
                  key={it.title}
                  className="ng-lift rounded-[18px] border border-ng-border bg-ng-card p-[26px]"
                >
                  <Icon size={32} strokeWidth={1.8} className={color} aria-hidden="true" />
                  <h3 className="ng-h3 mb-2 mt-3.5 !text-[22px]">{it.title}</h3>
                  <p className="text-base text-ng-muted">{it.body}</p>
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </section>
  );
}

function formatNaira(n: number) {
  return new Intl.NumberFormat("en-NG", {
    style: "currency",
    currency: "NGN",
    maximumFractionDigits: 0,
  }).format(n);
}

const CONTRACT_DEFAULT_PLANS: ReadonlyArray<LivePlan> = [
  { name: "Erudite", priceNaira: 1500, accessDays: 30 },
  { name: "Scholar", priceNaira: 2000, accessDays: 30 },
];

function Plans({ plans: propPlans }: { plans?: ReadonlyArray<LivePlan> }) {
  const [localPlans, setLocalPlans] = useState<LivePlan[] | undefined>();
  const plans =
    propPlans && propPlans.length > 0
      ? propPlans
      : localPlans && localPlans.length > 0
        ? localPlans
        : CONTRACT_DEFAULT_PLANS;

  useEffect(() => {
    if (propPlans && propPlans.length > 0) return;
    let cancelled = false;
    listPublicPlans({ data: {} }).then(
      (data) => {
        if (cancelled || !Array.isArray(data)) return;
        const live: LivePlan[] = [];
        for (const p of data) {
          const rawName = p.name.trim().toLowerCase();
          if (rawName === "erudite") {
            live.push({ name: "Erudite", priceNaira: p.priceNgn, accessDays: p.durationDays });
          } else if (rawName === "scholar") {
            live.push({ name: "Scholar", priceNaira: p.priceNgn, accessDays: p.durationDays });
          }
        }
        if (live.length > 0) setLocalPlans(live);
      },
      () => {
        /* Honest failure: the fallback text stays visible */
      },
    );
    return () => {
      cancelled = true;
    };
  }, [propPlans]);

  const r = landingPlans.rows;
  const erudite = plans?.find((p) => p.name === "Erudite");
  const scholar = plans?.find((p) => p.name === "Scholar");
  const price = (p?: LivePlan) =>
    p ? (
      <td>{formatNaira(p.priceNaira)}</td>
    ) : (
      <td className="!font-medium text-ng-muted">{landingPlans.fallback}</td>
    );
  const access = (p?: LivePlan) =>
    p ? (
      <td>{`${p.accessDays} days`}</td>
    ) : (
      <td className="!font-medium text-ng-muted">{landingPlans.fallback}</td>
    );

  return (
    <section
      id="plans"
      className="scroll-mt-20 pb-16 sm:pb-24 lg:pb-[120px]"
      aria-labelledby="plans-h"
    >
      <div className={wrap}>
        <SectionHead id="plans-h" title={landingPlans.title} lead={landingPlans.lead} />
        <div
          className="overflow-x-auto rounded-[28px] border border-ng-border bg-ng-card ng-focus"
          tabIndex={0}
          role="region"
          aria-label="Plan comparison"
        >
          <table className="w-full min-w-[640px] border-collapse text-left text-[17px] [&_td]:border-b [&_td]:border-ng-divider [&_td]:px-6 [&_td]:py-5 [&_td]:font-semibold [&_td]:tabular-nums [&_th]:border-b [&_th]:border-ng-divider [&_th]:px-6 [&_th]:py-5 [&_tr:last-child_td]:border-b-0 [&_tr:last-child_th]:border-b-0">
            <caption className="sr-only">{landingPlans.caption}</caption>
            <thead className="bg-ng-sunken font-display text-[22px] tracking-[-0.02em]">
              <tr>
                <th scope="col">
                  <span className="sr-only">{landingPlans.firstColumn}</span>
                </th>
                <th scope="col">Novice</th>
                <th scope="col">Erudite</th>
                <th scope="col">Scholar</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row" className="font-semibold text-ng-muted">
                  {r.perDay.label}
                </th>
                <td>{r.perDay.novice}</td>
                <td>{r.perDay.erudite}</td>
                <td>{r.perDay.scholar}</td>
              </tr>
              <tr>
                <th scope="row" className="font-semibold text-ng-muted">
                  {r.perTest.label}
                </th>
                <td>{r.perTest.novice}</td>
                <td>{r.perTest.erudite}</td>
                <td>{r.perTest.scholar}</td>
              </tr>
              <tr>
                <th scope="row" className="font-semibold text-ng-muted">
                  {r.price.label}
                </th>
                <td>{r.price.novice}</td>
                {price(erudite)}
                {price(scholar)}
              </tr>
              <tr>
                <th scope="row" className="font-semibold text-ng-muted">
                  {r.access.label}
                </th>
                <td>{r.access.novice}</td>
                {access(erudite)}
                {access(scholar)}
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}

function Faq() {
  const [open, setOpen] = useState<number | null>(null);
  const base = useId();
  return (
    <section id="faq" className="scroll-mt-20 pb-16 sm:pb-24 lg:pb-[120px]" aria-labelledby="faq-h">
      <div className={wrap}>
        <div className="grid items-start gap-8 lg:grid-cols-[1fr_1.4fr] lg:gap-20">
          <h2 id="faq-h" className="ng-h2">
            {landingFaq.title}
          </h2>
          <div className="border-t border-ng-border">
            {landingFaq.items.map((f, i) => {
              const isOpen = open === i;
              const panel = `${base}-panel-${i}`;
              return (
                <div key={f.q}>
                  <h3 className="m-0">
                    <button
                      type="button"
                      aria-expanded={isOpen}
                      aria-controls={panel}
                      onClick={() => setOpen(isOpen ? null : i)}
                      className="ng-focus flex min-h-16 w-full cursor-pointer items-center justify-between gap-5 border-0 border-b border-ng-border px-3 py-[22px] text-left font-display text-[clamp(18px,1.8vw,22px)] font-bold tracking-[-0.015em] hover:bg-ng-sunken"
                    >
                      <span>{f.q}</span>
                      <span
                        aria-hidden="true"
                        className="inline-flex size-9 shrink-0 items-center justify-center rounded-full bg-ng-accent text-ng-accent-text"
                      >
                        {isOpen ? (
                          <Minus size={18} strokeWidth={2.4} />
                        ) : (
                          <Plus size={18} strokeWidth={2.4} />
                        )}
                      </span>
                    </button>
                  </h3>
                  <div
                    id={panel}
                    role="region"
                    className="ng-accordion-panel"
                    data-open={isOpen ? "true" : "false"}
                  >
                    <div className="ng-accordion-inner">
                      <p className="max-w-[62ch] border-b border-ng-border px-3 pb-6 pt-1 text-ng-muted">
                        {f.a}
                      </p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}

function FinalCta({ links }: { links: Links }) {
  return (
    <section className={`${wrap} pb-16 sm:pb-24 lg:pb-[120px]`} aria-labelledby="cta-h">
      <div className="ng-dark relative grid items-center gap-10 overflow-hidden rounded-[28px] bg-ng-primary p-9 text-ng-on-primary sm:p-14 lg:grid-cols-[1.25fr_1fr] lg:gap-14 lg:p-[88px]">
        <div className="pointer-events-none absolute -right-40 -top-56 size-[560px] rounded-full bg-ng-signal/[0.14]" />
        <div className="pointer-events-none absolute -bottom-40 -left-24 size-80 rounded-full bg-ng-on-primary/[0.06]" />
        <div className="relative flex flex-col items-start gap-6">
          <h2 id="cta-h" className="ng-display relative text-[clamp(40px,6vw,76px)]">
            {landingCta.title}
          </h2>
          <p className="relative max-w-[44ch] text-[clamp(18px,1.7vw,22px)] leading-normal text-ng-on-primary/90 [text-wrap:pretty]">
            {landingCta.body}
          </p>
          <div className="relative mt-1.5 flex flex-wrap gap-3">
            {links.signedIn ? (
              <a
                href={links.dashboardHref}
                className="ng-btn ng-focus ng-arrow-nudge bg-ng-signal text-ng-on-signal hover:bg-ng-signal-hover"
              >
                {landingNav.dashboard}
                <span className="ng-arrow" aria-hidden="true">
                  <ArrowRight size={18} />
                </span>
              </a>
            ) : (
              <>
                <a
                  href={links.signUpHref}
                  className="ng-btn ng-focus ng-arrow-nudge bg-ng-signal text-ng-on-signal hover:bg-ng-signal-hover"
                >
                  {landingCta.primary}
                  <span className="ng-arrow" aria-hidden="true">
                    <ArrowRight size={18} />
                  </span>
                </a>
                <a
                  href={links.signInHref}
                  className="ng-btn ng-focus border-ng-on-primary/45 text-ng-on-primary hover:bg-ng-on-primary/10"
                >
                  {landingCta.secondary}
                </a>
              </>
            )}
          </div>
        </div>
        <img
          src="/images/landing/nurse-cta.webp"
          alt="A nurse in mint scrubs laughing, with a stethoscope around her neck"
          width={586}
          height={495}
          loading="lazy"
          decoding="async"
          className="relative aspect-[4/3] w-full rounded-[18px] object-cover object-top sm:aspect-[5/4]"
        />
      </div>
    </section>
  );
}

function Footer({ links }: { links: Links }) {
  const linkCls =
    "ng-focus inline-flex min-h-9 items-center text-[15px] font-medium text-ng-muted transition-colors duration-150 hover:text-ng-primary";
  return (
    <footer className="border-t border-ng-border/60 bg-ng-sunken">
      <div className={`${wrap} py-12 sm:py-16`}>
        <div className="grid gap-10 sm:grid-cols-2 md:grid-cols-3 md:gap-12 lg:gap-16">
          {/* Column 1 — Brand */}
          <div className="flex max-w-[32ch] flex-col items-start gap-3">
            <a href="#top" className="ng-focus" aria-label="NurseGenius home">
              <Brand className="size-20 sm:size-24" />
            </a>
            <p className="text-[15px] leading-relaxed text-ng-muted">{landingFooter.tagline}</p>
          </div>

          {/* Column 2 — Explore */}
          <nav aria-label={landingFooter.exploreTitle} className="flex flex-col gap-1.5">
            <h2 className="mb-2 font-display text-base font-bold tracking-[-0.01em] text-ng-ink">
              {landingFooter.exploreTitle}
            </h2>
            {landingFooter.explore.map((l) => (
              <a key={l.label} href={l.href} className={linkCls}>
                {l.label}
              </a>
            ))}
          </nav>

          {/* Column 3 — Account */}
          <nav aria-label={landingFooter.accountTitle} className="flex flex-col gap-1.5">
            <h2 className="mb-2 font-display text-base font-bold tracking-[-0.01em] text-ng-ink">
              {landingFooter.accountTitle}
            </h2>
            {links.signedIn ? (
              <a href={links.dashboardHref} className={linkCls}>
                {landingNav.dashboard}
              </a>
            ) : (
              <>
                <a href={links.signInHref} className={linkCls}>
                  {landingFooter.signIn}
                </a>
                <a href={links.signUpHref} className={linkCls}>
                  {landingFooter.create}
                </a>
              </>
            )}
          </nav>
        </div>

        {/* Copyright divider and row */}
        <div className="mt-12 border-t border-ng-border/60 pt-6">
          <p className="text-sm text-ng-muted">© {new Date().getFullYear()} NurseGenius</p>
        </div>
      </div>
    </footer>
  );
}

export function LandingPage({
  plans,
  signedIn = false,
  signInHref = "/auth",
  signUpHref = "/auth?mode=signup",
  dashboardHref = "/dashboard",
}: LandingPageProps) {
  const links: Links = { signedIn, signInHref, signUpHref, dashboardHref };

  useEffect(() => {
    const reveals = document.querySelectorAll<HTMLElement>("[data-reveal]");
    reveals.forEach((el) => el.classList.add("ng-reveal"));

    if (
      typeof window === "undefined" ||
      !("IntersectionObserver" in window) ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      reveals.forEach((el) => el.classList.add("is-visible"));
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.08, rootMargin: "0px 0px -40px 0px" },
    );

    reveals.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, []);

  return (
    <div className="ng-root min-h-dvh" id="top">
      <a
        href="#main"
        className="ng-btn absolute left-4 top-[-80px] z-50 bg-ng-primary text-ng-on-primary focus:top-3"
      >
        {landingNav.skip}
      </a>
      <Header links={links} />
      <main id="main">
        <Hero links={links} />
        <How />
        <Pathways />
        <Practice />
        <Progress />
        <Ai />
        <StudyPlan />
        <Plans plans={plans} />
        <Faq />
        <FinalCta links={links} />
      </main>
      <Footer links={links} />
    </div>
  );
}
