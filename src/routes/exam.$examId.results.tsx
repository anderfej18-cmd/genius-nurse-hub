import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Sparkles, Trophy, Star, AlertCircle } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/exam/$examId/results")({ component: Results });

interface Item {
  user_answer: string | null; is_correct: boolean | null; flagged: boolean; position: number;
  questions: {
    id: string; question_text: string; correct_answer: string; rationale: string | null; topic: string;
    option_a: string; option_b: string; option_c: string; option_d: string;
  };
}

function Results() {
  const { examId } = Route.useParams();
  const [exam, setExam] = useState<{ score_pct: number | null; correct_count: number | null; total_questions: number; exam_type: string } | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [aiLoading, setAiLoading] = useState<string | null>(null);
  const [aiAnswers, setAiAnswers] = useState<Record<string, string>>({});

  useEffect(() => {
    (async () => {
      const { data: e } = await supabase.from("exams").select("score_pct, correct_count, total_questions, exam_type").eq("id", examId).single();
      setExam(e as any);
      const { data } = await supabase.from("exam_answers")
        .select("user_answer, is_correct, flagged, position, questions(id, question_text, correct_answer, rationale, topic, option_a, option_b, option_c, option_d)")
        .eq("exam_id", examId).order("position");
      setItems((data as unknown as Item[]) ?? []);
    })();
  }, [examId]);

  const askAI = async (q: Item["questions"]) => {
    setAiLoading(q.id);
    try {
      const { data, error } = await supabase.functions.invoke("ask-ai", {
        body: {
          question: q.question_text,
          options: { A: q.option_a, B: q.option_b, C: q.option_c, D: q.option_d },
          correct: q.correct_answer,
          topic: q.topic,
        },
      });
      if (error) throw error;
      setAiAnswers(p => ({ ...p, [q.id]: (data as { explanation: string }).explanation }));
    } catch (err) {
      toast.error((err as Error).message || "AI request failed");
    } finally {
      setAiLoading(null);
    }
  };

  if (!exam) return <><AppHeader /><div className="p-12 text-center">Loading…</div></>;

  const score = exam.score_pct ?? 0;
  const tag =
    score >= 80 ? { icon: <Trophy />, label: "Trophy 🏆", cls: "bg-warning text-warning-foreground" } :
    score >= 70 ? { icon: <Star />, label: "Solid", cls: "bg-success text-success-foreground" } :
    score >= 50 ? { label: "Progress", cls: "bg-warning/60 text-warning-foreground" } :
                  { icon: <AlertCircle />, label: "Promising — wake up strike!", cls: "bg-destructive text-destructive-foreground" };

  return (
    <>
      <AppHeader />
      <main className="container mx-auto px-4 py-8 max-w-3xl space-y-6">
        <Card className="p-8 bg-card-soft text-center shadow-glow">
          <p className="text-sm text-muted-foreground">Your Score</p>
          <p className="text-6xl font-bold bg-hero bg-clip-text text-transparent mt-2">{score.toFixed(1)}%</p>
          <p className="text-sm mt-2">{exam.correct_count} / {exam.total_questions} correct</p>
          <Badge className={`mt-3 ${tag.cls}`}>{tag.label}</Badge>
          <div className="mt-4 flex justify-center gap-2">
            <Button asChild variant="outline"><Link to="/dashboard">Dashboard</Link></Button>
            <Button asChild className="bg-hero"><Link to="/exam/start">Take Another</Link></Button>
          </div>
        </Card>

        <div className="space-y-4">
          {items.map((it, i) => {
            const q = it.questions;
            const correct = it.is_correct;
            return (
              <Card key={q.id} className="p-5">
                <div className="flex justify-between items-start gap-3 mb-2">
                  <p className="text-xs text-muted-foreground">Question {i + 1} • {q.topic}</p>
                  <Badge className={correct ? "bg-success text-success-foreground" : "bg-destructive text-destructive-foreground"}>
                    {correct ? "Correct" : it.user_answer ? "Wrong" : "Skipped"}
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
                    <p className="font-semibold text-xs uppercase text-muted-foreground mb-1">Rationale</p>
                    {q.rationale}
                  </div>
                )}
                <div className="mt-3">
                  <Button size="sm" variant="outline" onClick={() => askAI(q)} disabled={aiLoading === q.id || !!aiAnswers[q.id]}>
                    <Sparkles className="h-4 w-4 mr-1" />
                    {aiLoading === q.id ? "Thinking…" : aiAnswers[q.id] ? "AI explained" : "Ask AI"}
                  </Button>
                  {aiAnswers[q.id] && (
                    <div className="mt-3 p-3 rounded bg-primary/5 border border-primary/20 text-sm whitespace-pre-wrap">
                      {aiAnswers[q.id]}
                    </div>
                  )}
                </div>
              </Card>
            );
          })}
        </div>
      </main>
    </>
  );
}
