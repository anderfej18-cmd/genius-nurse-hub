import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database, Json } from "@/integrations/supabase/types";
import { createHash } from "crypto";

type ExamType = Database["public"]["Enums"]["exam_type"];
type SnapshotQuestion = {
  question_text: string;
  option_a: string;
  option_b: string;
  option_c: string;
  option_d: string;
  correct_answer: string;
  rationale: string | null;
  source_question_id?: string | null;
  source_kind: "existing" | "custom";
};

const assertAdmin = async (context: { supabase: any; userId: string }) => {
  const { data, error } = await context.supabase.rpc("is_any_admin", { _user_id: context.userId });
  if (error || !data) throw new Error("You are not authorized to manage custom tests.");
};

const digest = (value: string) => createHash("sha256").update(value).digest("hex");

export const createCustomTest = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: {
    title: string; description: string; examType: ExamType; sourceMode: "existing" | "upload";
    durationMinutes: number; expiresAt: string; tokenHash: string; questions: SnapshotQuestion[];
  }) => data)
  .handler(async ({ data, context }) => {
    await assertAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    if (!data.title.trim() || data.questions.length < 1 || data.questions.length > 250) throw new Error("Enter a title and between 1 and 250 questions.");
    if (data.durationMinutes < 10 || data.durationMinutes > 180) throw new Error("Duration must be between 10 minutes and 3 hours.");
    if (new Date(data.expiresAt).getTime() <= Date.now()) throw new Error("Link expiry must be in the future.");
    const { data: test, error } = await supabaseAdmin.from("custom_tests").insert({
      owner_id: context.userId,
      title: data.title.trim(),
      description: data.description.trim() || null,
      exam_type: data.examType,
      source_mode: data.sourceMode,
      duration_minutes: data.durationMinutes,
      expires_at: data.expiresAt,
      token_hash: data.tokenHash,
      status: "published",
    }).select("id").single();
    if (error) throw new Error(error.message);
    const rows = data.questions.map((question, position) => ({
      custom_test_id: test.id,
      source_question_id: question.source_question_id ?? null,
      source_kind: question.source_kind,
      question_text: question.question_text,
      option_a: question.option_a,
      option_b: question.option_b,
      option_c: question.option_c,
      option_d: question.option_d,
      correct_answer: question.correct_answer.toUpperCase(),
      rationale: question.rationale,
      position,
    }));
    const { error: questionsError } = await supabaseAdmin.from("custom_test_questions").insert(rows);
    if (questionsError) {
      await supabaseAdmin.from("custom_tests").delete().eq("id", test.id);
      throw new Error(questionsError.message);
    }
    return { id: test.id };
  });

export const listCustomTests = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.from("custom_tests")
      .select("id, title, description, exam_type, source_mode, duration_minutes, expires_at, status, created_at, owner_id")
      .eq("owner_id", context.userId).order("created_at", { ascending: false });
    if (error) throw new Error(error.message);
    const tests = data ?? [];
    const summaries = await Promise.all(tests.map(async (test) => {
      const { data: analytics, error: analyticsError } = await supabaseAdmin.rpc("get_custom_test_analytics", { _custom_test_id: test.id });
      if (analyticsError) throw new Error(analyticsError.message);
      const { data: attempts, error: attemptsError } = await supabaseAdmin.from("custom_test_attempts")
        .select("id, email, score_pct, correct_count, total_questions, completed_at")
        .eq("custom_test_id", test.id).eq("status", "completed").order("score_pct", { ascending: false }).limit(100);
      if (attemptsError) throw new Error(attemptsError.message);
      const { count } = await supabaseAdmin.from("custom_test_questions").select("id", { count: "exact", head: true }).eq("custom_test_id", test.id);
      return { ...test, question_count: count ?? 0, analytics: analytics?.[0] ?? null, attempts: attempts ?? [] };
    }));
    return summaries;
  });

export const getSharedTest = createServerFn({ method: "POST" })
  .inputValidator((data: { tokenHash: string }) => data)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: rows, error } = await supabaseAdmin.rpc("get_custom_test_by_token", { _token_hash: data.tokenHash });
    if (error) throw new Error(error.message);
    if (!rows?.length) return { expired: true as const, test: null, questions: [] };
    const first = rows[0];
    return {
      expired: false as const,
      test: { id: first.test_id, title: first.title, description: first.description, exam_type: first.exam_type, duration_minutes: first.duration_minutes, expires_at: first.expires_at },
      questions: rows.map((row) => ({ id: row.question_id, position: row.question_position, question_text: row.question_text, option_a: row.option_a, option_b: row.option_b, option_c: row.option_c, option_d: row.option_d })),
    };
  });

export const startSharedTest = createServerFn({ method: "POST" })
  .inputValidator((data: { tokenHash: string; email: string; accessKey: string }) => data)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const email = data.email.trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(email)) throw new Error("Enter a valid email address.");
    if (data.accessKey.length < 32) throw new Error("Invalid attempt key.");
    const { data: attemptRows, error } = await supabaseAdmin.rpc("start_custom_test_attempt", {
      _token_hash: data.tokenHash, _email: email, _access_hash: digest(data.accessKey),
    });
    if (error) throw new Error(error.message);
    const attempt = attemptRows?.[0];
    if (!attempt) throw new Error("Could not start this test.");
    return { attemptId: attempt.attempt_id, durationMinutes: attempt.duration_minutes, totalQuestions: attempt.total_questions, accessKey: data.accessKey };
  });

export const submitSharedTest = createServerFn({ method: "POST" })
  .inputValidator((data: { attemptId: string; accessKey: string; answers: Array<{ question_id: string; user_answer: string | null }> }) => data)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: scores, error } = await supabaseAdmin.rpc("submit_custom_test_attempt", {
      _attempt_id: data.attemptId, _access_hash: digest(data.accessKey), _answers: data.answers as unknown as Json,
    });
    if (error) throw new Error(error.message);
    const score = scores?.[0];
    if (!score) throw new Error("Could not submit this test.");
    const { data: results, error: resultError } = await supabaseAdmin.rpc("get_custom_test_attempt_results", {
      _attempt_id: data.attemptId, _access_hash: digest(data.accessKey),
    });
    if (resultError) throw new Error(resultError.message);
    return { score: score.score_pct, correct: score.correct_count, total: score.total_questions, results: results ?? [] };
  });

export const claimSharedTestAttempt = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: { attemptId: string; accessKey: string }) => data)
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: updated, error } = await supabaseAdmin.from("custom_test_attempts")
      .update({ user_id: context.userId }).eq("id", data.attemptId).eq("access_hash", digest(data.accessKey)).is("user_id", null).select("id");
    if (error) throw new Error(error.message);
    return { claimed: (updated?.length ?? 0) > 0 };
  });

export const republishCustomTest = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: { testId: string; tokenHash: string; expiresAt: string }) => data)
  .handler(async ({ data, context }) => {
    await assertAdmin(context);
    if (new Date(data.expiresAt).getTime() <= Date.now()) throw new Error("Expiry must be in the future.");
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: updated, error } = await supabaseAdmin.from("custom_tests")
      .update({ status: "published", expires_at: data.expiresAt, token_hash: data.tokenHash })
      .eq("id", data.testId).eq("owner_id", context.userId).select("id");
    if (error) throw new Error(error.message);
    if (!updated?.length) throw new Error("Test not found or not owned by you.");
    return { ok: true };
  });

export const importCustomTestQuestions = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: { testId: string; topic: string; examType: ExamType }) => data)
  .handler(async ({ data, context }) => {
    await assertAdmin(context);
    if (!data.topic.trim()) throw new Error("Enter the destination subcategory.");
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: test, error: testError } = await supabaseAdmin.from("custom_tests").select("id").eq("id", data.testId).eq("owner_id", context.userId).maybeSingle();
    if (testError || !test) throw new Error("Test not found or not owned by you.");
    const { data: questions, error } = await supabaseAdmin.from("custom_test_questions").select("question_text, option_a, option_b, option_c, option_d, correct_answer, rationale")
      .eq("custom_test_id", data.testId).eq("imported_to_bank", false);
    if (error) throw new Error(error.message);
    if (!questions?.length) return { count: 0 };
    const { error: insertError } = await supabaseAdmin.from("questions").insert(questions.map((question) => ({ ...question, exam_type: data.examType, topic: data.topic.trim(), created_by: context.userId })));
    if (insertError) throw new Error(insertError.message);
    const { error: updateError } = await supabaseAdmin.from("custom_test_questions").update({ imported_to_bank: true, imported_at: new Date().toISOString() }).eq("custom_test_id", data.testId).eq("imported_to_bank", false);
    if (updateError) throw new Error(updateError.message);
    return { count: questions.length };
  });