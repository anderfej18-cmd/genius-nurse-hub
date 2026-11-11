-- OSCE Practice System Integration
-- Migration: 20261103000000_osce_practice_system.sql
-- Covers NMCN / MNSF OSCE Compendium (84 pages) clinical procedures, checklists, items, sessions, and evaluations.

-- 1. OSCE Categories ----------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.osce_categories (
  id text PRIMARY KEY,
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  description text NOT NULL DEFAULT '',
  icon text NOT NULL DEFAULT 'HeartPulse',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. OSCE Procedures ----------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.osce_procedures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id text NOT NULL REFERENCES public.osce_categories(id) ON DELETE RESTRICT,
  title text NOT NULL,
  slug text NOT NULL UNIQUE,
  station_number text NOT NULL,
  examining_body text NOT NULL,
  session_label text NOT NULL,
  page_start integer NOT NULL,
  page_end integer NOT NULL,
  total_marks numeric(5,2) NOT NULL,
  pass_mark numeric(5,2) NOT NULL,
  time_limit_seconds integer NOT NULL DEFAULT 420,
  instructions text NOT NULL,
  scenario_prompt text NOT NULL,
  assessment_mode text NOT NULL CHECK (assessment_mode IN ('oral', 'practical', 'both')),
  equipment_list jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_osce_procedures_category ON public.osce_procedures(category_id);
CREATE INDEX IF NOT EXISTS idx_osce_procedures_slug ON public.osce_procedures(slug);
CREATE INDEX IF NOT EXISTS idx_osce_procedures_published ON public.osce_procedures(is_published);

-- 3. OSCE Checklists ----------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.osce_checklists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  procedure_id uuid NOT NULL REFERENCES public.osce_procedures(id) ON DELETE CASCADE,
  version integer NOT NULL DEFAULT 1,
  is_active boolean NOT NULL DEFAULT true,
  total_items integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT osce_checklists_procedure_version_key UNIQUE (procedure_id, version)
);

CREATE INDEX IF NOT EXISTS idx_osce_checklists_procedure ON public.osce_checklists(procedure_id, is_active);

-- 4. OSCE Checklist Items -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.osce_checklist_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checklist_id uuid NOT NULL REFERENCES public.osce_checklists(id) ON DELETE CASCADE,
  step_order integer NOT NULL,
  section text NOT NULL,
  description text NOT NULL,
  allocated_marks numeric(4,2) NOT NULL,
  is_critical boolean NOT NULL DEFAULT false,
  assessment_mode text NOT NULL CHECK (assessment_mode IN ('oral', 'practical', 'both')),
  clinical_synonyms jsonb NOT NULL DEFAULT '[]'::jsonb,
  verification_criteria text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT osce_checklist_items_step_key UNIQUE (checklist_id, step_order)
);

CREATE INDEX IF NOT EXISTS idx_osce_checklist_items_checklist ON public.osce_checklist_items(checklist_id, step_order);

-- 5. OSCE Sessions ------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.osce_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  procedure_id uuid NOT NULL REFERENCES public.osce_procedures(id) ON DELETE RESTRICT,
  checklist_id uuid NOT NULL REFERENCES public.osce_checklists(id) ON DELETE RESTRICT,
  mode text NOT NULL CHECK (mode IN ('oral', 'practical')),
  status text NOT NULL CHECK (status IN ('in_progress', 'completed', 'abandoned')),
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  time_spent_seconds integer NOT NULL DEFAULT 0,
  score_obtained numeric(5,2) NOT NULL DEFAULT 0.00,
  total_possible numeric(5,2) NOT NULL DEFAULT 0.00,
  percentage numeric(5,2) NOT NULL DEFAULT 0.00,
  transcript jsonb NOT NULL DEFAULT '[]'::jsonb,
  clinical_feedback jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_osce_sessions_user ON public.osce_sessions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_osce_sessions_procedure ON public.osce_sessions(procedure_id);

-- 6. OSCE Session Evaluations -------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.osce_session_evaluations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.osce_sessions(id) ON DELETE CASCADE,
  item_id uuid NOT NULL REFERENCES public.osce_checklist_items(id) ON DELETE RESTRICT,
  status text NOT NULL CHECK (status IN ('awarded', 'missed', 'partially_awarded')),
  marks_awarded numeric(4,2) NOT NULL DEFAULT 0.00,
  confidence numeric(3,2) NOT NULL DEFAULT 1.00,
  matched_text text,
  evidence_type text NOT NULL CHECK (evidence_type IN ('verbal', 'physical', 'examiner_override')),
  timestamp_seconds integer NOT NULL DEFAULT 0,
  evaluated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT osce_session_evaluations_session_item_key UNIQUE (session_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_osce_session_evaluations_session ON public.osce_session_evaluations(session_id);

-- 7. Row Level Security (RLS) --------------------------------------------------------------------------

ALTER TABLE public.osce_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.osce_procedures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.osce_checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.osce_checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.osce_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.osce_session_evaluations ENABLE ROW LEVEL SECURITY;

-- Categories & Procedures: Authenticated read for published procedures
CREATE POLICY "authenticated view osce categories" ON public.osce_categories
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated view published osce procedures" ON public.osce_procedures
  FOR SELECT TO authenticated USING (is_published = true OR public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'central_admin'::public.app_role));

CREATE POLICY "admins manage osce categories" ON public.osce_categories
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'central_admin'::public.app_role));

CREATE POLICY "admins manage osce procedures" ON public.osce_procedures
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'central_admin'::public.app_role));

-- Checklists: Read for all active, Admin manage
CREATE POLICY "authenticated view active osce checklists" ON public.osce_checklists
  FOR SELECT TO authenticated USING (is_active = true OR public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'central_admin'::public.app_role));

CREATE POLICY "admins manage osce checklists" ON public.osce_checklists
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'central_admin'::public.app_role));

-- Checklist Items: Read for all active
CREATE POLICY "authenticated view osce checklist items" ON public.osce_checklist_items
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "admins manage osce checklist items" ON public.osce_checklist_items
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'central_admin'::public.app_role));

-- Sessions: User manages own, Central Admin view all
CREATE POLICY "users view own osce sessions or central admin" ON public.osce_sessions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'central_admin'::public.app_role));

CREATE POLICY "users insert own osce sessions" ON public.osce_sessions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "users update own osce sessions" ON public.osce_sessions
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- Session Evaluations: User manages own, Central Admin view all
CREATE POLICY "users view own osce evaluations or central admin" ON public.osce_session_evaluations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.osce_sessions s
      WHERE s.id = session_id
        AND (s.user_id = auth.uid() OR public.has_role(auth.uid(), 'central_admin'::public.app_role))
    )
  );

CREATE POLICY "users insert own osce evaluations" ON public.osce_session_evaluations
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.osce_sessions s
      WHERE s.id = session_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY "users update own osce evaluations" ON public.osce_session_evaluations
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.osce_sessions s
      WHERE s.id = session_id
        AND s.user_id = auth.uid()
    )
  );

-- Grants
GRANT SELECT ON public.osce_categories TO authenticated;
GRANT SELECT ON public.osce_procedures TO authenticated;
GRANT SELECT ON public.osce_checklists TO authenticated;
GRANT SELECT ON public.osce_checklist_items TO authenticated;
GRANT ALL ON public.osce_sessions TO authenticated;
GRANT ALL ON public.osce_session_evaluations TO authenticated;
