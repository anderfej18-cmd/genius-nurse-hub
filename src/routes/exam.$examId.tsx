import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useMemo, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Flag, ChevronLeft, ChevronRight, Send, Timer } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/exam/$examId")({ component: ExamRuntime });

interface Question {
  id: string;
  question_text: string;
  option_a: string; option_b: string; option_c: string; option_d: string;
  correct_answer: string; rationale: string | null; topic: string;
}
interface AnswerRow {
  id: string; question_id: string; user_answer: string | null; flagged: boolean; position: number;
}
interface ExamRow {
  id: string; total_questions: number; time_limit_minutes: number; started_at: string; status: string;
}

function ExamRuntime() {
  const { examId } = Route.useParams();
  const { user } = useAuth();
  const navigate = useNavigate();

  const [exam, setExam] = useState<ExamRow | null>(null);
  const [items, setItems] = useState<{ a: AnswerRow; q: Question }[]>([]);
  const [idx, setIdx] = useState(0);
  const [now, setNow] = useState(Date.now());
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data: e } = await supabase.from("exams").select("*").eq("id", examId).single();
      if (!e) { toast.error("Exam not found"); navigate({ to: "/dashboard" }); return; }
      if (e.status === "completed") { navigate({ to: "/exam/$examId/results", params: { examId } }); return; }
      setExam(e as ExamRow);

      const { data: ans } = await supabase.from("exam_answers")
        .select("id, question_id, user_answer, flagged, position")
        .eq("exam_id", examId).order("position");
      const ids = (ans ?? []).map(a => a.question_id);
      const { data: qs } = await supabase.from("questions").select("*").in("id", ids);
      const map = new Map((qs ?? []).map(q => [q.id, q as Question]));
      setItems((ans ?? []).map(a => ({ a: a as AnswerRow, q: map.get(a.question_id)! })));
    })();
  }, [examId, user, navigate]);

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  const elapsedSec = exam ? Math.floor((now - new Date(exam.started_at).getTime()) / 1000) : 0;
  const totalSec = exam ? exam.time_limit_minutes * 60 : 0;
  const remaining = Math.max(0, totalSec - elapsedSec);
  const mm = String(Math.floor(remaining / 60)).padStart(2, "0");
  const ss = String(remaining % 60).padStart(2, "0");

  const answeredCount = useMemo(() => items.filter(i => i.a.user_answer).length, [items]);
  const pctAnswered = items.length ? answeredCount / items.length : 0;
  const pctTime = totalSec ? elapsedSec / totalSec : 0;
  const canSubmit = pctAnswered >= 0.8 || pctTime >= 0.8;

  const current = items[idx];

  const setAnswer = async (letter: string) => {
    if (!current) return;
    setItems(prev => prev.map((it, i) => i === idx ? { ...it, a: { ...it.a, user_answer: letter } } : it));
    await supabase.from("exam_answers").update({ user_answer: letter }).eq("id", current.a.id);
  };
  const toggleFlag = async () => {
    if (!current) return;
    const f = !current.a.flagged;
    setItems(prev => prev.map((it, i) => i === idx ? { ...it, a: { ...it.a, flagged: f } } : it));
    await supabase.from("exam_answers").update({ flagged: f }).eq("id", current.a.id);
  };

  const submit = useCallback(async () => {
    if (!exam) return;
    setSubmitting(true);
    // Compute correctness
    const updates = items.map(it => ({
      id: it.a.id,
      is_correct: it.a.user_answer ? it.a.user_answer === it.q.correct_answer : false,
    }));
    // Update each (small batch)
    await Promise.all(updates.map(u =>
      supabase.from("exam_answers").update({ is_correct: u.is_correct }).eq("id", u.id)
    ));
    const correct = updates.filter(u => u.is_correct).length;
    const score = (correct / items.length) * 100;
    await supabase.from("exams").update({
      status: "completed", completed_at: new Date().toISOString(),
      correct_count: correct, score_pct: score,
    }).eq("id", exam.id);
    navigate({ to: "/exam/$examId/results", params: { examId: exam.id } });
  }, [exam, items, navigate]);

  // Auto-submit on time end
  useEffect(() => {
    if (exam && remaining === 0 && !submitting) submit();
  }, [exam, remaining, submitting, submit]);

  if (!exam || items.length === 0) return <div className="p-12 text-center">Loading exam…</div>;

  return (
    <div className="min-h-screen flex flex-col">
      {/* Top bar */}
      <header className="sticky top-0 z-30 border-b bg-background/90 backdrop-blur">
        <div className="container mx-auto px-4 py-3 flex items-center justify-between gap-3">
          <div>
            <p className="text-xs text-muted-foreground">Question {idx + 1} of {items.length}</p>
            <p className="text-sm font-medium">{answeredCount} answered</p>
          </div>
          <div className="flex items-center gap-2 text-lg font-mono font-bold">
            <Timer className="h-4 w-4 text-primary" />
            <span className={remaining < 300 ? "text-destructive" : ""}>{mm}:{ss}</span>
          </div>
          <Button
            disabled={!canSubmit || submitting}
            onClick={submit}
            className="bg-hero"
            size="sm"
          >
            <Send className="h-4 w-4 mr-1" /> Submit
          </Button>
        </div>
        {!canSubmit && (
          <p className="text-xs text-center text-muted-foreground pb-2">
            Submit unlocks at 80% answered ({Math.ceil(items.length * 0.8)} questions) or 80% time elapsed.
          </p>
        )}
      </header>

      <main className="flex-1 container mx-auto px-4 py-6 grid lg:grid-cols-[1fr_320px] gap-6">
        {/* Question */}
        <Card className="p-6 bg-card-soft">
          <div className="flex justify-between items-start mb-4 gap-3">
            <Badge variant="outline">{current.q.topic}</Badge>
            <Button variant={current.a.flagged ? "destructive" : "outline"} size="sm" onClick={toggleFlag}>
              <Flag className="h-4 w-4 mr-1" /> {current.a.flagged ? "Flagged" : "Flag"}
            </Button>
          </div>
          <p className="text-base md:text-lg font-medium leading-relaxed">{current.q.question_text}</p>

          <div className="mt-6 space-y-2">
            {(["A","B","C","D"] as const).map(letter => {
              const text = current.q[`option_${letter.toLowerCase()}` as "option_a"];
              const selected = current.a.user_answer === letter;
              return (
                <button key={letter} onClick={() => setAnswer(letter)}
                  className={`w-full text-left p-4 rounded-lg border transition-all ${
                    selected
                      ? "border-primary bg-primary/10 shadow-soft"
                      : "border-border hover:border-primary/40 hover:bg-accent/40"
                  }`}>
                  <span className="font-bold mr-2">{letter}.</span>{text}
                </button>
              );
            })}
          </div>

          <div className="mt-6 flex justify-between">
            <Button variant="outline" disabled={idx === 0} onClick={() => setIdx(i => i - 1)}>
              <ChevronLeft className="h-4 w-4 mr-1" /> Previous
            </Button>
            <Button disabled={idx === items.length - 1} onClick={() => setIdx(i => i + 1)}>
              Next <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          </div>
        </Card>

        {/* Grid sidebar */}
        <Card className="p-4 lg:sticky lg:top-24 lg:self-start">
          <h3 className="font-semibold mb-3 text-sm">Question Navigator</h3>
          <div className="grid grid-cols-8 lg:grid-cols-6 gap-1.5">
            {items.map((it, i) => {
              const cls =
                i === idx ? "ring-2 ring-primary " :
                "";
              const color =
                it.a.flagged ? "bg-destructive text-destructive-foreground" :
                it.a.user_answer ? "bg-success text-success-foreground" :
                "bg-muted text-muted-foreground hover:bg-accent";
              return (
                <button key={it.a.id} onClick={() => setIdx(i)}
                  className={`h-9 rounded text-xs font-medium ${color} ${cls}`}>
                  {i + 1}
                </button>
              );
            })}
          </div>
          <div className="mt-4 space-y-1 text-xs">
            <p><span className="inline-block w-3 h-3 rounded bg-success mr-2 align-middle" />Answered</p>
            <p><span className="inline-block w-3 h-3 rounded bg-destructive mr-2 align-middle" />Flagged</p>
            <p><span className="inline-block w-3 h-3 rounded bg-muted mr-2 align-middle" />Unanswered</p>
          </div>
        </Card>
      </main>
    </div>
  );
}
