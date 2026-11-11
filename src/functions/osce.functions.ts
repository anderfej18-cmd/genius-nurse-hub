import { createServerFn } from "@tanstack/react-start";
import { validated } from "./validated";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import {
  getProceduresSchema,
  getProcedureDetailSchema,
  startOsceSessionSchema,
  sessionIdSchema,
  speechChunkSchema,
} from "./osce.schemas";

// Client-safe module: server code is loaded with dynamic import inside each handler.

export const getOsceCategories = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async () => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.getCategories();
  });

export const getOsceProcedures = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(validated(getProceduresSchema))
  .handler(async ({ data }) => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.getProcedures(data.categoryId);
  });

export const getOsceProcedureDetail = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(validated(getProcedureDetailSchema))
  .handler(async ({ data }) => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.getProcedure(data.identifier);
  });

export const startOsceSession = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(validated(startOsceSessionSchema))
  .handler(async ({ data, context }) => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.startSession(context.userId, data);
  });

export const getOsceSession = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(validated(sessionIdSchema))
  .handler(async ({ data, context }) => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.getSession(context.userId, data.sessionId);
  });

export const processOsceSpeech = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(validated(speechChunkSchema))
  .handler(async ({ data, context }) => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.processSpeechChunk(context.userId, data);
  });

export const completeOsceSession = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(validated(sessionIdSchema))
  .handler(async ({ data, context }) => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.endSession(context.userId, data.sessionId);
  });

export const getOsceUserHistory = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { osceController } = await import("@/server/osce/osce.controller.server");
    return osceController.getUserHistory(context.userId);
  });
