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
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";

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
        <h1 className="text-3xl font-bold mb-6">Admin Panel</h1>
        <Tabs defaultValue="questions">
          <TabsList className="flex-wrap h-auto">
            <TabsTrigger value="questions">Questions</TabsTrigger>
            <TabsTrigger value="payments">Payments</TabsTrigger>
            <TabsTrigger value="leaderboards">Leaderboards</TabsTrigger>
            {isCentralAdmin && <TabsTrigger value="users">Users</TabsTrigger>}
            {isCentralAdmin && <TabsTrigger value="settings">Settings</TabsTrigger>}
            {isCentralAdmin && <TabsTrigger value="codes">Admin Codes</TabsTrigger>}
            {!isCentralAdmin && <TabsTrigger value="join">Become Admin</TabsTrigger>}
          </TabsList>
          <TabsContent value="questions"><QuestionsTab /></TabsContent>
          <TabsContent value="payments"><PaymentsTab /></TabsContent>
          <TabsContent value="leaderboards"><LeaderboardsTab /></TabsContent>
          {isCentralAdmin && <TabsContent value="users"><UsersTab /></TabsContent>}
          {isCentralAdmin && <TabsContent value="settings"><SettingsTab /></TabsContent>}
          {isCentralAdmin && <TabsContent value="codes"><CodesTab /></TabsContent>}
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

  const activeSub = (subMode === "new" ? subNew : subExisting).trim() || "General";

  const loadSubs = async (et: "RN" | "RM") => {
    const { data } = await supabase.from("questions").select("topic").eq("exam_type", et);
    const uniq = Array.from(new Set((data ?? []).map(r => r.topic).filter(Boolean))).sort();
    setExistingSubs(uniq);
    if (uniq.length && !subExisting) setSubExisting(uniq[0]);
  };

  useEffect(() => {
    supabase.from("questions").select("id", { count: "exact", head: true }).then(r => setCount(r.count ?? 0));
  }, []);
  useEffect(() => { loadSubs(examType); /* eslint-disable-next-line */ }, [examType]);

  const addOne = async () => {
    if (!text || !a || !b || !c || !d) return toast.error("All fields required");
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
    if (subMode === "new" && !subNew.trim()) return toast.error("Enter a new subcategory name first");
    const raw = await file.text();
    const parsed = parseTxt(raw);
    if (parsed.length === 0) return toast.error("No valid questions found in file. Check the format.");
    const rows = parsed.map(p => ({ exam_type: examType, topic: activeSub, ...p }));
    const { error } = await supabase.from("questions").insert(rows);
    if (error) return toast.error(error.message);
    toast.success(`Imported ${rows.length} questions into ${examType} · ${activeSub}`);
    setCount(c => (c ?? 0) + rows.length);
    loadSubs(examType);
    if (subMode === "new") { setSubExisting(subNew.trim()); setSubNew(""); setSubMode("existing"); }
  };

  return (
    <div className="space-y-4 mt-4">
      <Card className="p-5">
        <p className="text-sm text-muted-foreground">Total questions in bank: <strong className="text-foreground">{count ?? "…"}</strong></p>
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

interface ReceiptRow {
  id: string; user_id: string; file_path: string; amount: number | null;
  target_tier: string; status: string; created_at: string;
  auto_approved?: boolean; flag_reason?: string | null;
  profile?: { username: string | null; email: string | null; legal_full_name: string | null; tier: string } | null;
}

function PaymentsTab() {
  const [rows, setRows] = useState<ReceiptRow[]>([]);
  const [urls, setUrls] = useState<Record<string, string>>({});

  const load = async () => {
    const { data } = await supabase.from("payment_receipts").select("*").order("created_at", { ascending: false });
    const list = (data as ReceiptRow[]) ?? [];
    // Fetch profile info for each unique user
    const userIds = Array.from(new Set(list.map(r => r.user_id)));
    if (userIds.length) {
      const { data: profs } = await supabase.from("profiles")
        .select("id, username, email, legal_full_name, tier")
        .in("id", userIds);
      const byId = new Map((profs ?? []).map(p => [p.id, p]));
      list.forEach(r => { r.profile = byId.get(r.user_id) as ReceiptRow["profile"]; });
    }
    setRows(list);

    // Pre-sign URLs so images render inline
    const entries: Record<string, string> = {};
    await Promise.all(list.map(async r => {
      const { data: s } = await supabase.storage.from("receipts").createSignedUrl(r.file_path, 3600);
      if (s?.signedUrl) entries[r.id] = s.signedUrl;
    }));
    setUrls(entries);
  };
  useEffect(() => { load(); }, []);

  const revoke = async (r: ReceiptRow) => {
    if (!confirm(`Revoke upgrade for ${r.profile?.username ?? r.user_id.slice(0,8)}? This reverts them to Novice.`)) return;
    const { error } = await supabase.rpc("flag_receipt_and_revoke", {
      _receipt_id: r.id, _reason: "Admin manual review — receipt flagged as fake or edited.",
    });
    if (error) return toast.error(error.message);
    toast.success("Upgrade revoked; user reverted to Novice");
    load();
  };

  const isImage = (path: string) => /\.(jpe?g|png|webp|gif|bmp|heic)$/i.test(path);

  const statusBadge = (r: ReceiptRow) => {
    if (r.status === "approved" && r.auto_approved) return <Badge className="bg-success text-success-foreground">automatically_approved</Badge>;
    if (r.status === "approved") return <Badge className="bg-success text-success-foreground">approved</Badge>;
    if (r.status === "rejected") return <Badge variant="destructive">{r.flag_reason ? "flagged" : "rejected"}</Badge>;
    return <Badge>{r.status}</Badge>;
  };

  return (
    <Card className="p-4 mt-4 divide-y">
      {rows.length === 0 && <p className="p-6 text-center text-muted-foreground text-sm">No receipts.</p>}
      {rows.map(r => (
        <div key={r.id} className="py-4 grid md:grid-cols-[220px_1fr] gap-4">
          <div>
            {urls[r.id] && isImage(r.file_path) ? (
              <a href={urls[r.id]} target="_blank" rel="noreferrer">
                <img src={urls[r.id]} alt="receipt" className="w-full h-40 object-cover rounded border" />
              </a>
            ) : urls[r.id] ? (
              <a href={urls[r.id]} target="_blank" rel="noreferrer"
                className="flex items-center justify-center h-40 rounded border bg-muted text-xs text-muted-foreground">
                Open file
              </a>
            ) : (
              <div className="h-40 rounded border bg-muted animate-pulse" />
            )}
          </div>
          <div className="space-y-2">
            <div className="flex items-start justify-between gap-3 flex-wrap">
              <div className="text-sm">
                <p className="font-semibold">{r.target_tier} • ₦{r.amount?.toLocaleString()}</p>
                <p className="text-xs text-muted-foreground">
                  {r.profile?.username ?? "—"} · {r.profile?.email ?? r.user_id.slice(0,8)}
                </p>
                <p className="text-xs">
                  <span className="text-muted-foreground">Legal Name:</span>{" "}
                  <strong>{r.profile?.legal_full_name ?? "— not provided —"}</strong>
                </p>
                <p className="text-xs text-muted-foreground">
                  Current tier: <Badge variant="secondary">{r.profile?.tier ?? "?"}</Badge> ·
                  Submitted {new Date(r.created_at).toLocaleString()}
                </p>
                {r.flag_reason && <p className="text-xs text-destructive mt-1">⚠ {r.flag_reason}</p>}
              </div>
              <div className="flex flex-col items-end gap-2">
                {statusBadge(r)}
                {r.status !== "rejected" && (
                  <Button size="sm" variant="destructive" onClick={() => revoke(r)}>Revoke Upgrade</Button>
                )}
              </div>
            </div>
          </div>
        </div>
      ))}
    </Card>
  );
}

interface UserRow { id: string; email: string | null; username: string | null; legal_full_name: string | null; tier: string; expiry_date: string | null; }

function UsersTab() {
  const [rows, setRows] = useState<UserRow[]>([]);
  const [exams, setExams] = useState<Record<string, { avg: number; n: number }>>({});
  const [filter, setFilter] = useState("");
  const [assignFor, setAssignFor] = useState<string | null>(null);
  const [assignTier, setAssignTier] = useState<"erudite" | "scholar">("erudite");
  const [assignDays, setAssignDays] = useState<number>(30);

  const load = async () => {
    const { data } = await supabase.from("profiles").select("id, email, username, legal_full_name, tier, expiry_date");
    setRows((data as UserRow[]) ?? []);
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

  return (
    <div className="mt-4 space-y-3">
      <Input placeholder="Search by name or email…" value={filter} onChange={(e) => setFilter(e.target.value)} />
      <Card className="p-4 divide-y">
        {filtered.length === 0 && <p className="p-6 text-center text-muted-foreground text-sm">No users.</p>}
        {filtered.map(u => (
          <div key={u.id} className="py-3 space-y-2">
            <div className="flex items-center justify-between gap-3 flex-wrap">
              <div className="text-sm">
                <p className="font-medium">{u.username ?? "—"} <span className="text-muted-foreground">({u.email})</span></p>
                <p className="text-xs"><span className="text-muted-foreground">Legal Name:</span> <strong>{u.legal_full_name ?? "— not provided —"}</strong></p>
                <p className="text-xs text-muted-foreground">
                  <Badge variant="secondary" className="mr-1">{u.tier}</Badge>
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
                  <Select value={assignTier} onValueChange={(v) => setAssignTier(v as "erudite" | "scholar")}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
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
        ))}
      </Card>
    </div>
  );
}

function SettingsTab() {
  const [s, setS] = useState<{ erudite_price: number; scholar_price: number; erudite_days: number; scholar_days: number; bank_account: string; bank_account_name: string; bank_name: string } | null>(null);
  useEffect(() => { supabase.from("app_settings").select("*").eq("id", 1).single().then(({ data }) => setS(data as typeof s)); }, []);
  if (!s) return <div className="p-6">Loading…</div>;
  const save = async () => {
    const { error } = await supabase.from("app_settings").update(s).eq("id", 1);
    if (error) return toast.error(error.message);
    toast.success("Saved");
  };
  return (
    <Card className="p-5 mt-4 space-y-3 max-w-md">
      <div className="grid grid-cols-2 gap-3">
        <div><Label>Erudite Price</Label><Input type="number" value={s.erudite_price} onChange={(e) => setS({ ...s, erudite_price: Number(e.target.value) })} /></div>
        <div><Label>Erudite Days</Label><Input type="number" value={s.erudite_days} onChange={(e) => setS({ ...s, erudite_days: Number(e.target.value) })} /></div>
        <div><Label>Scholar Price</Label><Input type="number" value={s.scholar_price} onChange={(e) => setS({ ...s, scholar_price: Number(e.target.value) })} /></div>
        <div><Label>Scholar Days</Label><Input type="number" value={s.scholar_days} onChange={(e) => setS({ ...s, scholar_days: Number(e.target.value) })} /></div>
      </div>
      <div><Label>Bank Name</Label><Input value={s.bank_name} onChange={(e) => setS({ ...s, bank_name: e.target.value })} /></div>
      <div><Label>Account Number</Label><Input value={s.bank_account} onChange={(e) => setS({ ...s, bank_account: e.target.value })} /></div>
      <div><Label>Account Name</Label><Input value={s.bank_account_name} onChange={(e) => setS({ ...s, bank_account_name: e.target.value })} /></div>
      <Button onClick={save} className="bg-hero w-full">Save Settings</Button>
    </Card>
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
