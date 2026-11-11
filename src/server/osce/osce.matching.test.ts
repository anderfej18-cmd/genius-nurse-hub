import { describe, expect, it } from "vitest";
import {
  calculateTokenOverlap,
  evaluateItemMatch,
  evaluateTranscriptAgainstChecklist,
  isNegatedContext,
  normalizeClinicalText,
} from "./osce.matching";
import type { OsceChecklistItem } from "./osce.types";

describe("OSCE Clinical Text Normalization", () => {
  it("lowercases and strips punctuation while preserving numbers", () => {
    expect(normalizeClinicalText("Wash & Dry Hands (¼ mk)!")).toBe("wash dry hands mk");
    expect(normalizeClinicalText("Oxytocin 10 IU I.M.")).toBe("oxytocin 10 iu i.m.");
  });
});

describe("Negation and Regret Detection", () => {
  it("detects direct negations (did not, couldn't, forgot to)", () => {
    expect(
      isNegatedContext("I did not wash my hands before touching the patient", "wash my hands"),
    ).toBe(true);
    expect(
      isNegatedContext("I forgot to check the expiry date of the drug", "check the expiry date"),
    ).toBe(true);
    expect(
      isNegatedContext("I could not aspirate for blood return", "aspirate for blood return"),
    ).toBe(true);
  });

  it("detects retrospective regret", () => {
    expect(
      isNegatedContext(
        "I should have verified the two identifiers",
        "verified the two identifiers",
      ),
    ).toBe(true);
  });

  it("does not flag positive assertions", () => {
    expect(
      isNegatedContext("I will now wash my hands thoroughly with soap and water", "wash my hands"),
    ).toBe(false);
    expect(
      isNegatedContext(
        "I verified the patient identity and checked the expiry date",
        "checked the expiry date",
      ),
    ).toBe(false);
  });
});

describe("Token Overlap Scoring", () => {
  it("scores exact matches as 1.0", () => {
    const score = calculateTokenOverlap("i will wash and dry my hands", "wash and dry hands");
    expect(score).toBeGreaterThan(0.7);
  });

  it("scores disjoint phrases as 0", () => {
    const score = calculateTokenOverlap("administer enema slowly", "measure blood pressure");
    expect(score).toBe(0);
  });
});

describe("OSCE Item Evaluation", () => {
  const sampleItem: OsceChecklistItem = {
    id: "item-1",
    checklistId: "chk-1",
    stepOrder: 1,
    section: "Preparation & Equipment",
    description: "Wash and dry hands thoroughly or perform hand hygiene",
    allocatedMarks: 0.5,
    isCritical: true,
    assessmentMode: "both",
    clinicalSynonyms: ["wash hands", "dry hands", "hand hygiene", "alcohol rub"],
    verificationCriteria: "Candidate performs or states hand washing with soap and water",
  };

  it("awards marks when positive statement matches", () => {
    const transcript =
      "Good morning. I will wash my hands and dry them thoroughly with a clean towel.";
    const evalResult = evaluateItemMatch(sampleItem, transcript, "oral");
    expect(evalResult).not.toBeNull();
    expect(evalResult?.status).toBe("awarded");
    expect(evalResult?.marksAwarded).toBe(0.5);
  });

  it("does not award marks when statement is negated", () => {
    const transcript = "I forgot to wash hands because I was in a rush.";
    const evalResult = evaluateItemMatch(sampleItem, transcript, "oral");
    expect(evalResult).toBeNull();
  });

  it("handles clinically equivalent wording through synonyms", () => {
    const transcript = "I will perform hand hygiene with alcohol rub before patient contact.";
    const evalResult = evaluateItemMatch(sampleItem, transcript, "oral");
    expect(evalResult).not.toBeNull();
    expect(evalResult?.status).toBe("awarded");
    expect(evalResult?.marksAwarded).toBe(0.5);
  });

  it("handles pauses, interruptions, and filler words", () => {
    const transcript = "Um, uh, well... first I will, um, wash and dry my hands thoroughly.";
    const evalResult = evaluateItemMatch(sampleItem, transcript, "oral");
    expect(evalResult).not.toBeNull();
    expect(evalResult?.status).toBe("awarded");
  });

  it("handles background noise and extraneous conversational tokens", () => {
    const transcript =
      "Background noise door opens nurse steps in. Okay candidate states wash and dry hands with soap and water.";
    const evalResult = evaluateItemMatch(sampleItem, transcript, "oral");
    expect(evalResult).not.toBeNull();
    expect(evalResult?.status).toBe("awarded");
  });

  it("handles self-correction: student corrects themselves to the right procedure", () => {
    const oxytocinItem: OsceChecklistItem = {
      id: "item-amtsl-oxytocin",
      checklistId: "chk-amtsl",
      stepOrder: 2,
      section: "Procedure Execution",
      description: "Administer 10 IU of Oxytocin intramuscularly (IM) within 1 minute of birth",
      allocatedMarks: 1.0,
      isCritical: true,
      assessmentMode: "both",
      clinicalSynonyms: ["oxytocin 10 iu", "administer oxytocin im", "10 units oxytocin"],
      verificationCriteria: "Administers or states 10 IU Oxytocin IM",
    };

    const transcript =
      "I will give 5 units of ergometrine, wait no, sorry, I will administer 10 IU of Oxytocin IM.";
    const evalResult = evaluateItemMatch(oxytocinItem, transcript, "oral");
    expect(evalResult).not.toBeNull();
    expect(evalResult?.status).toBe("awarded");
    expect(evalResult?.marksAwarded).toBe(1.0);
  });

  it("does not award marks for statements admitting step was forgotten", () => {
    const transcript =
      "I omitted to check the patient's identity band and forgot to verify the expiry date.";
    const evalResult = evaluateItemMatch(sampleItem, transcript, "oral");
    expect(evalResult).toBeNull();
  });

  it("handles Nigerian nursing terminology in equipment and procedure steps", () => {
    const dressingItem: OsceChecklistItem = {
      id: "item-dressing-1",
      checklistId: "chk-dressing",
      stepOrder: 3,
      section: "Preparation & Equipment",
      description: "Prepare sterile trolley with gallipot, receiver, and Cheatle forceps",
      allocatedMarks: 1.0,
      isCritical: false,
      assessmentMode: "both",
      clinicalSynonyms: [
        "sterile dressing pack",
        "gallipot",
        "cheatle forceps",
        "kidney dish receiver",
      ],
      verificationCriteria: "Assembles gallipot and cheatle forceps on mackintosh",
    };

    const transcript =
      "I will place the mackintosh under the wound, assemble the sterile gallipot with cetrimide, and use Cheatle forceps to transfer sterile cotton wool swabs.";
    const evalResult = evaluateItemMatch(dressingItem, transcript, "oral");
    expect(evalResult).not.toBeNull();
    expect(evalResult?.status).toBe("awarded");
  });

  it("does not duplicate marks when the student repeats the same statement several times", () => {
    const items = [sampleItem];
    const transcriptRound1 = ["I will wash and dry my hands thoroughly."];
    const res1 = evaluateTranscriptAgainstChecklist(items, transcriptRound1, "oral");
    expect(res1.evaluations[0].marksAwarded).toBe(0.5);
    expect(res1.newlyAwardedIds).toEqual(["item-1"]);

    // Round 2 with repeated statement
    const existingAwarded = new Set(res1.newlyAwardedIds);
    const transcriptRound2 = [
      "I will wash and dry my hands thoroughly.",
      "Again, I wash my hands.",
      "I wash and dry hands once more.",
    ];
    const res2 = evaluateTranscriptAgainstChecklist(
      items,
      transcriptRound2,
      "oral",
      existingAwarded,
    );
    expect(res2.evaluations[0].marksAwarded).toBe(0.5);
    expect(res2.newlyAwardedIds.length).toBe(0); // No double-awarding
  });

  it("handles multi-part items with strictly proportionate partial marks", () => {
    const multiPartItem: OsceChecklistItem = {
      id: "item-history-1",
      checklistId: "chk-hist",
      stepOrder: 1,
      section: "Procedure Execution",
      description:
        "Enquire about family history of hypertension, diabetes mellitus, sickle cell disease, and twin pregnancy",
      allocatedMarks: 2.0,
      isCritical: false,
      assessmentMode: "both",
      clinicalSynonyms: ["hypertension", "diabetes mellitus", "sickle cell disease", "twinning"],
      verificationCriteria: "Asks about family medical conditions",
    };

    // 1 of 4 components: insufficient for reliable clinical scoring, must NOT award arbitrary 50%
    const singleComponent = "Does anyone in your family have a history of hypertension?";
    const singleRes = evaluateItemMatch(multiPartItem, singleComponent, "oral");
    expect(singleRes).toBeNull(); // Not awarded to avoid mark inflation

    // 2 of 4 components: exactly 50% coverage -> strictly proportionate marks (2/4 * 2.0 = 1.0)
    const twoComponents =
      "Does anyone in your family have a history of hypertension or diabetes mellitus?";
    const twoRes = evaluateItemMatch(multiPartItem, twoComponents, "oral");
    expect(twoRes).not.toBeNull();
    expect(twoRes?.status).toBe("partially_awarded");
    expect(twoRes?.marksAwarded).toBe(1.0);

    // 3 of 4 components: 75% coverage -> full award threshold for comprehensive articulation
    const threeComponents =
      "Does anyone in your family have a history of hypertension, diabetes mellitus, or sickle cell disease?";
    const threeRes = evaluateItemMatch(multiPartItem, threeComponents, "oral");
    expect(threeRes).not.toBeNull();
    expect(threeRes?.status).toBe("awarded");
    expect(threeRes?.marksAwarded).toBe(2.0);
  });

  it("does not inflate component coverage when candidate repeats multiple synonyms for a single component", () => {
    const compoundWithSynonyms: OsceChecklistItem = {
      id: "item-compound-syns",
      checklistId: "chk-syns",
      stepOrder: 2,
      section: "History",
      description: "Ask about chronic medical conditions",
      allocatedMarks: 2.0,
      isCritical: false,
      assessmentMode: "both",
      clinicalSynonyms: [
        "hypertension | high blood pressure | elevated bp",
        "diabetes mellitus | high blood sugar",
        "sickle cell disease | sickle cell anemia",
        "twin pregnancy | twinning",
      ],
      verificationCriteria: "Inquires about chronic conditions",
    };

    // Candidate speaks three synonyms all describing the same component (hypertension)
    const transcript =
      "Does anyone in your family have hypertension, high blood pressure, or elevated bp?";
    const res = evaluateItemMatch(compoundWithSynonyms, transcript, "oral");
    // Since only 1 distinct component was articulated (coverage = 1/4 = 25% < 40%), marks must NOT be awarded
    expect(res).toBeNull();
  });

  it("handles clause-boundary self-correction correctly (e.g. oral vs intramuscular route)", () => {
    const imItem: OsceChecklistItem = {
      id: "item-im-route",
      checklistId: "chk-im",
      stepOrder: 4,
      section: "Procedure Execution",
      description: "Administer the prescribed medication via intramuscular injection",
      allocatedMarks: 1.0,
      isCritical: true,
      assessmentMode: "both",
      clinicalSynonyms: ["administer intramuscularly", "intramuscular injection", "give im"],
      verificationCriteria: "Administers intramuscularly",
    };

    // Candidate states they would not administer orally; then explicitly states intramuscular administration
    const transcript = "I would not administer orally; I would administer intramuscularly.";
    const res = evaluateItemMatch(imItem, transcript, "oral");
    expect(res).not.toBeNull();
    expect(res?.status).toBe("awarded");
    expect(res?.marksAwarded).toBe(1.0);
  });

  it("does not award arbitrary partial marks to single-action checklist items", () => {
    const singleActionItem: OsceChecklistItem = {
      id: "item-single-action",
      checklistId: "chk-s",
      stepOrder: 5,
      section: "Preparation",
      description: "Check patient wristband to confirm two unique identifiers",
      allocatedMarks: 0.5,
      isCritical: true,
      assessmentMode: "both",
      clinicalSynonyms: ["check wristband", "verify patient identity", "two identifiers"],
      verificationCriteria: "Verifies two identifiers",
    };

    // Vague/incomplete phrase that does not satisfy full criteria
    const incompleteTranscript = "I look at the patient.";
    const res = evaluateItemMatch(singleActionItem, incompleteTranscript, "oral");
    expect(res).toBeNull();
  });
});
