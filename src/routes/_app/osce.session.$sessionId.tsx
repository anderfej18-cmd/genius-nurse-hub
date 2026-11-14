import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  AlertTriangle,
  Award,
  CheckCircle2,
  Circle,
  Clock,
  Mic,
  MicOff,
  XCircle,
} from "lucide-react";
import { SignedInPage } from "@/components/SignedInPage";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadFailed } from "@/components/app/LoadFailed";
import { OsceDisclaimer } from "@/components/osce/OsceDisclaimer";
import { useServerData } from "@/hooks/use-server-data";
import { getOsceSession, processOsceSpeech, completeOsceSession } from "@/functions/osce.functions";
import type { OsceChecklistItem, OsceSessionEvaluation } from "@/lib/osce";

interface SpeechRecognitionResultItem {
  transcript: string;
  confidence: number;
}
interface SpeechRecognitionResultList {
  length: number;
  item(index: number): SpeechRecognitionResult;
  [index: number]: SpeechRecognitionResult;
}
interface SpeechRecognitionResult {
  isFinal: boolean;
  length: number;
  item(index: number): SpeechRecognitionResultItem;
  [index: number]: SpeechRecognitionResultItem;
}
interface SpeechRecognitionEvent {
  resultIndex: number;
  results: SpeechRecognitionResultList;
}
interface SpeechRecognitionErrorEvent {
  error: string;
  message?: string;
}
interface SpeechRecognitionInstance {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onresult: ((event: SpeechRecognitionEvent) => void) | null;
  onerror: ((event: SpeechRecognitionErrorEvent) => void) | null;
  onend: (() => void) | null;
  start(): void;
  stop(): void;
}

export const Route = createFileRoute("/_app/osce/session/$sessionId")({
  component: OsceLiveSessionPage,
  head: () => ({
    meta: [
      { title: "OSCE Live Session | NurseGenius" },
      {
        name: "description",
        content:
          "Live OSCE practice session with real-time speech recognition and checklist matching.",
      },
    ],
  }),
});

function useTimer(startedAt: string | null, timeLimitSeconds: number) {
  const [elapsed, setElapsed] = useState(0);
  useEffect(() => {
    if (!startedAt) return;
    const startTime = new Date(startedAt).getTime();
    const interval = setInterval(() => {
      const now = Date.now();
      setElapsed(Math.floor((now - startTime) / 1000));
    }, 1000);
    return () => clearInterval(interval);
  }, [startedAt]);

  const remaining = Math.max(0, timeLimitSeconds - elapsed);
  const minutes = Math.floor(remaining / 60);
  const seconds = remaining % 60;
  const timeString = `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  const percentRemaining = timeLimitSeconds > 0 ? (remaining / timeLimitSeconds) * 100 : 0;
  const isExpired = remaining <= 0;
  const isWarning = remaining > 0 && remaining <= 60;

  return { elapsed, remaining, timeString, percentRemaining, isExpired, isWarning };
}

function useSpeechRecognition(onResult: (text: string) => void) {
  const [isListening, setIsListening] = useState(false);
  const [isSupported, setIsSupported] = useState(false);
  const [speechError, setSpeechError] = useState<string | null>(null);
  const recognitionRef = useRef<SpeechRecognitionInstance | null>(null);
  // Track listening state in a ref so the onend callback always reads the current value
  // without depending on a stale closure — avoids recreating the recognition instance on every toggle.
  const isListeningRef = useRef(false);
  const onResultRef = useRef(onResult);
  onResultRef.current = onResult;

  useEffect(() => {
    const SpeechRecognitionAPI = (typeof window !== "undefined" &&
      ((window as unknown as Record<string, unknown>).SpeechRecognition ||
        (window as unknown as Record<string, unknown>).webkitSpeechRecognition)) as
      | (new () => SpeechRecognitionInstance)
      | undefined;

    if (!SpeechRecognitionAPI) return;

    setIsSupported(true);
    const recognition = new SpeechRecognitionAPI();
    recognition.continuous = true;
    recognition.interimResults = false;
    recognition.lang = "en-NG";

    recognition.onresult = (event: SpeechRecognitionEvent) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        if (event.results[i].isFinal) {
          const transcript = event.results[i][0].transcript.trim();
          if (transcript) onResultRef.current(transcript);
        }
      }
    };

    recognition.onerror = (event: SpeechRecognitionErrorEvent) => {
      if (event.error === "not-allowed" || event.error === "service-not-allowed") {
        isListeningRef.current = false;
        setIsListening(false);
        setSpeechError(
          "Microphone permission was denied. Please allow microphone access in your browser to speak.",
        );
      } else if (event.error === "network") {
        isListeningRef.current = false;
        setIsListening(false);
        setSpeechError(
          "Speech recognition requires an active internet connection. Please verify your network connection.",
        );
      } else if (event.error !== "aborted" && event.error !== "no-speech") {
        console.error("Speech recognition error:", event.error);
      }
    };

    recognition.onend = () => {
      // Auto-restart only while still in listening mode (checked via ref, not stale closure).
      if (recognitionRef.current && isListeningRef.current) {
        try {
          recognitionRef.current.start();
        } catch {
          // Already started — ignore.
        }
      }
    };

    recognitionRef.current = recognition;

    return () => {
      try {
        recognition.stop();
      } catch {
        // Not started — ignore.
      }
    };
    // This effect runs once per mount. onResult updates are handled via onResultRef.
    // isListening is tracked via isListeningRef, NOT as an effect dependency, to avoid
    // tearing down and recreating the SpeechRecognition instance on every toggle.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const start = useCallback(() => {
    setSpeechError(null);
    if (recognitionRef.current) {
      try {
        recognitionRef.current.start();
        isListeningRef.current = true;
        setIsListening(true);
      } catch {
        // Already started
      }
    }
  }, []);

  const stop = useCallback(() => {
    isListeningRef.current = false;
    if (recognitionRef.current) {
      try {
        recognitionRef.current.stop();
      } catch {
        // Not started
      }
    }
    setIsListening(false);
  }, []);

  return { isListening, isSupported, speechError, start, stop };
}

function OsceLiveSessionPage() {
  const { sessionId } = Route.useParams() as { sessionId: string };
  const navigate = useNavigate();
  const [isEnding, setIsEnding] = useState(false);
  const [liveEvaluations, setLiveEvaluations] = useState<Map<string, OsceSessionEvaluation>>(
    new Map(),
  );
  const [liveScore, setLiveScore] = useState(0);
  const [transcriptLines, setTranscriptLines] = useState<Array<{ text: string; time: number }>>([]);
  const transcriptRef = useRef<HTMLDivElement>(null);

  const sessionQuery = useServerData(() => getOsceSession({ data: { sessionId } }), [sessionId]);

  const session = sessionQuery.data;
  const timeLimitSeconds = session?.checklistItems?.length
    ? Math.max(300, session.checklistItems.length * 30)
    : 420;

  const timer = useTimer(session?.startedAt ?? null, timeLimitSeconds);

  const handleSpeechResult = useCallback(
    async (text: string) => {
      if (!session || session.status !== "in_progress") return;
      const timestampSeconds = timer.elapsed;
      setTranscriptLines((prev) => [...prev, { text, time: timestampSeconds }]);

      setTimeout(() => {
        transcriptRef.current?.scrollTo({
          top: transcriptRef.current.scrollHeight,
          behavior: "smooth",
        });
      }, 50);

      try {
        const result = await processOsceSpeech({
          data: { sessionId, text, timestampSeconds },
        });
        if (result) {
          setLiveScore(result.totalScore);
          setLiveEvaluations((prev) => {
            const next = new Map(prev);
            for (const ev of result.evaluations) {
              next.set(ev.itemId, ev);
            }
            return next;
          });
        }
      } catch (err) {
        console.error("Failed to process speech:", err);
      }
    },
    [session, sessionId, timer.elapsed],
  );

  const speech = useSpeechRecognition(handleSpeechResult);

  const handleEndSession = useCallback(async () => {
    if (isEnding || !session) return;
    setIsEnding(true);
    speech.stop();
    try {
      await completeOsceSession({ data: { sessionId } });
      navigate({ to: "/osce/results/$sessionId", params: { sessionId } });
    } catch {
      setIsEnding(false);
    }
  }, [isEnding, session, speech, sessionId, navigate]);

  useEffect(() => {
    if (timer.isExpired && session?.status === "in_progress" && !isEnding) {
      handleEndSession();
    }
  }, [timer.isExpired, session?.status, isEnding, handleEndSession]);

  const totalPossible = session?.totalPossible ?? 0;
  const progressPercent = totalPossible > 0 ? (liveScore / totalPossible) * 100 : 0;
  const awardedCount = Array.from(liveEvaluations.values()).filter(
    (e) => e.status === "awarded",
  ).length;
  const totalItems = session?.checklistItems?.length ?? 0;

  return (
    <SignedInPage title="OSCE Live Session" description="">
      {() => (
        <div className="flex flex-col gap-4">
          {sessionQuery.loading && !session && (
            <div className="flex flex-col gap-4">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-40 w-full" />
              <Skeleton className="h-60 w-full" />
            </div>
          )}

          {sessionQuery.error && !session && (
            <LoadFailed load={sessionQuery} label="OSCE session" />
          )}

          {session && (
            <>
              {/* Mandatory Student Disclaimer */}
              <OsceDisclaimer />

              {/* Procedure Title + Timer Bar */}
              <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
                <div>
                  <h2 className="text-lg font-bold">{session.procedureTitle}</h2>
                  <p className="text-xs text-muted-foreground">
                    {session.stationNumber} • {session.examiningBody}
                  </p>
                </div>
                <div className="flex items-center gap-3">
                  <div
                    className={`flex items-center gap-1.5 font-mono text-lg font-bold tabular-nums ${
                      timer.isWarning
                        ? "text-destructive animate-pulse"
                        : timer.isExpired
                          ? "text-destructive"
                          : "text-foreground"
                    }`}
                  >
                    <Clock className="size-4" />
                    {timer.timeString}
                  </div>
                  <Badge variant="outline" className="text-xs gap-1 border-primary/40 text-primary">
                    <Mic className="size-3 text-primary" />
                    {session.mode === "oral" ? "Oral Viva" : "Procedure Walkthrough"} • Voice
                  </Badge>
                </div>
              </div>

              {/* Score Progress Bar */}
              <Card className="border-border/70">
                <CardContent className="p-3 flex items-center gap-3">
                  <Award className="size-5 text-primary flex-shrink-0" />
                  <div className="flex-1">
                    <div className="flex items-center justify-between text-xs mb-1 tabular-nums">
                      <span className="font-medium">
                        {liveScore.toFixed(1)} / {totalPossible.toFixed(1)} marks
                      </span>
                      <span className="text-muted-foreground">
                        {awardedCount} / {totalItems} steps awarded
                      </span>
                    </div>
                    <Progress value={progressPercent} className="h-2" />
                  </div>
                </CardContent>
              </Card>

              {/* Main Content: 2-column on desktop */}
              <div className="grid grid-cols-1 lg:grid-cols-5 gap-4">
                {/* Left: Transcript / Microphone Controls */}
                <div className="lg:col-span-2 flex flex-col gap-3">
                  {/* Speech & Microphone Controls */}
                  <Card className="border-border/70">
                    <CardContent className="p-4 flex flex-col items-center gap-3">
                      {!speech.isSupported ? (
                        <p className="text-sm text-destructive text-center">
                          Speech recognition is not supported in this browser. Try Google Chrome.
                        </p>
                      ) : (
                        <>
                          <Button
                            onClick={speech.isListening ? speech.stop : speech.start}
                            variant={speech.isListening ? "destructive" : "default"}
                            size="lg"
                            className="w-full gap-2 text-base min-h-[44px]"
                            disabled={session.status !== "in_progress"}
                          >
                            {speech.isListening ? (
                              <>
                                <MicOff className="size-5" /> Stop Listening
                              </>
                            ) : (
                              <>
                                <Mic className="size-5" /> Start Speaking
                              </>
                            )}
                          </Button>
                          {speech.isListening ? (
                            <div className="flex items-center gap-2 text-xs text-primary">
                              <span className="size-2 rounded-full bg-primary animate-pulse" />
                              Listening... Verbally explain each procedure step clearly.
                            </div>
                          ) : (
                            <p className="text-xs text-muted-foreground text-center">
                              Click above and verbally describe each step as if answering an OSCE
                              examiner.
                            </p>
                          )}
                          {speech.speechError && (
                            <p className="text-xs text-destructive text-center font-medium mt-1">
                              {speech.speechError}
                            </p>
                          )}
                        </>
                      )}
                    </CardContent>
                  </Card>

                  {/* Live Spoken Transcript */}
                  <Card className="border-border/70 flex-1">
                    <CardContent className="p-3">
                      <h4 className="text-xs font-semibold text-muted-foreground mb-2 uppercase tracking-wider">
                        Live Spoken Transcript
                      </h4>
                      <div
                        ref={transcriptRef}
                        className="max-h-60 overflow-y-auto flex flex-col gap-2 text-sm"
                      >
                        {transcriptLines.length === 0 && (
                          <p className="text-xs text-muted-foreground italic py-4 text-center">
                            Your spoken words will appear here in real time as you explain the
                            procedure...
                          </p>
                        )}
                        {transcriptLines.map((line, i) => (
                          <div key={i} className="flex gap-2 items-start">
                            <span className="text-[10px] font-mono text-muted-foreground mt-0.5 whitespace-nowrap">
                              {Math.floor(line.time / 60)}:{String(line.time % 60).padStart(2, "0")}
                            </span>
                            <p className="text-sm text-foreground">{line.text}</p>
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                </div>

                {/* Right: Live Checklist */}
                <div className="lg:col-span-3">
                  <Card className="border-border/70">
                    <CardContent className="p-3">
                      <div className="flex items-center justify-between mb-2">
                        <h4 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                          Examiner Checklist
                        </h4>
                        <span className="text-[11px] text-muted-foreground">
                          Auto-marked via speech
                        </span>
                      </div>
                      <div className="flex flex-col gap-1 max-h-[60vh] overflow-y-auto">
                        {(session.checklistItems ?? []).map((item: OsceChecklistItem) => {
                          const evaluation = liveEvaluations.get(item.id);
                          const status = evaluation?.status ?? "missed";
                          const isAwarded = status === "awarded";
                          const isPartial = status === "partially_awarded";

                          return (
                            <div
                              key={item.id}
                              className={`flex items-start gap-2 p-2 rounded-lg transition-colors ${
                                isAwarded
                                  ? "bg-primary/10 border border-primary/30"
                                  : isPartial
                                    ? "bg-muted border border-border"
                                    : "border border-transparent"
                              }`}
                            >
                              {/* Status Icon */}
                              <div className="mt-0.5 flex-shrink-0">
                                {isAwarded ? (
                                  <CheckCircle2 className="size-4 text-primary" />
                                ) : isPartial ? (
                                  <CheckCircle2 className="size-4 text-muted-foreground" />
                                ) : (
                                  <Circle className="size-4 text-muted-foreground/40" />
                                )}
                              </div>

                              {/* Step Content */}
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-1.5">
                                  <span className="text-xs font-mono text-muted-foreground">
                                    {item.stepOrder}.
                                  </span>
                                  <p
                                    className={`text-sm leading-snug ${isAwarded ? "text-foreground font-medium" : ""}`}
                                  >
                                    {item.description}
                                  </p>
                                </div>
                                <div className="flex items-center gap-2 mt-0.5">
                                  <span className="text-xs text-muted-foreground">
                                    {isAwarded
                                      ? `+${item.allocatedMarks} mk`
                                      : isPartial
                                        ? `+${(evaluation?.marksAwarded ?? 0).toFixed(2)} / ${item.allocatedMarks} mk`
                                        : `${item.allocatedMarks} mk`}
                                  </span>
                                  {item.isCritical && (
                                    <Badge
                                      variant="destructive"
                                      className="text-[10px] px-1 py-0 h-3.5 gap-0.5"
                                    >
                                      <AlertTriangle className="size-2.5" /> Critical
                                    </Badge>
                                  )}
                                  <Badge variant="outline" className="text-[10px] px-1 py-0 h-3.5">
                                    {item.section.split(" ")[0]}
                                  </Badge>
                                </div>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </div>

              {/* End Session Button */}
              <div className="flex justify-center pt-2">
                <Button
                  onClick={handleEndSession}
                  variant="destructive"
                  size="lg"
                  disabled={isEnding}
                  className="gap-2 min-w-[200px] min-h-[44px]"
                >
                  <XCircle className="size-5" />
                  {isEnding ? "Submitting..." : "End Examination"}
                </Button>
              </div>
            </>
          )}
        </div>
      )}
    </SignedInPage>
  );
}
