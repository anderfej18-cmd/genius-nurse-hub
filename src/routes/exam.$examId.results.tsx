import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Sparkles, Copy, Check, Trophy, Star, AlertCircle } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/exam/$examId/results")({ component: Results });

const GEMINI_URL = "https://gemini.google.com/app";

const buildAskAiPrompt = (q: QuestionShape) =>
  `Explain this nursing exam question and why the correct answer is ${q.correct_answer}:\n\n${q.question_text}\n\nA) ${q.option_a}\nB) ${q.option_b}\nC) ${q.option_c}\nD) ${q.option_d}`;

interface QuestionShape {
  id: string; question_text: string; correct_answer: string; rationale: string | null; topic: string;
  option_a: string; option_b: string; option_c: string; option_d: string;
}
interface Item {
  user_answer: string | null; is_correct: boolean | null; flagged: boolean; position: number;
  questions: QuestionShape;
}

function Results() {
  const { examId } = Route.useParams();
  const [exam, setExam] = useState<{ score_pct: number | null; correct_count: number | null; total_questions: number; exam_type: string } | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const { data: e, error: eErr } = await supabase
          .from("exams")
          .select("score_pct, correct_count, total_questions, exam_type")
          .eq("id", examId)
          .maybeSingle();
        if (eErr) throw eErr;
        if (!e) { setLoadErr("Exam not found or you don't have access."); return; }
        setExam(e as typeof exam);

        const { data, error } = await supabase
          .from("exam_answers")
          .select("user_answer, is_correct, flagged, position, questions(id, question_text, correct_answer, rationale, topic, option_a, option_b, option_c, option_d)")
          .eq("exam_id", examId)
          .order("position");
        if (error) throw error;
        setItems((data as unknown as Item[]) ?? []);
      } catch (err) {
        setLoadErr((err as Error).message ?? "Failed to load results");
      }
    })();
  }, [examId]);

  const copyQuestion = async (q: QuestionShape) => {
    const text = `${q.question_text}\n\nA) ${q.option_a}\nB) ${q.option_b}\nC) ${q.option_c}\nD) ${q.option_d}`;
    try {
      await navigator.clipboard.writeText(text);
      setCopiedId(q.id);
      toast.success("Copied to clipboard");
      setTimeout(() => setCopiedId(prev => (prev === q.id ? null : prev)), 1600);
    } catch {
      toast.error("Copy failed");
    }
  };

  const openAskAi = async (q: QuestionShape) => {
    const tab = window.open(GEMINI_URL, "_blank");
    if (tab) {
      tab.opener = null;
    } else {
      window.location.assign(GEMINI_URL);
      return;
    }

    try {
      await navigator.clipboard.writeText(buildAskAiPrompt(q));
      toast.success("Question copied — paste it into Gemini");
    } catch {
      toast.message("Opening Gemini");
    }

  };

  if (loadErr) return <><AppHeader /><div className="p-12 text-center space-y-3">
    <p className="text-destructive font-medium">{loadErr}</p>
    <Button asChild variant="outline"><Link to="/dashboard">Back to Dashboard</Link></Button>
  </div></>;

  if (!exam) return <><AppHeader /><div className="p-12 text-center">Loading results…</div></>;

  const total = exam.total_questions;
  const correct = items.filter(i => i.is_correct === true).length;
  const attempted = items.filter(i => i.user_answer !== null).length;
  const wrong = attempted - correct;
  const missed = total - attempted;
  const score = total > 0 ? (correct / total) * 100 : 0;

  const tag =
    score >= 80 ? { icon: <Trophy className="h-4 w-4" />, label: "Trophy 🏆", cls: "bg-warning text-warning-foreground" } :
    score >= 70 ? { icon: <Star className="h-4 w-4" />, label: "Solid", cls: "bg-success text-success-foreground" } :
    score >= 50 ? { label: "Progress", cls: "bg-warning/60 text-warning-foreground" } :
                  { icon: <AlertCircle className="h-4 w-4" />, label: "Keep going!", cls: "bg-destructive text-destructive-foreground" };

  return (
    <>
      <AppHeader />
      <main className="container mx-auto px-4 py-8 max-w-3xl space-y-6">
        {/* Scorecard */}
        <Card className="p-6 md:p-8 bg-card-soft shadow-glow">
          <div className="text-center">
            <p className="text-sm text-muted-foreground">Your Score</p>
            <p className="text-5xl md:text-6xl font-bold bg-hero bg-clip-text text-transparent mt-2">{score.toFixed(1)}%</p>
            <Badge className={`mt-3 ${tag.cls}`}>{tag.label}</Badge>
          </div>
          <div className="mt-6 grid grid-cols-2 md:grid-cols-5 gap-3">
            <Metric label="Total" value={total} />
            <Metric label="Attempted" value={attempted} />
            <Metric label="Correct" value={correct} tone="success" />
            <Metric label="Wrong" value={wrong} tone="destructive" />
            <Metric label="Missed" value={missed} tone="muted" />
          </div>
          <div className="mt-6 flex justify-center gap-2 flex-wrap">
            <Button asChild variant="outline"><Link to="/dashboard">Dashboard</Link></Button>
            <Button asChild className="bg-hero"><Link to="/exam/start">Take Another</Link></Button>
          </div>
        </Card>

        {/* All questions, continuous scroll */}
        <div className="space-y-4">
          {items.map((it, i) => {
            const q = it.questions;
            if (!q) return null;
            const status: "correct" | "wrong" | "skipped" =
              it.is_correct ? "correct" : it.user_answer ? "wrong" : "skipped";
            return (
              <Card key={q.id} className="p-5">
                <div className="flex justify-between items-start gap-3 mb-2">
                  <p className="text-xs text-muted-foreground">Question {i + 1} • {q.topic}</p>
                  <Badge className={
                    status === "correct" ? "bg-success text-success-foreground" :
                    status === "wrong" ? "bg-destructive text-destructive-foreground" :
                    "bg-muted text-muted-foreground"
                  }>
                    {status === "correct" ? "Correct" : status === "wrong" ? "Wrong" : "Skipped"}
                  </Badge>
                </div>
                <p className="font-medium">{q.question_text}</p>
                <ul className="mt-3 space-y-1 text-sm">
                  {(["A","B","C","D"] as const).map(L => {
                    const isCorrect = q.correct_answer === L;
                    const isUser = it.user_answer === L;
                    return (
                      <li key={L} className={`p-2 rounded ${
                        isCorrect ? "bg-success/15 border border-success/30" :
                        isUser ? "bg-destructive/15 border border-destructive/30" :
                        "bg-muted/40"
                      }`}>
                        <span className="font-bold mr-1">{L}.</span>{q[`option_${L.toLowerCase()}` as "option_a"]}
                        {isCorrect && <span className="ml-2 text-xs text-success">✓ Correct</span>}
                        {isUser && !isCorrect && <span className="ml-2 text-xs text-destructive">Your answer</span>}
                      </li>
                    );
                  })}
                </ul>

                {q.rationale && (
                  <div className="mt-3 p-3 rounded bg-accent/40 text-sm">
                    <p className="font-semibold text-xs uppercase text-muted-foreground mb-1">Explanation</p>
                    {q.rationale}
                  </div>
                )}

                <div className="mt-3 flex gap-2 flex-wrap">
                  <Button size="sm" variant="outline" onClick={() => openAskAi(q)}>
                    <Sparkles className="h-4 w-4 mr-1" /> Ask AI
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => copyQuestion(q)}>
                    {copiedId === q.id
                      ? <><Check className="h-4 w-4 mr-1" /> Copied!</>
                      : <><Copy className="h-4 w-4 mr-1" /> Copy</>}
                  </Button>
                </div>
              </Card>
            );
          })}
          {items.length === 0 && (
            <Card className="p-6 text-center text-muted-foreground text-sm">No questions to review.</Card>
          )}
        </div>
      </main>
    </>
  );
}

function Metric({ label, value, tone }: { label: string; value: number; tone?: "success" | "destructive" | "muted" }) {
  const cls =
    tone === "success" ? "text-success" :
    tone === "destructive" ? "text-destructive" :
    tone === "muted" ? "text-muted-foreground" :
    "text-foreground";
  return (
    <div className="rounded-lg border p-3 text-center bg-background/50">
      <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={`text-2xl font-bold mt-1 ${cls}`}>{value}</p>
    </div>
  );
}
