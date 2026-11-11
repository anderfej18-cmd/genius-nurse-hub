import { describe, expect, it } from "vitest";
import {
  getProceduresSchema,
  getProcedureDetailSchema,
  startOsceSessionSchema,
  sessionIdSchema,
  speechChunkSchema,
} from "./osce.schemas";

describe("OSCE Schemas Validation", () => {
  it("validates getProceduresSchema", () => {
    expect(getProceduresSchema.safeParse({}).success).toBe(true);
    expect(getProceduresSchema.safeParse({ categoryId: "maternal-midwifery" }).success).toBe(true);
    expect(getProceduresSchema.safeParse({ unknownField: true }).success).toBe(false);
  });

  it("validates getProcedureDetailSchema", () => {
    expect(
      getProcedureDetailSchema.safeParse({ identifier: "neurological-reflexes-newborn" }).success,
    ).toBe(true);
    expect(getProcedureDetailSchema.safeParse({ identifier: "" }).success).toBe(false);
  });

  it("validates startOsceSessionSchema", () => {
    expect(
      startOsceSessionSchema.safeParse({
        procedureId: "proc-123",
        mode: "oral",
      }).success,
    ).toBe(true);

    expect(
      startOsceSessionSchema.safeParse({
        procedureId: "proc-123",
        mode: "practical",
      }).success,
    ).toBe(true);

    expect(
      startOsceSessionSchema.safeParse({
        procedureId: "proc-123",
        mode: "invalid_mode",
      }).success,
    ).toBe(false);
  });

  it("validates speechChunkSchema", () => {
    expect(
      speechChunkSchema.safeParse({
        sessionId: "session-abc",
        text: "I am washing my hands with soap and water.",
        timestampSeconds: 15,
      }).success,
    ).toBe(true);

    expect(
      speechChunkSchema.safeParse({
        sessionId: "session-abc",
        text: "",
        timestampSeconds: 15,
      }).success,
    ).toBe(false);
  });
});
