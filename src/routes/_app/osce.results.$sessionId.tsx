import { Link, createFileRoute } from "@tanstack/react-router";
import {
  AlertTriangle,
  ArrowLeft,
  Award,
  CheckCircle2,
  Clock,
  Lightbulb,
  Mic,
  RefreshCcw,
  ShieldAlert,
  Trophy,
  XCircle,
} from "lucide-react";
import { SignedInPage } from "@/components/SignedInPage";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadFailed } from "@/components/app/LoadFailed";
import { OsceDisclaimer } from "@/components/osce/OsceDisclaimer";
import { useServerData } from "@/hooks/use-server-data";
import { getOsceSession } from "@/functions/osce.functions";
import type { OsceChecklistItem, OsceSessionEvaluation } from "@/lib/osce";

export const Route = createFileRoute("/_app/osce/results/$sessionId")({
  component: OsceResultsPage,
  head: () => ({
    meta: [
      { title: "OSCE Results | NurseGenius" },
      {
        name: "description",
        content: "Review your OSCE station results, marks breakdown, and clinical feedback.",
      },
    ],
  }),
});

function OsceResultsPage() {
  const { sessionId } = Route.useParams() as { sessionId: string };

  const sessionQuery = useServerData(() => getOsceSession({ data: { sessionId } }), [sessionId]);

  const session = sessionQuery.data;

  const evaluationMap = new Map<string, OsceSessionEvaluation>();
  if (session?.evaluations) {
    for (const ev of session.evaluations) {
      evaluationMap.set(ev.itemId, ev);
    }
  }

  const awardedItems =
    session?.checklistItems?.filter(
      (item: OsceChecklistItem) => evaluationMap.get(item.id)?.status === "awarded",
    ) ?? [];

  const missedItems =
    session?.checklistItems?.filter((item: OsceChecklistItem) => {
      const ev = evaluationMap.get(item.id);
      return !ev || ev.status === "missed";
    }) ?? [];

  const criticalMissed = missedItems.filter((item: OsceChecklistItem) => item.isCritical);

  const percentage = session?.percentage ?? 0;
  const passed = session?.passed ?? false;

  const formatTime = (seconds: number) => {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}m ${s}s`;
  };

  return (
    <SignedInPage title="OSCE Results" description="Your detailed station performance report.">
      {() => (
        <div className="flex flex-col gap-6">
          {sessionQuery.loading && !session && (
            <div className="flex flex-col gap-4">
              <Skeleton className="h-12 w-2/3" />
              <Skeleton className="h-40 w-full" />
              <Skeleton className="h-60 w-full" />
            </div>
          )}

          {sessionQuery.error && !session && (
            <LoadFailed load={sessionQuery} label="OSCE results" />
          )}

          {session && (
            <>
              {/* Back + Title */}
              <Button asChild variant="ghost" size="sm" className="self-start gap-1.5 -ml-2">
                <Link to="/osce">
                  <ArrowLeft className="size-4" /> All Stations
                </Link>
              </Button>

              {/* Mandatory Student Disclaimer */}
              <OsceDisclaimer />

              {/* Result Header */}
              <div
                className={`rounded-2xl p-6 text-center border-2 ${
                  passed
                    ? "bg-primary/5 border-primary/30"
                    : "bg-destructive/5 border-destructive/30"
                }`}
              >
                <div className="flex justify-center mb-3">
                  {passed ? (
                    <Trophy className="size-12 text-primary" />
                  ) : (
                    <ShieldAlert className="size-12 text-destructive" />
                  )}
                </div>
                <h2 className="text-2xl font-bold mb-1">
                  {passed ? "Station Passed!" : "Not Yet Passed"}
                </h2>
                <p className="text-sm text-muted-foreground mb-3">
                  {session.procedureTitle} • {session.stationNumber}
                </p>
                <div className="text-4xl font-black tabular-nums">
                  {session.scoreObtained.toFixed(1)} / {session.totalPossible.toFixed(1)}
                </div>
                <p className="text-lg font-semibold mt-1">{percentage.toFixed(1)}%</p>
              </div>

              {/* Stats Cards */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <Card className="bg-card/60 border-border/70">
                  <CardContent className="p-3 text-center">
                    <CheckCircle2 className="size-5 text-primary mx-auto mb-1" />
                    <p className="text-lg font-bold tabular-nums">{awardedItems.length}</p>
                    <p className="text-xs text-muted-foreground">Awarded</p>
                  </CardContent>
                </Card>
                <Card className="bg-card/60 border-border/70">
                  <CardContent className="p-3 text-center">
                    <XCircle className="size-5 text-destructive mx-auto mb-1" />
                    <p className="text-lg font-bold tabular-nums">{missedItems.length}</p>
                    <p className="text-xs text-muted-foreground">Missed</p>
                  </CardContent>
                </Card>
                <Card className="bg-card/60 border-border/70">
                  <CardContent className="p-3 text-center">
                    <Clock className="size-5 text-primary mx-auto mb-1" />
                    <p className="text-lg font-bold tabular-nums">
                      {formatTime(session.timeSpentSeconds)}
                    </p>
                    <p className="text-xs text-muted-foreground">Time Used</p>
                  </CardContent>
                </Card>
                <Card className="bg-card/60 border-border/70">
                  <CardContent className="p-3 text-center">
                    <Mic className="size-5 text-primary mx-auto mb-1" />
                    <p className="text-sm font-bold capitalize">
                      {session.mode === "oral" ? "Oral Viva" : "Walkthrough"}
                    </p>
                    <p className="text-xs text-muted-foreground">Voice Assessed</p>
                  </CardContent>
                </Card>
              </div>

              {/* Critical Safety Alerts */}
              {criticalMissed.length > 0 && (
                <Card className="border-destructive/30 bg-destructive/10">
                  <CardContent className="p-4">
                    <div className="flex items-center gap-2 mb-3">
                      <AlertTriangle className="size-5 text-destructive" />
                      <h3 className="font-semibold text-sm text-destructive">
                        Critical Safety Steps Missed ({criticalMissed.length})
                      </h3>
                    </div>
                    <p className="text-xs text-muted-foreground mb-3">
                      In NMCN licensing examinations, omitting these steps can result in station
                      failure regardless of total score.
                    </p>
                    <div className="flex flex-col gap-2">
                      {criticalMissed.map((item: OsceChecklistItem) => (
                        <div
                          key={item.id}
                          className="flex items-start gap-2 p-2 rounded bg-destructive/5"
                        >
                          <AlertTriangle className="size-3.5 text-destructive mt-0.5 flex-shrink-0" />
                          <div>
                            <p className="text-sm font-medium text-foreground">
                              {item.description}
                            </p>
                            <p className="text-xs text-muted-foreground mt-0.5">
                              {item.allocatedMarks} marks • Step {item.stepOrder}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Full Checklist Breakdown */}
              <Card className="border-border/70">
                <CardContent className="p-4">
                  <h3 className="font-semibold text-sm mb-3 flex items-center gap-2">
                    <Award className="size-4 text-primary" />
                    Complete Checklist Breakdown
                  </h3>

                  {/* Section groups */}
                  {[
                    "Preparation & Equipment",
                    "Procedure Execution",
                    "Post-Procedure & Documentation",
                  ].map((section) => {
                    const sectionItems = session.checklistItems.filter(
                      (item: OsceChecklistItem) => item.section === section,
                    );
                    if (sectionItems.length === 0) return null;

                    const sectionScore = sectionItems.reduce(
                      (acc: number, item: OsceChecklistItem) => {
                        const ev = evaluationMap.get(item.id);
                        return acc + (ev?.marksAwarded ?? 0);
                      },
                      0,
                    );

                    const sectionTotal = sectionItems.reduce(
                      (acc: number, item: OsceChecklistItem) => acc + item.allocatedMarks,
                      0,
                    );

                    return (
                      <div key={section} className="mb-4">
                        <div className="flex items-center justify-between mb-2">
                          <h4 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                            {section}
                          </h4>
                          <span className="text-xs font-medium text-muted-foreground">
                            {sectionScore.toFixed(1)} / {sectionTotal.toFixed(1)}
                          </span>
                        </div>

                        <div className="flex flex-col gap-1">
                          {sectionItems.map((item: OsceChecklistItem) => {
                            const ev = evaluationMap.get(item.id);
                            const status = ev?.status ?? "missed";

                            return (
                              <div
                                key={item.id}
                                className={`flex items-start gap-2 p-2 rounded-lg ${
                                  status === "awarded"
                                    ? "bg-primary/10"
                                    : status === "partially_awarded"
                                      ? "bg-muted"
                                      : "bg-destructive/5"
                                }`}
                              >
                                <div className="mt-0.5 flex-shrink-0">
                                  {status === "awarded" ? (
                                    <CheckCircle2 className="size-4 text-primary" />
                                  ) : status === "partially_awarded" ? (
                                    <CheckCircle2 className="size-4 text-muted-foreground" />
                                  ) : (
                                    <XCircle className="size-4 text-destructive" />
                                  )}
                                </div>
                                <div className="flex-1 min-w-0">
                                  <p className="text-sm leading-snug">{item.description}</p>
                                  <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                                    <span
                                      className={`text-xs font-medium ${
                                        status === "awarded"
                                          ? "text-primary"
                                          : status === "partially_awarded"
                                            ? "text-muted-foreground"
                                            : "text-destructive"
                                      }`}
                                    >
                                      {status === "awarded"
                                        ? `+${item.allocatedMarks} mk`
                                        : status === "partially_awarded"
                                          ? `+${(ev?.marksAwarded ?? 0).toFixed(2)} / ${item.allocatedMarks} mk`
                                          : `0 / ${item.allocatedMarks} mk`}
                                    </span>
                                    {item.isCritical && (
                                      <Badge
                                        variant="destructive"
                                        className="text-[10px] px-1 py-0 h-3.5 gap-0.5"
                                      >
                                        <AlertTriangle className="size-2.5" /> Critical
                                      </Badge>
                                    )}
                                    {ev?.matchedText && status === "awarded" && (
                                      <span className="text-[10px] text-muted-foreground italic truncate max-w-[200px]">
                                        Matched: "{ev.matchedText}"
                                      </span>
                                    )}
                                  </div>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    );
                  })}
                </CardContent>
              </Card>

              {/* Clinical Feedback */}
              {session.clinicalFeedback && (
                <Card className="border-primary/20 bg-primary/5">
                  <CardContent className="p-5">
                    <div className="flex items-center gap-2 mb-3">
                      <Lightbulb className="size-5 text-primary" />
                      <h3 className="font-semibold text-base">Clinical Feedback</h3>
                    </div>
                    <p className="text-sm text-foreground/90 mb-4 leading-relaxed">
                      {session.clinicalFeedback.summary}
                    </p>

                    {session.clinicalFeedback.nextSteps.length > 0 && (
                      <div className="mt-3">
                        <h4 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">
                          Recommended Next Steps
                        </h4>
                        <ul className="flex flex-col gap-1">
                          {session.clinicalFeedback.nextSteps.map((step: string, i: number) => (
                            <li key={i} className="text-sm flex items-start gap-2">
                              <span className="text-primary mt-0.5">•</span>
                              <span>{step}</span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </CardContent>
                </Card>
              )}

              {/* Action Buttons */}
              <div className="flex flex-col sm:flex-row gap-3 justify-center pt-2">
                <Button asChild variant="outline" size="lg" className="gap-2 min-h-[44px]">
                  <Link to="/osce/$procedureId" params={{ procedureId: session.procedureId }}>
                    <RefreshCcw className="size-4" /> Try This Station Again
                  </Link>
                </Button>
                <Button asChild size="lg" className="gap-2 min-h-[44px]">
                  <Link to="/osce">
                    <ArrowLeft className="size-4" /> All OSCE Stations
                  </Link>
                </Button>
              </div>
            </>
          )}
        </div>
      )}
    </SignedInPage>
  );
}
