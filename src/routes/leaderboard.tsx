import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Trophy } from "lucide-react";

export const Route = createFileRoute("/leaderboard")({ component: Leaderboard });

interface Row { user_id: string; avg_score: number; tests: number; username: string | null; }

function Leaderboard() {
  const { user, profile, loading } = useAuth();
  const navigate = useNavigate();
  const [rows, setRows] = useState<Row[]>([]);

  useEffect(() => { if (!loading && !user) navigate({ to: "/auth" }); }, [loading, user, navigate]);

  useEffect(() => {
    (async () => {
      const sevenDays = new Date(Date.now() - 7 * 86400000).toISOString();
      const { data: exams } = await supabase.from("exams")
        .select("user_id, score_pct")
        .eq("status", "completed")
        .gte("completed_at", sevenDays)
        .not("score_pct", "is", null);
      const agg: Record<string, { sum: number; n: number }> = {};
      (exams ?? []).forEach((e) => {
        const k = e.user_id;
        agg[k] = agg[k] || { sum: 0, n: 0 };
        agg[k].sum += Number(e.score_pct ?? 0);
        agg[k].n++;
      });
      const ids = Object.keys(agg);
      let usernames: Record<string, string> = {};
      if (ids.length > 0) {
        const { data: profs } = await supabase.from("profiles").select("id, username").in("id", ids);
        usernames = Object.fromEntries((profs ?? []).map(p => [p.id, p.username ?? "Anonymous"]));
      }
      const list: Row[] = ids
        .map(id => ({ user_id: id, avg_score: agg[id].sum / agg[id].n, tests: agg[id].n, username: usernames[id] ?? null }))
        .sort((a, b) => b.avg_score - a.avg_score)
        .slice(0, 10);
      setRows(list);
    })();
  }, []);

  if (!profile) return <><AppHeader /><div className="p-12 text-center">Loading…</div></>;

  if (profile.tier === "novice") {
    return (
      <>
        <AppHeader />
        <main className="container mx-auto px-4 py-12 max-w-md text-center">
          <Trophy className="mx-auto h-12 w-12 text-warning" />
          <h1 className="text-2xl font-bold mt-4">Leaderboard locked</h1>
          <p className="text-muted-foreground mt-2">Upgrade to Erudite or Scholar to see the weekly Top 10.</p>
        </main>
      </>
    );
  }

  return (
    <>
      <AppHeader />
      <main className="container mx-auto px-4 py-8 max-w-2xl">
        <h1 className="text-3xl font-bold flex items-center gap-2"><Trophy className="text-warning" /> Weekly Top 10</h1>
        <p className="text-muted-foreground text-sm">Past 7 days, by average score</p>
        <Card className="p-2 mt-6 divide-y">
          {rows.length === 0 && <p className="p-6 text-center text-muted-foreground text-sm">No data yet.</p>}
          {rows.map((r, i) => (
            <div key={r.user_id} className={`flex items-center justify-between p-3 ${r.user_id === user?.id ? "bg-primary/10 rounded" : ""}`}>
              <div className="flex items-center gap-3">
                <span className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-sm ${
                  i === 0 ? "bg-warning text-warning-foreground" :
                  i === 1 ? "bg-muted-foreground text-background" :
                  i === 2 ? "bg-accent-foreground/70 text-background" :
                  "bg-muted text-foreground"
                }`}>{i + 1}</span>
                <span className="font-medium">{r.username ?? "Anonymous"}</span>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant="secondary">{r.tests} tests</Badge>
                <Badge className="bg-hero text-primary-foreground">{r.avg_score.toFixed(1)}%</Badge>
              </div>
            </div>
          ))}
        </Card>
      </main>
    </>
  );
}
