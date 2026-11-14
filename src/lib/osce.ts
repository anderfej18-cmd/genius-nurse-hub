export type AssessmentMode = "oral" | "practical" | "both";
export type SessionMode = "oral" | "practical";
export type SessionStatus = "in_progress" | "completed" | "abandoned";
export type EvaluationStatus = "awarded" | "missed" | "partially_awarded";
export type EvidenceType = "verbal" | "physical" | "examiner_override";

export interface OsceCategory {
  id: string;
  name: string;
  slug: string;
  description: string;
  icon: string;
  sortOrder: number;
}

export interface OsceProcedureSummary {
  id: string;
  categoryId: string;
  title: string;
  slug: string;
  stationNumber: string;
  examiningBody: string;
  sessionLabel: string;
  pageStart: number;
  pageEnd: number;
  totalMarks: number;
  passMark: number;
  timeLimitSeconds: number;
  assessmentMode: AssessmentMode;
  isPublished: boolean;
  itemCount: number;
}

export interface OsceChecklistItem {
  id: string;
  checklistId: string;
  stepOrder: number;
  section: string;
  description: string;
  allocatedMarks: number;
  isCritical: boolean;
  assessmentMode: AssessmentMode;
  clinicalSynonyms: string[];
  verificationCriteria: string;
}

export interface OsceProcedureDetail extends OsceProcedureSummary {
  instructions: string;
  scenarioPrompt: string;
  equipmentList: string[];
  checklist: {
    id: string;
    version: number;
    totalItems: number;
    items: OsceChecklistItem[];
  };
}

export interface TranscriptUtterance {
  id: string;
  speaker: "candidate" | "examiner" | "patient";
  text: string;
  timestampSeconds: number;
}

export interface OsceSessionEvaluation {
  id: string;
  sessionId: string;
  itemId: string;
  status: EvaluationStatus;
  marksAwarded: number;
  confidence: number;
  matchedText: string | null;
  evidenceType: EvidenceType;
  timestampSeconds: number;
}

export interface ClinicalFeedbackSection {
  title: string;
  summary: string;
  strengths: string[];
  omissions: string[];
  criticalSafetyAlerts: string[];
  nextSteps: string[];
}

export interface OsceSessionDetail {
  id: string;
  userId: string;
  procedureId: string;
  /** URL-safe slug for the procedure — use this for navigation links (Try Again, etc.) */
  procedureSlug: string;
  checklistId: string;
  procedureTitle: string;
  stationNumber: string;
  examiningBody: string;
  mode: SessionMode;
  status: SessionStatus;
  startedAt: string;
  completedAt: string | null;
  timeSpentSeconds: number;
  scoreObtained: number;
  totalPossible: number;
  percentage: number;
  passed: boolean;
  transcript: TranscriptUtterance[];
  evaluations: OsceSessionEvaluation[];
  checklistItems: OsceChecklistItem[];
  clinicalFeedback: ClinicalFeedbackSection | null;
}

export interface StartSessionInput {
  procedureId: string;
  mode: SessionMode;
}

export interface ProcessSpeechChunkInput {
  sessionId: string;
  text: string;
  timestampSeconds: number;
}

export interface EvaluationResult {
  evaluations: OsceSessionEvaluation[];
  awardedCount: number;
  totalScore: number;
  newlyAwardedItemIds: string[];
}
