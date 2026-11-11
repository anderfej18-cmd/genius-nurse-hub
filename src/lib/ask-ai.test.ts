import { describe, expect, it } from "vitest";
import {
  FOLLOW_UP_MAX,
  FOLLOW_UP_MIN,
  followUpProblem,
  helpChoicesFor,
  messageFrom,
} from "./ask-ai";

describe("helpChoicesFor", () => {
  it("offers explain, simplify and compare to everyone", () => {
    expect(helpChoicesFor(false).map((c) => c.intent)).toEqual([
      "explain",
      "simplify",
      "compare_options",
    ]);
  });

  it("adds 'why was I wrong' only for a question the student got wrong", () => {
    expect(helpChoicesFor(true).map((c) => c.intent)).toEqual([
      "explain",
      "simplify",
      "compare_options",
      "why_wrong",
    ]);
  });

  it("gives every choice a label", () => {
    for (const choice of helpChoicesFor(true)) expect(choice.label.length).toBeGreaterThan(3);
  });
});

describe("followUpProblem", () => {
  it("accepts a question within the bounds, and an empty box", () => {
    expect(followUpProblem("Why not atropine?")).toBeNull();
    expect(followUpProblem("")).toBeNull();
    expect(followUpProblem("   ")).toBeNull();
  });

  it("says what is wrong with one that is too short or too long", () => {
    expect(followUpProblem("hi")).toMatch(new RegExp(`at least ${FOLLOW_UP_MIN}`));
    expect(followUpProblem("x".repeat(FOLLOW_UP_MAX + 1))).toMatch(new RegExp(`${FOLLOW_UP_MAX}`));
  });
});

describe("messageFrom", () => {
  it("extracts error message from server JSON response", async () => {
    const response = new Response(JSON.stringify({ error: "Custom server error" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
    expect(await messageFrom({ context: response })).toBe("Custom server error");
  });

  it("maps status 401 when response is not JSON", async () => {
    const response = new Response("Unauthorized", { status: 401 });
    expect(await messageFrom({ context: response })).toBe("Sign in to continue.");
  });

  it("maps status 403 when response is not JSON", async () => {
    const response = new Response("Forbidden", { status: 403 });
    expect(await messageFrom({ context: response })).toBe(
      "Access not allowed from this origin or domain.",
    );
  });

  it("maps status 404 when response is not JSON", async () => {
    const response = new Response("Not Found", { status: 404 });
    expect(await messageFrom({ context: response })).toBe(
      "Explanations are only available after completing the exam.",
    );
  });

  it("maps status 429 when response is not JSON", async () => {
    const response = new Response("Too Many Requests", { status: 429 });
    expect(await messageFrom({ context: response })).toBe(
      "Too many requests. Please wait and try again.",
    );
  });

  it("maps network or fetch failure", async () => {
    const error = new Error("Failed to send a request to the Edge Function");
    expect(await messageFrom(error)).toContain("Unable to connect to the AI service");
  });

  it("falls back to generic message for unknown failures", async () => {
    expect(await messageFrom(new Error("Something unknown"))).toBe(
      "The AI tutor could not answer. Please try again.",
    );
  });
});
