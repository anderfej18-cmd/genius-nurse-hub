import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "sonner";

export const Route = createFileRoute("/onboarding")({ component: Onboarding });

function Onboarding() {
  const { user, profile, loading, refresh } = useAuth();
  const navigate = useNavigate();

  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");
  const [username, setUsername] = useState("Nurse");
  const [examDate, setExamDate] = useState("");
  const [pref, setPref] = useState<"RN" | "RM" | "Both">("RN");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!loading) {
      if (!user) navigate({ to: "/auth" });
      else if (profile?.onboarded) navigate({ to: "/dashboard" });
    }
  }, [loading, user, profile, navigate]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!first.trim() || !last.trim()) return toast.error("First and last name required");
    if (!/^Nurse[A-Za-z0-9_]{2,20}$/.test(username)) return toast.error("Username must start with 'Nurse' and contain 2–20 letters/digits after");
    if (!examDate) return toast.error("Exam date required");

    setBusy(true);
    const { error } = await supabase.from("profiles").update({
      first_name: first.trim(),
      last_name: last.trim(),
      username,
      exam_date: examDate,
      exam_preference: pref,
      onboarded: true,
    }).eq("id", user!.id);
    setBusy(false);
    if (error) {
      if (error.code === "23505") toast.error("That username is already taken");
      else toast.error(error.message);
      return;
    }
    await refresh();
    toast.success("Profile complete!");
    navigate({ to: "/dashboard" });
  };

  return (
    <>
      <AppHeader />
      <main className="container mx-auto px-4 py-12 max-w-lg">
        <Card className="p-6 bg-card-soft shadow-glow">
          <h1 className="text-2xl font-bold">Set up your profile</h1>
          <p className="text-sm text-muted-foreground mt-1">Your username must start with <strong>Nurse</strong> (e.g. NurseAlex).</p>
          <form onSubmit={submit} className="space-y-4 mt-6">
            <div className="grid grid-cols-2 gap-3">
              <div><Label>First Name</Label><Input value={first} onChange={(e) => setFirst(e.target.value)} maxLength={50} /></div>
              <div><Label>Last Name</Label><Input value={last} onChange={(e) => setLast(e.target.value)} maxLength={50} /></div>
            </div>
            <div>
              <Label>Username</Label>
              <Input value={username} onChange={(e) => setUsername(e.target.value)} maxLength={25} />
            </div>
            <div>
              <Label>Exam Date</Label>
              <Input type="date" value={examDate} onChange={(e) => setExamDate(e.target.value)} />
            </div>
            <div>
              <Label>Exam Type</Label>
              <Select value={pref} onValueChange={(v) => setPref(v as "RN" | "RM" | "Both")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="RN">RN (Registered Nurse)</SelectItem>
                  <SelectItem value="RM">RM (Registered Midwife)</SelectItem>
                  <SelectItem value="Both">Both</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <Button type="submit" className="w-full bg-hero" disabled={busy}>Save & Continue</Button>
          </form>
        </Card>
      </main>
    </>
  );
}
