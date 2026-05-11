import { Link, useRouterState, useNavigate } from "@tanstack/react-router";
import { useAuth, TIER_LABEL } from "@/hooks/use-auth";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Activity, LogOut } from "lucide-react";

export function AppHeader() {
  const { user, profile, isAdmin, signOut } = useAuth();
  const navigate = useNavigate();
  const path = useRouterState({ select: (s) => s.location.pathname });

  const link = (to: string, label: string) => (
    <Link
      to={to}
      className={`px-3 py-2 rounded-md text-sm font-medium transition-colors ${
        path === to ? "bg-accent text-accent-foreground" : "text-foreground/70 hover:text-foreground hover:bg-accent/50"
      }`}
    >
      {label}
    </Link>
  );

  return (
    <header className="sticky top-0 z-40 border-b bg-background/80 backdrop-blur-md">
      <div className="container mx-auto flex h-16 items-center justify-between px-4">
        <Link to="/" className="flex items-center gap-2">
          <div className="h-9 w-9 rounded-lg bg-hero shadow-glow flex items-center justify-center">
            <Activity className="h-5 w-5 text-primary-foreground" />
          </div>
          <span className="font-bold text-lg tracking-tight">NurseGenius</span>
        </Link>

        {user && profile?.onboarded && (
          <nav className="hidden md:flex items-center gap-1">
            {link("/dashboard", "Dashboard")}
            {link("/exam/start", "Take Test")}
            {link("/leaderboard", "Leaderboard")}
            {link("/payments", "Upgrade")}
            {isAdmin && link("/admin", "Admin")}
          </nav>
        )}

        <div className="flex items-center gap-2">
          {user ? (
            <>
              {profile && (
                <Badge variant="secondary" className="hidden sm:inline-flex">
                  {TIER_LABEL[profile.tier]}
                </Badge>
              )}
              <Button
                size="sm"
                variant="ghost"
                onClick={async () => { await signOut(); navigate({ to: "/" }); }}
              >
                <LogOut className="h-4 w-4" />
              </Button>
            </>
          ) : (
            <Button size="sm" onClick={() => navigate({ to: "/auth" })}>Sign In</Button>
          )}
        </div>
      </div>
    </header>
  );
}
