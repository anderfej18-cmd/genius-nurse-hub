import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";
import seedDataRaw from "./data/osce_seed_data.json";
import type {
  OsceCategory,
  OsceProcedureSummary,
  OsceProcedureDetail,
  OsceChecklistItem,
  OsceSessionDetail,
  StartSessionInput,
  TranscriptUtterance,
  OsceSessionEvaluation,
  ClinicalFeedbackSection,
} from "./osce.types";

interface SeedDataStructure {
  categories: OsceCategory[];
  procedures: Array<{
    slug: string;
    category_id: string;
    title: string;
    station_number: string;
    examining_body: string;
    session_label: string;
    page_start: number;
    page_end: number;
    total_marks: number;
    time_limit_seconds: number;
    instructions: string;
    scenario_prompt: string;
    assessment_mode: "oral" | "practical" | "both";
    equipment_list: string[];
    items: Array<{
      step_order: number;
      section: string;
      description: string;
      allocated_marks: number;
      is_critical: boolean;
      assessment_mode: "oral" | "practical" | "both";
      clinical_synonyms: string[];
      verification_criteria: string;
    }>;
  }>;
}

const typedSeedData = seedDataRaw as unknown as SeedDataStructure;

export function shouldFallbackToSeed(error: unknown): boolean {
  if (typeof process !== "undefined" && process.env?.OSCE_USE_SEED_FALLBACK === "true") {
    return true;
  }
  if (!error) return false;

  const errObj = error as { code?: string; message?: string };
  const code = String(errObj.code ?? "");
  const message = String(errObj.message ?? "").toLowerCase();

  // If table does not exist (unmigrated database)
  if (code === "42P01" || code === "PGRST204" || code === "PGRST200") {
    return true;
  }
  if (message.includes("relation") && message.includes("does not exist")) {
    return true;
  }
  if (message.includes("could not find the table") || message.includes("schema cache")) {
    return true;
  }

  // Network connection failure / unconfigured local dev environment
  if (
    message.includes("fetch failed") ||
    message.includes("failed to fetch") ||
    message.includes("enotfound") ||
    message.includes("connection refused")
  ) {
    return true;
  }

  // Operational errors (permission denied 42501, RLS violation, constraint violation, etc.) must NOT fall back
  return false;
}

// ---------------------------------------------------------------------------
// Worker-safe in-memory session store
//
// Cloudflare Workers run each HTTP request inside a V8 isolate. Module-level
// variables are NOT shared across requests that land on different isolates.
// Using `globalThis` persists the Map within a single isolate instance and
// across warm requests on the same isolate, dramatically reducing "session
// not found" failures caused by isolate recycling.
//
// This is a best-effort development / seed-fallback mechanism.
// Production session persistence is handled by the `osce_sessions` DB table
// (applied via migration 20261103000000_osce_practice_system.sql).
// ---------------------------------------------------------------------------
declare const globalThis: typeof global & { __osceSessions?: Map<string, OsceSessionDetail> };

function getInMemorySessions(): Map<string, OsceSessionDetail> {
  if (!globalThis.__osceSessions) {
    globalThis.__osceSessions = new Map<string, OsceSessionDetail>();
  }
  return globalThis.__osceSessions;
}

export class SupabaseOsceRepository {
  constructor(private readonly db: SupabaseClient<Database>) {}

  async getCategories(): Promise<OsceCategory[]> {
    try {
      const { data, error } = await this.db
        .from("osce_categories")
        .select("id, name, slug, description, icon, sort_order")
        .order("sort_order", { ascending: true });

      if (!error) {
        return (data ?? []).map((c) => ({
          id: c.id,
          name: c.name,
          slug: c.slug,
          description: c.description,
          icon: c.icon,
          sortOrder: c.sort_order,
        }));
      }

      if (!shouldFallbackToSeed(error)) {
        throw new Error(`OSCE repository error [${error.code || "UNKNOWN"}]: ${error.message}`);
      }
    } catch (err) {
      if (!shouldFallbackToSeed(err)) {
        throw err;
      }
    }

    return typedSeedData.categories.map((c) => ({
      id: c.id,
      name: c.name,
      slug: c.slug,
      description: c.description,
      icon: c.icon,
      sortOrder: c.sortOrder ?? 0,
    }));
  }

  async getProcedures(categoryId?: string): Promise<OsceProcedureSummary[]> {
    try {
      let query = this.db
        .from("osce_procedures")
        .select(
          "id, category_id, title, slug, station_number, examining_body, session_label, page_start, page_end, total_marks, pass_mark, time_limit_seconds, assessment_mode, is_published, osce_checklists(total_items)",
        )
        .eq("is_published", true);

      if (categoryId) {
        query = query.eq("category_id", categoryId);
      }

      const { data, error } = await query;
      if (!error) {
        return (data ?? []).map((p) => {
          const checklist = Array.isArray(p.osce_checklists)
            ? p.osce_checklists[0]
            : p.osce_checklists;
          return {
            id: p.id,
            categoryId: p.category_id,
            title: p.title,
            slug: p.slug,
            stationNumber: p.station_number,
            examiningBody: p.examining_body,
            sessionLabel: p.session_label,
            pageStart: p.page_start,
            pageEnd: p.page_end,
            totalMarks: Number(p.total_marks),
            passMark: Number(p.pass_mark),
            timeLimitSeconds: p.time_limit_seconds,
            assessmentMode: p.assessment_mode,
            isPublished: p.is_published,
            itemCount: checklist?.total_items ?? 10,
          };
        });
      }

      if (!shouldFallbackToSeed(error)) {
        throw new Error(`OSCE repository error [${error.code || "UNKNOWN"}]: ${error.message}`);
      }
    } catch (err) {
      if (!shouldFallbackToSeed(err)) {
        throw err;
      }
    }

    // Filter seed procedures
    const list = categoryId
      ? typedSeedData.procedures.filter((p) => p.category_id === categoryId)
      : typedSeedData.procedures;

    return list.map((p, idx) => ({
      id: `seed-proc-${idx + 1}-${p.slug}`,
      categoryId: p.category_id,
      title: p.title,
      slug: p.slug,
      stationNumber: p.station_number,
      examiningBody: p.examining_body,
      sessionLabel: p.session_label,
      pageStart: p.page_start,
      pageEnd: p.page_end,
      totalMarks: p.total_marks,
      passMark: Number((p.total_marks * 0.5).toFixed(2)),
      timeLimitSeconds: p.time_limit_seconds,
      assessmentMode: p.assessment_mode,
      isPublished: true,
      itemCount: p.items.length,
    }));
  }

  async getProcedureDetail(identifier: string): Promise<OsceProcedureDetail | null> {
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      identifier,
    );

    try {
      let query = this.db.from("osce_procedures").select(
        `id, category_id, title, slug, station_number, examining_body, session_label, page_start, page_end,
           total_marks, pass_mark, time_limit_seconds, instructions, scenario_prompt, assessment_mode, equipment_list,
           is_published, osce_checklists(id, version, total_items, is_active, osce_checklist_items(*))`,
      );

      if (isUuid) {
        query = query.eq("id", identifier);
      } else {
        query = query.eq("slug", identifier);
      }

      const { data, error } = await query.maybeSingle();

      if (!error) {
        // In an operational database, if the procedure is not found, return null directly.
        // Do not silently conceal missing production records with seed fallback.
        if (!data) {
          return null;
        }

        const checklists = Array.isArray(data.osce_checklists)
          ? data.osce_checklists
          : data.osce_checklists
            ? [data.osce_checklists]
            : [];
        const activeChecklist = checklists.find((c) => c.is_active) ?? checklists[0];

        const rawItems = activeChecklist?.osce_checklist_items ?? [];
        const items: OsceChecklistItem[] = (Array.isArray(rawItems) ? rawItems : []).map(
          (item) => ({
            id: item.id,
            checklistId: item.checklist_id,
            stepOrder: item.step_order,
            section: item.section,
            description: item.description,
            allocatedMarks: Number(item.allocated_marks),
            isCritical: item.is_critical,
            assessmentMode: item.assessment_mode,
            clinicalSynonyms: Array.isArray(item.clinical_synonyms)
              ? (item.clinical_synonyms as string[])
              : [],
            verificationCriteria: item.verification_criteria,
          }),
        );

        items.sort((a, b) => a.stepOrder - b.stepOrder);

        return {
          id: data.id,
          categoryId: data.category_id,
          title: data.title,
          slug: data.slug,
          stationNumber: data.station_number,
          examiningBody: data.examining_body,
          sessionLabel: data.session_label,
          pageStart: data.page_start,
          pageEnd: data.page_end,
          totalMarks: Number(data.total_marks),
          passMark: Number(data.pass_mark),
          timeLimitSeconds: data.time_limit_seconds,
          instructions: data.instructions,
          scenarioPrompt: data.scenario_prompt,
          assessmentMode: data.assessment_mode,
          equipmentList: Array.isArray(data.equipment_list)
            ? (data.equipment_list as string[])
            : [],
          isPublished: data.is_published,
          itemCount: items.length,
          checklist: {
            id: activeChecklist?.id ?? `chk-${data.id}`,
            version: activeChecklist?.version ?? 1,
            totalItems: items.length,
            items,
          },
        };
      }

      if (!shouldFallbackToSeed(error)) {
        throw new Error(`OSCE repository error [${error.code || "UNKNOWN"}]: ${error.message}`);
      }
    } catch (err) {
      if (!shouldFallbackToSeed(err)) {
        throw err;
      }
    }

    // Match in seed data by slug or generated id
    const seedProc = typedSeedData.procedures.find(
      (p) => p.slug === identifier || identifier.includes(p.slug),
    );

    if (!seedProc) return null;

    const checklistId = `chk-seed-${seedProc.slug}`;
    const items: OsceChecklistItem[] = seedProc.items.map((item, idx) => ({
      id: `item-seed-${seedProc.slug}-${idx + 1}`,
      checklistId,
      stepOrder: item.step_order,
      section: item.section,
      description: item.description,
      allocatedMarks: item.allocated_marks,
      isCritical: item.is_critical,
      assessmentMode: item.assessment_mode,
      clinicalSynonyms: item.clinical_synonyms,
      verificationCriteria: item.verification_criteria,
    }));

    return {
      id: `seed-proc-${seedProc.slug}`,
      categoryId: seedProc.category_id,
      title: seedProc.title,
      slug: seedProc.slug,
      stationNumber: seedProc.station_number,
      examiningBody: seedProc.examining_body,
      sessionLabel: seedProc.session_label,
      pageStart: seedProc.page_start,
      pageEnd: seedProc.page_end,
      totalMarks: seedProc.total_marks,
      passMark: Number((seedProc.total_marks * 0.5).toFixed(2)),
      timeLimitSeconds: seedProc.time_limit_seconds,
      instructions: seedProc.instructions,
      scenarioPrompt: seedProc.scenario_prompt,
      assessmentMode: seedProc.assessment_mode,
      equipmentList: seedProc.equipment_list,
      isPublished: true,
      itemCount: items.length,
      checklist: {
        id: checklistId,
        version: 1,
        totalItems: items.length,
        items,
      },
    };
  }

  async startSession(userId: string, input: StartSessionInput): Promise<OsceSessionDetail> {
    const procedure = await this.getProcedureDetail(input.procedureId);
    if (!procedure) {
      throw new Error(`OSCE Procedure ${input.procedureId} not found.`);
    }

    const sessionId = crypto.randomUUID();
    const now = new Date().toISOString();

    const evaluations: OsceSessionEvaluation[] = procedure.checklist.items.map((item) => ({
      id: crypto.randomUUID(),
      sessionId,
      itemId: item.id,
      status: "missed",
      marksAwarded: 0,
      confidence: 1.0,
      matchedText: null,
      evidenceType: input.mode === "practical" ? "physical" : "verbal",
      timestampSeconds: 0,
    }));

    const sessionDetail: OsceSessionDetail = {
      id: sessionId,
      userId,
      procedureId: procedure.id,
      procedureSlug: procedure.slug,
      checklistId: procedure.checklist.id,
      procedureTitle: procedure.title,
      stationNumber: procedure.stationNumber,
      examiningBody: procedure.examiningBody,
      mode: input.mode,
      status: "in_progress",
      startedAt: now,
      completedAt: null,
      timeSpentSeconds: 0,
      scoreObtained: 0,
      totalPossible: procedure.totalMarks,
      percentage: 0,
      passed: false,
      transcript: [],
      evaluations,
      checklistItems: procedure.checklist.items,
      clinicalFeedback: null,
    };

    getInMemorySessions().set(sessionId, sessionDetail);

    // Only attempt the DB INSERT when the procedure_id is a real UUID (i.e. the OSCE
    // tables exist and the procedure record came from the database, not the seed fallback).
    // Seed-fallback procedure IDs are not valid UUIDs and would fail the FK constraint,
    // producing a silent error that masks the real state of the system.
    const isRealUuid =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(procedure.id);
    if (isRealUuid) {
      try {
        await this.db.from("osce_sessions").insert({
          id: sessionId,
          user_id: userId,
          procedure_id: procedure.id,
          checklist_id: procedure.checklist.id,
          mode: input.mode,
          status: "in_progress",
          started_at: now,
          score_obtained: 0,
          total_possible: procedure.totalMarks,
          percentage: 0,
          transcript: [],
        });
      } catch {
        // Non-blocking — session already persisted in globalThis store above.
      }
    }

    return sessionDetail;
  }

  async getSession(userId: string, sessionId: string): Promise<OsceSessionDetail | null> {
    const inMem = getInMemorySessions().get(sessionId);
    if (inMem && inMem.userId === userId) {
      return inMem;
    }

    try {
      const { data, error } = await this.db
        .from("osce_sessions")
        .select(
          `id, user_id, procedure_id, checklist_id, mode, status, started_at, completed_at,
           time_spent_seconds, score_obtained, total_possible, percentage, transcript, clinical_feedback,
           osce_procedures(title, slug, station_number, examining_body, pass_mark)`,
        )
        .eq("id", sessionId)
        .eq("user_id", userId)
        .maybeSingle();

      if (!error && data) {
        const proc = Array.isArray(data.osce_procedures)
          ? data.osce_procedures[0]
          : data.osce_procedures;

        const procedureDetail = await this.getProcedureDetail(data.procedure_id);

        const { data: evalRows } = await this.db
          .from("osce_session_evaluations")
          .select("*")
          .eq("session_id", sessionId);

        const evaluations: OsceSessionEvaluation[] = (evalRows ?? []).map((e) => ({
          id: e.id,
          sessionId: e.session_id,
          itemId: e.item_id,
          status: e.status,
          marksAwarded: Number(e.marks_awarded),
          confidence: Number(e.confidence),
          matchedText: e.matched_text,
          evidenceType: e.evidence_type,
          timestampSeconds: e.timestamp_seconds,
        }));

        const detail: OsceSessionDetail = {
          id: data.id,
          userId: data.user_id,
          procedureId: data.procedure_id,
          procedureSlug: (proc as { slug?: string } | null)?.slug ?? procedureDetail?.slug ?? data.procedure_id,
          checklistId: data.checklist_id,
          procedureTitle: proc?.title ?? "OSCE Procedure",
          stationNumber: proc?.station_number ?? "Station",
          examiningBody: proc?.examining_body ?? "NMCN",
          mode: data.mode,
          status: data.status,
          startedAt: data.started_at,
          completedAt: data.completed_at,
          timeSpentSeconds: data.time_spent_seconds,
          scoreObtained: Number(data.score_obtained),
          totalPossible: Number(data.total_possible),
          percentage: Number(data.percentage),
          passed:
            Number(data.score_obtained) >= Number(proc?.pass_mark ?? data.total_possible * 0.5),
          transcript: (data.transcript as unknown as TranscriptUtterance[]) ?? [],
          evaluations,
          checklistItems: procedureDetail?.checklist.items ?? [],
          clinicalFeedback: (data.clinical_feedback as unknown as ClinicalFeedbackSection) ?? null,
        };

        getInMemorySessions().set(sessionId, detail);
        return detail;
      }
    } catch {
      // Fallback to in-memory
    }

    return null;
  }

  async updateSessionLiveProgress(
    sessionId: string,
    transcript: TranscriptUtterance[],
    evaluations: OsceSessionEvaluation[],
    score: number,
    percentage: number,
    timeSpentSeconds: number,
  ): Promise<void> {
    const session = getInMemorySessions().get(sessionId);
    if (session) {
      session.transcript = transcript;
      session.evaluations = evaluations;
      session.scoreObtained = score;
      session.percentage = percentage;
      session.timeSpentSeconds = timeSpentSeconds;
    }

    try {
      await this.db
        .from("osce_sessions")
        .update({
          transcript:
            transcript as unknown as Database["public"]["Tables"]["osce_sessions"]["Row"]["transcript"],
          score_obtained: score,
          percentage,
          time_spent_seconds: timeSpentSeconds,
        })
        .eq("id", sessionId);
    } catch {
      // non-blocking
    }
  }

  async completeSession(
    userId: string,
    sessionId: string,
    feedback: ClinicalFeedbackSection,
  ): Promise<OsceSessionDetail> {
    const session = await this.getSession(userId, sessionId);
    if (!session) {
      throw new Error("OSCE session not found.");
    }

    const completedAt = new Date().toISOString();
    const passed = session.scoreObtained >= session.totalPossible * 0.5;

    session.status = "completed";
    session.completedAt = completedAt;
    session.passed = passed;
    session.clinicalFeedback = feedback;

    getInMemorySessions().set(sessionId, session);

    try {
      await this.db
        .from("osce_sessions")
        .update({
          status: "completed",
          completed_at: completedAt,
          clinical_feedback:
            feedback as unknown as Database["public"]["Tables"]["osce_sessions"]["Row"]["clinical_feedback"],
        })
        .eq("id", sessionId)
        .eq("user_id", userId);
    } catch {
      // non-blocking
    }

    return session;
  }

  async getUserHistory(userId: string): Promise<OsceSessionDetail[]> {
    const memList = Array.from(getInMemorySessions().values()).filter(
      (s) => s.userId === userId && s.status === "completed",
    );

    try {
      const { data, error } = await this.db
        .from("osce_sessions")
        .select("id")
        .eq("user_id", userId)
        .eq("status", "completed")
        .order("created_at", { ascending: false });

      if (!error) {
        if (!data || data.length === 0) return [];
        const fullSessions = await Promise.all(data.map((row) => this.getSession(userId, row.id)));
        return fullSessions.filter((s): s is OsceSessionDetail => s !== null);
      }
    } catch {
      // Fall through to memory only in unmigrated local mode
    }

    return memList.sort(
      (a, b) => new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime(),
    );
  }
}
