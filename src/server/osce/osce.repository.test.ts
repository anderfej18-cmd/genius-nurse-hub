import { describe, expect, it, vi } from "vitest";
import { SupabaseOsceRepository } from "./osce.repository.server";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";

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
