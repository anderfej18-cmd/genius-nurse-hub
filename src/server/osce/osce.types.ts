import type { Database } from "@/integrations/supabase/types";

export type OsceCategoryRow = Database["public"]["Tables"]["osce_categories"]["Row"];
export type OsceProcedureRow = Database["public"]["Tables"]["osce_procedures"]["Row"];
export type OsceChecklistRow = Database["public"]["Tables"]["osce_checklists"]["Row"];
export type OsceChecklistItemRow = Database["public"]["Tables"]["osce_checklist_items"]["Row"];
export type OsceSessionRow = Database["public"]["Tables"]["osce_sessions"]["Row"];
export type OsceSessionEvaluationRow =
  Database["public"]["Tables"]["osce_session_evaluations"]["Row"];

export type {
  AssessmentMode,
  SessionMode,
  SessionStatus,
  EvaluationStatus,
  EvidenceType,
  OsceCategory,
  OsceProcedureSummary,
  OsceChecklistItem,
  OsceProcedureDetail,
  TranscriptUtterance,
  OsceSessionEvaluation,
  ClinicalFeedbackSection,
  OsceSessionDetail,
  StartSessionInput,
  ProcessSpeechChunkInput,
  EvaluationResult,
} from "@/lib/osce";
