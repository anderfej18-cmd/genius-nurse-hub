import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Copy, Check } from "lucide-react";
import { toast } from "sonner";
import { verifyReceipt } from "@/lib/receipts.functions";

export const Route = createFileRoute("/payments")({ component: Payments });

interface Settings {
  erudite_price: number; scholar_price: number;
  erudite_days: number; scholar_days: number;
  bank_name: string; bank_account: string; bank_account_name: string;
}

interface Receipt {
  id: string; status: string; target_tier: string; amount: number | null; created_at: string;
}

function Payments() {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const [settings, setSettings] = useState<Settings | null>(null);
  const [tier, setTier] = useState<"erudite" | "scholar">("erudite");
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [copied, setCopied] = useState(false);

  useEffect(() => { if (!loading && !user) navigate({ to: "/auth" }); }, [loading, user, navigate]);

  useEffect(() => {
    (async () => {
      const { data: s } = await supabase.from("app_settings").select("*").eq("id", 1).single();
      setSettings(s as Settings);
      if (user) {
        const { data: r } = await supabase.from("payment_receipts")
          .select("id, status, target_tier, amount, created_at")
          .eq("user_id", user.id).order("created_at", { ascending: false });
        setReceipts((r as Receipt[]) ?? []);
      }
    })();
  }, [user]);

  const verifyFn = useServerFn(verifyReceipt);

  const upload = async () => {
    if (!user || !file || !settings) return;
    setBusy(true);

    // Make sure the session is still valid — an expired session makes storage
    // uploads fail with a confusing permission error.
    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData.session) {
      setBusy(false);
      toast.error("Your session expired. Please sign in again.");
      navigate({ to: "/auth" });
      return;
    }

    if (file.size > 10 * 1024 * 1024) {
      setBusy(false);
      return toast.error("File is too large. Please upload an image under 10MB.");
    }

    // Sanitise the filename: spaces/parentheses/unicode break storage keys.
    const ext = (file.name.split(".").pop() ?? "jpg").toLowerCase().replace(/[^a-z0-9]/g, "");
    const safeName = `${Date.now()}-receipt.${ext || "jpg"}`;
    const path = `${sessionData.session.user.id}/${safeName}`;

    const { error: upErr } = await supabase.storage
      .from("receipts")
      .upload(path, file, { contentType: file.type || "image/jpeg", upsert: false });
    if (upErr) {
      setBusy(false);
      return toast.error(`Upload failed: ${upErr.message}`);
    }
    const amount = tier === "erudite" ? settings.erudite_price : settings.scholar_price;

    // Instant upgrade + auto-approved receipt row
    const { data: receiptId, error } = await supabase.rpc("auto_upgrade_from_receipt", {
      _file_path: path, _tier: tier, _amount: amount,
    });
    if (error) { setBusy(false); return toast.error(error.message); }

    toast.success("Upgrade activated! Verifying receipt in background…");
    setFile(null);

    // Kick off server-side OCR + duplicate/amount guard
    verifyFn({ data: { receiptId: receiptId as unknown as string } })
      .then((res) => {
        if (!res.ok) {
          if (res.reason === "duplicate" || res.reason === "amount_mismatch") {
            toast.error(`Access revoked — ${("detail" in res && res.detail) || res.reason}`);
          }
        }
      })
      .catch(() => { /* silent; admin can still act */ })
      .finally(async () => {
        setBusy(false);
        const { data: r } = await supabase.from("payment_receipts")
          .select("id, status, target_tier, amount, created_at")
          .eq("user_id", user.id).order("created_at", { ascending: false });
        setReceipts((r as Receipt[]) ?? []);
      });
  };

  const copyAccount = () => {
    if (!settings) return;
    navigator.clipboard.writeText(settings.bank_account);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  if (!settings) return <><AppHeader /><div className="p-12 text-center">Loading…</div></>;

  return (
    <>
      <AppHeader />
      <main className="container mx-auto px-4 py-8 max-w-2xl space-y-6">
        <h1 className="text-3xl font-bold">Upgrade Your Tier</h1>

        <Card className="p-6 bg-hero text-primary-foreground shadow-glow">
          <p className="text-xs uppercase opacity-80">Pay to this account</p>
          <div className="mt-2 flex items-center justify-between gap-3">
            <div>
              <p className="text-2xl font-bold">{settings.bank_name}</p>
              <p className="font-mono text-xl mt-1">{settings.bank_account}</p>
              <p className="text-sm opacity-90">{settings.bank_account_name}</p>
            </div>
            <Button variant="secondary" onClick={copyAccount}>
              {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
            </Button>
          </div>
        </Card>

        <div className="grid md:grid-cols-2 gap-4">
          <Card className="p-5"><p className="text-xs uppercase text-muted-foreground">Erudite</p>
            <p className="text-3xl font-bold">₦{settings.erudite_price.toLocaleString()}</p>
            <p className="text-sm text-muted-foreground">150 questions/day • {settings.erudite_days} days • AI access</p>
          </Card>
          <Card className="p-5"><p className="text-xs uppercase text-muted-foreground">Scholar</p>
            <p className="text-3xl font-bold">₦{settings.scholar_price.toLocaleString()}</p>
            <p className="text-sm text-muted-foreground">250 questions/day • {settings.scholar_days} days • AI access</p>
          </Card>
        </div>

        <Card className="p-6 bg-card-soft">
          <h2 className="font-semibold mb-4">Upload Your Receipt</h2>
          <div className="space-y-3">
            <div>
              <Label>Tier you paid for</Label>
              <Select value={tier} onValueChange={(v) => setTier(v as "erudite" | "scholar")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="erudite">Erudite — ₦{settings.erudite_price.toLocaleString()}</SelectItem>
                  <SelectItem value="scholar">Scholar — ₦{settings.scholar_price.toLocaleString()}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Receipt (image or PDF)</Label>
              <Input type="file" accept="image/*,application/pdf" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
            </div>
            <Button onClick={upload} disabled={!file || busy} className="w-full bg-hero">
              {busy ? "Uploading…" : "Submit Receipt"}
            </Button>
          </div>
        </Card>

        {receipts.length > 0 && (
          <Card className="p-5">
            <h2 className="font-semibold mb-3">Your Receipts</h2>
            <div className="divide-y">
              {receipts.map(r => (
                <div key={r.id} className="flex justify-between items-center py-2 text-sm">
                  <div>
                    <p className="font-medium">{r.target_tier} — ₦{r.amount?.toLocaleString()}</p>
                    <p className="text-xs text-muted-foreground">{new Date(r.created_at).toLocaleString()}</p>
                  </div>
                  <Badge className={
                    r.status === "approved" ? "bg-success text-success-foreground" :
                    r.status === "rejected" ? "bg-destructive text-destructive-foreground" :
                    "bg-warning text-warning-foreground"
                  }>{r.status}</Badge>
                </div>
              ))}
            </div>
          </Card>
        )}

        <Card className="p-5 text-sm">
          <p className="font-semibold mb-1">Need help?</p>
          <p className="text-muted-foreground">
            Telegram: <a href="https://t.me/nursegenius" className="text-primary underline">@nursegenius</a> ·
            Email: <a href="mailto:nursegenius3@gmail.com" className="text-primary underline">nursegenius3@gmail.com</a>
          </p>
        </Card>
      </main>
    </>
  );
}
