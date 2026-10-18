import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { LandingPage, type LivePlan } from "@/components/landing/LandingPage";
import { listPublicPlans } from "@/functions/plans.functions";
import { useAuth } from "@/hooks/use-auth";
import { resolveToken } from "@/lib/design-tokens";

const TITLE = "NurseGenius: RN and RM exam practice with a study plan";
const DESCRIPTION =
  "Timed RN and RM practice with the reasoning behind every answer, a mistake bank, and a study plan built from your own results.";

const CONTRACT_DEFAULT_PLANS: LivePlan[] = [
  { name: "Erudite", priceNaira: 1500, accessDays: 30 },
  { name: "Scholar", priceNaira: 2000, accessDays: 30 },
];

export const Route = createFileRoute("/")({
  loader: async () => {
    try {
      const data = await listPublicPlans({ data: {} });
      const live: LivePlan[] = [];
      if (Array.isArray(data)) {
        for (const p of data) {
          const rawName = p.name.trim().toLowerCase();
          if (rawName === "erudite") {
            live.push({ name: "Erudite", priceNaira: p.priceNgn, accessDays: p.durationDays });
          } else if (rawName === "scholar") {
            live.push({ name: "Scholar", priceNaira: p.priceNgn, accessDays: p.durationDays });
          }
        }
      }
      return { initialPlans: live.length > 0 ? live : CONTRACT_DEFAULT_PLANS };
    } catch {
      return { initialPlans: CONTRACT_DEFAULT_PLANS };
    }
  },
  component: Index,
  head: () => ({
    meta: [
      { title: TITLE },
      { name: "description", content: DESCRIPTION },
      { property: "og:title", content: TITLE },
      { property: "og:description", content: DESCRIPTION },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "twitter:title", content: TITLE },
      { name: "twitter:description", content: DESCRIPTION },
      { name: "theme-color", content: resolveToken("light", "background") },
    ],
    links: [
      // Preload the LCP hero image so the browser fetches it during HTML parsing,
      // before the JS bundle has been parsed and executed.
      {
        rel: "preload",
        href: "/images/landing/hero-nurses-transparent.webp",
        as: "image",
        type: "image/webp",
        fetchPriority: "high",
      },
    ],
  }),
});

function Index() {
  const { user, profile, loading } = useAuth();
  const navigate = useNavigate();
  const loaderData = Route.useLoaderData();
  const [plans, setPlans] = useState<LivePlan[] | undefined>(loaderData?.initialPlans);

  // A signed-in person who has not finished setting up goes on to finish it.
  useEffect(() => {
    if (!loading && user && profile && !profile.onboarded) navigate({ to: "/onboarding" });
  }, [loading, user, profile, navigate]);

  // Keep dynamic plans synchronized with the database
  useEffect(() => {
    let cancelled = false;
    listPublicPlans({ data: {} }).then(
      (data) => {
        if (!cancelled && Array.isArray(data)) {
          const live: LivePlan[] = [];
          for (const p of data) {
            const rawName = p.name.trim().toLowerCase();
            if (rawName === "erudite") {
              live.push({ name: "Erudite", priceNaira: p.priceNgn, accessDays: p.durationDays });
            } else if (rawName === "scholar") {
              live.push({ name: "Scholar", priceNaira: p.priceNgn, accessDays: p.durationDays });
            }
          }
          if (live.length > 0) setPlans(live);
        }
      },
      () => {
        // Honest failure handling: leaving plans undefined renders the fallback "Shown after you sign in"
      },
    );
    return () => {
      cancelled = true;
    };
  }, []);

  const signedIn = !!user;

  return (
    // The landing page is always light: `theme-fixed` pins the light tokens whatever the visitor's
    // own theme preference is. Skip link href="#main" and landmark id="main" are in LandingPage.
    <div className="theme-fixed">
      <LandingPage
        plans={plans}
        signedIn={signedIn}
        signInHref="/auth"
        signUpHref="/auth?mode=signup"
        dashboardHref="/dashboard"
      />
    </div>
  );
}
