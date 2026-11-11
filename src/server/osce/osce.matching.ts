import type { OsceChecklistItem, EvaluationStatus, EvidenceType } from "./osce.types";

export interface MatchEvaluation {
  itemId: string;
  status: EvaluationStatus;
  marksAwarded: number;
  confidence: number;
  matchedText: string | null;
  evidenceType: EvidenceType;
}

const NEGATION_PATTERNS = [
  /\b(?:did\s*not|didn['’]?t|didnt|do\s*not|don['’]?t|dont|does\s*not|doesn['’]?t|doesnt)\b/i,
  /\b(?:would\s*not|wouldn['’]?t|wouldnt|will\s*not|won['’]?t|wont|should\s*not|shouldn['’]?t|shouldnt|must\s*not|mustn['’]?t|mustnt)\b/i,
  /\b(?:forgot\s*to|failed\s*to|neglected\s*to|omitted\s*to)\b/i,
  /\b(?:could\s*not|couldn['’]?t|couldnt|unable\s*to|cannot|can['’]?t|cant)\b/i,
  /\b(?:never|without|not\s+to|no\s+longer)\b/i,
  /\b(?:should\s*have|ought\s*to\s*have)\b/i, // Retrospective regret
];

/**
 * Normalizes text for clinical comparison:
 * Lowercases, removes punctuation (except decimals/numbers), strips excess whitespace.
 */
export function normalizeClinicalText(text: string): string {
  return text
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9\s/.]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Checks if a specific phrase occurrence in the text is preceded or governed by a negation phrase
 * within its governing sentence or clause boundary.
 */
export function isNegatedContext(fullText: string, matchedPhrase: string): boolean {
  const lowerText = fullText.toLowerCase();
  const lowerPhrase = matchedPhrase.toLowerCase().replace(/['’]/g, "").trim();
  const cleanText = lowerText.replace(/['’]/g, "");

  let phraseIndex = cleanText.indexOf(lowerPhrase);
  if (phraseIndex === -1) {
    const normPhrase = lowerPhrase
      .replace(/[^a-z0-9\s/.]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    const normText = cleanText.replace(/[^a-z0-9\s/.]/g, " ").replace(/\s+/g, " ");
    phraseIndex = normText.indexOf(normPhrase);

    if (phraseIndex === -1) {
      const tokens = normPhrase.split(/\s+/).filter((t) => t.length > 2);
      for (const token of tokens) {
        const idx = cleanText.indexOf(token);
        if (idx !== -1) {
          phraseIndex = idx;
          break;
        }
      }
      if (phraseIndex === -1) return false;
    }
  }

  // Find the start of the clause governing this phrase.
  // Boundary markers: punctuation (. ; ! ? \n) or contrastive / retraction connectors.
  const preText = cleanText.slice(0, phraseIndex);
  const boundaryRegex =
    /(?:[.;!?\n]|\b(?:but|however|whereas|although|though|rather\s+than)\b|\b(?:wait\s+no|sorry\s+no|scratch\s+that|correction|i\s+mean)\b)/gi;

  let clauseStart = 0;
  let match: RegExpExecArray | null;
  while ((match = boundaryRegex.exec(preText)) !== null) {
    clauseStart = match.index + match[0].length;
  }

  const leadingContext = preText.slice(clauseStart);

  for (const pattern of NEGATION_PATTERNS) {
    if (pattern.test(leadingContext)) {
      return true;
    }
  }

  // Check immediate trailing negation in the same clause: e.g. "wash hands was not done" or "wait no, sorry"
  const postText = cleanText.slice(phraseIndex + lowerPhrase.length);
  const endBoundaryMatch = /[.;!?\n]|\b(?:but|however)\b/i.exec(postText);
  const trailingClause = endBoundaryMatch
    ? postText.slice(0, endBoundaryMatch.index)
    : postText.slice(0, 50);

  if (/\b(?:was\s*not\s*done|not\s*performed|is\s*omitted|not\s*given)\b/i.test(trailingClause)) {
    return true;
  }
  if (/\b(?:wait\s*no|sorry\s*no|scratch\s*that|not\s*that)\b/i.test(trailingClause)) {
    return true;
  }

  return false;
}

/**
 * Parses clinical components from synonyms array, supporting pipe-separated synonyms per component.
 */
export function parseClinicalComponents(synonyms: string[]): string[][] {
  return synonyms.map((syn) =>
    syn
      .split("|")
      .map((s) => s.trim())
      .filter(Boolean),
  );
}

/**
 * Calculates token overlap score between two clinical phrases.
 */
export function calculateTokenOverlap(spoken: string, candidate: string): number {
  const spokenTokens = new Set(spoken.split(/\s+/).filter((t) => t.length > 2));
  const candidateTokens = candidate.split(/\s+/).filter((t) => t.length > 2);

  if (candidateTokens.length === 0) return 0;

  let matchCount = 0;
  for (const token of candidateTokens) {
    if (spokenTokens.has(token)) {
      matchCount++;
    }
  }

  return matchCount / candidateTokens.length;
}

/**
 * Evaluates candidate spoken text against a single OSCE checklist item.
 */
export function evaluateItemMatch(
  item: OsceChecklistItem,
  transcriptWindow: string,
  mode: "oral" | "practical",
): MatchEvaluation | null {
  const normalizedWindow = normalizeClinicalText(transcriptWindow);
  if (!normalizedWindow) return null;

  // If item is practical-only and mode is oral, speech alone cannot fulfill it without verbal protocol declaration
  if (item.assessmentMode === "practical" && mode === "oral") {
    // Requires explicit verbal statement of technique
  }

  const synonyms = [
    item.description,
    ...item.clinicalSynonyms,
    ...(item.verificationCriteria ? [item.verificationCriteria] : []),
  ];

  let bestScore = 0;
  let bestMatchedPhrase: string | null = null;
  let isNegated = false;
  let isProportionalMatch = false;
  let proportionalAward = 0;

  // Proportional multi-component item evaluation
  // When an item represents a compound clinical step (allocatedMarks > 1.0 and >= 3 criteria),
  // award marks proportionately to distinct articulated clinical components (not inflating across synonyms).
  const isMultiComponent = item.clinicalSynonyms.length >= 3 && item.allocatedMarks > 1.0;
  if (isMultiComponent) {
    const components = parseClinicalComponents(item.clinicalSynonyms);
    const matchedComponents: string[] = [];

    for (const componentVariants of components) {
      // A component is satisfied if ANY of its synonym variants is matched and not negated
      const matchedVariant = componentVariants.find((variant) => {
        const nVariant = normalizeClinicalText(variant);
        const matches =
          normalizedWindow.includes(nVariant) ||
          calculateTokenOverlap(normalizedWindow, nVariant) >= 0.7;
        return matches && !isNegatedContext(transcriptWindow, variant);
      });

      if (matchedVariant) {
        matchedComponents.push(matchedVariant);
      }
    }

    const totalComponents = components.length;
    const matchedCount = matchedComponents.length;
    const coverage = totalComponents > 0 ? matchedCount / totalComponents : 0;

    if (coverage >= 0.75) {
      // Substantial articulation (>= 75% of components articulated) -> full award
      bestScore = 1.0;
      bestMatchedPhrase = matchedComponents.join(", ");
    } else if (matchedCount >= 2 && coverage >= 0.4) {
      // Strictly proportionate partial award for multi-component steps
      isProportionalMatch = true;
      proportionalAward = Number((item.allocatedMarks * coverage).toFixed(2));
      bestScore = coverage;
      bestMatchedPhrase = matchedComponents.join(", ");
    } else {
      // Insufficient coverage (only 1 isolated component mentioned out of many).
      // Reliable proportional scoring cannot be guaranteed without mark inflation.
      // Explicitly return null rather than falling through to match single components as full synonyms.
      return null;
    }
  }

  if (bestScore === 0) {
    for (const synonym of synonyms) {
      const normSynonym = normalizeClinicalText(synonym);
      if (!normSynonym) continue;

      // Direct substring match
      if (normalizedWindow.includes(normSynonym)) {
        const negated = isNegatedContext(transcriptWindow, synonym);
        if (negated) {
          isNegated = true;
          continue;
        }
        bestScore = 1.0;
        bestMatchedPhrase = synonym;
        break;
      }

      // Token overlap match
      const overlap = calculateTokenOverlap(normalizedWindow, normSynonym);
      if (overlap > bestScore) {
        const negated = isNegatedContext(transcriptWindow, synonym);
        if (!negated) {
          bestScore = overlap;
          bestMatchedPhrase = synonym;
        } else {
          isNegated = true;
        }
      }
    }
  }

  // If negated and no positive assertion found, return missed/no award
  if (isNegated && bestScore < 0.7) {
    return null;
  }

  // Thresholds for awarding
  if (bestScore >= 0.65 && !isProportionalMatch) {
    return {
      itemId: item.id,
      status: "awarded",
      marksAwarded: item.allocatedMarks,
      confidence: Math.min(1.0, Number((bestScore + 0.1).toFixed(2))),
      matchedText: bestMatchedPhrase,
      evidenceType: "verbal",
    };
  }

  if (isProportionalMatch && proportionalAward > 0) {
    return {
      itemId: item.id,
      status: "partially_awarded",
      marksAwarded: proportionalAward,
      confidence: Number(bestScore.toFixed(2)),
      matchedText: bestMatchedPhrase,
      evidenceType: "verbal",
    };
  }

  return null;
}

/**
 * Evaluates an entire checklist against an accumulation of transcript utterances.
 */
export function evaluateTranscriptAgainstChecklist(
  items: OsceChecklistItem[],
  utterances: string[],
  mode: "oral" | "practical",
  existingAwardedIds = new Set<string>(),
): {
  evaluations: MatchEvaluation[];
  newlyAwardedIds: string[];
} {
  const fullText = utterances.join(" ");
  const evaluations: MatchEvaluation[] = [];
  const newlyAwardedIds: string[] = [];

  for (const item of items) {
    // If already fully awarded, preserve it
    if (existingAwardedIds.has(item.id)) {
      evaluations.push({
        itemId: item.id,
        status: "awarded",
        marksAwarded: item.allocatedMarks,
        confidence: 1.0,
        matchedText: item.description,
        evidenceType: "verbal",
      });
      continue;
    }

    const match = evaluateItemMatch(item, fullText, mode);
    if (match && match.status === "awarded") {
      evaluations.push(match);
      newlyAwardedIds.push(item.id);
    } else if (match && match.status === "partially_awarded") {
      evaluations.push(match);
    } else {
      evaluations.push({
        itemId: item.id,
        status: "missed",
        marksAwarded: 0,
        confidence: 1.0,
        matchedText: null,
        evidenceType: "verbal",
      });
    }
  }

  return {
    evaluations,
    newlyAwardedIds,
  };
}
