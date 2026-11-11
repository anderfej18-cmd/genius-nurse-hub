import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { guard } from "../errors";
import { SupabaseOsceRepository } from "./osce.repository.server";
import { OsceService } from "./osce.service";
import type { StartSessionInput, ProcessSpeechChunkInput } from "./osce.types";

const service = () => new OsceService(new SupabaseOsceRepository(supabaseAdmin));

export const osceController = {
  getCategories: () => guard(() => service().getCategories()),
  getProcedures: (categoryId?: string) => guard(() => service().getProcedures(categoryId)),
  getProcedure: (identifier: string) => guard(() => service().getProcedure(identifier)),
  startSession: (userId: string, input: StartSessionInput) =>
    guard(() => service().startSession(userId, input)),
  getSession: (userId: string, sessionId: string) =>
    guard(() => service().getSession(userId, sessionId)),
  processSpeechChunk: (userId: string, input: ProcessSpeechChunkInput) =>
    guard(() => service().processSpeechChunk(userId, input)),
  endSession: (userId: string, sessionId: string) =>
    guard(() => service().endSession(userId, sessionId)),
  getUserHistory: (userId: string) => guard(() => service().getUserHistory(userId)),
};
