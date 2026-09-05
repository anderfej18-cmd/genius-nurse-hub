# Custom Tests and Shared Links

## User-visible outcome
- Central Admins and Sub-Admins get a **Create a Test** tab.
- Admins can build a test from selected question-bank areas or upload an isolated TXT file.
- Each finalized test receives a unique shareable URL with configurable duration and expiry.
- Visitors enter an email before starting; registered users can use their account features, while guests can complete the test and later finish profile setup to keep the result.
- Admins can monitor active and expired tests, republish expired tests, view participation/pass-fail/leaderboard data, and import isolated questions into the main bank.

## Implementation stages
1. **Data model and security**
   - Add custom test, custom test question, custom test attempt, and custom test answer records.
   - Keep uploaded questions isolated from `public.questions` until an admin explicitly imports them.
   - Add secure public read/start/submit DTO functions and authenticated admin management functions with role checks.
   - Add the required grants, RLS policies, indexes, and expiry/ownership validation in the same migration.
2. **Admin creation and management**
   - Add the Create a Test tab for both admin roles.
   - Support existing-bank multi-select with complete-question filtering, single-area availability validation, max 250 questions, and randomized selection.
   - Support isolated TXT upload, file parsing/validation, randomized selection, test duration from 10 minutes to 3 hours, and link expiry.
   - Add a custom-test dashboard with participant totals, pass/fail percentages, leaderboard after expiry, republish, and Add to Question Bank.
3. **Public shared-test flow**
   - Add the shareable `/test/$token` page with email gate, expiry handling, question navigation, timer, scoring, explanations, and the existing 80% submit guard.
   - Let registered users associate attempts with their account and unlock Ask AI; keep it unavailable for guests until profile completion.
   - Add a profile-completion path that pre-fills the email, assigns Novice through the normal account flow, and attaches the completed attempt to the new account.
4. **Verification and polish**
   - Add route metadata for the new public page.
   - Verify admin role visibility, creation validation, isolated upload behavior, guest/registered paths, expiry/republish, analytics, import, mobile layout, and TypeScript/build output.

## Technical details
- Use TanStack Router route files and the existing UI primitives; do not change the normal public question-bank ingestion path.
- Use a cryptographically random public token, store only its hash for lookup, and return the raw token only when creating/republishing a link.
- Server-side functions enforce admin roles, test ownership/access, token expiry, attempt ownership, answer validation, and import authorization; the browser never receives privileged keys.
- Existing-bank tests reference copied question snapshots so later bank edits cannot change a published test. Isolated uploads store their own question snapshots and source metadata.
- Guest attempts use a durable attempt identifier and signed/unguessable access token; registered attempts also map to the authenticated user when available.
