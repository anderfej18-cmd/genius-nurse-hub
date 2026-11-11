import { Link, createFileRoute } from "@tanstack/react-router";
import { useState, useMemo } from "react";
import {
  HeartPulse,
  Baby,
  Bed,
  Syringe,
  ShieldAlert,
  MessageSquare,
  Search,
  Clock,
  Award,
  ChevronRight,
  Mic,
  CheckCircle2,
  ListOrdered,
  BookOpen,
} from "lucide-react";
import { SignedInPage } from "@/components/SignedInPage";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { LoadFailed } from "@/components/app/LoadFailed";
import { useServerData } from "@/hooks/use-server-data";
import {
  getOsceCategories,
  getOsceProcedures,
  getOsceUserHistory,
} from "@/functions/osce.functions";
import type { OsceCategory, OsceProcedureSummary } from "@/lib/osce";

export const Route = createFileRoute("/_app/osce")({
  component: OsceCataloguePage,
  head: () => ({
    meta: [
      { title: "OSCE Practice System | NurseGenius" },
      {
        name: "description",
        content:
          "Practice Nigerian Nursing & Midwifery Council (NMCN) OSCE procedures with real-time AI speech recognition, clinical checklist matching, and practical simulations.",
      },
    ],
  }),
});

const ICON_MAP: Record<string, typeof HeartPulse> = {
  Baby,
  HeartPulse,
  Bed,
  Syringe,
  ShieldAlert,
  MessageSquare,
};

function OsceCataloguePage() {
  const [selectedCategory, setSelectedCategory] = useState<string>("all");
  const [searchQuery, setSearchQuery] = useState<string>("");

  const categoriesQuery = useServerData(() => getOsceCategories(), []);
  const proceduresQuery = useServerData(
    () =>
      getOsceProcedures({
        data: {
          categoryId: selectedCategory === "all" ? undefined : selectedCategory,
        },
      }),
    [selectedCategory],
  );
  const historyQuery = useServerData(() => getOsceUserHistory(), []);

  const categories = categoriesQuery.data ?? [];
  const procedures = useMemo(() => proceduresQuery.data ?? [], [proceduresQuery.data]);
  const history = historyQuery.data ?? [];

  const filteredProcedures = useMemo(() => {
    if (!searchQuery.trim()) return procedures;
    const q = searchQuery.toLowerCase().trim();
    return procedures.filter(
      (p) =>
        p.title.toLowerCase().includes(q) ||
        p.stationNumber.toLowerCase().includes(q) ||
        p.examiningBody.toLowerCase().includes(q) ||
        p.sessionLabel.toLowerCase().includes(q),
    );
  }, [procedures, searchQuery]);

  const completedCount = history.length;
  const passedCount = history.filter((h) => h.passed).length;
  const averageScore =
    completedCount > 0
      ? Math.round(history.reduce((acc, h) => acc + h.percentage, 0) / completedCount)
      : null;

  return (
    <SignedInPage
      title="OSCE Clinical Practice"
      description="Official NMCN and University practicum clinical stations from the MNSF Compendium. Practice with real-time speech matching and practical examiner checklists."
    >
      {() => (
        <div className="flex flex-col gap-6">
          {/* Readiness Overview Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <Card className="border border-border/80 bg-card/60 backdrop-blur-sm">
              <CardContent className="p-4 flex items-center gap-3">
                <div className="p-2.5 rounded-xl bg-primary/10 text-primary">
                  <BookOpen className="size-5" />
                </div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium">Available Stations</p>
                  <p className="text-2xl font-bold tracking-tight text-foreground tabular-nums">
                    {procedures.length > 0 ? procedures.length : 34}
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card className="border border-border/80 bg-card/60 backdrop-blur-sm">
              <CardContent className="p-4 flex items-center gap-3">
                <div className="p-2.5 rounded-xl bg-primary/10 text-primary">
                  <CheckCircle2 className="size-5" />
                </div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium">Completed Stations</p>
                  <p className="text-2xl font-bold tracking-tight text-foreground tabular-nums">
                    {completedCount}
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card className="border border-border/80 bg-card/60 backdrop-blur-sm">
              <CardContent className="p-4 flex items-center gap-3">
                <div className="p-2.5 rounded-xl bg-primary/10 text-primary">
                  <Award className="size-5" />
                </div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium">Average Mark</p>
                  <p className="text-2xl font-bold tracking-tight text-foreground tabular-nums">
                    {averageScore !== null ? `${averageScore}%` : "None"}
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card className="border border-border/80 bg-card/60 backdrop-blur-sm">
              <CardContent className="p-4 flex items-center gap-3">
                <div className="p-2.5 rounded-xl bg-primary/10 text-primary">
                  <HeartPulse className="size-5" />
                </div>
                <div>
                  <p className="text-xs text-muted-foreground font-medium">Pass Rate</p>
                  <p className="text-2xl font-bold tracking-tight text-foreground tabular-nums">
                    {completedCount > 0
                      ? `${Math.round((passedCount / completedCount) * 100)}%`
                      : "None"}
                  </p>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Search & Category Filter Toolbar */}
          <div className="flex flex-col md:flex-row gap-3 items-stretch md:items-center justify-between">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-muted-foreground" />
              <Input
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search station (e.g., AMTSL, Episiotomy, Reflexes)..."
                className="pl-9 h-10 bg-background"
              />
            </div>

            <div className="flex items-center gap-1.5 overflow-x-auto pb-1 md:pb-0 scrollbar-none">
              <Button
                variant={selectedCategory === "all" ? "default" : "outline"}
                size="sm"
                onClick={() => setSelectedCategory("all")}
                className="text-xs whitespace-nowrap h-8 rounded-lg"
              >
                All Categories
              </Button>
              {categories.map((cat: OsceCategory) => {
                const IconComp = ICON_MAP[cat.icon] ?? HeartPulse;
                const isSelected = selectedCategory === cat.id;
                return (
                  <Button
                    key={cat.id}
                    variant={isSelected ? "default" : "outline"}
                    size="sm"
                    onClick={() => setSelectedCategory(cat.id)}
                    className="text-xs whitespace-nowrap h-8 rounded-lg flex items-center gap-1.5"
                  >
                    <IconComp className="size-3.5" />
                    {cat.name.split(" ")[0]}
                  </Button>
                );
              })}
            </div>
          </div>

          {/* Loading / Error States */}
          {proceduresQuery.loading && !proceduresQuery.data && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-48 w-full rounded-2xl" />
              ))}
            </div>
          )}

          {proceduresQuery.error && !proceduresQuery.data && (
            <LoadFailed load={proceduresQuery} label="OSCE procedures" />
          )}

          {/* Procedure Grid */}
          {!proceduresQuery.loading && filteredProcedures.length === 0 && (
            <div className="py-16 text-center border rounded-2xl bg-card/40 border-dashed border-border/80">
              <HeartPulse className="size-10 mx-auto text-muted-foreground mb-3" />
              <p className="text-base font-medium text-foreground">
                No procedures match your search
              </p>
              <p className="text-sm text-muted-foreground mt-1">
                Try searching with a different procedure name, station number, or clear filters.
              </p>
              <Button
                variant="outline"
                size="sm"
                className="mt-4"
                onClick={() => {
                  setSearchQuery("");
                  setSelectedCategory("all");
                }}
              >
                Reset Filters
              </Button>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filteredProcedures.map((proc: OsceProcedureSummary) => {
              const minutes = Math.round(proc.timeLimitSeconds / 60);
              return (
                <Card
                  key={proc.id}
                  className="group border border-border/70 hover:border-primary/50 transition-colors duration-200 hover:shadow-sm flex flex-col justify-between bg-card/60 backdrop-blur-sm"
                >
                  <CardContent className="p-5 flex flex-col gap-4">
                    {/* Station & Mode Badges */}
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs font-semibold px-2.5 py-1 rounded-md bg-primary/10 text-primary">
                        {proc.stationNumber}
                      </span>
                      <div className="flex items-center gap-1.5">
                        {proc.assessmentMode === "oral" && (
                          <Badge
                            variant="outline"
                            className="text-[11px] gap-1 px-2 py-0.5 border-border"
                          >
                            <Mic className="size-3 text-primary" /> Oral Viva
                          </Badge>
                        )}
                        {proc.assessmentMode === "practical" && (
                          <Badge
                            variant="outline"
                            className="text-[11px] gap-1 px-2 py-0.5 border-border"
                          >
                            <Mic className="size-3 text-primary" /> Procedure Walkthrough
                          </Badge>
                        )}
                        {proc.assessmentMode === "both" && (
                          <Badge
                            variant="outline"
                            className="text-[11px] gap-1 px-2 py-0.5 border-border"
                          >
                            <Mic className="size-3 text-primary" /> Oral & Practical
                          </Badge>
                        )}
                      </div>
                    </div>

                    {/* Procedure Title & Examining Body */}
                    <div>
                      <h3 className="font-semibold text-base leading-snug group-hover:text-primary transition-colors line-clamp-2 [text-wrap:balance]">
                        {proc.title}
                      </h3>
                      <p className="text-xs text-muted-foreground mt-1 line-clamp-1">
                        {proc.examiningBody} • {proc.sessionLabel}
                      </p>
                    </div>

                    {/* Metadata Row: Marks, Time, Items */}
                    <div className="grid grid-cols-3 gap-2 pt-2 border-t border-border/50 text-xs text-muted-foreground tabular-nums">
                      <div className="flex items-center gap-1">
                        <Award className="size-3.5 text-primary" />
                        <span>{proc.totalMarks} Marks</span>
                      </div>
                      <div className="flex items-center gap-1">
                        <Clock className="size-3.5 text-primary" />
                        <span>{minutes} mins</span>
                      </div>
                      <div className="flex items-center gap-1">
                        <ListOrdered className="size-3.5 text-primary" />
                        <span>{proc.itemCount} steps</span>
                      </div>
                    </div>

                    {/* Action Button */}
                    <Button asChild className="w-full mt-1 gap-1.5 min-h-[44px]" size="sm">
                      <Link to="/osce/$procedureId" params={{ procedureId: proc.slug }}>
                        <span>Start Station</span>
                        <ChevronRight className="size-4" />
                      </Link>
                    </Button>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </div>
      )}
    </SignedInPage>
  );
}
