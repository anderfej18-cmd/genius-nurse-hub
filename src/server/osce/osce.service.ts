import type { SupabaseOsceRepository } from "./osce.repository.server";
import { evaluateTranscriptAgainstChecklist } from "./osce.matching";
import type {
  OsceCategory,
  OsceProcedureSummary,
  OsceProcedureDetail,
  OsceSessionDetail,
  StartSessionInput,
  ProcessSpeechChunkInput,
  TranscriptUtterance,
  ClinicalFeedbackSection,
  EvaluationResult,
  OsceSessionEvaluation,
} from "./osce.types";

export class OsceService {
  constructor(private readonly repository: SupabaseOsceRepository) {}

  async getCategories(): Promise<OsceCategory[]> {
    return this.repository.getCategories();
  }

  async getProcedures(categoryId?: string): Promise<OsceProcedureSummary[]> {
    return this.repository.getProcedures(categoryId);
  }

  async getProcedure(identifier: string): Promise<OsceProcedureDetail | null> {
    return this.repository.getProcedureDetail(identifier);
  }

  async startSession(userId: string, input: StartSessionInput): Promise<OsceSessionDetail> {
    return this.repository.startSession(userId, input);
  }

  async getSession(userId: string, sessionId: string): Promise<OsceSessionDetail | null> {
    return this.repository.getSession(userId, sessionId);
  }

  async processSpeechChunk(
    userId: string,
    input: ProcessSpeechChunkInput,
  ): Promise<EvaluationResult> {
    const session = await this.repository.getSession(userId, input.sessionId);
    if (!session) {
      throw new Error(`OSCE Session ${input.sessionId} not found`);
    }

    if (session.status !== "in_progress") {
      throw new Error(`OSCE Session ${input.sessionId} is already ${session.status}`);
    }

    // Add utterance
    const utterance: TranscriptUtterance = {
      id: crypto.randomUUID(),
      speaker: "candidate",
      text: input.text.trim(),
      timestampSeconds: input.timestampSeconds,
    };

    const updatedTranscript = [...session.transcript, utterance];
    const utterancesText = updatedTranscript.map((u) => u.text);

    // Existing awarded item IDs
    const existingAwarded = new Set(
      session.evaluations.filter((e) => e.status === "awarded").map((e) => e.itemId),
    );

    const { evaluations, newlyAwardedIds } = evaluateTranscriptAgainstChecklist(
      session.checklistItems,
      utterancesText,
      session.mode,
      existingAwarded,
    );

    const fullEvaluations: OsceSessionEvaluation[] = evaluations.map((ev) => {
      const existing = session.evaluations.find((e) => e.itemId === ev.itemId);
      return {
        id: existing?.id ?? crypto.randomUUID(),
        sessionId: session.id,
        itemId: ev.itemId,
        status: ev.status,
        marksAwarded: ev.marksAwarded,
        confidence: ev.confidence,
        matchedText: ev.matchedText,
        evidenceType: ev.evidenceType,
        timestampSeconds: input.timestampSeconds,
      };
    });

    // Calculate total score
    let totalScore = 0;
    let awardedCount = 0;
    for (const ev of fullEvaluations) {
      if (ev.status === "awarded") {
        totalScore += ev.marksAwarded;
        awardedCount++;
      } else if (ev.status === "partially_awarded") {
        totalScore += ev.marksAwarded;
      }
    }

    const percentage =
      session.totalPossible > 0
        ? Number(((totalScore / session.totalPossible) * 100).toFixed(1))
        : 0;

    await this.repository.updateSessionLiveProgress(
      session.id,
      updatedTranscript,
      fullEvaluations,
      totalScore,
      percentage,
      input.timestampSeconds,
    );

    return {
      evaluations: fullEvaluations,
      awardedCount,
      totalScore,
      newlyAwardedItemIds: newlyAwardedIds,
    };
  }

  async endSession(userId: string, sessionId: string): Promise<OsceSessionDetail> {
    const session = await this.repository.getSession(userId, sessionId);
    if (!session) {
      throw new Error(`OSCE Session ${sessionId} not found`);
    }

    // Generate clinical feedback
    const strengths: string[] = [];
    const omissions: string[] = [];
    const criticalSafetyAlerts: string[] = [];
    const nextSteps: string[] = [];

    for (const item of session.checklistItems) {
      const evaluation = session.evaluations.find((e) => e.itemId === item.id);
      if (evaluation?.status === "awarded") {
        strengths.push(`${item.description} (+${item.allocatedMarks} mk)`);
      } else {
        const omissionDesc = `${item.description} (${item.allocatedMarks} mk)`;
        omissions.push(omissionDesc);
        if (item.isCritical) {
          criticalSafetyAlerts.push(
            `CRITICAL STEP MISSED: ${item.description} — In NMCN licensing examinations, omitting this safety-critical step can result in failure or significant station penalty.`,
          );
        }
      }
    }

    const passed = session.scoreObtained >= session.totalPossible * 0.5;
    const summary = passed
      ? `You achieved ${session.scoreObtained.toFixed(2)} / ${session.totalPossible.toFixed(2)} marks (${session.percentage.toFixed(1)}%). Excellent clinical procedure demonstration satisfying the pass threshold.`
      : `You achieved ${session.scoreObtained.toFixed(2)} / ${session.totalPossible.toFixed(2)} marks (${session.percentage.toFixed(1)}%). Review the missed checklist items and critical safety guidelines below.`;

    if (omissions.length > 0) {
      nextSteps.push(
        `Review the full checklist steps and practice verbalizing your clinical rationale aloud.`,
      );
      nextSteps.push(
        `Focus on the ${criticalSafetyAlerts.length} critical safety step(s) highlighted to ensure clinical safety in the exam.`,
      );
    } else {
      nextSteps.push(`Outstanding performance! You completed all criteria on this station.`);
    }

    const feedback: ClinicalFeedbackSection = {
      title: `${session.procedureTitle} — Assessment Feedback`,
      summary,
      strengths,
      omissions,
      criticalSafetyAlerts,
      nextSteps,
    };

    return this.repository.completeSession(userId, sessionId, feedback);
  }

  async getUserHistory(userId: string): Promise<OsceSessionDetail[]> {
    return this.repository.getUserHistory(userId);
  }
}
