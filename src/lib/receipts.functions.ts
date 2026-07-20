import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

/**
 * Server-side OCR + duplicate fingerprint guard.
 * - Downloads the receipt image via a service-role signed URL.
 * - Sends it to Lovable AI (Gemini vision) to extract raw text.
 * - Normalises the text and hashes it (SHA-256) to form a fingerprint.
 * - Records the fingerprint and checks for duplicates from other users.
 * - Validates the expected amount is present in the text.
 * - If duplicate OR amount mismatch => flags the receipt and revokes the user's tier.
 */
export const verifyReceipt = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) =>
    z.object({ receiptId: z.string().uuid() }).parse(input),
  )
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import(
      "@/integrations/supabase/client.server"
    );

    // Load the receipt (must belong to the caller, RLS via user client)
    const { data: receipt, error: recErr } = await context.supabase
      .from("payment_receipts")
      .select("id, user_id, file_path, amount, target_tier, status")
      .eq("id", data.receiptId)
      .maybeSingle();

    if (recErr || !receipt) {
      return { ok: false, reason: "receipt_not_found" as const };
    }

    // Signed URL for the image
    const { data: signed, error: signErr } = await supabaseAdmin.storage
      .from("receipts")
      .createSignedUrl(receipt.file_path, 120);
    if (signErr || !signed?.signedUrl) {
      return { ok: false, reason: "signed_url_failed" as const };
    }

    // Fetch image and base64 it
    let dataUrl: string;
    try {
      const resp = await fetch(signed.signedUrl);
      const buf = new Uint8Array(await resp.arrayBuffer());
      let b64 = "";
      const chunk = 0x8000;
      for (let i = 0; i < buf.length; i += chunk) {
        b64 += String.fromCharCode(...buf.subarray(i, i + chunk));
      }
      const mime =
        resp.headers.get("content-type")?.split(";")[0] || "image/jpeg";
      dataUrl = `data:${mime};base64,${btoa(b64)}`;
    } catch {
      return { ok: false, reason: "fetch_failed" as const };
    }

    // OCR via Lovable AI Gateway
    const apiKey = process.env.LOVABLE_API_KEY;
    if (!apiKey) return { ok: false, reason: "no_ai_key" as const };

    let extracted = "";
    try {
      const aiResp = await fetch(
        "https://ai.gateway.lovable.dev/v1/chat/completions",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
          },
          body: JSON.stringify({
            model: "google/gemini-2.5-flash",
            messages: [
              {
                role: "user",
                content: [
                  {
                    type: "text",
                    text: "Extract ALL visible text from this bank transfer receipt exactly as it appears. Include the amount, account names, reference IDs, dates, times, transaction IDs. Return plain text only, no commentary.",
                  },
                  { type: "image_url", image_url: { url: dataUrl } },
                ],
              },
            ],
          }),
        },
      );
      const aiJson = await aiResp.json();
      extracted = aiJson?.choices?.[0]?.message?.content ?? "";
    } catch {
      return { ok: false, reason: "ocr_failed" as const };
    }

    if (!extracted.trim()) {
      return { ok: false, reason: "ocr_empty" as const };
    }

    // Normalise: lowercase, keep alphanumerics only for stable fingerprint
    const normalised = extracted
      .toLowerCase()
      .replace(/\s+/g, " ")
      .replace(/[^a-z0-9 ]+/g, "")
      .trim();

    const fpBuf = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(normalised),
    );
    const fingerprint = Array.from(new Uint8Array(fpBuf))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // Record & check for duplicate via SECURITY DEFINER function
    const { data: dupResult, error: dupErr } = await context.supabase.rpc(
      "record_receipt_fingerprint",
      {
        _receipt_id: receipt.id,
        _fingerprint: fingerprint,
        _extracted_text: extracted,
      },
    );
    const isDuplicate = dupResult === true;

    // Amount validation: does the extracted text contain the expected amount?
    let amountMatches = true;
    if (receipt.amount != null) {
      const amt = Math.round(Number(receipt.amount));
      const digits = normalised.replace(/[^0-9]/g, " ");
      // Look for the exact integer amount as a standalone number
      const re = new RegExp(`(^|\\D)${amt}(\\D|$)`);
      amountMatches = re.test(digits) || normalised.includes(String(amt));
    }

    if (dupErr) {
      return { ok: false, reason: "record_failed" as const };
    }

    if (isDuplicate || !amountMatches) {
      const reason = isDuplicate
        ? "Duplicate receipt: same text layout was previously uploaded by another account."
        : `Amount mismatch: expected ₦${receipt.amount} not found in receipt text.`;
      await context.supabase.rpc("flag_receipt_and_revoke", {
        _receipt_id: receipt.id,
        _reason: reason,
      });
      return {
        ok: false,
        reason: isDuplicate ? ("duplicate" as const) : ("amount_mismatch" as const),
        detail: reason,
      };
    }

    return { ok: true as const, fingerprint };
  });
