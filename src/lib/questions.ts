export interface QuestionFields {
  question_text: string | null;
  option_a: string | null;
  option_b: string | null;
  option_c: string | null;
  option_d: string | null;
  correct_answer: string | null;
}

const OPTION_KEYS = ["option_a", "option_b", "option_c", "option_d"] as const;

export function questionIssues(question: QuestionFields): string[] {
  const issues: string[] = [];
  if (!question.question_text?.trim()) issues.push("question text");
  for (const key of OPTION_KEYS) {
    if (!question[key]?.trim()) issues.push(`${key.replace("option_", "Option ").toUpperCase()}`);
  }
  if (!question.correct_answer || !["A", "B", "C", "D"].includes(question.correct_answer.toUpperCase())) {
    issues.push("correct answer");
  }
  return issues;
}

export function isCompleteQuestion(question: QuestionFields): boolean {
  return questionIssues(question).length === 0;
}