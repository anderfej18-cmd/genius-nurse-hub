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
            {isCentralAdmin && <TabsTrigger value="users">Users</TabsTrigger>}
            {isCentralAdmin && <TabsTrigger value="settings">Settings</TabsTrigger>}
            {isCentralAdmin && <TabsTrigger value="codes">Admin Codes</TabsTrigger>}
            {!isCentralAdmin && <TabsTrigger value="join">Become Admin</TabsTrigger>}
          </TabsList>
          <TabsContent value="questions"><QuestionsTab /></TabsContent>
          <TabsContent value="payments"><PaymentsTab /></TabsContent>
          {isCentralAdmin && <TabsContent value="users"><UsersTab /></TabsContent>}
          {isCentralAdmin && <TabsContent value="settings"><SettingsTab /></TabsContent>}
          {isCentralAdmin && <TabsContent value="codes"><CodesTab /></TabsContent>}
          {!isCentralAdmin && <TabsContent value="join"><JoinTab /></TabsContent>}
        </Tabs>
      </main>
    </>
  );
}

function QuestionsTab() {
  const [examType, setExamType] = useState<"RN" | "RM">("RN");
  const [topic, setTopic] = useState("General");
  const [text, setText] = useState("");
  const [a, setA] = useState(""); const [b, setB] = useState("");
  const [c, setC] = useState(""); const [d, setD] = useState("");
  const [ans, setAns] = useState<"A" | "B" | "C" | "D">("A");
  const [rationale, setRationale] = useState("");
  const [count, setCount] = useState<number | null>(null);

  useEffect(() => {
    supabase.from("questions").select("id", { count: "exact", head: true }).then(r => setCount(r.count ?? 0));
  }, []);

  const addOne = async () => {
    if (!text || !a || !b || !c || !d) return toast.error("All fields required");
    const { error } = await supabase.from("questions").insert({
      exam_type: examType, topic, question_text: text,
      option_a: a, option_b: b, option_c: c, option_d: d,
      correct_answer: ans, rationale,
    });
    if (error) return toast.error(error.message);
    toast.success("Question added");
    setText(""); setA(""); setB(""); setC(""); setD(""); setRationale("");
  };

  const uploadCSV = async (file: File) => {
    const text = await file.text();
    const lines = text.split(/\r?\n/).filter(l => l.trim());
    const header = lines[0].toLowerCase().split(",");
    const idx = (k: string) => header.indexOf(k);
    const need = ["exam_type","topic","question","a","b","c","d","answer","rationale"];
    if (need.some(n => idx(n) === -1)) return toast.error("CSV header must be: exam_type,topic,question,a,b,c,d,answer,rationale");
    const rows = lines.slice(1).map(line => {
      // Naive CSV split (no embedded commas in quotes for simplicity)
      const cols = line.match(/("([^"]|"")*"|[^,]*)(,|$)/g)?.map(c => c.replace(/,$/, "").replace(/^"|"$/g, "").replace(/""/g, '"')) ?? [];
      return {
        exam_type: cols[idx("exam_type")]?.toUpperCase(),
        topic: cols[idx("topic")] || "General",
        question_text: cols[idx("question")],
        option_a: cols[idx("a")], option_b: cols[idx("b")],
        option_c: cols[idx("c")], option_d: cols[idx("d")],
        correct_answer: cols[idx("answer")]?.toUpperCase(),
        rationale: cols[idx("rationale")] || null,
      };
    }).filter(r => r.question_text && ["RN","RM"].includes(r.exam_type) && ["A","B","C","D"].includes(r.correct_answer));
    if (rows.length === 0) return toast.error("No valid rows found");
    const { error } = await supabase.from("questions").insert(rows);
    if (error) return toast.error(error.message);
    toast.success(`Imported ${rows.length} questions`);
    setCount(c => (c ?? 0) + rows.length);
  };

  return (
    <div className="space-y-4 mt-4">
      <Card className="p-5">
        <p className="text-sm text-muted-foreground">Total questions in bank: <strong className="text-foreground">{count ?? "…"}</strong></p>
      </Card>
      <Card className="p-5">
        <h3 className="font-semibold mb-3">Bulk CSV Upload</h3>
        <p className="text-xs text-muted-foreground mb-2">
          Header row required: <code>exam_type,topic,question,a,b,c,d,answer,rationale</code>
        </p>
        <Input type="file" accept=".csv" onChange={(e) => e.target.files?.[0] && uploadCSV(e.target.files[0])} />
      </Card>
      <Card className="p-5 space-y-3">
        <h3 className="font-semibold">Add One Question</h3>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Exam Type</Label>
            <Select value={examType} onValueChange={(v) => setExamType(v as "RN" | "RM")}><SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value="RN">RN</SelectItem><SelectItem value="RM">RM</SelectItem></SelectContent>
            </Select>
          </div>
          <div><Label>Topic</Label><Input value={topic} onChange={(e) => setTopic(e.target.value)} /></div>
        </div>
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
        <div><Label>Rationale</Label><Textarea value={rationale} onChange={(e) => setRationale(e.target.value)} rows={2} /></div>
        <Button onClick={addOne} className="bg-hero">Add Question</Button>
      </Card>
    </div>
  );
}

interface ReceiptRow { id: string; user_id: string; file_path: string; amount: number | null; target_tier: string; status: string; created_at: string; }

function PaymentsTab() {
  const [rows, setRows] = useState<ReceiptRow[]>([]);
  const load = async () => {
    const { data } = await supabase.from("payment_receipts").select("*").order("created_at", { ascending: false });
    setRows((data as ReceiptRow[]) ?? []);
  };
  useEffect(() => { load(); }, []);

  const view = async (path: string) => {
    const { data } = await supabase.storage.from("receipts").createSignedUrl(path, 60);
    if (data?.signedUrl) window.open(data.signedUrl, "_blank");
  };
  const approve = async (id: string) => {
    const { error } = await supabase.rpc("approve_receipt", { _receipt_id: id });
    if (error) return toast.error(error.message);
    toast.success("Approved");
    load();
  };
  const reject = async (id: string) => {
    const { error } = await supabase.from("payment_receipts").update({ status: "rejected", reviewed_at: new Date().toISOString() }).eq("id", id);
    if (error) return toast.error(error.message);
    toast.success("Rejected");
    load();
  };

  return (
    <Card className="p-4 mt-4 divide-y">
      {rows.length === 0 && <p className="p-6 text-center text-muted-foreground text-sm">No receipts.</p>}
      {rows.map(r => (
        <div key={r.id} className="py-3 flex items-center justify-between gap-3 flex-wrap">
          <div className="text-sm">
            <p className="font-medium">{r.target_tier} • ₦{r.amount?.toLocaleString()}</p>
            <p className="text-xs text-muted-foreground">User: {r.user_id.slice(0,8)} · {new Date(r.created_at).toLocaleString()}</p>
          </div>
          <div className="flex gap-2 items-center">
            <Badge>{r.status}</Badge>
            <Button size="sm" variant="outline" onClick={() => view(r.file_path)}>View</Button>
            {r.status === "pending" && <>
              <Button size="sm" className="bg-success text-success-foreground" onClick={() => approve(r.id)}>Approve</Button>
              <Button size="sm" variant="destructive" onClick={() => reject(r.id)}>Reject</Button>
            </>}
          </div>
        </div>
      ))}
    </Card>
  );
}

interface UserRow { id: string; email: string | null; username: string | null; tier: string; expiry_date: string | null; }

function UsersTab() {
  const [rows, setRows] = useState<UserRow[]>([]);
  const [exams, setExams] = useState<Record<string, { avg: number; n: number }>>({});

  const load = async () => {
    const { data } = await supabase.from("profiles").select("id, email, username, tier, expiry_date");
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
    if (!confirm("Reset this user to Novice?")) return;
    const { error } = await supabase.rpc("reset_user_to_novice", { _user_id: id });
    if (error) return toast.error(error.message);
    toast.success("User reset");
    load();
  };

  return (
    <Card className="p-4 mt-4 divide-y">
      {rows.map(u => (
        <div key={u.id} className="py-3 flex items-center justify-between gap-3 flex-wrap">
          <div className="text-sm">
            <p className="font-medium">{u.username ?? "—"} <span className="text-muted-foreground">({u.email})</span></p>
            <p className="text-xs text-muted-foreground">
              {u.tier} {u.expiry_date && `· expires ${new Date(u.expiry_date).toLocaleDateString()}`}
              {exams[u.id] && ` · avg ${exams[u.id].avg.toFixed(1)}% (${exams[u.id].n} tests)`}
            </p>
          </div>
          {u.tier !== "novice" && <Button size="sm" variant="destructive" onClick={() => reset(u.id)}>Kill-Switch</Button>}
        </div>
      ))}
    </Card>
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
