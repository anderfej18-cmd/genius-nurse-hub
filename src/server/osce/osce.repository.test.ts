import { describe, expect, it, vi, beforeEach } from "vitest";
import { SupabaseOsceRepository, shouldFallbackToSeed } from "./osce.repository.server";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build a minimal Supabase-like fake that returns the given response for any
 *  chain of .from().select().order() or .from().select().eq().maybeSingle() */
function makeFakeClient(response: { data: unknown; error: unknown }): SupabaseClient<Database> {
  const chain = {
    select: vi.fn().mockReturnThis(),
    order: vi.fn().mockResolvedValue(response),
    eq: vi.fn().mockReturnThis(),
    maybeSingle: vi.fn().mockResolvedValue(response),
    insert: vi.fn().mockResolvedValue(response),
    update: vi.fn().mockReturnThis(),
  };
  return {
    from: vi.fn().mockReturnValue(chain),
  } as unknown as SupabaseClient<Database>;
}

// ---------------------------------------------------------------------------
// shouldFallbackToSeed unit tests
// ---------------------------------------------------------------------------

describe("shouldFallbackToSeed", () => {
  it("returns true for Postgres 42P01 (relation does not exist)", () => {
    expect(shouldFallbackToSeed({ code: "42P01", message: "" })).toBe(true);
  });

  it("returns true for PGRST204 / PGRST200 schema-cache errors", () => {
    expect(shouldFallbackToSeed({ code: "PGRST204", message: "" })).toBe(true);
    expect(shouldFallbackToSeed({ code: "PGRST200", message: "" })).toBe(true);
  });

  it("returns true for 'relation … does not exist' message", () => {
    expect(
      shouldFallbackToSeed({
        code: "UNKNOWN",
        message: "relation public.osce_categories does not exist",
      }),
    ).toBe(true);
  });

  it("returns true for fetch-failed network errors", () => {
    expect(shouldFallbackToSeed({ code: "", message: "fetch failed" })).toBe(true);
    expect(shouldFallbackToSeed({ code: "", message: "Failed to fetch" })).toBe(true);
  });

  it("returns false for 42501 (permission denied) — must NOT mask with seed data", () => {
    expect(shouldFallbackToSeed({ code: "42501", message: "permission denied" })).toBe(false);
  });

  it("returns false for null/undefined error", () => {
    expect(shouldFallbackToSeed(null)).toBe(false);
    expect(shouldFallbackToSeed(undefined)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// SupabaseOsceRepository Fallback Boundaries
// ---------------------------------------------------------------------------

describe("SupabaseOsceRepository Fallback Boundaries", () => {
  it("uses seed fallback when database query throws or errors (unmigrated mode)", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          order: vi.fn().mockResolvedValue({
            data: null,
            error: { code: "42P01", message: "relation public.osce_categories does not exist" },
          }),
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    const categories = await repo.getCategories();

    // Fallback returns 6 seed categories
    expect(categories.length).toBe(6);
    expect(categories[0].id).toBe("maternal-midwifery");
  });

  it("returns null (not found) when operational database returns data: null, error: null", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({
              data: null,
              error: null, // Table exists, query succeeded, record genuinely absent
            }),
          }),
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    const proc = await repo.getProcedureDetail("non-existent-procedure-slug");

    // In operational database, must return null rather than silently falling back to seed data
    expect(proc).toBeNull();
  });

  it("returns database records when operational database has data", async () => {
    const mockDbCategories = [
      {
        id: "cat-db-1",
        name: "Database Category",
        slug: "db-cat",
        description: "From Supabase",
        icon: "HeartPulse",
        sort_order: 1,
      },
    ];

    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          order: vi.fn().mockResolvedValue({
            data: mockDbCategories,
            error: null,
          }),
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    const categories = await repo.getCategories();

    // Returns the operational DB records directly
    expect(categories.length).toBe(1);
    expect(categories[0].id).toBe("cat-db-1");
    expect(categories[0].name).toBe("Database Category");
  });

  it("returns empty array when operational database returns empty list without error", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          order: vi.fn().mockResolvedValue({
            data: [],
            error: null, // Table exists and is empty
          }),
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    const categories = await repo.getCategories();

    // Does NOT silently replace empty DB table with seed data
    expect(categories).toEqual([]);
  });

  it("throws on permission denied (PGRST / Postgres code 42501) instead of masking with seed data", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          order: vi.fn().mockResolvedValue({
            data: null,
            error: {
              code: "42501",
              message: "permission denied for table osce_categories",
            },
          }),
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    await expect(repo.getCategories()).rejects.toThrow("OSCE repository error [42501]");
  });

  it("throws on RLS violation / auth failure instead of falling back to seed data", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({
              data: null,
              error: {
                code: "42501",
                message: "new row violates row-level security policy for table osce_procedures",
              },
            }),
          }),
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    await expect(repo.getProcedureDetail("test-slug")).rejects.toThrow(
      "OSCE repository error [42501]",
    );
  });

  it("allows seed fallback when OSCE_USE_SEED_FALLBACK is explicitly set to true", async () => {
    process.env.OSCE_USE_SEED_FALLBACK = "true";
    try {
      const fakeClient = {
        from: vi.fn().mockReturnValue({
          select: vi.fn().mockReturnValue({
            order: vi.fn().mockResolvedValue({
              data: null,
              error: {
                code: "42501",
                message: "permission denied",
              },
            }),
          }),
        }),
      } as unknown as SupabaseClient<Database>;

      const repo = new SupabaseOsceRepository(fakeClient);
      const categories = await repo.getCategories();
      expect(categories.length).toBe(6);
    } finally {
      delete process.env.OSCE_USE_SEED_FALLBACK;
    }
  });
});

// ---------------------------------------------------------------------------
// Session lifecycle — seed-fallback mode (no OSCE DB tables)
// ---------------------------------------------------------------------------

describe("SupabaseOsceRepository — startSession in seed-fallback mode", () => {
  beforeEach(() => {
    // Clear globalThis store between tests so sessions don't leak across test cases
    if ((globalThis as Record<string, unknown>).__osceSessions) {
      ((globalThis as Record<string, unknown>).__osceSessions as Map<unknown, unknown>).clear();
    }
  });

  it("creates a session in the globalThis store and returns it immediately (no DB required)", async () => {
    // Simulate a client where ALL queries fail with 42P01 (tables don't exist)
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({
              data: null,
              error: { code: "42P01", message: "relation does not exist" },
            }),
          }),
          order: vi.fn().mockResolvedValue({
            data: null,
            error: { code: "42P01", message: "relation does not exist" },
          }),
        }),
        insert: vi.fn().mockResolvedValue({
          data: null,
          error: { code: "42P01", message: "relation does not exist" },
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);

    // Start a session using the first seed procedure slug
    const session = await repo.startSession("user-abc", {
      procedureId: "neurological-reflexes-newborn",
      mode: "oral",
    });

    expect(session.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    );
    expect(session.userId).toBe("user-abc");
    expect(session.mode).toBe("oral");
    expect(session.status).toBe("in_progress");
    expect(session.procedureSlug).toBe("neurological-reflexes-newborn");
    expect(session.checklistItems.length).toBeGreaterThan(0);
    expect(session.evaluations.length).toBe(session.checklistItems.length);
    // All evaluations must start as "missed"
    expect(session.evaluations.every((e) => e.status === "missed")).toBe(true);
  });

  it("retrieves the session from globalThis store when DB is unavailable (simulating new isolate read)", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({
              data: null,
              error: { code: "42P01", message: "relation does not exist" },
            }),
          }),
          order: vi.fn().mockResolvedValue({
            data: null,
            error: { code: "42P01", message: "relation does not exist" },
          }),
        }),
        insert: vi.fn().mockResolvedValue({ data: null, error: null }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);

    const session = await repo.startSession("user-def", {
      procedureId: "neurological-reflexes-newborn",
      mode: "practical",
    });

    // getSession must find it via globalThis even though DB query fails
    const found = await repo.getSession("user-def", session.id);
    expect(found).not.toBeNull();
    expect(found!.id).toBe(session.id);
    expect(found!.mode).toBe("practical");
    expect(found!.procedureSlug).toBe("neurological-reflexes-newborn");
  });

  it("returns null for a sessionId that was never created", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({
              data: null,
              error: { code: "42P01", message: "relation does not exist" },
            }),
          }),
        }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    const result = await repo.getSession("user-xyz", "00000000-0000-0000-0000-000000000000");
    expect(result).toBeNull();
  });

  it("does NOT attempt DB INSERT when procedure ID is a non-UUID seed identifier", async () => {
    const insertMock = vi.fn().mockResolvedValue({ data: null, error: null });
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({
              data: null,
              error: { code: "42P01", message: "relation does not exist" },
            }),
          }),
          order: vi.fn().mockResolvedValue({
            data: null,
            error: { code: "42P01", message: "relation does not exist" },
          }),
        }),
        insert: insertMock,
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);

    // The seed fallback gives procedure.id = "seed-proc-neurological-reflexes-newborn" (non-UUID)
    // Starting via slug triggers seed path
    await repo.startSession("user-ghi", {
      procedureId: "neurological-reflexes-newborn",
      mode: "oral",
    });

    // The DB insert MUST NOT be called when the procedure ID is not a real UUID,
    // to prevent silent FK constraint failures masking the system state.
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("procedureSlug is always the slug string, not the internal seed ID", async () => {
    const fakeClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({
              data: null,
              error: { code: "42P01", message: "relation does not exist" },
            }),
          }),
          order: vi.fn().mockResolvedValue({
            data: null,
            error: { code: "42P01", message: "relation does not exist" },
          }),
        }),
        insert: vi.fn().mockResolvedValue({ data: null, error: null }),
      }),
    } as unknown as SupabaseClient<Database>;

    const repo = new SupabaseOsceRepository(fakeClient);
    const session = await repo.startSession("user-jkl", {
      procedureId: "neurological-reflexes-newborn",
      mode: "oral",
    });

    // procedureSlug must be the clean slug, NOT "seed-proc-neurological-reflexes-newborn"
    expect(session.procedureSlug).toBe("neurological-reflexes-newborn");
    expect(session.procedureSlug).not.toContain("seed-proc-");
  });
});
