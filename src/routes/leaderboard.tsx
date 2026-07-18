import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Trophy } from "lucide-react";

export const Route = createFileRoute("/leaderboard")({ component: Leaderboard });

interface Row {
  user_id: string;
  username: string | null;
  avg_score: number;
  attempted: number;
  correct: number;
}

function Leaderboard() {
  const { user, profile, loading } = useAuth();
  const navigate = useNavigate();
  const [rows, setRows] = useState<Row[]>([]);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => { if (!loading && !user) navigate({ to: "/auth" }); }, [loading, user, navigate]);

  useEffect(() => {
    (async () => {
      const { data, error } = await supabase.rpc("get_daily_leaderboard");
      if (!error && data) {
        setRows((data as Array<{ user_id: string; username: string | null; avg_score: number | string; attempted: number; correct: number }>).map(r => ({
          user_id: r.user_id,
          username: r.username,
          avg_score: Number(r.avg_score) || 0,
          attempted: Number(r.attempted) || 0,
          correct: Number(r.correct) || 0,
        })));
      }
      setLoaded(true);
    })();
  }, []);

  if (!profile) return <><AppHeader /><div className="p-12 text-center">Loading…</div></>;

  return (
    <>
      <AppHeader />
      <main className="container mx-auto px-4 py-8 max-w-3xl">
        <h1 className="text-3xl font-bold flex items-center gap-2">
          <Trophy className="text-warning" /> Daily Leaderboard
        </h1>
        <p className="text-muted-foreground text-sm mt-1">
          Today's top performers — minimum 100 questions attempted to qualify. Resets at 00:00 UTC.
        </p>

        <Card className="p-2 mt-6">
          {!loaded && <p className="p-6 text-center text-muted-foreground text-sm">Loading…</p>}
          {loaded && rows.length === 0 && (
            <p className="p-6 text-center text-muted-foreground text-sm">
              No qualifiers yet today. Attempt 100+ questions to appear on the board.
            </p>
          )}
          {rows.length > 0 && (
            <div className="divide-y">
              <div className="grid grid-cols-12 gap-2 px-3 py-2 text-xs uppercase text-muted-foreground font-medium">
                <div className="col-span-1">#</div>
                <div className="col-span-5">Name</div>
                <div className="col-span-2 text-right">Avg %</div>
                <div className="col-span-2 text-right">Attempted</div>
                <div className="col-span-2 text-right">Correct</div>
              </div>
              {rows.map((r, i) => (
                <div key={r.user_id} className={`grid grid-cols-12 gap-2 items-center px-3 py-3 text-sm ${r.user_id === user?.id ? "bg-primary/10 rounded" : ""}`}>
                  <div className="col-span-1">
                    <span className={`w-7 h-7 rounded-full flex items-center justify-center font-bold text-xs ${
                      i === 0 ? "bg-warning text-warning-foreground" :
                      i === 1 ? "bg-muted-foreground text-background" :
                      i === 2 ? "bg-accent-foreground/70 text-background" :
                      "bg-muted text-foreground"
                    }`}>{i + 1}</span>
                  </div>
                  <div className="col-span-5 font-medium truncate">{r.username ?? "Anonymous"}</div>
                  <div className="col-span-2 text-right">
                    <Badge className="bg-hero text-primary-foreground">{r.avg_score.toFixed(1)}%</Badge>
                  </div>
                  <div className="col-span-2 text-right">{r.attempted}</div>
                  <div className="col-span-2 text-right">{r.correct}</div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </main>
    </>
  );
}
