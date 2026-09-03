import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { LeaderboardTable } from "@/components/LeaderboardTable";
import { fetchTopicCounts } from "@/lib/topics";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { questionIssues, type QuestionFields } from "@/lib/questions";
import { AlertTriangle, Pencil, Search, ShieldCheck, ShieldOff, Trash2 } from "lucide-react";

export const Route = createFileRoute("/admin")({ component: Admin });

function Admin() {
  const { user, isAdmin, isCentralAdmin, loading } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (!loading && (!user || !isAdmin)) navigate({ to: "/dashboard" });
  }, [loading, user, isAdmin, navigate]);

  if (!isAdmin) return <><AppHeader /><div className="p-12 text-center">Loading…</div></>;

  return (
    <>
      <AppHeader />
      <main className="container mx-auto px-4 py-8 max-w-5xl">
        <h1 className="text-3xl font-bold mb-6">{isCentralAdmin ? "Central Admin Panel" : "Admin Section"}</h1>
        <Tabs defaultValue="questions">
          <TabsList className="flex-wrap h-auto">
            <TabsTrigger value="questions">Questions</TabsTrigger>
            <TabsTrigger value="audit">Audit / Broken Questions</TabsTrigger>
            <TabsTrigger value="payments">Upgrades</TabsTrigger>
            <TabsTrigger value="leaderboards">Leaderboards</TabsTrigger>
            {isCentralAdmin && <TabsTrigger value="pricing">Pricing &amp; Duration</TabsTrigger>}
            {isCentralAdmin && <TabsTrigger value="users">Users</TabsTrigger>}
            {isCentralAdmin && <TabsTrigger value="admin-access">Assign Admin</TabsTrigger>}
            {isCentralAdmin && <TabsTrigger value="codes">Admin Codes</TabsTrigger>}
            {!isCentralAdmin && <TabsTrigger value="sub-users">Users</TabsTrigger>}
            {!isCentralAdmin && <TabsTrigger value="join">Become Admin</TabsTrigger>}
          </TabsList>
          <TabsContent value="questions"><QuestionsTab /></TabsContent>
          <TabsContent value="audit"><BrokenQuestionsTab /></TabsContent>
          <TabsContent value="payments"><PaymentsTab /></TabsContent>
          <TabsContent value="leaderboards"><LeaderboardsTab /></TabsContent>
          {isCentralAdmin && <TabsContent value="pricing"><PricingTab /></TabsContent>}
          {isCentralAdmin && <TabsContent value="users"><UsersTab /></TabsContent>}
           {isCentralAdmin && <TabsContent value="admin-access"><AdminAccessTab /></TabsContent>}
          {isCentralAdmin && <TabsContent value="codes"><CodesTab /></TabsContent>}
           {!isCentralAdmin && <TabsContent value="sub-users"><SubAdminUsersTab /></TabsContent>}
          {!isCentralAdmin && <TabsContent value="join"><JoinTab /></TabsContent>}
        </Tabs>

      </main>
    </>
  );
}

interface ParsedQ {
  question_text: string;
  option_a: string; option_b: string; option_c: string; option_d: string;
  correct_answer: string;
  rationale: string | null;
}

function parseTxt(raw: string): ParsedQ[] {
  // Split questions by blank line or "---" separator
  const blocks = raw.replace(/\r\n/g, "\n").split(/\n\s*(?:---+|===+)\s*\n|\n\s*\n/).map(b => b.trim()).filter(Boolean);
  const out: ParsedQ[] = [];
  for (const block of blocks) {
    const lines = block.split("\n").map(l => l.trim()).filter(Boolean);
    let question = ""; let a = ""; let b = ""; let c = ""; let d = "";
    let answer = ""; let explanation = "";
    let mode: "explanation" | null = null;
    for (const line of lines) {
      const mQ = line.match(/^(?:Q\s*[:.)]|Question\s*[:.)])\s*(.*)$/i);
      const mA = line.match(/^A[).:\-]\s*(.*)$/i);
      const mB = line.match(/^B[).:\-]\s*(.*)$/i);
      const mC = line.match(/^C[).:\-]\s*(.*)$/i);
      const mD = line.match(/^D[).:\-]\s*(.*)$/i);
      const mAns = line.match(/^(?:Answer|Ans|Correct)\s*[:\-]\s*([A-D])/i);
      const mExp = line.match(/^(?:Explanation|Rationale)\s*[:\-]\s*(.*)$/i);
      if (mQ) { question = mQ[1]; mode = null; }
      else if (mA) { a = mA[1]; mode = null; }
      else if (mB) { b = mB[1]; mode = null; }
      else if (mC) { c = mC[1]; mode = null; }
      else if (mD) { d = mD[1]; mode = null; }
      else if (mAns) { answer = mAns[1].toUpperCase(); mode = null; }
      else if (mExp) { explanation = mExp[1]; mode = "explanation"; }
      else if (mode === "explanation") { explanation += " " + line; }
      else if (!question) { question = line; }
    }
    if (question && a && b && c && d && ["A","B","C","D"].includes(answer)) {
      out.push({
        question_text: question, option_a: a, option_b: b, option_c: c, option_d: d,
        correct_answer: answer, rationale: explanation.trim() || null,
      });
    }
  }
  return out;
}

interface LastUpload {
  fileName: string;
  examType: string;
  topic: string;
  imported: number;
  at: string;
}

const LAST_UPLOAD_KEY = "ng.lastQuestionUpload";

function QuestionsTab() {
  const [examType, setExamType] = useState<"RN" | "RM">("RN");
  const [existingSubs, setExistingSubs] = useState<string[]>([]);
  const [subMode, setSubMode] = useState<"existing" | "new">("existing");
  const [subExisting, setSubExisting] = useState<string>("");
  const [subNew, setSubNew] = useState<string>("");
  const [text, setText] = useState("");
  const [a, setA] = useState(""); const [b, setB] = useState("");
  const [c, setC] = useState(""); const [d, setD] = useState("");
  const [ans, setAns] = useState<"A" | "B" | "C" | "D">("A");
  const [rationale, setRationale] = useState("");
  const [count, setCount] = useState<number | null>(null);
  const [rnCounts, setRnCounts] = useState<Record<string, number>>({});
  const [rmCounts, setRmCounts] = useState<Record<string, number>>({});
  const [lastUpload, setLastUpload] = useState<LastUpload | null>(null);

  const activeSub = (subMode === "new" ? subNew : subExisting).trim();

  const loadSubs = async (et: "RN" | "RM") => {
    const counts = await fetchTopicCounts(et);
    if (et === "RN") setRnCounts(counts); else setRmCounts(counts);
    const uniq = Object.keys(counts).sort();
    setExistingSubs(uniq);
    if (uniq.length && !subExisting) setSubExisting(uniq[0]);
  };

  const loadAllCounts = async () => {
    const [rn, rm] = await Promise.all([fetchTopicCounts("RN"), fetchTopicCounts("RM")]);
    setRnCounts(rn); setRmCounts(rm);
  };

  useEffect(() => {
    supabase.from("questions").select("id", { count: "exact", head: true }).then(r => setCount(r.count ?? 0));
    loadAllCounts();
    try {
      const raw = localStorage.getItem(LAST_UPLOAD_KEY);
      if (raw) setLastUpload(JSON.parse(raw) as LastUpload);
    } catch { /* ignore corrupt cache */ }
  }, []);
  useEffect(() => { loadSubs(examType); /* eslint-disable-next-line */ }, [examType]);

  const addOne = async () => {
    if (!text || !a || !b || !c || !d) return toast.error("All fields required");
    if (!activeSub) return toast.error("Pick or enter a subcategory first");
    const { error } = await supabase.from("questions").insert({
      exam_type: examType, topic: activeSub, question_text: text,
      option_a: a, option_b: b, option_c: c, option_d: d,
      correct_answer: ans, rationale,
    });
    if (error) return toast.error(error.message);
    toast.success("Question added");
    setText(""); setA(""); setB(""); setC(""); setD(""); setRationale("");
    loadSubs(examType);
    setCount(c => (c ?? 0) + 1);
  };

  const uploadTXT = async (file: File) => {
    if (!activeSub) return toast.error("Pick or enter a subcategory first");
    const raw = await file.text();
    const parsed = parseTxt(raw);
    if (parsed.length === 0) return toast.error("No valid questions found in file. Check the format.");
    const target = activeSub;
    const rows = parsed.map(p => ({ exam_type: examType, topic: target, ...p }));
    const { error } = await supabase.from("questions").insert(rows);
    if (error) return toast.error(error.message);
    toast.success(`Imported ${rows.length} questions into ${examType} · ${target}`);
    setCount(c => (c ?? 0) + rows.length);

    const record: LastUpload = {
      fileName: file.name,
      examType,
      topic: target,
      imported: rows.length,
      at: new Date().toISOString(),
    };
    setLastUpload(record);
    try { localStorage.setItem(LAST_UPLOAD_KEY, JSON.stringify(record)); } catch { /* ignore */ }

    if (subMode === "new") { setSubExisting(target); setSubNew(""); setSubMode("existing"); }
    await loadSubs(examType);
  };

  const renderBreakdown = (label: string, counts: Record<string, number>) => {
    const entries = Object.entries(counts).sort((x, y) => y[1] - x[1]);
    const total = entries.reduce((s, [, n]) => s + n, 0);
    return (
      <div className="space-y-1">
        <div className="flex items-center justify-between text-sm font-semibold">
          <span>{label}</span>
          <span>{total.toLocaleString()}</span>
        </div>
        {entries.length === 0 ? (
          <p className="text-xs text-muted-foreground">No questions yet.</p>
        ) : (
          <div className="divide-y">
            {entries.map(([topic, n]) => (
              <div key={topic} className="flex items-center justify-between py-1.5 text-sm">
                <span className="text-muted-foreground truncate pr-2">{topic}</span>
                <span className="font-mono">{n.toLocaleString()}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="space-y-4 mt-4">
      <Card className="p-5 space-y-4">
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted-foreground">Total questions in bank: <strong className="text-foreground">{count ?? "…"}</strong></p>
          <Button variant="outline" size="sm" onClick={loadAllCounts}>Refresh counts</Button>
        </div>
        <div className="grid md:grid-cols-2 gap-5">
          {renderBreakdown("RN — Registered Nurse", rnCounts)}
          {renderBreakdown("RM — Registered Midwife", rmCounts)}
        </div>
      </Card>

      <Card className="p-5">
        <h3 className="font-semibold mb-2 text-sm">Last TXT Upload</h3>
        {lastUpload ? (
          <div className="text-sm space-y-1">
            <p className="font-medium break-all">{lastUpload.fileName}</p>
            <p className="text-muted-foreground">
              {lastUpload.imported} questions → <strong className="text-foreground">{lastUpload.examType}</strong> · <strong className="text-foreground">{lastUpload.topic}</strong>
            </p>
            <p className="text-xs text-muted-foreground">{new Date(lastUpload.at).toLocaleString()}</p>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">No upload recorded on this device yet.</p>
        )}
      </Card>


      <Card className="p-5 space-y-4">
        <h3 className="font-semibold">Bulk TXT Upload</h3>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Major Category</Label>
            <Select value={examType} onValueChange={(v) => setExamType(v as "RN" | "RM")}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="RN">RN — Registered Nurse</SelectItem>
                <SelectItem value="RM">RM — Registered Midwife</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>Subcategory Mode</Label>
            <Select value={subMode} onValueChange={(v) => setSubMode(v as "existing" | "new")}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="existing">Choose existing</SelectItem>
                <SelectItem value="new">Create new</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        {subMode === "existing" ? (
          <div>
            <Label>Existing Subcategory</Label>
            {existingSubs.length === 0 ? (
              <p className="text-xs text-muted-foreground mt-1">No subcategories yet for {examType}. Switch to “Create new”.</p>
            ) : (
              <Select value={subExisting} onValueChange={setSubExisting}>
                <SelectTrigger><SelectValue placeholder="Pick one" /></SelectTrigger>
                <SelectContent>
                  {existingSubs.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}
                </SelectContent>
              </Select>
            )}
          </div>
        ) : (
          <div>
            <Label>New Subcategory Name</Label>
            <Input value={subNew} onChange={(e) => setSubNew(e.target.value)} placeholder="e.g. Maternal and Child Health" />
          </div>
        )}

        <div className="text-xs text-muted-foreground space-y-1 p-3 rounded bg-muted/40">
          <p className="font-semibold">TXT format (one block per question, separated by blank line or ---):</p>
          <pre className="whitespace-pre-wrap font-mono text-[11px]">{`Q: What is the normal adult resting heart rate?
A) 40-60 bpm
B) 60-100 bpm
C) 100-140 bpm
D) 140-180 bpm
Answer: B
Explanation: The normal adult resting heart rate ranges from 60 to 100 bpm.`}</pre>
        </div>

        <Input type="file" accept=".txt,text/plain" onChange={(e) => e.target.files?.[0] && uploadTXT(e.target.files[0])} />
      </Card>

      <Card className="p-5 space-y-3">
        <h3 className="font-semibold">Add One Question</h3>
        <p className="text-xs text-muted-foreground">
          Uploading into: <strong>{examType}</strong> · <strong>{activeSub}</strong>
        </p>
        <div><Label>Question</Label><Textarea value={text} onChange={(e) => setText(e.target.value)} rows={3} /></div>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>A</Label><Input value={a} onChange={(e) => setA(e.target.value)} /></div>
          <div><Label>B</Label><Input value={b} onChange={(e) => setB(e.target.value)} /></div>
          <div><Label>C</Label><Input value={c} onChange={(e) => setC(e.target.value)} /></div>
          <div><Label>D</Label><Input value={d} onChange={(e) => setD(e.target.value)} /></div>
        </div>
        <div><Label>Correct Answer</Label>
          <Select value={ans} onValueChange={(v) => setAns(v as "A" | "B" | "C" | "D")}><SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>{["A","B","C","D"].map(x => <SelectItem key={x} value={x}>{x}</SelectItem>)}</SelectContent>
          </Select>
        </div>
        <div><Label>Explanation</Label><Textarea value={rationale} onChange={(e) => setRationale(e.target.value)} rows={2} /></div>
        <Button onClick={addOne} className="bg-hero">Add Question</Button>
      </Card>
    </div>
  );
}

interface BrokenQuestion extends QuestionFields {
  id: string;
  exam_type: "RN" | "RM";
  topic: string;
}

function BrokenQuestionsTab() {
  const [rows, setRows] = useState<BrokenQuestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<BrokenQuestion | null>(null);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    const pageSize = 1000;
    const all: BrokenQuestion[] = [];
    let errorMessage: string | null = null;
    for (let from = 0; ; from += pageSize) {
      const { data, error } = await supabase.from("questions")
        .select("id, exam_type, topic, question_text, option_a, option_b, option_c, option_d, correct_answer")
        .order("id", { ascending: true })
        .range(from, from + pageSize - 1);
      if (error) { errorMessage = error.message; break; }
      all.push(...((data ?? []) as BrokenQuestion[]));
      if (!data || data.length < pageSize) break;
    }
    if (errorMessage) toast.error(errorMessage);
    setRows(all.filter(row => questionIssues(row).length > 0));
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const save = async () => {
    if (!editing) return;
    setSaving(true);
    const { id, exam_type: _examType, topic: _topic, ...fields } = editing;
    const changes = {
      question_text: fields.question_text ?? "",
      option_a: fields.option_a ?? "",
      option_b: fields.option_b ?? "",
      option_c: fields.option_c ?? "",
      option_d: fields.option_d ?? "",
      correct_answer: fields.correct_answer ?? "",
    };
    const { error } = await supabase.from("questions").update(changes).eq("id", id);
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success("Question repaired");
    setEditing(null);
    load();
  };

  const remove = async (row: BrokenQuestion) => {
    if (!confirm("Delete this broken question permanently?")) return;
    const { error } = await supabase.from("questions").delete().eq("id", row.id);
    if (error) return toast.error(error.message);
    toast.success("Question deleted");
    setRows(current => current.filter(item => item.id !== row.id));
  };

  const updateEditing = (key: keyof QuestionFields, value: string) => {
    setEditing(current => current ? { ...current, [key]: value } : current);
  };

  return (
    <div className="mt-4 space-y-4">
      <Card className="p-5 flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-warning" />
            <h2 className="font-semibold">Broken question inspector</h2>
          </div>
          <p className="mt-1 text-sm text-muted-foreground">Scans every RN and RM question for missing text, options, or a valid A–D answer.</p>
        </div>
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>Rescan</Button>
      </Card>

      <Card className="p-4">
        <p className="text-sm font-medium mb-3">{loading ? "Scanning question bank…" : `${rows.length} broken question${rows.length === 1 ? "" : "s"} found`}</p>
        {!loading && rows.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">All questions are complete.</p>}
        <div className="divide-y">
          {rows.map(row => (
            <div key={row.id} className="py-4 flex items-start justify-between gap-4 flex-wrap">
              <div className="min-w-0 text-sm">
                <p className="font-medium break-all">{row.id}</p>
                <p className="text-muted-foreground">{row.exam_type} · {row.topic || "No subcategory"}</p>
                <p className="mt-1 text-xs text-destructive">Missing: {questionIssues(row).join(", ")}</p>
              </div>
              <div className="flex gap-2 shrink-0">
                <Button size="sm" variant="outline" onClick={() => setEditing(row)}><Pencil /> Edit</Button>
                <Button size="sm" variant="destructive" onClick={() => remove(row)}><Trash2 /> Delete Row</Button>
              </div>
            </div>
          ))}
        </div>
      </Card>

      <Dialog open={!!editing} onOpenChange={open => !open && setEditing(null)}>
        <DialogContent className="max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Edit broken question</DialogTitle>
            <DialogDescription>Repair the fields below, then save to remove it from the audit.</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="space-y-3">
              <div><Label>Question</Label><Textarea rows={3} value={editing.question_text ?? ""} onChange={e => updateEditing("question_text", e.target.value)} /></div>
              {(["option_a", "option_b", "option_c", "option_d"] as const).map(key => (
                <div key={key}><Label>{key.replace("option_", "Option ").toUpperCase()}</Label><Input value={editing[key] ?? ""} onChange={e => updateEditing(key, e.target.value)} /></div>
              ))}
              <div><Label>Correct Answer</Label><Select value={editing.correct_answer ?? ""} onValueChange={value => updateEditing("correct_answer", value)}>
                <SelectTrigger><SelectValue placeholder="Choose A–D" /></SelectTrigger>
                <SelectContent>{["A", "B", "C", "D"].map(value => <SelectItem key={value} value={value}>{value}</SelectItem>)}</SelectContent>
              </Select></div>
              <Button className="w-full bg-hero" onClick={save} disabled={saving}>{saving ? "Saving…" : "Save repair"}</Button>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

interface UpgradeRow {
  id: string; user_id: string; plan_name: string; amount_ngn: number;
  duration_days: number; created_at: string; reference: string | null;
  profile?: { username: string | null; email: string | null; tier: string; expiry_date: string | null } | null;
}

function PaymentsTab() {
  const [rows, setRows] = useState<UpgradeRow[]>([]);

  const load = async () => {
    const { data } = await supabase.from("subscription_payments").select("*").order("created_at", { ascending: false });
    const list = (data as UpgradeRow[]) ?? [];
    const userIds = Array.from(new Set(list.map(r => r.user_id)));
    if (userIds.length) {
      const { data: profs } = await supabase.from("profiles")
        .select("id, username, email, tier, expiry_date")
        .in("id", userIds);
      const byId = new Map((profs ?? []).map(p => [p.id, p]));
      list.forEach(r => { r.profile = byId.get(r.user_id) as UpgradeRow["profile"]; });
    }
    setRows(list);
  };
  useEffect(() => { load(); }, []);

  const students = new Set(rows.map(r => r.user_id)).size;
  const byTier = rows.reduce<Record<string, number>>((acc, r) => {
    acc[r.plan_name] = (acc[r.plan_name] ?? 0) + 1; return acc;
  }, {});
  const revenue = rows.reduce((s, r) => s + Number(r.amount_ngn ?? 0), 0);

  return (
    <div className="mt-4 space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Card className="p-4"><p className="text-xs uppercase text-muted-foreground">Students upgraded</p><p className="text-2xl font-bold">{students}</p></Card>
        <Card className="p-4"><p className="text-xs uppercase text-muted-foreground">Erudite purchases</p><p className="text-2xl font-bold">{byTier["erudite"] ?? 0}</p></Card>
        <Card className="p-4"><p className="text-xs uppercase text-muted-foreground">Scholar purchases</p><p className="text-2xl font-bold">{byTier["scholar"] ?? 0}</p></Card>
        <Card className="p-4"><p className="text-xs uppercase text-muted-foreground">Total collected</p><p className="text-2xl font-bold">₦{revenue.toLocaleString()}</p></Card>
      </div>

      <div className="flex justify-end">
        <Button variant="outline" size="sm" onClick={load}>Refresh</Button>
      </div>

      <Card className="p-4 divide-y">
        {rows.length === 0 && <p className="p-6 text-center text-muted-foreground text-sm">No upgrades yet.</p>}
        {rows.map(r => (
          <div key={r.id} className="py-3 flex items-start justify-between gap-3 flex-wrap">
            <div className="text-sm">
              <p className="font-medium">
                {r.profile?.username ?? "—"}{" "}
                <span className="text-muted-foreground">({r.profile?.email ?? r.user_id.slice(0, 8)})</span>
              </p>
              <p className="text-xs text-muted-foreground">
                Current tier: <Badge variant="secondary">{r.profile?.tier ?? "?"}</Badge>
                {r.profile?.expiry_date && ` · expires ${new Date(r.profile.expiry_date).toLocaleDateString()}`}
              </p>
              <p className="text-xs text-muted-foreground">
                Paid {new Date(r.created_at).toLocaleString()}{r.reference ? ` · ref ${r.reference}` : ""}
              </p>
            </div>
            <div className="text-right">
              <Badge className="bg-success text-success-foreground capitalize">{r.plan_name}</Badge>
              <p className="text-sm font-semibold mt-1">₦{Number(r.amount_ngn).toLocaleString()}</p>
              <p className="text-xs text-muted-foreground">{r.duration_days} days</p>
            </div>
          </div>
        ))}
      </Card>
    </div>
  );
}

interface PlanRow { id: string; name: string; price_ngn: number; duration_days: number; is_active: boolean }

function PricingTab() {
  const [plans, setPlans] = useState<PlanRow[] | null>(null);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    const { data } = await supabase.from("plans")
      .select("id, name, price_ngn, duration_days, is_active")
      .in("name", ["erudite", "scholar"]).order("name");
    setPlans((data as PlanRow[]) ?? []);
  };
  useEffect(() => { load(); }, []);

  const patch = (id: string, p: Partial<PlanRow>) =>
    setPlans(list => (list ?? []).map(x => (x.id === id ? { ...x, ...p } : x)));

  const save = async () => {
    if (!plans) return;
    if (plans.some(p => p.price_ngn <= 0 || p.duration_days <= 0)) {
      return toast.error("Price and duration must both be greater than 0");
    }
    setSaving(true);
    for (const p of plans) {
      const { error } = await supabase.from("plans")
        .update({ price_ngn: p.price_ngn, duration_days: p.duration_days, is_active: p.is_active })
        .eq("id", p.id);
      if (error) { setSaving(false); return toast.error(error.message); }
    }
    setSaving(false);
    toast.success("Pricing & duration updated");
    load();
  };

  if (!plans) return <div className="p-6">Loading…</div>;

  return (
    <div className="mt-4 space-y-4 max-w-2xl">
      <p className="text-sm text-muted-foreground">
        These values drive the student checkout screen and how long access lasts after payment.
      </p>
      {plans.map(p => (
        <Card key={p.id} className="p-5 space-y-3">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold capitalize">{p.name}</h3>
            <Badge variant={p.is_active ? "secondary" : "outline"}>{p.is_active ? "active" : "hidden"}</Badge>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Price (₦)</Label>
              <Input type="number" min={1} value={p.price_ngn}
                onChange={(e) => patch(p.id, { price_ngn: Number(e.target.value) })} />
            </div>
            <div>
              <Label>Duration (days)</Label>
              <Input type="number" min={1} value={p.duration_days}
                onChange={(e) => patch(p.id, { duration_days: Number(e.target.value) })} />
            </div>
          </div>
          <div>
            <Label>Visibility</Label>
            <Select value={p.is_active ? "yes" : "no"} onValueChange={(v) => patch(p.id, { is_active: v === "yes" })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="yes">Show on checkout</SelectItem>
                <SelectItem value="no">Hide from checkout</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <p className="text-xs text-muted-foreground">
            Students will see: ₦{Number(p.price_ngn || 0).toLocaleString()} / {p.duration_days} days
          </p>
        </Card>
      ))}
      <Button onClick={save} disabled={saving} className="bg-hero w-full">
        {saving ? "Saving…" : "Save Changes"}
      </Button>
    </div>
  );
}


interface UserRow { id: string; email: string | null; username: string | null; tier: string; expiry_date: string | null; }

function UsersTab() {
  const [rows, setRows] = useState<UserRow[]>([]);
  const [exams, setExams] = useState<Record<string, { avg: number; n: number }>>({});
  const [filter, setFilter] = useState("");
  const [assignFor, setAssignFor] = useState<string | null>(null);
  const [assignTier, setAssignTier] = useState<"novice" | "erudite" | "scholar">("erudite");
  const [assignDays, setAssignDays] = useState<number>(30);

  const load = async () => {
    const pageSize = 1000;
    const allUsers: UserRow[] = [];
    for (let from = 0; ; from += pageSize) {
      const { data, error } = await supabase.from("profiles")
        .select("id, email, username, tier, expiry_date")
        .order("created_at", { ascending: true })
        .range(from, from + pageSize - 1);
      if (error) return toast.error(error.message);
      allUsers.push(...((data ?? []) as UserRow[]));
      if (!data || data.length < pageSize) break;
    }
    setRows(allUsers);
    const { data: ex } = await supabase.from("exams").select("user_id, score_pct").eq("status", "completed").not("score_pct", "is", null);
    const agg: Record<string, { sum: number; n: number }> = {};
    (ex ?? []).forEach((e) => {
      agg[e.user_id] = agg[e.user_id] || { sum: 0, n: 0 };
      agg[e.user_id].sum += Number(e.score_pct ?? 0); agg[e.user_id].n++;
    });
    setExams(Object.fromEntries(Object.entries(agg).map(([k, v]) => [k, { avg: v.sum / v.n, n: v.n }])));
  };
  useEffect(() => { load(); }, []);

  const reset = async (id: string) => {
    if (!confirm("Revoke this user's tier and revert to Novice?")) return;
    const { error } = await supabase.rpc("assign_user_tier", { _user_id: id, _tier: "novice", _days: 0 });
    if (error) return toast.error(error.message);
    toast.success("Reverted to Novice");
    load();
  };

  const assign = async () => {
    if (!assignFor) return;
    if (assignDays < 0) return toast.error("Days must be 0 or greater (0 = no expiry)");
    const { error } = await supabase.rpc("assign_user_tier", {
      _user_id: assignFor, _tier: assignTier, _days: assignDays,
    });
    if (error) return toast.error(error.message);
    toast.success(`Assigned ${assignTier}${assignDays > 0 ? ` for ${assignDays} days` : " (no expiry)"}`);
    setAssignFor(null);
    load();
  };

  const filtered = rows.filter(u => {
    const q = filter.trim().toLowerCase();
    if (!q) return true;
    return (u.email ?? "").toLowerCase().includes(q) || (u.username ?? "").toLowerCase().includes(q);
  });

  const tierGroups = [
    { tier: "novice", label: "Novice", description: "Default access" },
    { tier: "scholar", label: "Scholar", description: "Unlimited daily questions" },
    { tier: "erudite", label: "Erudite", description: "Expanded daily access" },
  ] as const;

  const renderUser = (u: UserRow) => (
    <div key={u.id} className="py-3 px-4 space-y-2">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="text-sm min-w-0">
          <p className="font-medium break-words">{u.username ?? "—"} <span className="text-muted-foreground">({u.email})</span></p>
          <p className="text-xs text-muted-foreground">
            <Badge variant="secondary" className="mr-1 capitalize">{u.tier}</Badge>
            {u.expiry_date && `expires ${new Date(u.expiry_date).toLocaleDateString()}`}
            {exams[u.id] && ` · avg ${exams[u.id].avg.toFixed(1)}% (${exams[u.id].n} tests)`}
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button size="sm" variant="outline" onClick={() => { setAssignFor(assignFor === u.id ? null : u.id); }}>
            {assignFor === u.id ? "Cancel" : "Assign Tier"}
          </Button>
          {u.tier !== "novice" && (
            <Button size="sm" variant="destructive" onClick={() => reset(u.id)}>Revoke</Button>
          )}
        </div>
      </div>
      {assignFor === u.id && (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 p-3 rounded bg-muted/40">
          <div>
            <Label className="text-xs">Tier</Label>
            <Select value={assignTier} onValueChange={(v) => setAssignTier(v as "novice" | "erudite" | "scholar")}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="novice">Novice</SelectItem>
                <SelectItem value="erudite">Erudite (500/day, 150/session)</SelectItem>
                <SelectItem value="scholar">Scholar (unlimited/day, 250/session)</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label className="text-xs">Duration (days, 0 = no expiry)</Label>
            <Input type="number" min={0} value={assignDays} onChange={(e) => setAssignDays(Number(e.target.value))} />
          </div>
          <div className="flex items-end">
            <Button size="sm" className="bg-hero w-full" onClick={assign}>Confirm Assign</Button>
          </div>
        </div>
      )}
    </div>
  );

  return (
    <div className="mt-4 space-y-3">
      <Card className="p-5 bg-hero text-primary-foreground shadow-glow">
        <p className="text-xs uppercase opacity-80 tracking-wide">Total registered users</p>
        <p className="text-4xl font-bold">{rows.length}</p>
      </Card>
      <Input placeholder="Search by name or email…" value={filter} onChange={(e) => setFilter(e.target.value)} />
      <div className="space-y-3" aria-label="Users grouped by subscription tier">
        {tierGroups.map(({ tier, label, description }) => {
          const totalInTier = rows.filter(u => u.tier === tier).length;
          const visibleInTier = filtered.filter(u => u.tier === tier);
          return (
            <details key={tier} open className="rounded-lg border border-border overflow-hidden">
              <summary className="cursor-pointer list-none px-4 py-3 bg-muted/30 hover:bg-muted/50">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="font-semibold">{label} ({totalInTier})</p>
                    <p className="text-xs text-muted-foreground">{description}</p>
                  </div>
                  <span className="text-muted-foreground text-lg" aria-hidden="true">⌄</span>
                </div>
              </summary>
              <div className="divide-y">
                {visibleInTier.length === 0 ? (
                  <p className="px-4 py-6 text-center text-sm text-muted-foreground">
                    {totalInTier === 0 ? "No users in this tier." : "No matching users in this tier."}
                  </p>
                ) : visibleInTier.map(renderUser)}
              </div>
            </details>
          );
        })}
      </div>
    </div>
  );
}

function CodesTab() {
  const [rows, setRows] = useState<Array<{ id: string; code: string; used_by: string | null; used_at: string | null }>>([]);
  const load = async () => {
    const { data } = await supabase.from("admin_codes").select("*").order("created_at", { ascending: false });
    setRows(data ?? []);
  };
  useEffect(() => { load(); }, []);
  const gen = async () => {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    const { error } = await supabase.from("admin_codes").insert({ code });
    if (error) return toast.error(error.message);
    toast.success(`Generated code: ${code}`);
    load();
  };
  return (
    <div className="mt-4 space-y-3">
      <Button onClick={gen} className="bg-hero">Generate New 4-Digit Code</Button>
      <Card className="p-4 divide-y">
        {rows.map(r => (
          <div key={r.id} className="py-2 flex justify-between text-sm">
            <span className="font-mono font-bold">{r.code}</span>
            <span className="text-muted-foreground">{r.used_by ? `Used ${new Date(r.used_at!).toLocaleString()}` : "Available"}</span>
          </div>
        ))}
      </Card>
    </div>
  );
}

function JoinTab() {
  const [code, setCode] = useState("");
  const { refresh } = useAuth();
  const submit = async () => {
    const { data, error } = await supabase.rpc("redeem_admin_code", { _code: code });
    if (error) return toast.error(error.message);
    if (data) { toast.success("You are now an Admin!"); refresh(); }
    else toast.error("Invalid or used code");
  };
  return (
    <Card className="p-5 mt-4 max-w-sm">
      <Label>Enter 4-digit admin code</Label>
      <Input value={code} onChange={(e) => setCode(e.target.value)} maxLength={4} className="font-mono text-center text-xl mt-2" />
      <Button onClick={submit} className="bg-hero w-full mt-3">Redeem</Button>
    </Card>
  );
}

function LeaderboardsTab() {
  return (
    <div className="space-y-8">
      <div>
        <h3 className="text-lg font-bold mb-1">Daily Leaderboard (Live)</h3>
        <p className="text-xs text-muted-foreground mb-3">Live view — 100+ questions today required. Ranked by avg %, ties broken by more questions attempted.</p>
        <LeaderboardTable rpc="get_daily_leaderboard" liveShuffle />
      </div>
      <div>
        <h3 className="text-lg font-bold mb-1">Weekly Performance Board</h3>
        <p className="text-xs text-muted-foreground mb-3">Mon–Sun (UTC). Requires 100+ questions on at least 4 of 7 days. Resets Monday 00:00 UTC.</p>
        <LeaderboardTable rpc="get_weekly_leaderboard" showActiveDays emptyMessage="No consistent qualifiers this week yet — users must hit 100+ questions on 4 of 7 days." />
      </div>
    </div>
  );
}
