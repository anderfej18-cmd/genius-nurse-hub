import { Link, createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import {
  ArrowLeft,
  Award,
  CheckCircle2,
  Clock,
  ListOrdered,
  Mic,
  ChevronRight,
  AlertTriangle,
  FileText,
  Wrench,
  AlertCircle,
} from "lucide-react";
import { SignedInPage } from "@/components/SignedInPage";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadFailed } from "@/components/app/LoadFailed";
import { OsceDisclaimer } from "@/components/osce/OsceDisclaimer";
import { useServerData } from "@/hooks/use-server-data";
import { getOsceProcedureDetail, startOsceSession } from "@/functions/osce.functions";
import type { OsceChecklistItem, SessionMode } from "@/lib/osce";

export const Route = createFileRoute("/_app/osce/$procedureId")({
  component: OsceProcedureDetailPage,
  head: () => ({
    meta: [
      { title: "OSCE Station Briefing | NurseGenius" },
      {
        name: "description",
        content:
          "Review the OSCE station instructions, equipment list, checklist steps, and choose your assessment mode before starting.",
      },
    ],
  }),
});

function OsceProcedureDetailPage() {
  const { procedureId } = Route.useParams() as { procedureId: string };
  const navigate = useNavigate();
  const [selectedMode, setSelectedMode] = useState<SessionMode>("oral");
  const [isStarting, setIsStarting] = useState(false);
  const [startError, setStartError] = useState<string | null>(null);

  const procedureQuery = useServerData(
    () => getOsceProcedureDetail({ data: { identifier: procedureId } }),
    [procedureId],
  );

  const procedure = procedureQuery.data;

  const handleStart = async () => {
    if (!procedure || isStarting) return;
    setIsStarting(true);
    setStartError(null);
    try {
      const session = await startOsceSession({
        data: { procedureId: procedure.id, mode: selectedMode },
      });
      navigate({
        to: "/osce/session/$sessionId",
        params: { sessionId: session.id },
      });
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Unable to start the station. Please try again.";
      setStartError(message);
      setIsStarting(false);
    }
  };

  const minutes = procedure ? Math.round(procedure.timeLimitSeconds / 60) : 0;

  return (
    <SignedInPage
      title="OSCE Station Briefing"
      description="Review the station details and start your practice."
    >
      {() => (
        <div className="flex flex-col gap-6">
          {/* Back Navigation */}
          <Button asChild variant="ghost" size="sm" className="self-start gap-1.5 -ml-2">
            <Link to="/osce">
              <ArrowLeft className="size-4" /> All Stations
            </Link>
          </Button>

          {procedureQuery.loading && !procedure && (
            <div className="flex flex-col gap-4">
              <Skeleton className="h-10 w-3/4" />
              <Skeleton className="h-6 w-1/2" />
              <Skeleton className="h-40 w-full" />
              <Skeleton className="h-60 w-full" />
            </div>
          )}

          {procedureQuery.error && !procedure && (
            <LoadFailed load={procedureQuery} label="OSCE procedure" />
          )}

          {procedure && (
            <>
              {/* Header */}
              <div className="flex flex-col gap-2">
                <div className="flex items-center gap-2 flex-wrap">
                  <Badge variant="default" className="text-xs">
                    {procedure.stationNumber}
                  </Badge>
                  {procedure.assessmentMode === "oral" && (
                    <Badge variant="outline" className="text-xs gap-1 border-border">
                      <Mic className="size-3 text-primary" /> Oral Viva
                    </Badge>
                  )}
                  {procedure.assessmentMode === "practical" && (
                    <Badge variant="outline" className="text-xs gap-1 border-border">
                      <Mic className="size-3 text-primary" /> Procedure Walkthrough
                    </Badge>
                  )}
                  {procedure.assessmentMode === "both" && (
                    <Badge variant="outline" className="text-xs gap-1 border-border">
                      <Mic className="size-3 text-primary" /> Oral & Practical
                    </Badge>
                  )}
                </div>
                <h1 className="text-2xl font-bold text-foreground [text-wrap:balance]">
                  {procedure.title}
                </h1>
                <p className="text-sm text-muted-foreground">
                  {procedure.examiningBody} • {procedure.sessionLabel}
                </p>
              </div>

              {/* Stats Row */}
              <div className="grid grid-cols-3 gap-3">
                <Card className="bg-card/60 border-border/70">
                  <CardContent className="p-3 flex items-center gap-2">
                    <Award className="size-5 text-primary" />
                    <div>
                      <p className="text-lg font-bold tabular-nums">{procedure.totalMarks}</p>
                      <p className="text-xs text-muted-foreground">Total Marks</p>
                    </div>
                  </CardContent>
                </Card>
                <Card className="bg-card/60 border-border/70">
                  <CardContent className="p-3 flex items-center gap-2">
                    <Clock className="size-5 text-primary" />
                    <div>
                      <p className="text-lg font-bold tabular-nums">{minutes} min</p>
                      <p className="text-xs text-muted-foreground">Time Limit</p>
                    </div>
                  </CardContent>
                </Card>
                <Card className="bg-card/60 border-border/70">
                  <CardContent className="p-3 flex items-center gap-2">
                    <ListOrdered className="size-5 text-primary" />
                    <div>
                      <p className="text-lg font-bold tabular-nums">
                        {procedure.checklist.totalItems}
                      </p>
                      <p className="text-xs text-muted-foreground">Steps</p>
                    </div>
                  </CardContent>
                </Card>
              </div>

              {/* Scenario Prompt */}
              <Card className="bg-primary/5 border-primary/20">
                <CardContent className="p-4">
                  <div className="flex items-start gap-2.5">
                    <FileText className="size-5 text-primary flex-shrink-0 mt-0.5" />
                    <div>
                      <h3 className="font-semibold text-sm text-primary mb-1">
                        Examiner Instructions
                      </h3>
                      <p className="text-sm text-foreground/90 leading-relaxed">
                        {procedure.scenarioPrompt}
                      </p>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* Equipment List */}
              {procedure.equipmentList.length > 0 && (
                <Card className="border-border/70">
                  <CardContent className="p-4">
                    <div className="flex items-center gap-2 mb-3">
                      <Wrench className="size-4 text-muted-foreground" />
                      <h3 className="font-semibold text-sm">Equipment Required</h3>
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      {procedure.equipmentList.map((item, i) => (
                        <Badge
                          key={i}
                          variant="secondary"
                          className="text-xs font-normal px-2.5 py-1"
                        >
                          {item}
                        </Badge>
                      ))}
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Checklist Preview */}
              <Card className="border-border/70">
                <CardContent className="p-4">
                  <h3 className="font-semibold text-sm mb-3 flex items-center gap-2">
                    <CheckCircle2 className="size-4 text-primary" />
                    Checklist Steps ({procedure.checklist.totalItems})
                  </h3>
                  <div className="flex flex-col gap-1.5 max-h-96 overflow-y-auto">
                    {procedure.checklist.items.map((item: OsceChecklistItem) => (
                      <div
                        key={item.id}
                        className="flex items-start gap-2.5 p-2 rounded-lg hover:bg-muted/50 transition-colors"
                      >
                        <span className="text-xs font-mono text-muted-foreground mt-0.5 min-w-[1.5rem] text-right">
                          {item.stepOrder}.
                        </span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm leading-snug">{item.description}</p>
                          <div className="flex items-center gap-2 mt-0.5">
                            <span className="text-xs text-muted-foreground">
                              {item.allocatedMarks} mk
                            </span>
                            {item.isCritical && (
                              <Badge
                                variant="destructive"
                                className="text-[10px] px-1.5 py-0 h-4 gap-0.5"
                              >
                                <AlertTriangle className="size-2.5" /> Critical
                              </Badge>
                            )}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>

              {/* Mandatory Student Disclaimer */}
              <OsceDisclaimer />

              {/* Mode Selection & Start */}
              <Card className="border-primary/30 bg-card/80">
                <CardContent className="p-5">
                  <div className="flex items-center justify-between mb-3">
                    <h3 className="font-semibold text-base">Select Verbal Practice Format</h3>
                    <Badge variant="outline" className="text-[11px] gap-1">
                      <Mic className="size-3 text-primary" /> Voice Assessed
                    </Badge>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-4">
                    <button
                      type="button"
                      onClick={() => setSelectedMode("oral")}
                      disabled={procedure.assessmentMode === "practical"}
                      className={`p-4 rounded-xl border-2 text-left transition-colors focus-ring ${
                        selectedMode === "oral"
                          ? "border-primary bg-primary/5 ring-2 ring-primary/20"
                          : "border-border hover:border-primary/30"
                      } ${procedure.assessmentMode === "practical" ? "opacity-50 cursor-not-allowed" : "cursor-pointer"}`}
                    >
                      <div className="flex items-center gap-2 mb-1.5">
                        <Mic className="size-5 text-primary" />
                        <span className="font-semibold text-sm">Oral Viva</span>
                      </div>
                      <p className="text-xs text-muted-foreground [text-wrap:pretty]">
                        Verbalize answers to examiner questions, clinical rationales, and
                        theoretical principles.
                      </p>
                    </button>

                    <button
                      type="button"
                      onClick={() => setSelectedMode("practical")}
                      disabled={procedure.assessmentMode === "oral"}
                      className={`p-4 rounded-xl border-2 text-left transition-colors focus-ring ${
                        selectedMode === "practical"
                          ? "border-primary bg-primary/5 ring-2 ring-primary/20"
                          : "border-border hover:border-primary/30"
                      } ${procedure.assessmentMode === "oral" ? "opacity-50 cursor-not-allowed" : "cursor-pointer"}`}
                    >
                      <div className="flex items-center gap-2 mb-1.5">
                        <Mic className="size-5 text-primary" />
                        <span className="font-semibold text-sm">Procedure Walkthrough</span>
                      </div>
                      <p className="text-xs text-muted-foreground [text-wrap:pretty]">
                        Verbally walk through each physical action, aseptic technique, and equipment
                        handling step.
                      </p>
                    </button>
                  </div>

                  {/* Start Error */}
                  {startError && (
                    <div className="flex items-start gap-2 rounded-xl bg-destructive/10 border border-destructive/30 p-3">
                      <AlertCircle className="size-4 text-destructive flex-shrink-0 mt-0.5" />
                      <p className="text-sm text-destructive">{startError}</p>
                    </div>
                  )}

                  <Button
                    onClick={handleStart}
                    disabled={isStarting}
                    size="lg"
                    className="w-full gap-2 text-base min-h-[44px]"
                  >
                    {isStarting ? "Starting Station..." : "Begin Voice Examination"}
                    <ChevronRight className="size-5" />
                  </Button>
                </CardContent>
              </Card>
            </>
          )}
        </div>
      )}
    </SignedInPage>
  );
}
