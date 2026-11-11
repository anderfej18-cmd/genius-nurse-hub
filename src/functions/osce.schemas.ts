import { z } from "zod";

export const getProceduresSchema = z
  .object({
    categoryId: z.string().trim().max(100).optional(),
  })
  .strict();

export const getProcedureDetailSchema = z
  .object({
    identifier: z.string().trim().min(1).max(200),
  })
  .strict();

export const startOsceSessionSchema = z
  .object({
    procedureId: z.string().trim().min(1).max(200),
    mode: z.enum(["oral", "practical"]),
  })
  .strict();

export const sessionIdSchema = z
  .object({
    sessionId: z.string().trim().min(1).max(200),
  })
  .strict();

export const speechChunkSchema = z
  .object({
    sessionId: z.string().trim().min(1).max(200),
    text: z.string().trim().min(1).max(2000),
    timestampSeconds: z.number().int().min(0).max(3600),
  })
  .strict();
