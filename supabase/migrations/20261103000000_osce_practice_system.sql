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


-- ============================================================================
-- 8. SEED DATA: NMCN / MNSF OSCE Compendium (6 Categories, 34 Procedures, 370 Items)
-- ============================================================================

-- 8.1 Categories -----------------------------------------------------------------------

INSERT INTO public.osce_categories (id, name, slug, description, icon, sort_order)
VALUES ('maternal-midwifery', 'Maternal & Midwifery Care', 'maternal-midwifery', 'NMCN and university midwifery stations covering labour mechanics, delivery of placenta, AMTSL, episiotomy, fetal palpation, and obstetric emergencies.', 'Baby', 1)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  slug = EXCLUDED.slug,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  sort_order = EXCLUDED.sort_order;
INSERT INTO public.osce_categories (id, name, slug, description, icon, sort_order)
VALUES ('neonatal-pediatric', 'Neonatal & Pediatric Care', 'neonatal-pediatric', 'Newborn physical examination, bag-mask resuscitation, neurological reflexes, and umbilical cord care.', 'HeartPulse', 2)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  slug = EXCLUDED.slug,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  sort_order = EXCLUDED.sort_order;
INSERT INTO public.osce_categories (id, name, slug, description, icon, sort_order)
VALUES ('fundamental-nursing', 'Fundamental & Bedside Nursing', 'fundamental-nursing', 'Core nursing procedures: hospital bed making, bed bathing, tepid sponging, oral hygiene, enema administration, nasogastric tube insertion, and urinalysis.', 'Bed', 3)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  slug = EXCLUDED.slug,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  sort_order = EXCLUDED.sort_order;
INSERT INTO public.osce_categories (id, name, slug, description, icon, sort_order)
VALUES ('clinical-pharmacotherapy', 'Clinical Skills & Pharmacotherapy', 'clinical-pharmacotherapy', 'Intramuscular injections (dorsogluteal and ventrogluteal), blood pressure measurement, blood transfusion nursing role, oxygen therapy, bandaging, and surgical wound dressing.', 'Syringe', 4)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  slug = EXCLUDED.slug,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  sort_order = EXCLUDED.sort_order;
INSERT INTO public.osce_categories (id, name, slug, description, icon, sort_order)
VALUES ('reproductive-health', 'Reproductive & Women''s Health', 'reproductive-health', 'Pelvic floor & vulva anatomy, perineal care, lithotomy positioning, IUCD insertion, VIA cervical screening, manual vacuum aspiration, and breast self-examination.', 'ShieldAlert', 5)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  slug = EXCLUDED.slug,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  sort_order = EXCLUDED.sort_order;
INSERT INTO public.osce_categories (id, name, slug, description, icon, sort_order)
VALUES ('health-education', 'Health Education & Clinical Communication', 'health-education', 'Structured patient counseling stations: sickle cell crisis prevention, modern family planning, uterine fibroids, nutrition, minor disorders of pregnancy, and comprehensive health history.', 'MessageSquare', 6)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  slug = EXCLUDED.slug,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  sort_order = EXCLUDED.sort_order;

-- 8.2 Procedures, Checklists & Items --------------------------------------------------

-- Procedure: Neurological Reflexes in the Newborn (Station 3)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '740771cb-b2b1-5173-840a-6e3ed482dcdb', 'neonatal-pediatric', 'Neurological Reflexes in the Newborn', 'neurological-reflexes-newborn',
  'Station 3', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for Midwives - March 2018',
  1, 2, 11, 5.5, 420,
  'Examine the newborn baby for neurological reflexes. State each reflex, demonstrate the eliciting technique, and state the normal response and clinical significance.', 'You are stationed in the postnatal nursery. A full-term baby born 24 hours ago requires a complete neurological reflexes assessment prior to discharge. Conduct the examination, demonstrating each maneuver clearly and reporting your findings to the examiner.', 'both',
  '["Warm examination table / cot","Clean warm towel","Hand sanitizer","Penlight","Soft blanket"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('554d1457-3761-5c9b-aab0-1ccccccee970', '740771cb-b2b1-5173-840a-6e3ed482dcdb', 1, true, 17)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5d2fc5fe-ac43-5c92-ae0b-d593ff041681', '554d1457-3761-5c9b-aab0-1ccccccee970', 1, 'Preparation & Equipment', 'Greet the examiner and introduce self',
  0.25, false, 'both',
  '["good morning examiner","hello examiner","my name is","candidate number"]'::jsonb, 'Greet the examiner and introduce self'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6c36890d-b5ee-562f-ae99-5e5acb588620', '554d1457-3761-5c9b-aab0-1ccccccee970', 2, 'Preparation & Equipment', 'Explain procedure to the mother and gain consent',
  0.25, false, 'both',
  '["explain to mother","obtain consent","ask permission","informed consent"]'::jsonb, 'Explain procedure to the mother and gain consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '95e74ef2-5173-5680-91df-33d26e2b8be0', '554d1457-3761-5c9b-aab0-1ccccccee970', 3, 'Preparation & Equipment', 'Wash and dry hands thoroughly or perform hand hygiene',
  0.5, false, 'both',
  '["wash hands","dry hands","hand hygiene","alcohol rub"]'::jsonb, 'Wash and dry hands thoroughly or perform hand hygiene'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3c602a50-1cb7-570c-9081-47efc696c1d7', '554d1457-3761-5c9b-aab0-1ccccccee970', 4, 'Preparation & Equipment', 'Ensure baby is in a warm, draft-free room with adequate lighting',
  0.5, false, 'both',
  '["warm room","draft free","adequate lighting","prevent heat loss"]'::jsonb, 'Ensure baby is in a warm, draft-free room with adequate lighting'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7ca8ec3d-96f5-5fd2-86c3-005526f34e39', '554d1457-3761-5c9b-aab0-1ccccccee970', 5, 'Preparation & Equipment', 'Carry baby, wrap up with warm towel, and check reflexes one after another',
  0.25, false, 'both',
  '["wrap with warm towel","handle baby gently","expose baby appropriately"]'::jsonb, 'Carry baby, wrap up with warm towel, and check reflexes one after another'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6ca55ba4-c690-5832-abff-e5efce037636', '554d1457-3761-5c9b-aab0-1ccccccee970', 6, 'Procedure Execution', 'List the key primitive reflexes present in the newborn (Moro, rooting, sucking, swallowing, palmar, plantar, tonic neck, stepping, Babinski, cornea/blink)',
  1, false, 'both',
  '["moro","rooting","sucking","palmar grasp","plantar grasp","asymmetric tonic neck","babinski","stepping reflex"]'::jsonb, 'List the key primitive reflexes present in the newborn (Moro, rooting, sucking, swallowing, palmar, plantar, tonic neck, stepping, Babinski, cornea/blink)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4dea0caa-8445-5686-9317-9e58aaf9c1cd', '554d1457-3761-5c9b-aab0-1ccccccee970', 7, 'Procedure Execution', 'Demonstrate Moro reflex: Hold infant at 45° angle, allow head to drop 1-2 cm gently; observe symmetric abduction, extension of arms, fanning of fingers followed by flexion',
  1, true, 'both',
  '["drop head slightly","abduction and extension of arms","fanning of fingers","moro reflex elicited"]'::jsonb, 'Demonstrate Moro reflex: Hold infant at 45° angle, allow head to drop 1-2 cm gently; observe symmetric abduction, extension of arms, fanning of fingers followed by flexion'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5c61ef17-ea87-5d20-8322-f769c3c996eb', '554d1457-3761-5c9b-aab0-1ccccccee970', 8, 'Procedure Execution', 'Demonstrate Rooting reflex: Stroke infant''s cheek or corner of mouth; infant turns head toward stimulus and opens mouth to suck',
  0.75, false, 'both',
  '["stroke cheek","corner of mouth","turns head toward stimulus","opens mouth to seek nipple"]'::jsonb, 'Demonstrate Rooting reflex: Stroke infant''s cheek or corner of mouth; infant turns head toward stimulus and opens mouth to suck'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'fb20947a-abc0-50e7-bdcb-9453415e7ca7', '554d1457-3761-5c9b-aab0-1ccccccee970', 9, 'Procedure Execution', 'Demonstrate Sucking and Swallowing reflex: Place clean gloved finger or nipple into infant''s mouth; baby initiates strong, rhythmic sucking and swallows coordinated with breathing',
  0.75, false, 'both',
  '["clean gloved finger in mouth","rhythmic sucking","coordinated swallowing"]'::jsonb, 'Demonstrate Sucking and Swallowing reflex: Place clean gloved finger or nipple into infant''s mouth; baby initiates strong, rhythmic sucking and swallows coordinated with breathing'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ff0a0cb9-30f9-514d-91ec-974f59de7596', '554d1457-3761-5c9b-aab0-1ccccccee970', 10, 'Procedure Execution', 'Demonstrate Palmar Grasp reflex: Place finger in palm from ulnar side; infant curls fingers around examiner''s finger with firm grasp',
  0.75, false, 'both',
  '["finger in palm","curls fingers firmly","ulnar grasp"]'::jsonb, 'Demonstrate Palmar Grasp reflex: Place finger in palm from ulnar side; infant curls fingers around examiner''s finger with firm grasp'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '004aa7dd-d3a0-55e5-b213-88d1ea113ac5', '554d1457-3761-5c9b-aab0-1ccccccee970', 11, 'Procedure Execution', 'Demonstrate Plantar Grasp reflex: Press thumb against ball of infant''s foot; toes curl downward tightly',
  0.5, false, 'both',
  '["press ball of foot","toes curl downward","plantar grasp"]'::jsonb, 'Demonstrate Plantar Grasp reflex: Press thumb against ball of infant''s foot; toes curl downward tightly'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd9491298-ba1f-5595-9d58-c3dd8120dea0', '554d1457-3761-5c9b-aab0-1ccccccee970', 12, 'Procedure Execution', 'Demonstrate Asymmetric Tonic Neck Reflex (Fencing position): Turn infant''s head to one side while supine; ipsilateral arm/leg extend, contralateral arm/leg flex',
  0.75, false, 'both',
  '["turn head to one side","fencing posture","arm on side head faces extends","opposite arm flexes"]'::jsonb, 'Demonstrate Asymmetric Tonic Neck Reflex (Fencing position): Turn infant''s head to one side while supine; ipsilateral arm/leg extend, contralateral arm/leg flex'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '02ab6eed-daaf-5f37-ab65-284d0ec14b72', '554d1457-3761-5c9b-aab0-1ccccccee970', 13, 'Procedure Execution', 'Demonstrate Babinski (Plantar) reflex: Stroke lateral aspect of sole from heel upward across ball of foot; hyperextension/dorsiflexion of great toe with fanning of other toes',
  1, false, 'both',
  '["stroke lateral sole","great toe dorsiflexes","fanning of toes","normal up to 12-24 months"]'::jsonb, 'Demonstrate Babinski (Plantar) reflex: Stroke lateral aspect of sole from heel upward across ball of foot; hyperextension/dorsiflexion of great toe with fanning of other toes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'efe2c283-9f5f-59c6-b0d7-9592adf26abe', '554d1457-3761-5c9b-aab0-1ccccccee970', 14, 'Procedure Execution', 'Demonstrate Stepping / Walking reflex: Hold baby upright with feet touching flat surface; baby makes coordinated stepping movements',
  0.75, false, 'both',
  '["hold upright","soles touch surface","stepping motion","walking reflex"]'::jsonb, 'Demonstrate Stepping / Walking reflex: Hold baby upright with feet touching flat surface; baby makes coordinated stepping movements'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f12649df-9d0a-59ed-929f-1ec2117b93bc', '554d1457-3761-5c9b-aab0-1ccccccee970', 15, 'Procedure Execution', 'State clinical significance: Absence or asymmetry indicates CNS depression, birth trauma (e.g. brachial plexus palsy, clavicle fracture), or neurological impairment',
  1, false, 'both',
  '["cns depression","asymmetry indicates trauma","brachial plexus injury","neurological deficit"]'::jsonb, 'State clinical significance: Absence or asymmetry indicates CNS depression, birth trauma (e.g. brachial plexus palsy, clavicle fracture), or neurological impairment'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'bd7d56f8-aab8-5561-8d43-babff1a6d68b', '554d1457-3761-5c9b-aab0-1ccccccee970', 16, 'Post-Procedure & Documentation', 'Comfort and re-wrap baby warmly, place in safe position in cot',
  0.5, false, 'both',
  '["re-swaddle baby","place in cot safely","comfort infant"]'::jsonb, 'Comfort and re-wrap baby warmly, place in safe position in cot'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '499cbad3-ac6a-5587-8165-b7c74ba74010', '554d1457-3761-5c9b-aab0-1ccccccee970', 17, 'Post-Procedure & Documentation', 'Wash hands and document procedure, reflexes elicited, and newborn neurological findings',
  0.5, false, 'both',
  '["wash hands","document findings in medical record","chart results"]'::jsonb, 'Wash hands and document procedure, reflexes elicited, and newborn neurological findings'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Anatomy, Diameters and Sutures of the Foetal Skull (Station 19)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'b88c744e-60cc-506f-a80e-656556636b73', 'maternal-midwifery', 'Anatomy, Diameters and Sutures of the Foetal Skull', 'fetal-skull-anatomy-diameters',
  'Station 19', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'NMCN Midwifery Licensing Examination',
  4, 5, 10, 5, 420,
  'Using the model of the fetal skull and a pointer, demonstrate the regions, sutures, fontanelles, and state the longitudinal and transverse diameters with their measurements.', 'You are at Station 19 with a fetal skull model. The examiner asks you to demonstrate the anatomical areas, sutures, fontanelles, and describe all engaging diameters and their clinical significance in labor.', 'both',
  '["Foetal skull model","Anatomical pointer","Measuring tape / caliper"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 'b88c744e-60cc-506f-a80e-656556636b73', 1, true, 13)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e7099fe0-e954-5858-a16e-2047a464dcac', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 1, 'Preparation & Equipment', 'Greet the examiner, introduce self, and hold model of fetal skull correctly at eye level with both hands',
  0.25, false, 'both',
  '["greet examiner","introduce self","hold fetal skull correctly","eye level"]'::jsonb, 'Greet the examiner, introduce self, and hold model of fetal skull correctly at eye level with both hands'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '0659cb8b-e21c-521b-8d1c-cb6ac961b598', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 2, 'Procedure Execution', 'Identify and describe the three anatomical regions of the skull: Vault, Face, and Base',
  0.75, false, 'both',
  '["vault","face","base of skull","cranium"]'::jsonb, 'Identify and describe the three anatomical regions of the skull: Vault, Face, and Base'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'af1bbda4-7897-50e7-9f71-e29d28a16d57', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 3, 'Procedure Execution', 'Identify the bones of the skull: 2 Frontal, 2 Parietal, 1 Occipital, and 2 Temporal bones',
  1, false, 'both',
  '["frontal bones","parietal bones","occipital bone","temporal bones"]'::jsonb, 'Identify the bones of the skull: 2 Frontal, 2 Parietal, 1 Occipital, and 2 Temporal bones'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '50d5916c-d5dd-5929-9354-f5bebdcbc604', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 4, 'Procedure Execution', 'Identify and demonstrate the four main sutures using the pointer: Frontal suture, Sagittal suture, Coronal suture, Lambdoidal suture',
  1, false, 'both',
  '["frontal suture","sagittal suture","coronal suture","lambdoidal suture"]'::jsonb, 'Identify and demonstrate the four main sutures using the pointer: Frontal suture, Sagittal suture, Coronal suture, Lambdoidal suture'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e7ce491a-66a4-549b-9aac-cf8bb6bd99f5', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 5, 'Procedure Execution', 'Demonstrate Anterior Fontanelle (Bregma): Diamond shaped, formed by junction of sagittal, frontal and coronal sutures, closes at 18 months',
  1, false, 'both',
  '["anterior fontanelle","bregma","diamond shape","closes at 18 months","four suture lines"]'::jsonb, 'Demonstrate Anterior Fontanelle (Bregma): Diamond shaped, formed by junction of sagittal, frontal and coronal sutures, closes at 18 months'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '66e3e992-a6e6-5d11-bb88-d7ab7d84f7e0', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 6, 'Procedure Execution', 'Demonstrate Posterior Fontanelle (Lambda): Triangular shaped, formed by junction of sagittal and lambdoidal sutures, closes at 6-8 weeks',
  1, false, 'both',
  '["posterior fontanelle","lambda","triangular shape","closes at 6 to 8 weeks"]'::jsonb, 'Demonstrate Posterior Fontanelle (Lambda): Triangular shaped, formed by junction of sagittal and lambdoidal sutures, closes at 6-8 weeks'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'fda0b01c-8e4f-573b-ace3-41b4618e4832', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 7, 'Procedure Execution', 'Demonstrate Suboccipito-Bregmatic diameter: Extends from nape of neck to center of bregma, measures 9.5 cm (presenting in fully flexed vertex)',
  1, true, 'both',
  '["suboccipito-bregmatic","9.5 cm","fully flexed vertex","nape of neck to bregma"]'::jsonb, 'Demonstrate Suboccipito-Bregmatic diameter: Extends from nape of neck to center of bregma, measures 9.5 cm (presenting in fully flexed vertex)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c55528ab-d48b-5998-8674-ed042e2ef3db', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 8, 'Procedure Execution', 'Demonstrate Suboccipito-Frontal diameter: Extends from nape of neck to front of bregma, measures 10.0 cm (partially flexed vertex)',
  0.75, false, 'both',
  '["suboccipito-frontal","10 cm","partially flexed vertex"]'::jsonb, 'Demonstrate Suboccipito-Frontal diameter: Extends from nape of neck to front of bregma, measures 10.0 cm (partially flexed vertex)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6351df1f-6373-5f2c-8782-4fbe465c8ac3', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 9, 'Procedure Execution', 'Demonstrate Occipito-Frontal diameter: Extends from occipital protuberance to glabella / root of nose, measures 11.5 cm (deflexed head)',
  0.75, false, 'both',
  '["occipito-frontal","11.5 cm","deflexed head","persistent occipito-posterior"]'::jsonb, 'Demonstrate Occipito-Frontal diameter: Extends from occipital protuberance to glabella / root of nose, measures 11.5 cm (deflexed head)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a0c42ba9-e985-5ada-aef9-7ac4c1386598', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 10, 'Procedure Execution', 'Demonstrate Mento-Vertical diameter: Extends from tip of chin to highest point of vertex, measures 13.5 cm (brow presentation, cannot deliver vaginally)',
  1, false, 'both',
  '["mento-vertical","13.5 cm","brow presentation","largest diameter"]'::jsonb, 'Demonstrate Mento-Vertical diameter: Extends from tip of chin to highest point of vertex, measures 13.5 cm (brow presentation, cannot deliver vaginally)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '0f3b73dc-c576-5230-82bc-abb3dad09135', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 11, 'Procedure Execution', 'Demonstrate Submento-Bregmatic (9.5 cm) and Submento-Vertical (11.5 cm) diameters in face presentation',
  0.5, false, 'both',
  '["submento-bregmatic","9.5 cm","face presentation"]'::jsonb, 'Demonstrate Submento-Bregmatic (9.5 cm) and Submento-Vertical (11.5 cm) diameters in face presentation'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '77942859-ce41-58d3-b623-85ea2f346e59', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 12, 'Procedure Execution', 'Demonstrate transverse diameters: Biparietal diameter (9.5 cm between parietal eminences) and Bitemporal diameter (8.2 cm between coronal suture ends)',
  0.75, false, 'both',
  '["biparietal diameter 9.5 cm","bitemporal diameter 8.2 cm","transverse diameters"]'::jsonb, 'Demonstrate transverse diameters: Biparietal diameter (9.5 cm between parietal eminences) and Bitemporal diameter (8.2 cm between coronal suture ends)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '482b882f-b622-5da3-8516-7b112ea770f2', 'b1ccff6d-4cfb-5264-85ee-9bde1b9b7a8b', 13, 'Post-Procedure & Documentation', 'Explain moulding: Overlapping of cranial bones at sutures to reduce diameters for passage through the birth canal; conclude procedure',
  0.25, false, 'both',
  '["moulding of fetal skull","overlapping of bones","conclude procedure","thank examiner"]'::jsonb, 'Explain moulding: Overlapping of cranial bones at sutures to reduce diameters for passage through the birth canal; conclude procedure'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Comprehensive Physical Examination of the Newborn (Station 6)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'fb0c3f66-41d0-510e-9fc7-95f754d2914b', 'neonatal-pediatric', 'Comprehensive Physical Examination of the Newborn', 'physical-examination-newborn',
  'Station 6', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for Midwives',
  6, 6, 10, 5, 420,
  'Perform a systematic head-to-toe physical examination of the newborn infant. Explain reasons, observe asepsis, describe each body system examined, and state normal and abnormal findings.', 'You are assigned to examine a newly delivered neonate. Perform a head-to-toe physical assessment while explaining your findings and clinical rationale to the examiner.', 'both',
  '["Warm examination cot","Baby weighing scale","Measuring tape","Neonatal stethoscope","Penlight","Thermometer","Clean gloves"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('20e6e06f-241f-5c30-ad75-6ea53365c624', 'fb0c3f66-41d0-510e-9fc7-95f754d2914b', 1, true, 12)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '12382029-e203-5430-8556-2bdc65ffef07', '20e6e06f-241f-5c30-ad75-6ea53365c624', 1, 'Preparation & Equipment', 'Greet examiner, introduce self, and explain procedure to mother to gain consent',
  0.5, false, 'both',
  '["greet examiner","introduce self","explain to mother","gain consent"]'::jsonb, 'Greet examiner, introduce self, and explain procedure to mother to gain consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '579c3c85-9a72-5807-aa31-79fae82413e7', '20e6e06f-241f-5c30-ad75-6ea53365c624', 2, 'Preparation & Equipment', 'State reasons for physical examination: assess extrauterine transition, detect congenital anomalies, and establish baseline health status',
  0.5, false, 'both',
  '["extrauterine transition","detect congenital anomalies","baseline health","birth injuries"]'::jsonb, 'State reasons for physical examination: assess extrauterine transition, detect congenital anomalies, and establish baseline health status'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '93d11e93-fb2f-57f0-b9f0-f01e63da1f7a', '20e6e06f-241f-5c30-ad75-6ea53365c624', 3, 'Preparation & Equipment', 'Perform hand hygiene, ensure warm draft-free room under radiant heater/light, and expose baby systematically',
  0.5, false, 'both',
  '["hand hygiene","warm room","prevent hypothermia","radiant warmer"]'::jsonb, 'Perform hand hygiene, ensure warm draft-free room under radiant heater/light, and expose baby systematically'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '25768260-b7d3-56dd-b930-1f241cb445c4', '20e6e06f-241f-5c30-ad75-6ea53365c624', 4, 'Procedure Execution', 'Assess general appearance: posture (flexed), skin color (pink, absence of central cyanosis, jaundice or pallor), cry, muscle tone, and respiratory effort',
  1, false, 'both',
  '["flexed posture","pink color","vigorous cry","good muscle tone","no central cyanosis"]'::jsonb, 'Assess general appearance: posture (flexed), skin color (pink, absence of central cyanosis, jaundice or pallor), cry, muscle tone, and respiratory effort'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '345a30c6-0d49-50e8-a30d-cef7f30f24e4', '20e6e06f-241f-5c30-ad75-6ea53365c624', 5, 'Procedure Execution', 'Examine Head: Check size, shape, moulding, caput succedaneum vs cephalhematoma; palpate anterior and posterior fontanelles and sutures',
  1, false, 'both',
  '["head shape","caput succedaneum","cephalhematoma","anterior fontanelle flat and soft","sutures"]'::jsonb, 'Examine Head: Check size, shape, moulding, caput succedaneum vs cephalhematoma; palpate anterior and posterior fontanelles and sutures'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9c080060-a43e-5fc4-ae25-c3950c54c41c', '20e6e06f-241f-5c30-ad75-6ea53365c624', 6, 'Procedure Execution', 'Examine Face, Eyes, Ears, Nose: Check for dysmorphic features, subconjunctival haemorrhage, discharge, patent nares (no flaring), ear alignment and recoil',
  1, false, 'both',
  '["eyes clean","no discharge","ear alignment at eye level","patent nares","no nasal flaring"]'::jsonb, 'Examine Face, Eyes, Ears, Nose: Check for dysmorphic features, subconjunctival haemorrhage, discharge, patent nares (no flaring), ear alignment and recoil'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c78943d5-1924-5fe6-b00e-e1f72cd568c6', '20e6e06f-241f-5c30-ad75-6ea53365c624', 7, 'Procedure Execution', 'Examine Mouth: Inspect lips, gums, hard and soft palates using gloved finger/penlight to exclude cleft lip/palate, Epstein pearls, and assess sucking',
  1, false, 'both',
  '["palpate palate with gloved finger","exclude cleft lip and palate","intact palate","sucking reflex"]'::jsonb, 'Examine Mouth: Inspect lips, gums, hard and soft palates using gloved finger/penlight to exclude cleft lip/palate, Epstein pearls, and assess sucking'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'edd15dfa-f8bf-5ec1-b720-20b95ba327e0', '20e6e06f-241f-5c30-ad75-6ea53365c624', 8, 'Procedure Execution', 'Examine Neck, Chest and Heart: Palpate clavicles (exclude fracture), inspect chest symmetry, count respirations (30-60 bpm, no retractions), auscultate apical heart rate (120-160 bpm)',
  1, false, 'both',
  '["palpate clavicles intact","no chest indrawing","heart rate 120-160","respirations 30-60","clear breath sounds"]'::jsonb, 'Examine Neck, Chest and Heart: Palpate clavicles (exclude fracture), inspect chest symmetry, count respirations (30-60 bpm, no retractions), auscultate apical heart rate (120-160 bpm)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c24a433c-0008-5796-8045-ddc29d006694', '20e6e06f-241f-5c30-ad75-6ea53365c624', 9, 'Procedure Execution', 'Examine Abdomen and Cord: Inspect contour (soft, slightly protuberant), palpate liver/spleen, inspect umbilical cord for 3 vessels (2 arteries, 1 vein) and no bleeding/discharge',
  1, false, 'both',
  '["soft abdomen","three cord vessels","two arteries one vein","no cord bleeding","umbilicus clean"]'::jsonb, 'Examine Abdomen and Cord: Inspect contour (soft, slightly protuberant), palpate liver/spleen, inspect umbilical cord for 3 vessels (2 arteries, 1 vein) and no bleeding/discharge'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3e9b18f0-38f0-55d0-bdde-6d22f22c346f', '20e6e06f-241f-5c30-ad75-6ea53365c624', 10, 'Procedure Execution', 'Examine Genitalia and Anus: For male, check urethral meatus at tip, descended testes in scrotum, no hydrocele; for female, labia majora covering minora; check anal patency and meconium passage',
  1, false, 'both',
  '["descended testes","urethral meatus central","female labia","patent anus","passage of meconium"]'::jsonb, 'Examine Genitalia and Anus: For male, check urethral meatus at tip, descended testes in scrotum, no hydrocele; for female, labia majora covering minora; check anal patency and meconium passage'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '81f47dc0-518d-51c2-879f-4015b6511d41', '20e6e06f-241f-5c30-ad75-6ea53365c624', 11, 'Procedure Execution', 'Examine Spine and Extremities: Inspect back/spine for spina bifida/sacral dimple; check limbs, count 10 fingers/toes (exclude polydactyly/syndactyly), check hip stability (Ortolani/Barlow test)',
  1, false, 'both',
  '["intact spine","no sacral dimple","count ten fingers and toes","no polydactyly","hip abduction stable"]'::jsonb, 'Examine Spine and Extremities: Inspect back/spine for spina bifida/sacral dimple; check limbs, count 10 fingers/toes (exclude polydactyly/syndactyly), check hip stability (Ortolani/Barlow test)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4057d832-1642-57e1-afb7-e1e76e657889', '20e6e06f-241f-5c30-ad75-6ea53365c624', 12, 'Post-Procedure & Documentation', 'Dress and swaddle baby warmly, return to mother, wash hands, and document all findings in newborn examination chart',
  0.5, false, 'both',
  '["swaddle baby","return to mother","wash hands","document complete examination"]'::jsonb, 'Dress and swaddle baby warmly, return to mother, wash hands, and document all findings in newborn examination chart'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Resuscitation of the Newborn by Face Mask Ventilation (Station 1)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '5be44165-589e-547e-8749-971e7c3ae754', 'neonatal-pediatric', 'Resuscitation of the Newborn by Face Mask Ventilation', 'resuscitation-newborn-face-mask',
  'Station 1', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'NMCN Practical OSCE Examination',
  7, 7, 10, 5, 420,
  'Demonstrate immediate neonatal resuscitation using a bag and face mask on the newborn mannequin. Follow Helping Babies Breathe (HBB) / NRP guidelines within the Golden Minute.', 'A neonate has just been delivered apnoic and limp with thick meconium-stained amniotic fluid. You must initiate immediate resuscitation within the Golden Minute. Demonstrate your actions and report to the examiner.', 'both',
  '["Newborn resuscitation mannequin","Self-inflating bag (250-500ml) with pressure release valve","Anatomical face masks (sizes 0 and 1)","Suction apparatus / Penguin suction bulb","Radiant warmer / Resuscitaire","Pre-warmed dry towels","Stethoscope","Clock timer"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('d33beb75-94a4-584a-b7d5-6698a9493ee6', '5be44165-589e-547e-8749-971e7c3ae754', 1, true, 13)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8547b81d-ee19-53bd-8df0-e6874b2071ad', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 1, 'Preparation & Equipment', 'Ensure adequate lighting and warmth in the delivery room; start the clock/timer immediately upon delivery',
  0.5, false, 'both',
  '["warm delivery room","start timer","clock timer at delivery","prevent heat loss"]'::jsonb, 'Ensure adequate lighting and warmth in the delivery room; start the clock/timer immediately upon delivery'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4c3b3e17-dae3-58c7-9e8e-4cb743700342', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 2, 'Preparation & Equipment', 'Assess APGAR / initial vitality: breathing/crying, heart rate, and muscle tone within the first seconds',
  0.5, false, 'both',
  '["assess breathing","assess heart rate","assess tone","apgar score"]'::jsonb, 'Assess APGAR / initial vitality: breathing/crying, heart rate, and muscle tone within the first seconds'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '310046ec-bd93-5493-b5f5-66acac6ae814', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 3, 'Procedure Execution', 'Transfer baby to pre-warmed resuscitaire; dry baby quickly and thoroughly from head to toe, removing wet linen',
  0.75, false, 'both',
  '["dry thoroughly","remove wet cloth","replace with warm dry towel","radiant warmer"]'::jsonb, 'Transfer baby to pre-warmed resuscitaire; dry baby quickly and thoroughly from head to toe, removing wet linen'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'fb98a088-029f-58d1-80b4-bda6fdf11118', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 4, 'Procedure Execution', 'Position baby with neck slightly extended in sniffing position by placing a small shoulder roll (towel) under shoulders',
  0.75, true, 'both',
  '["sniffing position","shoulder roll","slight neck extension","open airway"]'::jsonb, 'Position baby with neck slightly extended in sniffing position by placing a small shoulder roll (towel) under shoulders'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3665b9d2-7caf-5879-8251-f7a2052c451a', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 5, 'Procedure Execution', 'Clear upper airway: Gentle suctioning of mouth first, then nose (M before N) using suction bulb or catheter (depth not exceeding 2 cm / 2 inches)',
  1, false, 'both',
  '["suction mouth then nose","bulb suction","suction depth under 2 inches","do not suction deeply"]'::jsonb, 'Clear upper airway: Gentle suctioning of mouth first, then nose (M before N) using suction bulb or catheter (depth not exceeding 2 cm / 2 inches)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9119af12-6582-5187-9cb4-11ebfb61c7af', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 6, 'Procedure Execution', 'Stimulate breathing by gently rubbing baby''s back or flicking the soles of the feet (maximum twice)',
  0.5, false, 'both',
  '["tactile stimulation","rub back","flick soles","stimulate breathing"]'::jsonb, 'Stimulate breathing by gently rubbing baby''s back or flicking the soles of the feet (maximum twice)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'baca7bef-30e7-53c4-a397-4734716fcfc5', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 7, 'Procedure Execution', 'Re-evaluate within 30 seconds: If baby remains gasping, apnoic, or HR < 100 bpm, initiate Positive Pressure Ventilation (PPV) immediately within Golden Minute',
  1, true, 'both',
  '["re-evaluate heart rate","apnoea or hr under 100","positive pressure ventilation","golden minute"]'::jsonb, 'Re-evaluate within 30 seconds: If baby remains gasping, apnoic, or HR < 100 bpm, initiate Positive Pressure Ventilation (PPV) immediately within Golden Minute'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e311bece-bbd6-5e41-b244-a910ae73f0a0', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 8, 'Procedure Execution', 'Select correct mask size (size 1 for term, size 0 for preterm) covering mouth, nose, and chin without covering eyes',
  0.75, false, 'both',
  '["correct mask size","covers chin mouth nose","does not cover eyes"]'::jsonb, 'Select correct mask size (size 1 for term, size 0 for preterm) covering mouth, nose, and chin without covering eyes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3fe92d97-2552-539e-9b30-f1f4b15a7f48', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 9, 'Procedure Execution', 'Apply mask using C-E grip with thumb and index finger holding mask and remaining three fingers lifting mandible upward into mask to create airtight seal',
  1, false, 'both',
  '["c-e grip","airtight seal","lift jaw upward","do not press soft tissue"]'::jsonb, 'Apply mask using C-E grip with thumb and index finger holding mask and remaining three fingers lifting mandible upward into mask to create airtight seal'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c06d713e-f1c8-5e45-a09c-879c76fe4329', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 10, 'Procedure Execution', 'Ventilate at a rate of 40-60 breaths per minute, calling cadence: ''Squeeze, two, three, squeeze, two, three''',
  1, false, 'both',
  '["40 to 60 breaths per minute","squeeze two three","effective ventilation cadence"]'::jsonb, 'Ventilate at a rate of 40-60 breaths per minute, calling cadence: ''Squeeze, two, three, squeeze, two, three'''
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cb1fe806-6313-5bf1-b333-626947498389', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 11, 'Procedure Execution', 'Check chest rise: If chest is not rising, perform ventilation corrective steps (MRSOPA: Mask readjust, Reposition airway, Suction mouth/nose, Open mouth, Pressure increase, Alternative airway)',
  1, false, 'both',
  '["observe chest rise","mrsopa corrective steps","airtight seal adjustment"]'::jsonb, 'Check chest rise: If chest is not rising, perform ventilation corrective steps (MRSOPA: Mask readjust, Reposition airway, Suction mouth/nose, Open mouth, Pressure increase, Alternative airway)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6acf17fd-14dc-56cc-bb63-29f2f2c2814c', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 12, 'Procedure Execution', 'Auscultate heart rate after 30 seconds of effective ventilation: If HR > 100 bpm and baby breathes spontaneously, gradually discontinue PPV and provide supportive care',
  0.75, false, 'both',
  '["auscultate heart rate","hr over 100","spontaneous breathing","wean ventilation"]'::jsonb, 'Auscultate heart rate after 30 seconds of effective ventilation: If HR > 100 bpm and baby breathes spontaneously, gradually discontinue PPV and provide supportive care'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2e3a0bed-7360-5745-869c-d18b54bc1e54', 'd33beb75-94a4-584a-b7d5-6698a9493ee6', 13, 'Post-Procedure & Documentation', 'Keep infant warm (skin-to-skin or incubator), document resuscitation steps, duration, APGAR scores, and notify pediatrician/NICU',
  0.5, false, 'both',
  '["skin to skin","document resuscitation duration","record apgar score","transfer to nursery"]'::jsonb, 'Keep infant warm (skin-to-skin or incubator), document resuscitation steps, duration, APGAR scores, and notify pediatrician/NICU'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Insertion of Nasogastric (NG) Tube (Station 3)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'b88af1c8-8cbf-56fd-a406-cc3543700413', 'fundamental-nursing', 'Insertion of Nasogastric (NG) Tube', 'insertion-nasogastric-tube',
  'Station 3', 'General Nursing Practicum / NMCN', 'Procedure Station Examination',
  8, 8, 10, 5, 420,
  'Demonstrate the complete procedure for inserting a nasogastric tube into an adult patient model. Observe sterile technique, measurement, insertion technique, placement verification, and documentation.', 'You are ordered to insert a nasogastric tube for decompression and enteral feeding for an adult patient. Carry out the procedure on the mannequin model and explain each step to the examiner.', 'both',
  '["Mannequin with nasal passages","Nasogastric tube (Size 14-16 Fr)","Water-soluble lubricant (K-Y Jelly)","20ml / 50ml enteral syringe","Stethoscope","Litmus / pH indicator paper","Hypoallergenic adhesive tape","Emesis basin (kidney dish)","Cup of water with straw","Clean gloves","Waterproof towel / mackintosh"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('494a1832-c159-5ed9-aedc-99bd9e949a2c', 'b88af1c8-8cbf-56fd-a406-cc3543700413', 1, true, 13)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '56738a6d-e42c-575d-9fab-807fcc5dd568', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 1, 'Preparation & Equipment', 'Identify the patient correctly using two identifiers, check physician''s order, and explain procedure to reduce anxiety and gain consent',
  0.5, false, 'both',
  '["identify patient","check physician order","explain procedure","gain consent"]'::jsonb, 'Identify the patient correctly using two identifiers, check physician''s order, and explain procedure to reduce anxiety and gain consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '147b0d91-89aa-5199-adb3-a3b56adc380d', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 2, 'Preparation & Equipment', 'Perform hand hygiene and assemble all required equipment neatly on a sterile tray / trolley',
  0.5, false, 'both',
  '["hand hygiene","assemble tray","equipment organized"]'::jsonb, 'Perform hand hygiene and assemble all required equipment neatly on a sterile tray / trolley'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f50c0940-06c1-5b09-9170-5c9554e57780', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 3, 'Preparation & Equipment', 'Position patient in high Fowler''s position (or sitting upright at 45-90°) with pillow behind head and shoulders; place protective towel across chest',
  0.5, false, 'both',
  '["high fowlers position","sitting upright","towel across chest","emesis basin handy"]'::jsonb, 'Position patient in high Fowler''s position (or sitting upright at 45-90°) with pillow behind head and shoulders; place protective towel across chest'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'bf3e46f8-48f6-56b5-b354-9d98d2d8aaaf', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 4, 'Preparation & Equipment', 'Assess patency of nares: Ask patient to occlude one nostril and breathe through the other; select nostril with greater airflow',
  0.5, false, 'both',
  '["assess nostril patency","select clearer nostril","inspect nasal septum"]'::jsonb, 'Assess patency of nares: Ask patient to occlude one nostril and breathe through the other; select nostril with greater airflow'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '255da305-815b-59c1-8470-43021cacdd66', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 5, 'Procedure Execution', 'Measure tube length accurately using NEX method: From tip of Nose to Earlobe, then from Earlobe to Xiphoid process; mark distance with adhesive tape',
  1, true, 'both',
  '["nex measurement","nose to earlobe to xiphoid","mark tube with tape","correct measurement"]'::jsonb, 'Measure tube length accurately using NEX method: From tip of Nose to Earlobe, then from Earlobe to Xiphoid process; mark distance with adhesive tape'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '09719c42-6b9a-55ea-ad55-124ac3aef8ba', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 6, 'Procedure Execution', 'Put on clean gloves and lubricate first 7.5 to 10 cm (3-4 inches) of tube tip with water-soluble lubricant',
  0.5, false, 'both',
  '["clean gloves","water soluble lubricant","lubricate tube tip","do not use oil"]'::jsonb, 'Put on clean gloves and lubricate first 7.5 to 10 cm (3-4 inches) of tube tip with water-soluble lubricant'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '208a78c1-1a4a-5c15-a7b5-342174196afe', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 7, 'Procedure Execution', 'Instruct patient to tilt head back slightly; gently insert tube into selected nostril advancing along nasal floor towards ear until posterior pharynx is reached',
  1, false, 'both',
  '["tilt head back slightly","advance along nasal floor","gentle insertion","aim towards ear"]'::jsonb, 'Instruct patient to tilt head back slightly; gently insert tube into selected nostril advancing along nasal floor towards ear until posterior pharynx is reached'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'eb4aaa6d-3ac6-55a7-b335-882db52531b5', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 8, 'Procedure Execution', 'When tube reaches pharynx, instruct patient to tilt head forward (chin to chest) and swallow sips of water (or dry swallow); advance tube 5-10 cm with each swallow',
  1, true, 'both',
  '["chin to chest","swallow sips of water","advance tube with swallowing","synchronize with swallow"]'::jsonb, 'When tube reaches pharynx, instruct patient to tilt head forward (chin to chest) and swallow sips of water (or dry swallow); advance tube 5-10 cm with each swallow'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd0c2c076-5cbe-5093-95f7-cbfda741ddd4', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 9, 'Procedure Execution', 'If patient coughs, chokes, becomes cyanotic or cannot speak, stop immediately, pull tube back into pharynx and let patient rest (prevents tracheal entry)',
  1, true, 'both',
  '["check for choking or coughing","stop if resistance","pull back if in trachea","ensure airway safety"]'::jsonb, 'If patient coughs, chokes, becomes cyanotic or cannot speak, stop immediately, pull tube back into pharynx and let patient rest (prevents tracheal entry)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c81d6e53-54d0-57e8-99fb-d7882bc66ace', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 10, 'Procedure Execution', 'Advance tube until previously marked tape indicator reaches patient''s nostril',
  0.5, false, 'both',
  '["advance to marked line","reach tape indicator"]'::jsonb, 'Advance tube until previously marked tape indicator reaches patient''s nostril'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ee73d3f0-4bb8-5df5-b28c-0f17de4c1c38', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 11, 'Procedure Execution', 'Verify tube placement: Aspirate gastric contents with syringe and check pH using litmus paper (pH ≤ 5.5 confirms gastric placement) AND auscultate whoosh sound over epigastrium while injecting 10-20ml air',
  2, true, 'both',
  '["aspirate gastric juice","check ph under 5.5","auscultate whoosh sound","epigastric auscultation","verify placement"]'::jsonb, 'Verify tube placement: Aspirate gastric contents with syringe and check pH using litmus paper (pH ≤ 5.5 confirms gastric placement) AND auscultate whoosh sound over epigastrium while injecting 10-20ml air'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e78942a5-6bcd-5a13-aea6-4a084bae1c55', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 12, 'Post-Procedure & Documentation', 'Secure tube to nose using split adhesive tape / fixation device without pressing on nostril tissue, and clip tube to patient''s gown',
  0.5, false, 'both',
  '["secure tube to nose","hypoallergenic tape","fasten to gown"]'::jsonb, 'Secure tube to nose using split adhesive tape / fixation device without pressing on nostril tissue, and clip tube to patient''s gown'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3ba8095b-bc25-5e68-8af1-07f75e106dac', '494a1832-c159-5ed9-aedc-99bd9e949a2c', 13, 'Post-Procedure & Documentation', 'Clean patient''s face, remove gloves, wash hands, and document date, time, tube type/size, insertion distance, verification method, and aspirate characteristics',
  0.5, false, 'both',
  '["remove gloves","wash hands","document tube size and ph","chart procedure"]'::jsonb, 'Clean patient''s face, remove gloves, wash hands, and document date, time, tube type/size, insertion distance, verification method, and aspirate characteristics'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Clinical Hand Washing and Hand Hygiene Technique (Station 1)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'bbfab427-2422-560c-af04-d486d2775c7c', 'fundamental-nursing', 'Clinical Hand Washing and Hand Hygiene Technique', 'hand-washing-hygiene',
  'Station 1', 'Ahmadu Bello University (ABU) Zaria', 'Practicum Examination NURS 307',
  9, 9, 8, 4, 360,
  'Demonstrate the WHO 6-step medical hand hygiene procedure using running water and soap. Explain the importance of infection prevention and each step.', 'You are entering the surgical ward to care for a patient. Demonstrate the proper medical hand washing procedure at the sink, verbalizing each step to the examiner.', 'both',
  '["Sink with running water","Liquid soap dispenser","Single-use paper towels","Foot-operated pedal waste bin"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('8a349f03-5258-5df5-ba90-4a6b443f8b02', 'bbfab427-2422-560c-af04-d486d2775c7c', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2deced41-94a9-5e8e-bd81-24f564d96c2d', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 1, 'Preparation & Equipment', 'Candidate greets examiner, introduces self, and explains rationale: prevent cross-contamination and hospital-acquired infections',
  0.25, false, 'both',
  '["greet examiner","introduce self","prevent infection","cross contamination"]'::jsonb, 'Candidate greets examiner, introduces self, and explains rationale: prevent cross-contamination and hospital-acquired infections'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6d9a425d-8d8e-5240-95ec-9cb5ef68a750', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 2, 'Preparation & Equipment', 'Remove rings, wristwatch and roll up sleeves above elbows; stand away from sink so clothes do not touch sink edges',
  0.25, false, 'both',
  '["remove jewellery","roll up sleeves","do not touch sink","stand clear"]'::jsonb, 'Remove rings, wristwatch and roll up sleeves above elbows; stand away from sink so clothes do not touch sink edges'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a8552a48-bfbb-5b16-b20a-55285f6eb2db', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 3, 'Procedure Execution', 'Turn on tap, wet hands with clean water thoroughly and apply sufficient liquid soap (coin size / 3-5ml) to cover all hand surfaces',
  0.5, false, 'both',
  '["wet hands with water","apply soap","coin size soap"]'::jsonb, 'Turn on tap, wet hands with clean water thoroughly and apply sufficient liquid soap (coin size / 3-5ml) to cover all hand surfaces'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7133d096-4beb-5367-a051-2faa421203dd', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 4, 'Procedure Execution', 'Step 1: Rub hands palm to palm in a circular motion',
  1, false, 'both',
  '["palm to palm","rub palms together","generate lather"]'::jsonb, 'Step 1: Rub hands palm to palm in a circular motion'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd624ee6a-9db2-5ba1-9902-00e6558f5f23', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 5, 'Procedure Execution', 'Step 2: Rub right palm over left dorsum with interlaced fingers, and vice versa',
  1, false, 'both',
  '["right palm over left dorsum","left palm over right dorsum","fingers interlaced"]'::jsonb, 'Step 2: Rub right palm over left dorsum with interlaced fingers, and vice versa'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3eda3557-c171-5949-9465-307a1c2cd40a', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 6, 'Procedure Execution', 'Step 3: Rub palm to palm with fingers interlaced',
  1, false, 'both',
  '["palm to palm with fingers interlaced","clean webbing between fingers"]'::jsonb, 'Step 3: Rub palm to palm with fingers interlaced'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f18ed511-eb15-5242-93cf-4c5d2be1fbb2', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 7, 'Procedure Execution', 'Step 4: Rub backs of fingers to opposing palms with fingers interlocked',
  1, false, 'both',
  '["backs of fingers to opposing palms","fingers interlocked"]'::jsonb, 'Step 4: Rub backs of fingers to opposing palms with fingers interlocked'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7187f900-43f7-529e-87ca-bcfe11a119ad', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 8, 'Procedure Execution', 'Step 5: Rotational rubbing of left thumb clasped in right palm, and vice versa',
  1, false, 'both',
  '["rotational rubbing of thumb","clean thumbs","clasped thumb"]'::jsonb, 'Step 5: Rotational rubbing of left thumb clasped in right palm, and vice versa'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b79fd387-7610-561d-9c9b-fe2b4a86782f', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 9, 'Procedure Execution', 'Step 6: Rotational rubbing backwards and forwards with clasped fingers of right hand in left palm, and vice versa',
  1, false, 'both',
  '["clasped fingernails in palm","clean fingertips and nails","rotational motion in palm"]'::jsonb, 'Step 6: Rotational rubbing backwards and forwards with clasped fingers of right hand in left palm, and vice versa'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f5ee353b-5f31-511e-b20c-5fda28d3e05c', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 10, 'Post-Procedure & Documentation', 'Rinse hands thoroughly under running water keeping hands lower than elbows so contaminated water drains off fingertips',
  0.5, false, 'both',
  '["rinse hands thoroughly","hands lower than elbows","water flows off fingertips"]'::jsonb, 'Rinse hands thoroughly under running water keeping hands lower than elbows so contaminated water drains off fingertips'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b1a98dcd-0e3f-5ab7-8337-3069ca3570a8', '8a349f03-5258-5df5-ba90-4a6b443f8b02', 11, 'Post-Procedure & Documentation', 'Dry hands completely with single-use paper towel from fingers to wrists; use paper towel / elbow to turn off tap without recontaminating hands',
  0.5, true, 'both',
  '["dry with paper towel","turn off tap with paper towel","do not recontaminate hands","discard in pedal bin"]'::jsonb, 'Dry hands completely with single-use paper towel from fingers to wrists; use paper towel / elbow to turn off tap without recontaminating hands'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Preparation of an Unoccupied Hospital Bed (Station 5)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'bdd2d610-a6bb-51c9-bbf9-db76a2ef8de6', 'fundamental-nursing', 'Preparation of an Unoccupied Hospital Bed', 'preparation-unoccupied-bed',
  'Station 5', 'General Nursing Practicum / NMCN', 'Nursing Practicum Examination',
  10, 10, 11, 5.5, 480,
  'Demonstrate the complete method for stripping and making an unoccupied hospital bed. Observe ergonomics, hygiene, tight mitered corners, and neat finished bed.', 'A patient has been discharged and the bed has been sanitized. Prepare a clean, unoccupied closed bed ready for a new admission following nursing principles.', 'both',
  '["Hospital bed with mattress","2 straight chairs placed back-to-back","Clean bottom sheet","Mackintosh (rubber draw sheet)","Cotton draw sheet","Top sheet","Blanket","Bedspread (counterpane)","Pillow and pillowcase","Laundry hamper / soiled linen bag"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('468f044d-0153-5f46-a5fa-bfa316c11161', 'bdd2d610-a6bb-51c9-bbf9-db76a2ef8de6', 1, true, 13)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '08932427-b431-5f66-81c2-5398ec4b95ba', '468f044d-0153-5f46-a5fa-bfa316c11161', 1, 'Preparation & Equipment', 'Greet examiner, explain procedure, wash and dry hands, and assemble clean linen in reverse order of use on two chairs at foot of bed',
  0.5, false, 'both',
  '["greet examiner","wash hands","stack linen reverse order","chairs back to back"]'::jsonb, 'Greet examiner, explain procedure, wash and dry hands, and assemble clean linen in reverse order of use on two chairs at foot of bed'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ce3160f2-ae42-5f94-84d6-388e637cea4d', '468f044d-0153-5f46-a5fa-bfa316c11161', 2, 'Preparation & Equipment', 'Check bed height, adjust to comfortable working height, switch off fan to prevent air current dispersal of organisms',
  0.5, false, 'both',
  '["adjust bed height","switch off fan","ergonomics"]'::jsonb, 'Check bed height, adjust to comfortable working height, switch off fan to prevent air current dispersal of organisms'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a3135cfc-0f3c-50d1-a9aa-d801c39f050e', '468f044d-0153-5f46-a5fa-bfa316c11161', 3, 'Procedure Execution', 'Strip soiled linen: Remove pillow and place on chair, strip each sheet from head to foot, roll inward without shaking, place in laundry bag',
  1, false, 'both',
  '["strip linen head to foot","roll inward","do not shake linen","put in laundry hamper"]'::jsonb, 'Strip soiled linen: Remove pillow and place on chair, strip each sheet from head to foot, roll inward without shaking, place in laundry bag'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '62198558-1172-58b7-af52-49a13a186668', '468f044d-0153-5f46-a5fa-bfa316c11161', 4, 'Procedure Execution', 'Inspect mattress: Clean/carbolize mattress if required and turn mattress according to ward protocol',
  0.5, false, 'both',
  '["inspect mattress","turn mattress","damp dust mattress"]'::jsonb, 'Inspect mattress: Clean/carbolize mattress if required and turn mattress according to ward protocol'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '301309e8-e5e3-518c-bb34-c9107cfe36c9', '468f044d-0153-5f46-a5fa-bfa316c11161', 5, 'Procedure Execution', 'Place clean bottom sheet right side up, align center fold along midline of mattress, unfold evenly leaving sufficient overhang at head end',
  1, false, 'both',
  '["bottom sheet right side up","center fold along midline","overhang at head end"]'::jsonb, 'Place clean bottom sheet right side up, align center fold along midline of mattress, unfold evenly leaving sufficient overhang at head end'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4284c3b3-0a6a-56dc-989a-8eedc5aa4cac', '468f044d-0153-5f46-a5fa-bfa316c11161', 6, 'Procedure Execution', 'Tuck bottom sheet firmly under mattress at head end and make a neat mitred (envelope) corner; tuck along the side',
  1.5, true, 'both',
  '["tuck under at head end","make mitred corner","miter corner","tuck side firmly"]'::jsonb, 'Tuck bottom sheet firmly under mattress at head end and make a neat mitred (envelope) corner; tuck along the side'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '70691da3-025d-5cee-bf5e-fe37d9cced98', '468f044d-0153-5f46-a5fa-bfa316c11161', 7, 'Procedure Execution', 'Place mackintosh (waterproof sheet) across middle third of bed, tuck tightly under mattress',
  0.75, false, 'both',
  '["mackintosh middle third","rubber sheet","tuck under mattress"]'::jsonb, 'Place mackintosh (waterproof sheet) across middle third of bed, tuck tightly under mattress'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e5bafda0-cfbf-5dee-af55-92dd4e14591c', '468f044d-0153-5f46-a5fa-bfa316c11161', 8, 'Procedure Execution', 'Place cotton draw sheet over mackintosh covering it completely (5 cm wider), tuck tightly under mattress on near side',
  1, false, 'both',
  '["cotton draw sheet","covers mackintosh","tuck tightly under mattress"]'::jsonb, 'Place cotton draw sheet over mackintosh covering it completely (5 cm wider), tuck tightly under mattress on near side'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '27e54faa-16da-5196-823d-77c863f0c916', '468f044d-0153-5f46-a5fa-bfa316c11161', 9, 'Procedure Execution', 'Move to opposite side of bed: Tuck bottom sheet, make mitred corner at head end, pull mackintosh and draw sheet firmly to remove all wrinkles, tuck tightly',
  1.5, false, 'both',
  '["move to opposite side","mitre corner opposite side","smooth all wrinkles","tuck draw sheet tightly"]'::jsonb, 'Move to opposite side of bed: Tuck bottom sheet, make mitred corner at head end, pull mackintosh and draw sheet firmly to remove all wrinkles, tuck tightly'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6e40d661-d7d2-515c-950e-5257f78ed691', '468f044d-0153-5f46-a5fa-bfa316c11161', 10, 'Procedure Execution', 'Place top sheet wrong side up with center fold in middle, tuck at foot end and make mitred corner at bottom; place blanket and bedspread',
  1.5, false, 'both',
  '["top sheet wrong side up","tuck at foot end","mitred corner at foot","bedspread and blanket"]'::jsonb, 'Place top sheet wrong side up with center fold in middle, tuck at foot end and make mitred corner at bottom; place blanket and bedspread'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '159ad130-959c-5d1f-85aa-04a043cff811', '468f044d-0153-5f46-a5fa-bfa316c11161', 11, 'Procedure Execution', 'Fold top sheet back over blanket/bedspread at head end to make neat 15-20 cm cuff',
  0.5, false, 'both',
  '["fold top sheet cuff","neat cuff at head end"]'::jsonb, 'Fold top sheet back over blanket/bedspread at head end to make neat 15-20 cm cuff'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c631c790-d1b3-5f75-ad34-626c2e9a48f2', '468f044d-0153-5f46-a5fa-bfa316c11161', 12, 'Post-Procedure & Documentation', 'Fit clean pillowcase onto pillow without touching uniform; place pillow on bed with opening away from the ward entrance',
  0.5, false, 'both',
  '["pillowcase without touching uniform","pillow opening away from entrance","place pillow neatly"]'::jsonb, 'Fit clean pillowcase onto pillow without touching uniform; place pillow on bed with opening away from the ward entrance'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cbed10ef-8e35-551b-8e4d-9a88cbfb1904', '468f044d-0153-5f46-a5fa-bfa316c11161', 13, 'Post-Procedure & Documentation', 'Tidy room, reposition bed to lowest height, wash hands, and document bed making completion',
  0.25, false, 'both',
  '["lower bed","tidy unit","wash hands","document completed"]'::jsonb, 'Tidy room, reposition bed to lowest height, wash hands, and document bed making completion'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Bathing of the Vulva and Perineal Area (Perineal Toilet) (Station 11)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '2047ac9a-9909-5ee2-8ee0-91d0a3adf1be', 'reproductive-health', 'Bathing of the Vulva and Perineal Area (Perineal Toilet)', 'bathing-vulva-perineal-area',
  'Station 11', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for General Nurses - November 2012',
  11, 11, 7.5, 3.75, 420,
  'Perform perineal toilet/swabbing on a postnatal/gynaecological patient model. Observe aseptic technique, proper direction of swabbing, client dignity and comfort.', 'A patient on the postnatal ward who had a normal vaginal delivery with a repaired second-degree tear requires perineal toilet. Demonstrate the aseptic procedure on the model.', 'both',
  '["Dressing trolley","Sterile dressing pack (swabs/cotton balls, gallipots, dissecting forceps, receiver)","Antiseptic solution (e.g. Savlon / Chlorhexidine 1:2000)","Warm sterile water / jug","Sterile gloves","Waterproof draw sheet (mackintosh)","Bedpan","Perineal pad / sanitary pad","Screens / curtains"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('ce03e362-32f7-59e0-a778-8212fc284618', '2047ac9a-9909-5ee2-8ee0-91d0a3adf1be', 1, true, 13)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '920406b3-eeb4-5be3-99b1-7b61ffb1bc4f', 'ce03e362-32f7-59e0-a778-8212fc284618', 1, 'Preparation & Equipment', 'Greet patient, introduce self, verify patient identity, and explain procedure to reduce apprehension and secure cooperation',
  0.5, false, 'both',
  '["greet patient","introduce self","explain procedure","gain consent"]'::jsonb, 'Greet patient, introduce self, verify patient identity, and explain procedure to reduce apprehension and secure cooperation'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f3ed2d57-44fc-5f5d-ad99-a02fc5c39745', 'ce03e362-32f7-59e0-a778-8212fc284618', 2, 'Preparation & Equipment', 'Screen the bed to provide privacy, close nearby windows and switch off fan to avoid drafts',
  0.25, false, 'both',
  '["provide privacy","screen bed","close windows","switch off fan"]'::jsonb, 'Screen the bed to provide privacy, close nearby windows and switch off fan to avoid drafts'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '18016b38-dade-5e2c-8e75-68f46c03a838', 'ce03e362-32f7-59e0-a778-8212fc284618', 3, 'Preparation & Equipment', 'Wash hands, assemble sterile equipment on top shelf of trolley and clean equipment on bottom shelf',
  0.5, false, 'both',
  '["wash hands","prepare trolley","sterile pack on top shelf"]'::jsonb, 'Wash hands, assemble sterile equipment on top shelf of trolley and clean equipment on bottom shelf'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '58133ca3-b82c-514c-bf8b-72e2f6ee318b', 'ce03e362-32f7-59e0-a778-8212fc284618', 4, 'Preparation & Equipment', 'Position patient in dorsal recumbent position with knees flexed and thighs abducted; place mackintosh and bedpan under buttocks',
  0.75, false, 'both',
  '["dorsal recumbent","flex knees","abduct thighs","bedpan under buttocks"]'::jsonb, 'Position patient in dorsal recumbent position with knees flexed and thighs abducted; place mackintosh and bedpan under buttocks'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '47fad665-6faf-5c7e-be67-4b508283bf7d', 'ce03e362-32f7-59e0-a778-8212fc284618', 5, 'Procedure Execution', 'Open sterile pack using aseptic technique; pour warm antiseptic lotion into gallipots; perform surgical hand rub and don sterile gloves',
  0.5, false, 'both',
  '["open sterile pack","pour antiseptic","don sterile gloves","aseptic technique"]'::jsonb, 'Open sterile pack using aseptic technique; pour warm antiseptic lotion into gallipots; perform surgical hand rub and don sterile gloves'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8ae744cf-a791-59e0-8113-00f9953f5b93', 'ce03e362-32f7-59e0-a778-8212fc284618', 6, 'Procedure Execution', 'Inspect perineum, labia, and episiotomy/tear site for redness, edema, ecchymosis, discharge, and approximation (REEDA scale)',
  0.5, false, 'both',
  '["inspect perineum","reeda scale","check episiotomy site","inspect lochia"]'::jsonb, 'Inspect perineum, labia, and episiotomy/tear site for redness, edema, ecchymosis, discharge, and approximation (REEDA scale)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5bc7d97e-3b04-5d6b-a523-9a64b87af435', 'ce03e362-32f7-59e0-a778-8212fc284618', 7, 'Procedure Execution', 'Swab labium majus on the far side from top to bottom (anterior to posterior / towards anus) in one single stroke, discard swab into receiver',
  0.75, true, 'both',
  '["far labium majus","single stroke downward","front to back","discard swab"]'::jsonb, 'Swab labium majus on the far side from top to bottom (anterior to posterior / towards anus) in one single stroke, discard swab into receiver'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c05036d5-de31-51be-ae5c-7cee430e06e1', 'ce03e362-32f7-59e0-a778-8212fc284618', 8, 'Procedure Execution', 'Swab labium majus on the near side from top to bottom in one single stroke, discard swab',
  0.75, false, 'both',
  '["near labium majus","top to bottom","single downward stroke"]'::jsonb, 'Swab labium majus on the near side from top to bottom in one single stroke, discard swab'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '0885912a-6171-5382-bb9c-e956011a06d5', 'ce03e362-32f7-59e0-a778-8212fc284618', 9, 'Procedure Execution', 'Separate labia with non-dominant hand; swab labium minus on the far side from above downwards in one stroke, discard swab',
  0.75, false, 'both',
  '["separate labia","far labium minus","anterior to posterior"]'::jsonb, 'Separate labia with non-dominant hand; swab labium minus on the far side from above downwards in one stroke, discard swab'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7c536836-4db2-50dd-83b8-50d485ca19f0', 'ce03e362-32f7-59e0-a778-8212fc284618', 10, 'Procedure Execution', 'Swab labium minus on the near side from above downwards in one stroke, discard swab',
  0.75, false, 'both',
  '["near labium minus","single downward stroke","discard swab"]'::jsonb, 'Swab labium minus on the near side from above downwards in one stroke, discard swab'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3a616216-4e15-5999-887b-d13a54ed127a', 'ce03e362-32f7-59e0-a778-8212fc284618', 11, 'Procedure Execution', 'Swab vestibule down over the perineal body and anus in the midline with final swab, discard immediately',
  0.5, true, 'both',
  '["swab vestibule and anus","midline downward","never re-use swab"]'::jsonb, 'Swab vestibule down over the perineal body and anus in the midline with final swab, discard immediately'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7f8062ba-362c-5cb8-a926-6ceb92bc9fe7', 'ce03e362-32f7-59e0-a778-8212fc284618', 12, 'Procedure Execution', 'Dry the area using sterile dry cotton swabs in the same sequence; apply sterile perineal pad from front to back',
  0.5, false, 'both',
  '["dry perineum with dry swabs","apply sterile perineal pad","front to back pad placement"]'::jsonb, 'Dry the area using sterile dry cotton swabs in the same sequence; apply sterile perineal pad from front to back'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5c6b506e-be77-5a8c-a557-131e5d1a5176', 'ce03e362-32f7-59e0-a778-8212fc284618', 13, 'Post-Procedure & Documentation', 'Remove bedpan and mackintosh, make patient comfortable, dispose used supplies, wash hands and document lochia, wound status and patient comfort',
  0.5, false, 'both',
  '["remove bedpan","comfort patient","wash hands","document findings in chart"]'::jsonb, 'Remove bedpan and mackintosh, make patient comfortable, dispose used supplies, wash hands and document lochia, wound status and patient comfort'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Administration of an Evacuant Enema (Station 7)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '1537fd1b-b2dc-5d70-bb6c-ad3af5e58bbc', 'fundamental-nursing', 'Administration of an Evacuant Enema', 'administration-of-enema',
  'Station 7', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for General Nurses - May 2019',
  12, 12, 9.5, 4.75, 420,
  'Demonstrate the preparation and administration of an evacuant enema on a medical/surgical training mannequin. Observe correct patient positioning, temperature, height of can, insertion technique, and aftercare.', 'A patient scheduled for pelvic surgery has an order for a cleansing soap-suds enema. Demonstrate the procedure on the mannequin model and answer the examiner''s questions.', 'both',
  '["Mannequin with rectal orifice","Enema can with rubber tubing, clamp and rectal tube (size 22-26 Fr)","Warm enema solution (soap suds or saline, 500-1000ml at 38-40°C)","Water-soluble lubricant (K-Y jelly)","Clean gloves","Protective mackintosh and draw sheet","Bedpan and toilet tissue","IV stand / hook","Bath blanket / screens"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('91c752b6-1905-55b2-b999-af5cd3e64016', '1537fd1b-b2dc-5d70-bb6c-ad3af5e58bbc', 1, true, 13)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '010aa573-f22c-5857-ab95-09bbce1925a1', '91c752b6-1905-55b2-b999-af5cd3e64016', 1, 'Preparation & Equipment', 'Identify patient, check doctor''s prescription, explain procedure, reassure patient and obtain consent',
  0.5, false, 'both',
  '["identify patient","check prescription","explain enema","gain consent"]'::jsonb, 'Identify patient, check doctor''s prescription, explain procedure, reassure patient and obtain consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7fda2605-aa70-5bd3-b0d8-4ea841093d96', '91c752b6-1905-55b2-b999-af5cd3e64016', 2, 'Preparation & Equipment', 'Provide privacy by screening the bed; ensure toilet or bedpan is readily available nearby',
  0.5, false, 'both',
  '["screen bed","bedpan ready","ensure privacy"]'::jsonb, 'Provide privacy by screening the bed; ensure toilet or bedpan is readily available nearby'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'defcb0f4-fac9-5dc1-95d3-d4b4fb294174', '91c752b6-1905-55b2-b999-af5cd3e64016', 3, 'Preparation & Equipment', 'Wash hands, don clean gloves, and prepare prescribed solution at appropriate temperature (38°C - 40°C / warm to inner wrist)',
  0.75, false, 'both',
  '["prepare solution","check water temperature","38 to 40 degrees","warm on inner wrist"]'::jsonb, 'Wash hands, don clean gloves, and prepare prescribed solution at appropriate temperature (38°C - 40°C / warm to inner wrist)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3bf17758-151d-577a-b8cf-9fce04b23701', '91c752b6-1905-55b2-b999-af5cd3e64016', 4, 'Preparation & Equipment', 'Position patient in Left Lateral (Sims'') position with right knee and hip flexed; place protective mackintosh under buttocks',
  0.75, true, 'both',
  '["left lateral position","sims position","flex right knee","mackintosh under hips"]'::jsonb, 'Position patient in Left Lateral (Sims'') position with right knee and hip flexed; place protective mackintosh under buttocks'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '26021500-b4ce-5a1a-97e8-9825620ca0e4', '91c752b6-1905-55b2-b999-af5cd3e64016', 5, 'Procedure Execution', 'Fill enema can, connect tubing and rectal tube; open clamp to prime tubing and expel all air into a receiver, then clamp tubing',
  1, false, 'both',
  '["prime tubing","expel air from tube","clamp tubing","prevent air entry"]'::jsonb, 'Fill enema can, connect tubing and rectal tube; open clamp to prime tubing and expel all air into a receiver, then clamp tubing'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1ed02ae0-d731-54a9-a201-30b130bd2b51', '91c752b6-1905-55b2-b999-af5cd3e64016', 6, 'Procedure Execution', 'Hang enema can on IV stand 30 to 45 cm (12 to 18 inches) above patient''s anus to ensure gentle gravity flow',
  0.75, false, 'both',
  '["hang can 30 to 45 cm","12 to 18 inches above anus","correct height"]'::jsonb, 'Hang enema can on IV stand 30 to 45 cm (12 to 18 inches) above patient''s anus to ensure gentle gravity flow'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'bc594c4b-de73-52e0-a32c-0d1c50fadc47', '91c752b6-1905-55b2-b999-af5cd3e64016', 7, 'Procedure Execution', 'Lubricate the distal 7.5 to 10 cm (3 to 4 inches) of the rectal tube with water-soluble lubricant',
  0.5, false, 'both',
  '["lubricate rectal tube","3 to 4 inches lubricated","water soluble lubricant"]'::jsonb, 'Lubricate the distal 7.5 to 10 cm (3 to 4 inches) of the rectal tube with water-soluble lubricant'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e75b5583-ef1e-5d42-8c0d-be66b6e7e5ab', '91c752b6-1905-55b2-b999-af5cd3e64016', 8, 'Procedure Execution', 'Expose only the anal area; instruct patient to breathe slowly through mouth to relax anal sphincters',
  0.5, false, 'both',
  '["expose anus only","breathe through mouth","relax sphincter"]'::jsonb, 'Expose only the anal area; instruct patient to breathe slowly through mouth to relax anal sphincters'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'af81d29f-5631-55f2-a338-f953bad00b8e', '91c752b6-1905-55b2-b999-af5cd3e64016', 9, 'Procedure Execution', 'Gently insert rectal tube 7.5 to 10 cm into rectum pointing towards the umbilicus; never force against resistance',
  1, true, 'both',
  '["insert 7.5 to 10 cm","point towards umbilicus","never force insertion","smooth entry"]'::jsonb, 'Gently insert rectal tube 7.5 to 10 cm into rectum pointing towards the umbilicus; never force against resistance'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5dab1048-f1aa-57b6-b0d8-e856c1243eb6', '91c752b6-1905-55b2-b999-af5cd3e64016', 10, 'Procedure Execution', 'Unclamp tubing and allow solution to flow slowly over 10-15 minutes; if patient complains of cramping, clamp temporarily or lower can',
  1.25, false, 'both',
  '["unclamp tubing","slow flow rate","clamp if cramping","lower can to reduce pressure"]'::jsonb, 'Unclamp tubing and allow solution to flow slowly over 10-15 minutes; if patient complains of cramping, clamp temporarily or lower can'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1354523d-41c9-589e-aa2d-f4dde60c9d8d', '91c752b6-1905-55b2-b999-af5cd3e64016', 11, 'Procedure Execution', 'When desired volume has run in, clamp tubing; withdraw rectal tube smoothly through toilet paper and place in receiver',
  0.75, false, 'both',
  '["clamp before empty","withdraw smoothly","tube in receiver"]'::jsonb, 'When desired volume has run in, clamp tubing; withdraw rectal tube smoothly through toilet paper and place in receiver'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ffa39c25-51e2-5228-9bfa-38aed56c5aa8', '91c752b6-1905-55b2-b999-af5cd3e64016', 12, 'Post-Procedure & Documentation', 'Encourage patient to retain solution for 5 to 10 minutes (or as long as possible); assist onto bedpan or commode when ready',
  0.75, false, 'both',
  '["retain solution 5 to 10 minutes","assist onto bedpan","provide toilet paper"]'::jsonb, 'Encourage patient to retain solution for 5 to 10 minutes (or as long as possible); assist onto bedpan or commode when ready'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9fd17ce7-8d4b-56e2-870c-6d9941f30bfb', '91c752b6-1905-55b2-b999-af5cd3e64016', 13, 'Post-Procedure & Documentation', 'Clean patient, remove equipment, wash hands, and document time, solution type, volume, return outcome, and patient tolerance',
  0.5, false, 'both',
  '["clean patient","wash hands","document return outcome","stool characteristics"]'::jsonb, 'Clean patient, remove equipment, wash hands, and document time, solution type, volume, return outcome, and patient tolerance'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Taking General, Personal, Family and Social Health History (Station 1)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '59ef1150-e9a7-54e4-b55a-6a57585d5112', 'health-education', 'Taking General, Personal, Family and Social Health History', 'comprehensive-health-history',
  'Station 1', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Licensing Examination',
  13, 14, 12, 6, 480,
  'Take a comprehensive clinical health history from a simulated standardized patient. Cover biographical data, chief complaint, history of present illness, past medical/surgical history, family history, and personal/social history using effective communication skills.', 'A 32-year-old client is admitted to the medical clinic. Conduct a thorough initial nursing health history interview, recording data systematically while maintaining rapport and active listening.', 'oral',
  '["Standardized patient / role-player","Interview table and two chairs","Patient intake form / clipboard","Pen"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', '59ef1150-e9a7-54e4-b55a-6a57585d5112', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '28ecab48-841a-57a9-ba6b-44ef7702f0c1', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 1, 'Preparation & Equipment', 'Greet client warmly, introduce self, explain purpose of interview, ensure confidentiality, and create comfortable environment',
  0.5, false, 'oral',
  '["greet client","introduce self","explain purpose","assure confidentiality"]'::jsonb, 'Greet client warmly, introduce self, explain purpose of interview, ensure confidentiality, and create comfortable environment'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'aae3b849-222d-59b2-a74c-671cbb37f9f9', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 2, 'Procedure Execution', 'Obtain Biographical data: Full name, age, gender, marital status, address, telephone, next of kin, occupation, religion',
  1, false, 'oral',
  '["biographical data","name and age","marital status","next of kin","occupation"]'::jsonb, 'Obtain Biographical data: Full name, age, gender, marital status, address, telephone, next of kin, occupation, religion'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '65cda1d7-7d8e-5b76-a7a0-01e7c8deb74f', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 3, 'Procedure Execution', 'Elicit Chief Complaint (Reason for visit) in the client''s own words with duration',
  1, true, 'oral',
  '["chief complaint","reason for visit","duration of symptoms","in client own words"]'::jsonb, 'Elicit Chief Complaint (Reason for visit) in the client''s own words with duration'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1b780abc-7426-5d0d-b669-d472c1fa73aa', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 4, 'Procedure Execution', 'Explore History of Present Illness (HPI) using SOCRATES / PQRST: Onset, Location, Duration, Character, Aggravating/relieving factors, Radiation, Timing, Severity',
  2, true, 'oral',
  '["history of present illness","socrates","pqrst","onset and duration","severity scale","relieving factors"]'::jsonb, 'Explore History of Present Illness (HPI) using SOCRATES / PQRST: Onset, Location, Duration, Character, Aggravating/relieving factors, Radiation, Timing, Severity'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '263e0237-c789-57fd-9f99-4698e9e38513', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 5, 'Procedure Execution', 'Inquire about Past Medical History: Childhood illnesses, major adult medical conditions (hypertension, diabetes, asthma, sickle cell), previous hospitalizations',
  1, false, 'oral',
  '["past medical history","hypertension","diabetes","asthma","previous hospitalizations"]'::jsonb, 'Inquire about Past Medical History: Childhood illnesses, major adult medical conditions (hypertension, diabetes, asthma, sickle cell), previous hospitalizations'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '14a3c854-0890-5ed2-9b3a-9b67d3b28aee', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 6, 'Procedure Execution', 'Inquire about Past Surgical and Obstetric History: Previous operations, blood transfusions, pregnancies, parity, deliveries, complications',
  1, false, 'oral',
  '["past surgical history","previous operations","blood transfusions","obstetric history"]'::jsonb, 'Inquire about Past Surgical and Obstetric History: Previous operations, blood transfusions, pregnancies, parity, deliveries, complications'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4b3f1fcc-90db-5f35-9efa-372dfe999b6d', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 7, 'Procedure Execution', 'Ask about Current Medications and Allergies: Prescription drugs, over-the-counter herbs, drug allergies (penicillin, sulfa), food/environmental allergies',
  1, true, 'oral',
  '["current medications","drug allergies","food allergies","herbal remedies"]'::jsonb, 'Ask about Current Medications and Allergies: Prescription drugs, over-the-counter herbs, drug allergies (penicillin, sulfa), food/environmental allergies'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c1f499f9-11a6-5d9c-a70b-1537ea03e285', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 8, 'Procedure Execution', 'Take Family History: Familial diseases in parents/siblings (hypertension, diabetes, sickle cell trait/disease, twin gestation, cancer)',
  1, false, 'oral',
  '["family history","hereditary conditions","hypertension in family","sickle cell in siblings"]'::jsonb, 'Take Family History: Familial diseases in parents/siblings (hypertension, diabetes, sickle cell trait/disease, twin gestation, cancer)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'aa5fcafe-f4c3-556f-abed-94662f7586f4', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 9, 'Procedure Execution', 'Take Personal and Social History: Educational background, living conditions, water supply, dietary habits, alcohol intake, cigarette/tobacco use, exercise, stress',
  1.5, false, 'oral',
  '["social history","educational attainment","alcohol and smoking","dietary pattern","living conditions"]'::jsonb, 'Take Personal and Social History: Educational background, living conditions, water supply, dietary habits, alcohol intake, cigarette/tobacco use, exercise, stress'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4348c5fb-bcae-5c69-b1d8-9133a69a1278', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 10, 'Procedure Execution', 'Perform Brief Review of Systems (ROS): General (fever, weight loss), respiratory (cough), cardiovascular (palpitations, chest pain), GI (nausea, bowel habits), urinary',
  1, false, 'oral',
  '["review of systems","fever or weight loss","cough or dyspnea","chest pain","bowel and bladder habits"]'::jsonb, 'Perform Brief Review of Systems (ROS): General (fever, weight loss), respiratory (cough), cardiovascular (palpitations, chest pain), GI (nausea, bowel habits), urinary'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '771f5134-ea5a-5c17-b5d1-59f8baa4fb7e', 'f6f110fd-5ca1-57b3-b814-cc4ad3ec2035', 11, 'Post-Procedure & Documentation', 'Demonstrate active listening: Maintain eye contact, nod appropriately, summarize findings with client for verification, thank client',
  1, false, 'oral',
  '["active listening","eye contact","summarize history","thank client"]'::jsonb, 'Demonstrate active listening: Maintain eye contact, nod appropriately, summarize findings with client for verification, thank client'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Aseptic Surgical Wound Dressing (Station 6)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'da60a56e-83ff-537c-80e9-4cb0cf03044c', 'clinical-pharmacotherapy', 'Aseptic Surgical Wound Dressing', 'surgical-wound-dressing',
  'Station 6', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Clinical Practicum Examination',
  16, 16, 8, 4, 420,
  'Perform an aseptic surgical wound dressing on a postoperative abdominal wound model. Observe strict surgical asepsis, sterile field maintenance, wound assessment, and proper waste segregation.', 'A patient on Day 3 following an emergency Caesarean section requires an aseptic wound dressing change. The wound is clean with sutures in place. Carry out the procedure following surgical asepsis.', 'both',
  '["Dressing trolley (decontaminated)","Sterile dressing pack (gauze swabs, cotton balls, dissecting forceps, tissue forceps, sterile drape, receiver)","Sterile normal saline 0.9% / cleansing agent","Sterile gloves","Hypoallergenic tape (Micropore) / dressing bandage","Mackintosh and towel","Clinical waste bag (yellow) and domestic waste bag (black)"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('36d116e5-4220-5f92-a083-6b7d5e1e1225', 'da60a56e-83ff-537c-80e9-4cb0cf03044c', 1, true, 12)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3962e93a-f6d7-5f0b-b399-4ca3c32ffc57', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 1, 'Preparation & Equipment', 'Greet patient, introduce self, verify patient identity, explain procedure, check for pain/allergies, and screen bed for privacy',
  0.5, false, 'both',
  '["greet patient","introduce self","explain dressing","gain consent","privacy"]'::jsonb, 'Greet patient, introduce self, verify patient identity, explain procedure, check for pain/allergies, and screen bed for privacy'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8f4b0f46-04cb-5c8d-99f1-28e7551ff2c7', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 2, 'Preparation & Equipment', 'Clean and decontaminate dressing trolley from top to bottom with 70% alcohol; wash hands and gather sterile supplies',
  0.5, false, 'both',
  '["clean trolley","alcohol wipe trolley","wash hands","assemble equipment"]'::jsonb, 'Clean and decontaminate dressing trolley from top to bottom with 70% alcohol; wash hands and gather sterile supplies'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '678affc0-9a14-597c-91f8-d102d7b09cfa', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 3, 'Preparation & Equipment', 'Expose wound area, position patient comfortably, place protective mackintosh under wound site, and position waste receiver nearby',
  0.5, false, 'both',
  '["expose wound","protect bed with mackintosh","position waste receiver"]'::jsonb, 'Expose wound area, position patient comfortably, place protective mackintosh under wound site, and position waste receiver nearby'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '88ba4272-965f-584e-9edc-dcfc9ed8c589', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 4, 'Procedure Execution', 'Wash hands, open sterile dressing pack maintaining sterile borders; pour sterile 0.9% normal saline into sterile gallipot',
  0.75, false, 'both',
  '["open sterile pack","maintain sterile borders","pour normal saline","sterile field"]'::jsonb, 'Wash hands, open sterile dressing pack maintaining sterile borders; pour sterile 0.9% normal saline into sterile gallipot'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '375bdf12-b5ea-5dcc-ae8b-26c3bac66d0c', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 5, 'Procedure Execution', 'Don clean gloves to gently remove soiled dressing by peeling tape towards the wound to avoid traction; inspect soiled dressing for exudate, odor, amount',
  0.75, false, 'both',
  '["remove old dressing","peel towards wound","inspect soiled dressing","discard gloves"]'::jsonb, 'Don clean gloves to gently remove soiled dressing by peeling tape towards the wound to avoid traction; inspect soiled dressing for exudate, odor, amount'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2ef636a9-aaf3-5ee3-af85-543c7bef1459', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 6, 'Procedure Execution', 'Discard soiled dressing into yellow clinical waste bin, remove clean gloves, perform hand hygiene, and don sterile gloves (or use forceps)',
  0.75, true, 'both',
  '["clinical waste bin","hand hygiene","don sterile gloves","aseptic no touch technique"]'::jsonb, 'Discard soiled dressing into yellow clinical waste bin, remove clean gloves, perform hand hygiene, and don sterile gloves (or use forceps)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cd003b48-f4f2-5ba1-b891-48551d89c04e', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 7, 'Procedure Execution', 'Inspect surgical wound: Assess incision length, edges approximation, signs of infection (erythema, edema, warmth, tenderness), and suture/staple integrity',
  0.75, false, 'both',
  '["inspect wound edges","reeda scale","check approximation","no erythema or purulent discharge"]'::jsonb, 'Inspect surgical wound: Assess incision length, edges approximation, signs of infection (erythema, edema, warmth, tenderness), and suture/staple integrity'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '216c4137-cb17-5d99-bcc0-563f2bb1fe8c', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 8, 'Procedure Execution', 'Clean wound using sterile forceps and saline-soaked swabs: First stroke down the center along the incision line from top to bottom in one stroke; discard swab',
  1, true, 'both',
  '["clean along incision line","top to bottom","single stroke","discard swab"]'::jsonb, 'Clean wound using sterile forceps and saline-soaked swabs: First stroke down the center along the incision line from top to bottom in one stroke; discard swab'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1a3c3b0e-5980-56fa-97ca-b8026d68c4b5', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 9, 'Procedure Execution', 'Clean wound side 1 (far side) from top to bottom using fresh swab; discard swab. Clean wound side 2 (near side) from top to bottom using fresh swab; discard swab',
  1, false, 'both',
  '["clean outer margins","far side then near side","one swab per stroke","never go backwards"]'::jsonb, 'Clean wound side 1 (far side) from top to bottom using fresh swab; discard swab. Clean wound side 2 (near side) from top to bottom using fresh swab; discard swab'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2a0c7d60-1998-5c3d-8046-f5eeffd5e27d', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 10, 'Procedure Execution', 'Dry the wound gently using sterile dry gauze swabs in the same order; apply sterile dressing pads covering incision with 2.5 cm margin',
  0.5, false, 'both',
  '["dry wound","apply sterile gauze","cover incision"]'::jsonb, 'Dry the wound gently using sterile dry gauze swabs in the same order; apply sterile dressing pads covering incision with 2.5 cm margin'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6d48d50c-a68e-5b33-a32a-05fb4d18cb9f', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 11, 'Post-Procedure & Documentation', 'Secure dressing with hypoallergenic tape (Micropore), remove gloves, dispose of waste, make patient comfortable',
  0.5, false, 'both',
  '["secure with tape","dispose waste","comfort patient"]'::jsonb, 'Secure dressing with hypoallergenic tape (Micropore), remove gloves, dispose of waste, make patient comfortable'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e141cf75-88d8-57f4-a53a-68c4b4f83a45', '36d116e5-4220-5f92-a083-6b7d5e1e1225', 12, 'Post-Procedure & Documentation', 'Wash hands and document dressing change, wound appearance, drainage, healing progress, and patient reaction in nursing notes',
  0.5, false, 'both',
  '["wash hands","document in chart","wound condition recorded"]'::jsonb, 'Wash hands and document dressing change, wound appearance, drainage, healing progress, and patient reaction in nursing notes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Nutrition: Food Group Identification and Dietary Counseling (Station 5)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '50afa52e-5121-5af8-a9c7-ac7189cd3e0a', 'health-education', 'Nutrition: Food Group Identification and Dietary Counseling', 'nutrition-food-groups-counseling',
  'Station 5', 'Nursing Practicum Examination', 'Procedure Station Examination',
  17, 17, 6, 3, 360,
  'Identify the food specimens displayed (Specimens A, B, C, D). Classify each into its nutrient group, state its biological function, and provide nutritional counseling for a malnourished or convalescent patient.', 'Four food specimens are displayed before you: Specimen A (Rice/Grains), Specimen B (Fish/Beans), Specimen C (Palm oil/Groundnut oil), Specimen D (Spinach/Citrus fruits). Identify, classify, and counsel a mother on balanced diet.', 'oral',
  '["Specimen A (Grain/Rice)","Specimen B (Protein/Fish or Beans)","Specimen C (Lipid/Palm oil)","Specimen D (Vitamins/Vegetable)","Food wheel / nutritional chart"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('88737efc-ebfe-544b-830d-e41b85d38934', '50afa52e-5121-5af8-a9c7-ac7189cd3e0a', 1, true, 7)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cccc367d-5206-5c7f-a0d9-eed4971cf063', '88737efc-ebfe-544b-830d-e41b85d38934', 1, 'Preparation & Equipment', 'Greet examiner, introduce self, and identify the four food specimens accurately',
  0.5, false, 'oral',
  '["greet examiner","introduce self","identify specimens"]'::jsonb, 'Greet examiner, introduce self, and identify the four food specimens accurately'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c651506f-453a-53a3-b697-6ad3dd741180', '88737efc-ebfe-544b-830d-e41b85d38934', 2, 'Procedure Execution', 'Classify Specimen A (Rice/Yam/Maize): Carbohydrate (Energy-giving food); function: provides glucose for cellular energy and bodily functions',
  1, false, 'oral',
  '["specimen a carbohydrate","energy giving food","rice or yam","provides glucose"]'::jsonb, 'Classify Specimen A (Rice/Yam/Maize): Carbohydrate (Energy-giving food); function: provides glucose for cellular energy and bodily functions'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6658d6c8-08b6-5dca-ac32-2434ff3f6dfc', '88737efc-ebfe-544b-830d-e41b85d38934', 3, 'Procedure Execution', 'Classify Specimen B (Fish/Meat/Beans): Protein (Body-building food); function: growth, tissue repair, enzyme and antibody synthesis',
  1, false, 'oral',
  '["specimen b protein","body building food","tissue repair","growth and repair"]'::jsonb, 'Classify Specimen B (Fish/Meat/Beans): Protein (Body-building food); function: growth, tissue repair, enzyme and antibody synthesis'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3548ee8f-3072-5d03-a23f-ef0a8aa3a844', '88737efc-ebfe-544b-830d-e41b85d38934', 4, 'Procedure Execution', 'Classify Specimen C (Palm oil/Groundnut oil): Lipids/Fats; function: concentrated energy source, cell membrane structure, absorption of fat-soluble vitamins (A, D, E, K)',
  1, false, 'oral',
  '["specimen c lipids","fats and oils","absorption of fat soluble vitamins","concentrated energy"]'::jsonb, 'Classify Specimen C (Palm oil/Groundnut oil): Lipids/Fats; function: concentrated energy source, cell membrane structure, absorption of fat-soluble vitamins (A, D, E, K)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e59aea45-60f6-550b-a1c9-5aadbe5ea63c', '88737efc-ebfe-544b-830d-e41b85d38934', 5, 'Procedure Execution', 'Classify Specimen D (Green leafy vegetables / Fruits): Vitamins and Minerals (Protective food); function: immunity, wound healing, bone density, regulation of metabolic processes',
  1, false, 'oral',
  '["specimen d vitamins and minerals","protective food","immunity","leafy vegetables"]'::jsonb, 'Classify Specimen D (Green leafy vegetables / Fruits): Vitamins and Minerals (Protective food); function: immunity, wound healing, bone density, regulation of metabolic processes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1f44568a-28bd-5594-901e-717e9f7a5442', '88737efc-ebfe-544b-830d-e41b85d38934', 6, 'Procedure Execution', 'Define a balanced diet: A diet containing all six food classes in correct proportions according to age, sex, activity, and physiological state',
  0.5, false, 'oral',
  '["balanced diet definition","all six food classes","correct proportions"]'::jsonb, 'Define a balanced diet: A diet containing all six food classes in correct proportions according to age, sex, activity, and physiological state'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'de9c47df-48f9-5144-a529-b019ab867511', '88737efc-ebfe-544b-830d-e41b85d38934', 7, 'Post-Procedure & Documentation', 'Provide practical dietary counseling: Use locally available and affordable foods (four-star diet: staples, legumes, animal-source foods, fruits/vegetables) for family and child feeding',
  1, false, 'oral',
  '["dietary counseling","locally available foods","four star diet","affordable nutrition"]'::jsonb, 'Provide practical dietary counseling: Use locally available and affordable foods (four-star diet: staples, legumes, animal-source foods, fruits/vegetables) for family and child feeding'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Administration of Intramuscular Injection (Gluteal Route) (Station 3)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'b15bc04b-9039-5337-a2ae-6795bd5d5d91', 'clinical-pharmacotherapy', 'Administration of Intramuscular Injection (Gluteal Route)', 'intramuscular-injection',
  'Station 3', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'General Nursing Licensing Examination',
  23, 23, 10, 5, 420,
  'Demonstrate the preparation and administration of an intramuscular injection via the gluteal route on an injection mannequin model. Follow the ''Five Rights'' of medication administration, aseptic technique, site landmarking, aspiration, and sharps disposal.', 'An adult patient is prescribed Ampicillin 500mg IM stat. Demonstrate the complete preparation, site identification (dorsogluteal/ventrogluteal), injection technique, and aftercare.', 'both',
  '["Injection trainer / mannequin buttocks","Prescribed medication vial / ampoule","Sterile 2ml / 5ml syringe with 21G/23G needle","Drawing up needle (blunt/filter)","70% alcohol swabs","Clean gloves","Sharps disposal container","Medication administration record (MAR)"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('760caa03-f013-54bf-aecc-a47795589cfa', 'b15bc04b-9039-5337-a2ae-6795bd5d5d91', 1, true, 13)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9899cecc-3faa-51cd-8062-69888e5b5830', '760caa03-f013-54bf-aecc-a47795589cfa', 1, 'Preparation & Equipment', 'Check prescription order: Verify the Five Rights (Right Patient, Right Drug, Right Dose, Right Route, Right Time) and check expiry date',
  0.75, true, 'both',
  '["five rights","right patient drug dose route time","check expiry date","medication order"]'::jsonb, 'Check prescription order: Verify the Five Rights (Right Patient, Right Drug, Right Dose, Right Route, Right Time) and check expiry date'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '76173af0-34ee-5bdf-80c2-1774d96a1599', '760caa03-f013-54bf-aecc-a47795589cfa', 2, 'Preparation & Equipment', 'Greet patient, introduce self, verify identity with two identifiers, explain procedure, check for allergies, and gain consent',
  0.5, false, 'both',
  '["greet patient","introduce self","verify identity","check allergies","gain consent"]'::jsonb, 'Greet patient, introduce self, verify identity with two identifiers, explain procedure, check for allergies, and gain consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '23e751a4-80d1-50de-a88f-b5aedd90ce7a', '760caa03-f013-54bf-aecc-a47795589cfa', 3, 'Preparation & Equipment', 'Perform hand hygiene, assemble medication, syringe, needle, alcohol swabs, and clean injection tray',
  0.5, false, 'both',
  '["hand hygiene","assemble syringe and needle","clean tray"]'::jsonb, 'Perform hand hygiene, assemble medication, syringe, needle, alcohol swabs, and clean injection tray'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8e3006f4-3645-59ba-8adf-2cf9e0d954f4', '760caa03-f013-54bf-aecc-a47795589cfa', 4, 'Procedure Execution', 'Draw up medication aseptically: Disinfect vial top / snap ampoule with gauze, draw correct dose, expel air bubbles, replace with injection needle',
  1, false, 'both',
  '["draw up medication","expel air bubbles","sterile technique","correct volume"]'::jsonb, 'Draw up medication aseptically: Disinfect vial top / snap ampoule with gauze, draw correct dose, expel air bubbles, replace with injection needle'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '60ec2f5a-f855-53cc-adbf-467480947b78', '760caa03-f013-54bf-aecc-a47795589cfa', 5, 'Procedure Execution', 'Position patient comfortably in prone position with toes pointed inward (or lateral position with flexed knee) to relax gluteal muscles',
  0.5, false, 'both',
  '["prone with toes in","lateral with knee flexed","relax gluteal muscles"]'::jsonb, 'Position patient comfortably in prone position with toes pointed inward (or lateral position with flexed knee) to relax gluteal muscles'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9443e4f2-da2c-5cdf-89bc-cbc1cc294aeb', '760caa03-f013-54bf-aecc-a47795589cfa', 6, 'Procedure Execution', 'Landmark the injection site accurately: For Dorsogluteal, divide buttock into four quadrants and select upper outer quadrant (above line from PSIS to greater trochanter) to avoid sciatic nerve; OR landmark Ventrogluteal site',
  1.5, true, 'both',
  '["upper outer quadrant","divide into quadrants","avoid sciatic nerve","ventrogluteal site","greater trochanter"]'::jsonb, 'Landmark the injection site accurately: For Dorsogluteal, divide buttock into four quadrants and select upper outer quadrant (above line from PSIS to greater trochanter) to avoid sciatic nerve; OR landmark Ventrogluteal site'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '13b54825-0f25-52c7-b5c6-4dad103e4ce9', '760caa03-f013-54bf-aecc-a47795589cfa', 7, 'Procedure Execution', 'Don clean gloves; cleanse injection site with 70% alcohol swab in a circular motion from center outwards (5 cm diameter); allow to air-dry completely (30 seconds)',
  0.75, false, 'both',
  '["cleanse site with alcohol","circular motion outward","allow to air dry","do not fan"]'::jsonb, 'Don clean gloves; cleanse injection site with 70% alcohol swab in a circular motion from center outwards (5 cm diameter); allow to air-dry completely (30 seconds)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f3eb33d9-116b-5014-97f4-311ab0ee1fce', '760caa03-f013-54bf-aecc-a47795589cfa', 8, 'Procedure Execution', 'Spread skin taut with non-dominant hand (or Z-track technique); hold syringe like a dart at 90-degree angle to skin surface',
  0.75, false, 'both',
  '["spread skin taut","hold like a dart","90 degree angle"]'::jsonb, 'Spread skin taut with non-dominant hand (or Z-track technique); hold syringe like a dart at 90-degree angle to skin surface'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '70f89fa8-4cd7-58a6-9c9f-18fd640f93a5', '760caa03-f013-54bf-aecc-a47795589cfa', 9, 'Procedure Execution', 'Insert needle smoothly and firmly into the muscle using a quick darting motion, leaving 1/3 of needle shaft visible',
  1, false, 'both',
  '["insert needle quickly","smooth 90 degree entry","darting motion"]'::jsonb, 'Insert needle smoothly and firmly into the muscle using a quick darting motion, leaving 1/3 of needle shaft visible'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2695a27f-b7fc-50af-8a87-7fdb1dd1cfc9', '760caa03-f013-54bf-aecc-a47795589cfa', 10, 'Procedure Execution', 'Aspirate: Pull back plunger gently for 5-10 seconds; check for blood return. If blood appears, withdraw needle, discard, and restart. If no blood, proceed',
  1, true, 'both',
  '["aspirate for blood return","pull back plunger","no blood return","confirm intramuscular"]'::jsonb, 'Aspirate: Pull back plunger gently for 5-10 seconds; check for blood return. If blood appears, withdraw needle, discard, and restart. If no blood, proceed'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1ffe3796-f780-5b64-af71-14e4a02db780', '760caa03-f013-54bf-aecc-a47795589cfa', 11, 'Procedure Execution', 'Inject medication slowly at a rate of 1 ml per 10 seconds to allow muscle fibers to stretch and reduce pain; wait 10 seconds before withdrawal',
  0.75, false, 'both',
  '["inject slowly","1 ml per 10 seconds","steady injection"]'::jsonb, 'Inject medication slowly at a rate of 1 ml per 10 seconds to allow muscle fibers to stretch and reduce pain; wait 10 seconds before withdrawal'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'aeb70061-e318-5380-88ae-43ff7d41ca64', '760caa03-f013-54bf-aecc-a47795589cfa', 12, 'Post-Procedure & Documentation', 'Withdraw needle smoothly at same 90° angle while applying dry sterile cotton ball with gentle pressure; do not massage site',
  0.5, false, 'both',
  '["withdraw at 90 degrees","dry cotton ball pressure","do not massage"]'::jsonb, 'Withdraw needle smoothly at same 90° angle while applying dry sterile cotton ball with gentle pressure; do not massage site'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '98573196-baf7-5676-a400-38083f9f1cbc', '760caa03-f013-54bf-aecc-a47795589cfa', 13, 'Post-Procedure & Documentation', 'Dispose needle immediately into puncture-proof sharps box without recapping; remove gloves, wash hands, and document in MAR',
  0.5, true, 'both',
  '["sharps box immediately","do not recap needle","wash hands","record on mar"]'::jsonb, 'Dispose needle immediately into puncture-proof sharps box without recapping; remove gloves, wash hands, and document in MAR'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Application of Figure-of-Eight Bandage (Ankle/Joint) (Station 13)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '1af122f5-709e-5607-be52-6fab83b2d288', 'clinical-pharmacotherapy', 'Application of Figure-of-Eight Bandage (Ankle/Joint)', 'figure-of-eight-bandaging',
  'Station 13', 'Nursing Practicum Examination', 'Procedure Station Examination',
  22, 22, 8, 4, 420,
  'Apply a figure-of-eight roller bandage to a client presenting with a sprained ankle or wrist. Ensure correct tension, direction, heel coverage, and distal neurovascular assessment.', 'A client presents with an inversion sprain of the right ankle. Apply a supportive figure-of-eight bandage to immobilize and reduce edema, demonstrating proper bandaging principles.', 'both',
  '["Client model / volunteer","Crepe roller bandage (7.5cm or 10cm)","Safety pins / adhesive tape","Scissors","Pillow for limb elevation"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('d1e1e137-22c2-564c-a919-1bdc789cb3f8', '1af122f5-709e-5607-be52-6fab83b2d288', 1, true, 9)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f2d1a068-7d56-5898-94a0-fabb862daf77', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 1, 'Preparation & Equipment', 'Greet patient, introduce self, explain procedure, inspect injured joint, and check distal pulse and skin warmth',
  0.5, false, 'both',
  '["greet patient","introduce self","explain procedure","inspect joint","check circulation"]'::jsonb, 'Greet patient, introduce self, explain procedure, inspect injured joint, and check distal pulse and skin warmth'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3c99be6f-78d6-5f93-be85-83681d6695fc', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 2, 'Preparation & Equipment', 'Position patient comfortably with leg extended and ankle supported at 90-degree functional flexion (dorsiflexion)',
  0.75, false, 'both',
  '["support limb","ankle at 90 degrees","functional position"]'::jsonb, 'Position patient comfortably with leg extended and ankle supported at 90-degree functional flexion (dorsiflexion)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4916e576-f504-5199-90b5-7bd2f8bee9e4', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 3, 'Procedure Execution', 'Hold bandage roll correctly: Head (roll) uppermost and tail underneath facing the limb',
  0.75, false, 'both',
  '["hold bandage correctly","roll uppermost","tail on limb"]'::jsonb, 'Hold bandage roll correctly: Head (roll) uppermost and tail underneath facing the limb'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f32e3f76-8f66-5b3c-985d-1ef659b3d1ee', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 4, 'Procedure Execution', 'Anchor bandage with two circular turns around the ball of the foot (metatarsal heads) moving from medial to lateral',
  1, false, 'both',
  '["anchor turns around foot","two circular turns","medial to lateral"]'::jsonb, 'Anchor bandage with two circular turns around the ball of the foot (metatarsal heads) moving from medial to lateral'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '90fe685b-b850-581c-b9e0-c594df36bbdd', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 5, 'Procedure Execution', 'Carry bandage obliquely across dorsum of foot, around back of ankle joint above malleoli, and cross back over dorsum of foot to opposite side',
  1.5, true, 'both',
  '["figure of eight turns","across dorsum of foot","around ankle joint","cross back over instep"]'::jsonb, 'Carry bandage obliquely across dorsum of foot, around back of ankle joint above malleoli, and cross back over dorsum of foot to opposite side'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ae87cd94-fd36-512a-9842-d254ba2aa24f', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 6, 'Procedure Execution', 'Repeat figure-of-eight turns overlapping the previous turn by two-thirds of bandage width with even, consistent tension',
  1.5, false, 'both',
  '["overlap by two thirds","consistent tension","repeat figure of eight"]'::jsonb, 'Repeat figure-of-eight turns overlapping the previous turn by two-thirds of bandage width with even, consistent tension'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4a4a584d-9e93-58fb-81a7-2920a29b761d', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 7, 'Procedure Execution', 'Finish with two circular turns around the lower leg 5 cm above ankle joint; secure end with adhesive tape or safety pin on lateral aspect (not over bone or wound)',
  0.75, false, 'both',
  '["two circular turns above ankle","secure with tape or pin","lateral side"]'::jsonb, 'Finish with two circular turns around the lower leg 5 cm above ankle joint; secure end with adhesive tape or safety pin on lateral aspect (not over bone or wound)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '625a5749-2e7d-5f03-8f82-82dc06147432', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 8, 'Post-Procedure & Documentation', 'Assess distal neurovascular status: Check capillary refill (< 2 seconds), skin temperature, color, toe sensation and motor movement to ensure no constriction',
  0.75, true, 'both',
  '["assess capillary refill under 2 seconds","check toe sensation","ensure no numbness","no vascular compromise"]'::jsonb, 'Assess distal neurovascular status: Check capillary refill (< 2 seconds), skin temperature, color, toe sensation and motor movement to ensure no constriction'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '70fecb44-574b-5ee3-8db0-77de30a12e7e', 'd1e1e137-22c2-564c-a919-1bdc789cb3f8', 9, 'Post-Procedure & Documentation', 'Advise client on RICE principles (Rest, Ice, Compression, Elevation) and when to report numbness/pain; document procedure',
  0.5, false, 'both',
  '["rice principles","elevate limb","report numbness","document bandaging"]'::jsonb, 'Advise client on RICE principles (Rest, Ice, Compression, Elevation) and when to report numbness/pain; document procedure'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Non-Invasive Arterial Blood Pressure Measurement (Station 1)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '7a082602-3569-5651-a2c4-fb9ccb2767b2', 'clinical-pharmacotherapy', 'Non-Invasive Arterial Blood Pressure Measurement', 'blood-pressure-measurement',
  'Station 1', 'Nursing Practicum Examination', 'Procedure Station Examination',
  31, 31, 8, 4, 360,
  'Measure and report the arterial blood pressure of an adult client using an aneroid or mercury sphygmomanometer and acoustic stethoscope. Follow standard clinical guidelines.', 'A client attends the antenatal/medical clinic for a routine check-up. Demonstrate blood pressure measurement following AHA/WHO clinical standards.', 'both',
  '["Sphygmomanometer with standard adult cuff","Acoustic stethoscope with bell and diaphragm","Alcohol prep pads","Chair and desk","Vital signs chart and pen"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('4e1d15f0-b6d9-5182-a2f8-43a6352b6586', '7a082602-3569-5651-a2c4-fb9ccb2767b2', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ed3f676d-fadc-5434-8dfb-c74fcbcd464a', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 1, 'Preparation & Equipment', 'Greet client, introduce self, verify identity, explain procedure, and confirm client has rested for 5 minutes without smoking/caffeine',
  0.5, false, 'both',
  '["greet client","introduce self","rest for 5 minutes","no caffeine or smoking"]'::jsonb, 'Greet client, introduce self, verify identity, explain procedure, and confirm client has rested for 5 minutes without smoking/caffeine'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2faa759c-2bfe-54e5-bbb9-34b6b9d0b999', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 2, 'Preparation & Equipment', 'Clean stethoscope earpieces and diaphragm with alcohol swab; wash hands',
  0.5, false, 'both',
  '["clean stethoscope","alcohol swab earpieces","wash hands"]'::jsonb, 'Clean stethoscope earpieces and diaphragm with alcohol swab; wash hands'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8dcb4fef-c7ed-501b-b5d8-b75a4fa30713', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 3, 'Preparation & Equipment', 'Position client comfortably sitting with back supported, legs uncrossed, arm bare and supported at heart level (4th intercostal space)',
  0.75, false, 'both',
  '["arm supported at heart level","legs uncrossed","back supported"]'::jsonb, 'Position client comfortably sitting with back supported, legs uncrossed, arm bare and supported at heart level (4th intercostal space)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6b8ba098-25d3-5299-834c-89501f9856cd', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 4, 'Procedure Execution', 'Select correct cuff size (bladder width 40% of arm circumference, length 80%); palpate brachial artery in antecubital fossa',
  0.75, false, 'both',
  '["correct cuff size","palpate brachial artery","bladder covers 80 percent"]'::jsonb, 'Select correct cuff size (bladder width 40% of arm circumference, length 80%); palpate brachial artery in antecubital fossa'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6a90489c-e239-5ba9-8404-15beab44f210', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 5, 'Procedure Execution', 'Wrap cuff smoothly and snugly around upper arm with center of bladder over brachial artery, 2.5 cm (1 inch) above antecubital fossa',
  0.75, false, 'both',
  '["wrap cuff snugly","2.5 cm above antecubital fossa","arrow over brachial artery"]'::jsonb, 'Wrap cuff smoothly and snugly around upper arm with center of bladder over brachial artery, 2.5 cm (1 inch) above antecubital fossa'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '60267b89-ea60-5707-b0fc-add2e7ba0a2c', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 6, 'Procedure Execution', 'Estimate systolic pressure by palpation: Palpate radial artery, inflate cuff until pulse disappears, note pressure, add 30 mmHg, then deflate fully',
  0.75, true, 'both',
  '["palpatory method","radial pulse disappears","add 30 mmhg","prevent auscultatory gap"]'::jsonb, 'Estimate systolic pressure by palpation: Palpate radial artery, inflate cuff until pulse disappears, note pressure, add 30 mmHg, then deflate fully'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '52175216-fb9f-58b2-9194-2728b3348a9d', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 7, 'Procedure Execution', 'Place stethoscope diaphragm/bell lightly over brachial artery pulse (not tucked under cuff edge); insert earpieces angled forward',
  0.75, false, 'both',
  '["stethoscope over brachial artery","do not tuck under cuff","earpieces angled forward"]'::jsonb, 'Place stethoscope diaphragm/bell lightly over brachial artery pulse (not tucked under cuff edge); insert earpieces angled forward'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b8978f31-8a7e-51ea-824a-0c6c30008ba7', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 8, 'Procedure Execution', 'Inflate cuff rapidly to 30 mmHg above previously estimated palpated systolic level; open valve to deflate slowly at 2-3 mmHg per second',
  0.75, false, 'both',
  '["inflate to target","deflate at 2 to 3 mmhg per second","slow controlled deflation"]'::jsonb, 'Inflate cuff rapidly to 30 mmHg above previously estimated palpated systolic level; open valve to deflate slowly at 2-3 mmHg per second'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '93243275-091a-5b92-a73c-490a63c3bdc1', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 9, 'Procedure Execution', 'Identify Systolic Pressure: Note reading at onset of first clear tapping sound (Korotkoff Phase I)',
  1, true, 'both',
  '["systolic pressure","korotkoff phase 1","first tapping sound"]'::jsonb, 'Identify Systolic Pressure: Note reading at onset of first clear tapping sound (Korotkoff Phase I)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '09b0f8b0-844e-596b-b658-1a32b786eea8', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 10, 'Procedure Execution', 'Identify Diastolic Pressure: Note reading when sounds disappear completely (Korotkoff Phase V in adults); continue deflating for 10 mmHg then release fully',
  1, true, 'both',
  '["diastolic pressure","korotkoff phase 5","disappearance of sounds"]'::jsonb, 'Identify Diastolic Pressure: Note reading when sounds disappear completely (Korotkoff Phase V in adults); continue deflating for 10 mmHg then release fully'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'db078abd-31b0-5db8-8cf5-daa019faf57a', '4e1d15f0-b6d9-5182-a2f8-43a6352b6586', 11, 'Post-Procedure & Documentation', 'Remove cuff, make client comfortable, inform client of reading, wash hands, and record blood pressure immediately in client''s chart',
  0.5, false, 'both',
  '["remove cuff","inform client of reading","wash hands","document in chart"]'::jsonb, 'Remove cuff, make client comfortable, inform client of reading, wash hands, and record blood pressure immediately in client''s chart'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Nurse's Role in Blood Transfusion and Reaction Management (Station 3)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'a413318a-fd42-55b2-b9ae-a7fbc3a90385', 'clinical-pharmacotherapy', 'Nurse''s Role in Blood Transfusion and Reaction Management', 'blood-transfusion-nursing-care',
  'Station 3', 'Nursing Practicum Examination', 'Procedure Station Examination',
  33, 33, 10, 5, 420,
  'Demonstrate and explain the nurse''s responsibilities before, during, and after blood transfusion, and the immediate nursing actions in acute transfusion reactions.', 'A patient with severe postpartum anemia requires 1 unit of Packed Red Blood Cells. Demonstrate the pre-transfusion verification, administration protocol, monitoring, and reaction management.', 'both',
  '["Blood unit mockup with compatibility label","Blood administration set with micro-aggregate filter","0.9% Normal Saline IV bag","IV pole and infusion pump","Thermometer, BP apparatus, pulse oximeter","Emergency drug tray (Hydrocortisone, Chlorpheniramine, Adrenaline)"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('86ea5241-1591-58c5-9609-f40b6dbdd207', 'a413318a-fd42-55b2-b9ae-a7fbc3a90385', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a05b2d84-2d7d-5b56-b3c8-ef90e16bd062', '86ea5241-1591-58c5-9609-f40b6dbdd207', 1, 'Preparation & Equipment', 'Verify doctor''s prescription for blood transfusion, check informed consent, and check IV cannula patency (18G or 20G wide-bore)',
  0.75, false, 'both',
  '["verify prescription","check consent","18 or 20 gauge cannula","wide bore iv cannula"]'::jsonb, 'Verify doctor''s prescription for blood transfusion, check informed consent, and check IV cannula patency (18G or 20G wide-bore)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c53b7936-a3dd-550e-a041-e167dc0ba4fe', '86ea5241-1591-58c5-9609-f40b6dbdd207', 2, 'Preparation & Equipment', 'Perform two-nurse independent bedside verification: Patient name, hospital number, blood group (ABO/Rh), donor unit number, expiry date, compatibility form',
  1.5, true, 'both',
  '["two nurse check","patient name and id","blood group abo rh","unit number matches","expiry date checked"]'::jsonb, 'Perform two-nurse independent bedside verification: Patient name, hospital number, blood group (ABO/Rh), donor unit number, expiry date, compatibility form'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1f356cf2-42e6-57c3-812b-3b8af51eecb3', '86ea5241-1591-58c5-9609-f40b6dbdd207', 3, 'Preparation & Equipment', 'Inspect blood bag: Check for clots, hemolysis, gas bubbles, turbidity, or purple discoloration; confirm transfusion starts within 30 min of leaving blood bank',
  0.75, false, 'both',
  '["inspect blood bag","no clots or discoloration","start within 30 minutes of collection"]'::jsonb, 'Inspect blood bag: Check for clots, hemolysis, gas bubbles, turbidity, or purple discoloration; confirm transfusion starts within 30 min of leaving blood bank'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7ab94eb2-be5d-5cdb-b4a4-6967de520a24', '86ea5241-1591-58c5-9609-f40b6dbdd207', 4, 'Preparation & Equipment', 'Measure and record baseline vital signs (Temperature, Pulse, Blood Pressure, Respiratory Rate) immediately before commencing transfusion',
  0.75, false, 'both',
  '["baseline vital signs","pre transfusion temp and bp","vital signs recorded"]'::jsonb, 'Measure and record baseline vital signs (Temperature, Pulse, Blood Pressure, Respiratory Rate) immediately before commencing transfusion'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd322b317-e4bb-52e6-9c7b-fe26e462b1f2', '86ea5241-1591-58c5-9609-f40b6dbdd207', 5, 'Procedure Execution', 'Prime blood administration set containing in-line 170-micron filter with 0.9% Normal Saline only (never prime with dextrose or Ringer''s lactate)',
  0.75, true, 'both',
  '["normal saline only","prime with 0.9 percent saline","170 micron blood filter"]'::jsonb, 'Prime blood administration set containing in-line 170-micron filter with 0.9% Normal Saline only (never prime with dextrose or Ringer''s lactate)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'dedcacd0-c1c9-5fdd-a790-c996fd0923dd', '86ea5241-1591-58c5-9609-f40b6dbdd207', 6, 'Procedure Execution', 'Connect blood to patient IV line; initiate transfusion slowly at 2 ml/min (20-30 drops/min or ~50 ml/hr) for the first 15 minutes',
  1, false, 'both',
  '["run slowly first 15 minutes","20 to 30 drops per minute","50 ml per hour","slow initial rate"]'::jsonb, 'Connect blood to patient IV line; initiate transfusion slowly at 2 ml/min (20-30 drops/min or ~50 ml/hr) for the first 15 minutes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5d104515-d99a-5299-a29b-ed7da417983d', '86ea5241-1591-58c5-9609-f40b6dbdd207', 7, 'Procedure Execution', 'Remain at bedside with patient for the first 15 minutes: Monitor closely for acute hemolytic, febrile, or allergic reactions',
  1, true, 'both',
  '["remain bedside first 15 minutes","monitor acute reaction","observe patient closely"]'::jsonb, 'Remain at bedside with patient for the first 15 minutes: Monitor closely for acute hemolytic, febrile, or allergic reactions'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'fceca07a-e48d-5ab4-aacf-89cdd21ce0b1', '86ea5241-1591-58c5-9609-f40b6dbdd207', 8, 'Procedure Execution', 'Re-check vital signs at 15 minutes: If stable, adjust infusion rate to complete unit within prescribed duration (2 to 4 hours maximum per unit)',
  0.75, false, 'both',
  '["recheck vitals at 15 minutes","complete within 4 hours","never exceed 4 hours"]'::jsonb, 'Re-check vital signs at 15 minutes: If stable, adjust infusion rate to complete unit within prescribed duration (2 to 4 hours maximum per unit)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '32e2bbb3-4943-5c39-b286-2cb39cc663a4', '86ea5241-1591-58c5-9609-f40b6dbdd207', 9, 'Procedure Execution', 'State acute reaction symptoms: Chills, fever, rigor, dyspnea, lumbar/chest pain, facial flushing, urticaria, hypotension, hemoglobinuria',
  1, false, 'both',
  '["fever chills rigor","lumbar back pain","dyspnea chest tightness","urticaria pruritus"]'::jsonb, 'State acute reaction symptoms: Chills, fever, rigor, dyspnea, lumbar/chest pain, facial flushing, urticaria, hypotension, hemoglobinuria'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8dbaa8bb-13d1-5909-b62d-0af8fe74a37e', '86ea5241-1591-58c5-9609-f40b6dbdd207', 10, 'Procedure Execution', 'State immediate reaction management: STOP transfusion immediately! Disconnect blood set, keep IV line open with fresh saline, notify doctor, check vitals, save blood and urine for lab',
  1, true, 'both',
  '["stop transfusion immediately","keep vein open with normal saline","notify doctor","save blood bag and tubing"]'::jsonb, 'State immediate reaction management: STOP transfusion immediately! Disconnect blood set, keep IV line open with fresh saline, notify doctor, check vitals, save blood and urine for lab'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f466156e-25d3-52ff-afd2-b9a6ea6a4a99', '86ea5241-1591-58c5-9609-f40b6dbdd207', 11, 'Post-Procedure & Documentation', 'Upon completion, flush line with saline, dispose blood bag per hospital policy, record post-transfusion vitals, volume infused, and urine output in chart',
  0.75, false, 'both',
  '["flush line with saline","post transfusion vitals","document total volume","chart in nursing notes"]'::jsonb, 'Upon completion, flush line with saline, dispose blood bag per hospital policy, record post-transfusion vitals, volume infused, and urine output in chart'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Health Education on Prevention of Sickle Cell Crisis (Station 11)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'a09c4a1c-3386-53a3-9f62-269c9c5d626b', 'health-education', 'Health Education on Prevention of Sickle Cell Crisis', 'health-education-sickle-cell',
  'Station 11', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Nursing Licensing Examination',
  34, 34, 8, 4, 420,
  'Counsel a client or caregiver with sickle cell disease on preventing acute vaso-occlusive and hemolytic crises, recognizing danger signs, and maintaining health.', 'The mother of an 8-year-old child recently diagnosed with Sickle Cell Anaemia (HbSS) attends your clinic. Deliver structured health education on crisis prevention and home management.', 'oral',
  '["Health education flipchart on sickle cell disease","Chairs and counseling desk","Information pamphlet"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('055a24e7-32fe-5720-8ba2-cea30b018185', 'a09c4a1c-3386-53a3-9f62-269c9c5d626b', 1, true, 9)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2dea6ab4-4af9-5a50-b141-db5665f3ee5a', '055a24e7-32fe-5720-8ba2-cea30b018185', 1, 'Preparation & Equipment', 'Candidate greets examiner/client, introduces self, establishes rapport, and explains the objective of the counseling session',
  0.5, false, 'oral',
  '["greet client","introduce self","establish rapport","explain counseling"]'::jsonb, 'Candidate greets examiner/client, introduces self, establishes rapport, and explains the objective of the counseling session'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9e2ab6a2-5ebf-57b1-a6d8-6853f0798600', '055a24e7-32fe-5720-8ba2-cea30b018185', 2, 'Procedure Execution', 'Explain Sickle Cell Disease simply: An inherited hemoglobin disorder (HbSS) where red blood cells become crescent/sickle shaped under low oxygen',
  0.75, false, 'oral',
  '["inherited hemoglobin disorder","hbss genotype","crescent or sickle shape","abnormal hemoglobin"]'::jsonb, 'Explain Sickle Cell Disease simply: An inherited hemoglobin disorder (HbSS) where red blood cells become crescent/sickle shaped under low oxygen'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '15cd8d70-633e-52a9-a87c-ce0c65621d11', '055a24e7-32fe-5720-8ba2-cea30b018185', 3, 'Procedure Execution', 'Explain Vaso-occlusive Crisis triggers: Dehydration, infections/malaria, cold exposure/hypothermia, high altitude, strenuous physical exertion, emotional stress',
  1, true, 'oral',
  '["triggers of crisis","dehydration","cold weather","malaria infection","stress and exertion"]'::jsonb, 'Explain Vaso-occlusive Crisis triggers: Dehydration, infections/malaria, cold exposure/hypothermia, high altitude, strenuous physical exertion, emotional stress'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7542d380-a20e-5fca-b7b8-3ecbec6adb20', '055a24e7-32fe-5720-8ba2-cea30b018185', 4, 'Procedure Execution', 'Emphasize Adequate Hydration: Encourage drinking plenty of clean fluids daily (at least 2.5 - 3 liters/day for older child/adult) to maintain blood flow and prevent sickling',
  1.25, true, 'oral',
  '["drink plenty of water","stay hydrated","at least 3 liters daily","copious fluids prevents sickling"]'::jsonb, 'Emphasize Adequate Hydration: Encourage drinking plenty of clean fluids daily (at least 2.5 - 3 liters/day for older child/adult) to maintain blood flow and prevent sickling'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a0134782-9bd5-5bd6-af79-bb254866fcc0', '055a24e7-32fe-5720-8ba2-cea30b018185', 5, 'Procedure Execution', 'Explain Infection and Malaria Prevention: Sleep inside insecticide-treated nets (ITNs), take daily proguanil / malaria prophylaxis, and complete childhood immunizations (Pneumococcal, Hib, Meningococcal)',
  1.25, true, 'oral',
  '["malaria prophylaxis","sleep under mosquito nets","pneumococcal vaccine","routine immunizations","prevent infections"]'::jsonb, 'Explain Infection and Malaria Prevention: Sleep inside insecticide-treated nets (ITNs), take daily proguanil / malaria prophylaxis, and complete childhood immunizations (Pneumococcal, Hib, Meningococcal)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e0228b88-9fff-5af9-93ef-6df51dd0be9e', '055a24e7-32fe-5720-8ba2-cea30b018185', 6, 'Procedure Execution', 'Advise on Daily Medications: Emphasize daily Folic Acid supplementation (5mg daily) to support erythropoiesis, and adherence to Hydroxyurea where prescribed',
  0.75, false, 'oral',
  '["daily folic acid 5mg","hydroxyurea compliance","routine supplements"]'::jsonb, 'Advise on Daily Medications: Emphasize daily Folic Acid supplementation (5mg daily) to support erythropoiesis, and adherence to Hydroxyurea where prescribed'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '58ecffe2-3e6f-522f-ac79-b0d29bbb97c0', '055a24e7-32fe-5720-8ba2-cea30b018185', 7, 'Procedure Execution', 'Advise on Temperature Regulation and Avoidance of Extremes: Wear warm clothes in cold weather, avoid swimming in cold water, avoid excessive unventilated heat',
  0.75, false, 'oral',
  '["wear warm clothing","avoid cold water","avoid extreme temperatures"]'::jsonb, 'Advise on Temperature Regulation and Avoidance of Extremes: Wear warm clothes in cold weather, avoid swimming in cold water, avoid excessive unventilated heat'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '463e33db-cae0-5d50-bab3-f3f2fff9ed3b', '055a24e7-32fe-5720-8ba2-cea30b018185', 8, 'Procedure Execution', 'Teach Danger Signs requiring immediate hospital presentation: High fever, severe bone/joint pain, acute chest pain/breathlessness (Acute Chest Syndrome), sudden pallor, abdominal enlargement (splenic sequestration), priapism, neurological deficits (stroke)',
  1, true, 'oral',
  '["danger signs","high fever","acute chest syndrome","splenic sequestration","sudden pallor","stroke signs"]'::jsonb, 'Teach Danger Signs requiring immediate hospital presentation: High fever, severe bone/joint pain, acute chest pain/breathlessness (Acute Chest Syndrome), sudden pallor, abdominal enlargement (splenic sequestration), priapism, neurological deficits (stroke)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f0f3f4ea-8407-5126-aa47-4300c4e5f156', '055a24e7-32fe-5720-8ba2-cea30b018185', 9, 'Post-Procedure & Documentation', 'Allow client to ask questions, verify understanding through teach-back, provide educational leaflet, and document counseling in patient record',
  0.75, false, 'oral',
  '["teach back method","answer questions","provide pamphlet","document counseling"]'::jsonb, 'Allow client to ask questions, verify understanding through teach-back, provide educational leaflet, and document counseling in patient record'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Technique and Education on Breast Self-Examination (BSE) (Station 19)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'e49fa732-321c-59d5-9cc1-2d3814e7cd27', 'reproductive-health', 'Technique and Education on Breast Self-Examination (BSE)', 'breast-self-examination',
  'Station 19', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Final Qualifying Examination for Midwives - March 2011',
  73, 73, 8, 4, 420,
  'Demonstrate and teach the systematic technique of Breast Self-Examination to a woman using a breast model. State the timing, inspection positions, palpation methods, and warning signs.', 'A 26-year-old woman visits the family planning clinic and requests guidance on how to examine her breasts. Demonstrate and explain the step-by-step BSE procedure.', 'both',
  '["Breast model with palpable lumps","Mirror","Patient education chart / diagram of breast quadrants","Hand sanitizer"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('5ed9f46b-3edd-513f-9778-348f33aa9825', 'e49fa732-321c-59d5-9cc1-2d3814e7cd27', 1, true, 12)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd9e75a32-a917-5de1-9104-fbd2e3f25b08', '5ed9f46b-3edd-513f-9778-348f33aa9825', 1, 'Preparation & Equipment', 'Greet woman warmly, introduce self, explain importance of BSE for early detection of breast lumps and cancer, and establish rapport',
  0.5, false, 'both',
  '["greet woman","introduce self","early detection","importance of bse"]'::jsonb, 'Greet woman warmly, introduce self, explain importance of BSE for early detection of breast lumps and cancer, and establish rapport'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '79673603-9bac-543d-9c85-9ba7fa78d544', '5ed9f46b-3edd-513f-9778-348f33aa9825', 2, 'Procedure Execution', 'State the ideal timing: Perform BSE once a month, 7 to 10 days after the onset of menses when breasts are least tender and engorged; post-menopausal women choose a fixed date each month',
  1, true, 'both',
  '["timing 7 to 10 days after menses","once monthly","breasts least tender","fixed calendar day after menopause"]'::jsonb, 'State the ideal timing: Perform BSE once a month, 7 to 10 days after the onset of menses when breasts are least tender and engorged; post-menopausal women choose a fixed date each month'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '97111a5d-c806-5b73-bb6b-dfaeb97c3fd4', '5ed9f46b-3edd-513f-9778-348f33aa9825', 3, 'Procedure Execution', 'Demonstrate Visual Inspection in Front of Mirror - Position 1: Stand undressed to waist with arms relaxed at sides; inspect symmetry, contour, skin changes, dimpling, nipple inversion',
  0.75, false, 'both',
  '["stand before mirror","arms at sides","inspect symmetry","look for dimpling or skin changes"]'::jsonb, 'Demonstrate Visual Inspection in Front of Mirror - Position 1: Stand undressed to waist with arms relaxed at sides; inspect symmetry, contour, skin changes, dimpling, nipple inversion'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd9e8fec9-42d6-5bb4-81c3-fc4cee148eee', '5ed9f46b-3edd-513f-9778-348f33aa9825', 4, 'Procedure Execution', 'Demonstrate Visual Inspection - Position 2 & 3: Raise arms high above head; then place hands on hips and press down firmly to flex pectoral muscles; observe for retraction or puckering',
  0.75, false, 'both',
  '["raise arms overhead","hands on hips press down","flex pectoral muscles","check for puckering"]'::jsonb, 'Demonstrate Visual Inspection - Position 2 & 3: Raise arms high above head; then place hands on hips and press down firmly to flex pectoral muscles; observe for retraction or puckering'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5f8ac534-46a7-5745-a593-d81bd78ac044', '5ed9f46b-3edd-513f-9778-348f33aa9825', 5, 'Procedure Execution', 'Demonstrate Palpation in Supine Position: Lie flat with a small pillow/towel under shoulder of breast being examined, placing ipsilateral arm behind head to flatten breast tissue',
  0.75, false, 'both',
  '["lie flat","pillow under shoulder","arm behind head","flattens breast tissue"]'::jsonb, 'Demonstrate Palpation in Supine Position: Lie flat with a small pillow/towel under shoulder of breast being examined, placing ipsilateral arm behind head to flatten breast tissue'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6eb53480-1c10-5dc9-be6c-21247de1c029', '5ed9f46b-3edd-513f-9778-348f33aa9825', 6, 'Procedure Execution', 'Demonstrate Palpation Technique: Use the pads (pulps) of the three middle fingers of opposite hand; keep fingers flat and together; use small dime-sized circular motions',
  1, true, 'both',
  '["pads of three middle fingers","flat fingers","circular motions","opposite hand"]'::jsonb, 'Demonstrate Palpation Technique: Use the pads (pulps) of the three middle fingers of opposite hand; keep fingers flat and together; use small dime-sized circular motions'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f8db6e26-202a-5280-b336-2082442bee48', '5ed9f46b-3edd-513f-9778-348f33aa9825', 7, 'Procedure Execution', 'Demonstrate Three Levels of Pressure: Light pressure (subcutaneous tissue), medium pressure (deeper breast tissue), and firm pressure (tissue down to chest wall/ribs) at every spot',
  0.75, false, 'both',
  '["light medium and firm pressure","three levels of pressure","reach chest wall"]'::jsonb, 'Demonstrate Three Levels of Pressure: Light pressure (subcutaneous tissue), medium pressure (deeper breast tissue), and firm pressure (tissue down to chest wall/ribs) at every spot'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b029bb15-73e1-5200-ae9b-f8930ddb1080', '5ed9f46b-3edd-513f-9778-348f33aa9825', 8, 'Procedure Execution', 'Demonstrate Systematic Examination Patterns: Vertical strip method (lawnmower pattern), circular (spiral) pattern, or wedge/spoke pattern covering all 4 quadrants and the axillary tail of Spence',
  1, false, 'both',
  '["vertical strip pattern","circular spiral pattern","cover all quadrants","axillary tail of spence"]'::jsonb, 'Demonstrate Systematic Examination Patterns: Vertical strip method (lawnmower pattern), circular (spiral) pattern, or wedge/spoke pattern covering all 4 quadrants and the axillary tail of Spence'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1c007df5-1b82-593f-b558-842e9362c53c', '5ed9f46b-3edd-513f-9778-348f33aa9825', 9, 'Procedure Execution', 'Palpate the Axilla and Supraclavicular Areas: Palpate axillary lymph node chain and supraclavicular fossa for enlarged or hard lymph nodes',
  0.5, false, 'both',
  '["palpate axillary nodes","check armpit","supraclavicular nodes"]'::jsonb, 'Palpate the Axilla and Supraclavicular Areas: Palpate axillary lymph node chain and supraclavicular fossa for enlarged or hard lymph nodes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1fc8bb1b-769d-555b-859e-461019c4dccb', '5ed9f46b-3edd-513f-9778-348f33aa9825', 10, 'Procedure Execution', 'Examine Nipple-Areola Complex: Gently compress nipple between thumb and index finger; observe for spontaneous bloody or serous discharge',
  0.5, false, 'both',
  '["gently compress nipple","check for nipple discharge","bloody discharge"]'::jsonb, 'Examine Nipple-Areola Complex: Gently compress nipple between thumb and index finger; observe for spontaneous bloody or serous discharge'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '13437772-85a5-544d-aa45-6c6504fb54bd', '5ed9f46b-3edd-513f-9778-348f33aa9825', 11, 'Procedure Execution', 'State that the entire procedure must be repeated on the opposite breast',
  0.25, false, 'both',
  '["repeat on opposite breast","examine both breasts"]'::jsonb, 'State that the entire procedure must be repeated on the opposite breast'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e080d3d9-836b-53af-8f92-0a732da830d4', '5ed9f46b-3edd-513f-9778-348f33aa9825', 12, 'Post-Procedure & Documentation', 'Summarize Warning Signs requiring immediate medical evaluation: Painless hard lump, nipple retraction/discharge, peau d''orange skin, skin ulceration, axillary mass; conclude session',
  0.25, false, 'both',
  '["painless hard lump","peau d orange","nipple retraction","conclude session","encourage clinical screening"]'::jsonb, 'Summarize Warning Signs requiring immediate medical evaluation: Painless hard lump, nipple retraction/discharge, peau d''orange skin, skin ulceration, axillary mass; conclude session'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Tepid Sponging for Hyperpyrexia / Febrile Patient (Station 25)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '3da729b4-5742-54a9-8688-348c6909d705', 'fundamental-nursing', 'Tepid Sponging for Hyperpyrexia / Febrile Patient', 'tepid-sponging-hyperpyrexia',
  'Station 25', 'General Nursing Practicum / NMCN', 'Procedure Station Examination',
  44, 44, 8, 4, 420,
  'Demonstrate the nursing procedure of tepid sponging for a patient with severe pyrexia (temperature > 39.5°C). Explain mechanisms of heat loss, cooling principles, and nursing observations.', 'A 5-year-old child admitted with severe malaria presents with a temperature of 40.0°C and febrile restlessness. Demonstrate tepid sponging to reduce body temperature safely without inducing shivering.', 'both',
  '["Basin with tepid water (temperature 28-32°C / comfortably lukewarm)","Bath thermometer","5 to 6 cotton face cloths / washcloths","Mackintosh and bath blanket","Clinical thermometer","Bath towels","Screen for privacy"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('c67454c9-64c5-5121-8ddb-5f70f5c78f7a', '3da729b4-5742-54a9-8688-348c6909d705', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3d2f8a9b-e4c2-55c7-813a-8d36c680fe9d', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 1, 'Preparation & Equipment', 'Greet patient/caregiver, introduce self, verify identity, explain procedure, explain mechanism (heat loss via evaporation and conduction), and gain consent',
  0.5, false, 'both',
  '["greet patient","introduce self","explain procedure","evaporation and conduction"]'::jsonb, 'Greet patient/caregiver, introduce self, verify identity, explain procedure, explain mechanism (heat loss via evaporation and conduction), and gain consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd5f6f3ad-5070-5176-985b-2d95300764a2', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 2, 'Preparation & Equipment', 'Check baseline temperature, pulse, and respirations immediately prior to procedure',
  0.5, false, 'both',
  '["baseline vitals","check temperature","fever recorded"]'::jsonb, 'Check baseline temperature, pulse, and respirations immediately prior to procedure'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '89d7b1fa-bf70-5537-93b3-01d13b4fb942', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 3, 'Preparation & Equipment', 'Provide privacy, close windows, turn off ceiling fans/AC to avoid rapid chilling and violent shivering',
  0.5, false, 'both',
  '["close windows","turn off fan","prevent shivering"]'::jsonb, 'Provide privacy, close windows, turn off ceiling fans/AC to avoid rapid chilling and violent shivering'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '175af89f-43ee-578f-abdb-46326f2eb325', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 4, 'Preparation & Equipment', 'Prepare tepid water in basin: Test temperature with bath thermometer (28°C - 32°C / 82°F - 90°F); test on inner aspect of wrist; never use cold water or alcohol',
  0.75, true, 'both',
  '["tepid water 28 to 32 degrees","test water temperature","never use ice or alcohol","lukewarm water"]'::jsonb, 'Prepare tepid water in basin: Test temperature with bath thermometer (28°C - 32°C / 82°F - 90°F); test on inner aspect of wrist; never use cold water or alcohol'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cdbdd419-6e5f-5bcd-b618-13975a426339', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 5, 'Procedure Execution', 'Place protective mackintosh and bath towel under patient; remove clothing and cover with light bath blanket exposing only areas being sponged',
  0.5, false, 'both',
  '["mackintosh under patient","expose limb being sponged","light covering"]'::jsonb, 'Place protective mackintosh and bath towel under patient; remove clothing and cover with light bath blanket exposing only areas being sponged'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '629d3d93-2aab-50c9-a0f0-6be6e2e1c3f8', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 6, 'Procedure Execution', 'Wring out washcloths so they are moist but not dripping; place damp washcloths on areas of large superficial blood vessels: Axillae, Groin, and Forehead (prevents cerebral congestion)',
  1.25, true, 'both',
  '["place cloths on axillae and groin","damp cloth on forehead","superficial large blood vessels","cooling major vessels"]'::jsonb, 'Wring out washcloths so they are moist but not dripping; place damp washcloths on areas of large superficial blood vessels: Axillae, Groin, and Forehead (prevents cerebral congestion)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '27bd7fab-c60a-52da-a47e-82bbe9dc1a99', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 7, 'Procedure Execution', 'Sponge extremities and trunk systematically using gentle, long, slow downward strokes: Arms from shoulders to fingers, legs from thighs to toes (do not rub briskly, which increases metabolic heat)',
  1.25, false, 'both',
  '["slow downward strokes","do not rub vigorously","sponge extremities","evaporative cooling"]'::jsonb, 'Sponge extremities and trunk systematically using gentle, long, slow downward strokes: Arms from shoulders to fingers, legs from thighs to toes (do not rub briskly, which increases metabolic heat)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '21f38a1e-e5be-5289-8702-497a58afecc4', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 8, 'Procedure Execution', 'Change washcloths periodically as they absorb body heat and warm up; continue sponging for 20-30 minutes',
  0.75, false, 'both',
  '["change warm washcloths","sponge for 20 to 30 minutes"]'::jsonb, 'Change washcloths periodically as they absorb body heat and warm up; continue sponging for 20-30 minutes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9867860f-938d-5c19-8a07-5fc11bd5d058', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 9, 'Procedure Execution', 'Observe patient continuously: If patient starts shivering, becomes cyanotic, or appears mottled, STOP tepid sponging immediately and cover warmly (shivering raises core temperature)',
  1, true, 'both',
  '["stop if shivering starts","monitor for cyanosis","prevent shivering induced heat","vital observations"]'::jsonb, 'Observe patient continuously: If patient starts shivering, becomes cyanotic, or appears mottled, STOP tepid sponging immediately and cover warmly (shivering raises core temperature)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '548242b5-ac27-5dbb-8a0e-d99a28f508c2', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 10, 'Post-Procedure & Documentation', 'Pat skin dry gently with soft towel leaving slight moisture for evaporative cooling; dress patient in light cotton clothing and cover lightly',
  0.5, false, 'both',
  '["pat dry gently","light cotton clothing","comfort patient"]'::jsonb, 'Pat skin dry gently with soft towel leaving slight moisture for evaporative cooling; dress patient in light cotton clothing and cover lightly'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9138fc4a-c7d4-5048-aaf3-efff6b83d3e9', 'c67454c9-64c5-5121-8ddb-5f70f5c78f7a', 11, 'Post-Procedure & Documentation', 'Re-check vital signs (temperature) 30 minutes post-procedure; wash hands and document pre/post temperatures and patient response',
  0.5, false, 'both',
  '["recheck temperature after 30 minutes","wash hands","document in nursing chart"]'::jsonb, 'Re-check vital signs (temperature) 30 minutes post-procedure; wash hands and document pre/post temperatures and patient response'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Active Management of Third Stage of Labour (AMTSL) (Station 9)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '66a68f96-9e88-5166-8858-8a8cc93ffabf', 'maternal-midwifery', 'Active Management of Third Stage of Labour (AMTSL)', 'amtsl-third-stage-labour',
  'Station 9', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for Midwives',
  70, 71, 12, 6, 480,
  'Demonstrate the three components of Active Management of Third Stage of Labour (AMTSL) on a maternal birthing model according to ICM/FIGO and WHO guidelines. Include pharmacology of uterotonics.', 'You have just delivered a vigorous term neonate who is placed on the mother''s abdomen for skin-to-skin care. Demonstrate the active management of the third stage of labour to prevent postpartum haemorrhage.', 'both',
  '["Birthing model with placenta, umbilical cord and fetus","Oxytocin 10 IU ampoule / Misoprostol 600mcg","Sterile 2ml syringe and needle","Sterile cord clamps / ties","Sterile cord scissors","Sterile kidney dish / placenta basin","Sterile gloves"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('93b30c53-8d54-57f0-95c3-f6d20c993115', '66a68f96-9e88-5166-8858-8a8cc93ffabf', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '304148f8-acdc-52a7-9106-570eca8ef605', '93b30c53-8d54-57f0-95c3-f6d20c993115', 1, 'Preparation & Equipment', 'Explain procedure to the mother, reassure her, and ensure all AMTSL supplies are ready at hand',
  0.5, false, 'both',
  '["explain to mother","amtsl readiness","gain cooperation"]'::jsonb, 'Explain procedure to the mother, reassure her, and ensure all AMTSL supplies are ready at hand'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '571a1b96-abb8-52ef-aeb2-d5085939af3c', '93b30c53-8d54-57f0-95c3-f6d20c993115', 2, 'Procedure Execution', 'Component 1 (Uterotonic): Palpate mother''s abdomen to rule out the presence of an undiagnosed second twin before administering uterotonic',
  1, true, 'both',
  '["palpate abdomen to rule out second twin","rule out undiagnosed twin","abdominal palpation"]'::jsonb, 'Component 1 (Uterotonic): Palpate mother''s abdomen to rule out the presence of an undiagnosed second twin before administering uterotonic'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '08a4b97f-5aab-583a-b5d3-d870f02a6382', '93b30c53-8d54-57f0-95c3-f6d20c993115', 3, 'Procedure Execution', 'Administer Uterotonic: Inject Oxytocin 10 IU intramuscularly into the anterolateral thigh within 1 minute of fetal delivery (or Misoprostol 600 mcg orally if oxytocin unavailable)',
  1.5, true, 'both',
  '["oxytocin 10 iu im","within 1 minute of birth","anterolateral thigh","uterotonic administration"]'::jsonb, 'Administer Uterotonic: Inject Oxytocin 10 IU intramuscularly into the anterolateral thigh within 1 minute of fetal delivery (or Misoprostol 600 mcg orally if oxytocin unavailable)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '0a5f18d4-a85a-5230-a8c2-ba07cf3a1844', '93b30c53-8d54-57f0-95c3-f6d20c993115', 4, 'Procedure Execution', 'State pharmacology of Oxytocin: Onset 2-3 min IM, duration 2-3 hours; stimulates rhythmic uterine contractions; Misoprostol: E1 prostaglandin analogue, softens cervix, causes strong myometrial contractions',
  1, false, 'both',
  '["oxytocin onset and duration","misoprostol prostaglandin e1","myometrial contractions","pharmacology"]'::jsonb, 'State pharmacology of Oxytocin: Onset 2-3 min IM, duration 2-3 hours; stimulates rhythmic uterine contractions; Misoprostol: E1 prostaglandin analogue, softens cervix, causes strong myometrial contractions'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5619f75d-b0c4-5b9e-8bbe-7cf638abacca', '93b30c53-8d54-57f0-95c3-f6d20c993115', 5, 'Procedure Execution', 'Perform Delayed Cord Clamping: Wait 1 to 3 minutes after birth (or until cord pulsation ceases) before clamping and cutting cord, while keeping baby warm on mother''s chest',
  1, false, 'both',
  '["delayed cord clamping 1 to 3 minutes","wait until pulsations cease","skin to skin"]'::jsonb, 'Perform Delayed Cord Clamping: Wait 1 to 3 minutes after birth (or until cord pulsation ceases) before clamping and cutting cord, while keeping baby warm on mother''s chest'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9cdf88ed-c179-512d-817a-3badaccf1fbe', '93b30c53-8d54-57f0-95c3-f6d20c993115', 6, 'Procedure Execution', 'Clamp cord close to perineum with forceps/clamp; place non-dominant hand suprapubic just above symphysis pubis with palm facing mother''s umbilicus (providing counter-traction)',
  1.25, true, 'both',
  '["clamp cord close to perineum","suprapubic counter traction","hand above symphysis pubis","brandt andrews maneuver"]'::jsonb, 'Clamp cord close to perineum with forceps/clamp; place non-dominant hand suprapubic just above symphysis pubis with palm facing mother''s umbilicus (providing counter-traction)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9b92a525-a48b-51a3-a53e-6323bc9db1e9', '93b30c53-8d54-57f0-95c3-f6d20c993115', 7, 'Procedure Execution', 'Component 2 (Controlled Cord Traction - CCT): Wait for uterine contraction; pull cord gently downwards and outwards while pushing uterus upward and backwards with suprapubic hand',
  1.5, true, 'both',
  '["controlled cord traction","during contraction","downward cord traction","upward counter traction","never pull without counter traction"]'::jsonb, 'Component 2 (Controlled Cord Traction - CCT): Wait for uterine contraction; pull cord gently downwards and outwards while pushing uterus upward and backwards with suprapubic hand'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '0e04c01a-e34e-5d5f-befa-e67d3975f7c1', '93b30c53-8d54-57f0-95c3-f6d20c993115', 8, 'Procedure Execution', 'Delivery of Placenta: As placenta emerges from vagina, catch it with both hands, gently twist and rotate in a circular motion so membranes wind into a rope and peel off intact without tearing',
  1.25, false, 'both',
  '["catch placenta with both hands","rotate in circular motion","wind membranes into rope","prevent torn membranes"]'::jsonb, 'Delivery of Placenta: As placenta emerges from vagina, catch it with both hands, gently twist and rotate in a circular motion so membranes wind into a rope and peel off intact without tearing'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '10153bcd-3b7b-573d-b9f9-1f6075b95873', '93b30c53-8d54-57f0-95c3-f6d20c993115', 9, 'Procedure Execution', 'Component 3 (Uterine Massage): Immediately massage the fundus through mother''s abdomen until uterus is contracted hard like a cricket ball; teach mother how to self-massage fundus',
  1.25, true, 'both',
  '["immediate fundal massage","uterus contracted hard","teach mother self massage","rub up a contraction"]'::jsonb, 'Component 3 (Uterine Massage): Immediately massage the fundus through mother''s abdomen until uterus is contracted hard like a cricket ball; teach mother how to self-massage fundus'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b223ec4a-7125-5ae4-95a4-b81391b17e6c', '93b30c53-8d54-57f0-95c3-f6d20c993115', 10, 'Procedure Execution', 'Examine Placenta and Membranes: Inspect maternal cotyledons (all present, no missing lobes/succenturiate), inspect fetal surface, insertion of cord, 3 vessels, and complete membranes',
  1, false, 'both',
  '["examine placenta cotyledons","intact maternal surface","complete membranes","inspect umbilical cord vessels"]'::jsonb, 'Examine Placenta and Membranes: Inspect maternal cotyledons (all present, no missing lobes/succenturiate), inspect fetal surface, insertion of cord, 3 vessels, and complete membranes'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '0902d8d7-0502-5d4a-8924-1eb5c0b3d002', '93b30c53-8d54-57f0-95c3-f6d20c993115', 11, 'Post-Procedure & Documentation', 'Estimate blood loss (< 500ml), inspect perineum for tears, ensure mother is clean and comfortable, wash hands, and record details in delivery register',
  0.75, false, 'both',
  '["estimate blood loss","inspect perineum","wash hands","document delivery of placenta"]'::jsonb, 'Estimate blood loss (< 500ml), inspect perineum for tears, ensure mother is clean and comfortable, wash hands, and record details in delivery register'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Mechanism of Normal Labour: Left Occipito-Anterior (LOA) (Station 15)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'b2777532-48c6-535a-b4d4-c1590dffefcc', 'maternal-midwifery', 'Mechanism of Normal Labour: Left Occipito-Anterior (LOA)', 'mechanism-of-labour-loa',
  'Station 15', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for Midwives',
  83, 83, 10, 5, 420,
  'Demonstrate the mechanism of normal labour for Left Occipito-Anterior (LOA) position using the obstetric pelvic model and fetal doll. Name and demonstrate all seven Cardinal Movements in sequence.', 'You are at Station 15 with a bony female pelvis and fetal doll. Demonstrate the sequential mechanism of labour for an LOA presentation, explaining the movement of the occiput, shoulders, and trunk.', 'both',
  '["Obstetric bony female pelvis model","Fetal doll with palpable skull sutures and fontanelles","Pointer"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('6c9a79de-2b8b-518e-baad-7d04619bbf6c', 'b2777532-48c6-535a-b4d4-c1590dffefcc', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f83da9d7-3e7f-5594-a2a8-76b3de29b95f', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 1, 'Preparation & Equipment', 'Greet examiner, introduce self, hold the bony pelvis and fetal doll correctly and orient them in true anatomical position',
  0.5, false, 'both',
  '["greet examiner","introduce self","orient pelvis anatomically","hold doll correctly"]'::jsonb, 'Greet examiner, introduce self, hold the bony pelvis and fetal doll correctly and orient them in true anatomical position'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4c56546f-fc60-5b8d-ac45-a3377fc7fc07', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 2, 'Procedure Execution', 'State the Presentation, Denominator, and Position: Lie is longitudinal, Presentation is cephalic (vertex), Denominator is occiput, Position is Left Occipito-Anterior (LOA)',
  0.75, false, 'both',
  '["longitudinal lie","cephalic presentation","denominator occiput","left occipito anterior loa"]'::jsonb, 'State the Presentation, Denominator, and Position: Lie is longitudinal, Presentation is cephalic (vertex), Denominator is occiput, Position is Left Occipito-Anterior (LOA)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a22ae885-049e-5c86-b04b-e3db3b825186', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 3, 'Procedure Execution', 'Step 1 - Descent: Head enters the pelvic brim in the right oblique diameter with suboccipito-frontal diameter (10 cm) engaging; descent continues throughout labour',
  1, false, 'both',
  '["descent","right oblique diameter of brim","suboccipito-frontal engaging","continuous descent"]'::jsonb, 'Step 1 - Descent: Head enters the pelvic brim in the right oblique diameter with suboccipito-frontal diameter (10 cm) engaging; descent continues throughout labour'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '83f7ebc5-0afe-5be0-9988-ac6dea8fd6a6', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 4, 'Procedure Execution', 'Step 2 - Flexion: As descending head meets resistance of soft tissues / pelvic floor, increased flexion occurs, substituting suboccipito-bregmatic diameter (9.5 cm)',
  1, true, 'both',
  '["flexion","chin touches chest","suboccipito-bregmatic diameter 9.5 cm","increased flexion"]'::jsonb, 'Step 2 - Flexion: As descending head meets resistance of soft tissues / pelvic floor, increased flexion occurs, substituting suboccipito-bregmatic diameter (9.5 cm)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b74fc8bf-5ac3-5709-9eec-edbce1e60d86', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 5, 'Procedure Execution', 'Step 3 - Internal Rotation of the Head: Occiput reaches pelvic floor and rotates 1/8th of a circle (45 degrees) anteriorly to lie under the symphysis pubis (anteroposterior diameter of outlet)',
  1.25, true, 'both',
  '["internal rotation of head","rotates 1/8 of a circle anteriorly","45 degrees anterior rotation","occiput under symphysis pubis"]'::jsonb, 'Step 3 - Internal Rotation of the Head: Occiput reaches pelvic floor and rotates 1/8th of a circle (45 degrees) anteriorly to lie under the symphysis pubis (anteroposterior diameter of outlet)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '46c6d48a-1d0b-5b34-813c-61e8262e0994', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 6, 'Procedure Execution', 'Step 4 - Crowning: The widest diameter of the fetal head (biparietal 9.5 cm) stretches the vulval outlet without head receding between contractions',
  1, false, 'both',
  '["crowning","biparietal diameter stretches vulva","head does not recede","widest transverse diameter"]'::jsonb, 'Step 4 - Crowning: The widest diameter of the fetal head (biparietal 9.5 cm) stretches the vulval outlet without head receding between contractions'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c9b29a79-f514-5eee-9a37-7b35996df6f0', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 7, 'Procedure Execution', 'Step 5 - Extension: Nape of the neck pivots under the subpubic arch; with extension, sinciput, face, and chin sweep over the perineum and head is born',
  1, true, 'both',
  '["extension of head","nape pivots under subpubic arch","head born by extension","sinciput face chin born"]'::jsonb, 'Step 5 - Extension: Nape of the neck pivots under the subpubic arch; with extension, sinciput, face, and chin sweep over the perineum and head is born'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6112f33a-eea5-5899-bb39-2eb7a5c5cfdf', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 8, 'Procedure Execution', 'Step 6 - Restitution: Head rotates 1/8th of a circle back to the left to align with the shoulders which are engaging in the left oblique diameter of the brim',
  1, false, 'both',
  '["restitution","rotates 1/8 of a circle to left","aligns with shoulders","undoes neck twist"]'::jsonb, 'Step 6 - Restitution: Head rotates 1/8th of a circle back to the left to align with the shoulders which are engaging in the left oblique diameter of the brim'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'bb49d23e-ab68-5ffb-b979-e2b29bfdcc1d', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 9, 'Procedure Execution', 'Step 7 - Internal Rotation of Shoulders: Anterior shoulder reaches pelvic floor and rotates 1/8th of a circle anteriorly to lie behind symphysis pubis; causes External Rotation of the head (another 1/8th circle)',
  1, false, 'both',
  '["internal rotation of shoulders","anterior shoulder rotates under symphysis","external rotation of head","shoulders in ap diameter"]'::jsonb, 'Step 7 - Internal Rotation of Shoulders: Anterior shoulder reaches pelvic floor and rotates 1/8th of a circle anteriorly to lie behind symphysis pubis; causes External Rotation of the head (another 1/8th circle)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'af7009af-64e0-5811-bf11-09255c06e9d0', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 10, 'Procedure Execution', 'Step 8 - Lateral Flexion: Anterior shoulder is born under symphysis pubis, followed by posterior shoulder over perineum; remaining body is born by lateral flexion',
  1, true, 'both',
  '["lateral flexion","anterior shoulder born","posterior shoulder born","trunk born by lateral flexion"]'::jsonb, 'Step 8 - Lateral Flexion: Anterior shoulder is born under symphysis pubis, followed by posterior shoulder over perineum; remaining body is born by lateral flexion'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b9533a42-b3e5-58fd-b42e-7236d633d246', '6c9a79de-2b8b-518e-baad-7d04619bbf6c', 11, 'Post-Procedure & Documentation', 'Conclude demonstration, replace models neatly, and thank the examiner',
  0.5, false, 'both',
  '["conclude demonstration","thank examiner"]'::jsonb, 'Conclude demonstration, replace models neatly, and thank the examiner'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Infiltration and Performance of Mediolateral Episiotomy (Station 5)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'ea56274c-790a-56bb-9ced-b88b0fb2e45e', 'maternal-midwifery', 'Infiltration and Performance of Mediolateral Episiotomy', 'giving-of-episiotomy',
  'Station 5', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for Midwives',
  52, 52, 8, 4, 420,
  'Demonstrate local anaesthetic perineal infiltration and cutting of a mediolateral episiotomy on the perineal model. State indications, timing, structures cut, and protection of fetal head.', 'A primigravida is in the second stage of labour with crowning. The perineum is rigid and threatens a jagged 3rd-degree tear. Demonstrate the correct timing, perineal infiltration, and execution of a mediolateral episiotomy.', 'both',
  '["Perineal delivery model","1% Lignocaine / Lidocaine without adrenaline (10ml)","10ml syringe with 21G green needle","Mayo / Braun-Stadler curved episiotomy scissors","Antiseptic solution and sterile gauze swabs","Sterile gloves"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('3963758e-dd16-5ba0-a4aa-54089959f3a7', 'ea56274c-790a-56bb-9ced-b88b0fb2e45e', 1, true, 10)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f87c0b98-bbae-578c-a908-e06f6260089c', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 1, 'Preparation & Equipment', 'State indications for episiotomy: Rigid perineum, fetal distress in 2nd stage, instrumental delivery (forceps/vacuum), shoulder dystocia, preterm delivery',
  0.75, false, 'both',
  '["indications for episiotomy","rigid perineum","fetal distress","preterm delivery","instrumental birth"]'::jsonb, 'State indications for episiotomy: Rigid perineum, fetal distress in 2nd stage, instrumental delivery (forceps/vacuum), shoulder dystocia, preterm delivery'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd14c2966-b326-5fa8-8354-ed812d2dc89d', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 2, 'Preparation & Equipment', 'Explain procedure to mother, obtain informed consent, ensure bladder is empty, clean perineum with antiseptic, and don sterile gloves',
  0.5, false, 'both',
  '["explain to mother","informed consent","clean perineum","sterile gloves"]'::jsonb, 'Explain procedure to mother, obtain informed consent, ensure bladder is empty, clean perineum with antiseptic, and don sterile gloves'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '33b5af52-a317-506b-a845-07926df4431a', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 3, 'Procedure Execution', 'State the correct timing: Episiotomy must be performed when the perineum is bulging and thinned, and 3-4 cm of fetal head is visible during a contraction (crowning)',
  0.75, true, 'both',
  '["timing at crowning","perineum thinned and bulging","3 to 4 cm head visible","during contraction"]'::jsonb, 'State the correct timing: Episiotomy must be performed when the perineum is bulging and thinned, and 3-4 cm of fetal head is visible during a contraction (crowning)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '914514f0-c010-589d-b3c7-9ee35248caf4', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 4, 'Procedure Execution', 'Perform Perineal Infiltration: Insert two fingers of non-dominant hand into vagina between fetal head and posterior vaginal wall to protect the fetal head',
  1, true, 'both',
  '["insert two fingers into vagina","protect fetal head","fingers between head and perineum"]'::jsonb, 'Perform Perineal Infiltration: Insert two fingers of non-dominant hand into vagina between fetal head and posterior vaginal wall to protect the fetal head'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cc79191b-8841-54b0-8a46-c6225c08effc', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 5, 'Procedure Execution', 'Introduce needle at posterior fourchette; infiltrate 10ml of 1% Lignocaine along the planned mediolateral incision line in a fan-shaped manner, aspirating before injection to avoid intravascular entry',
  1.25, true, 'both',
  '["infiltrate 1 percent lignocaine","aspirate before injection","fan shaped infiltration","along planned incision"]'::jsonb, 'Introduce needle at posterior fourchette; infiltrate 10ml of 1% Lignocaine along the planned mediolateral incision line in a fan-shaped manner, aspirating before injection to avoid intravascular entry'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '97d75ba7-a7ca-5357-b100-395573d4e72f', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 6, 'Procedure Execution', 'Allow 2-3 minutes for anaesthetic effect (unless acute fetal distress); test for analgesia by pinching gently with forceps',
  0.5, false, 'both',
  '["wait for anaesthesia","test analgesia with forceps","confirm numbness"]'::jsonb, 'Allow 2-3 minutes for anaesthetic effect (unless acute fetal distress); test for analgesia by pinching gently with forceps'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a2292e9b-6680-5f06-926c-0d7412a01b88', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 7, 'Procedure Execution', 'Position fingers: Keep two fingers inside vagina depressing vaginal wall to protect baby''s head from scissors blades',
  0.75, true, 'both',
  '["two fingers protecting head","depress posterior wall","guard fetal skull"]'::jsonb, 'Position fingers: Keep two fingers inside vagina depressing vaginal wall to protect baby''s head from scissors blades'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '37a03e6c-cfc1-5ecb-a078-a0203b69ebea', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 8, 'Procedure Execution', 'Cut Mediolateral Episiotomy: Place one blade of blunt-ended episiotomy scissors inside vagina and other outside; make a single clean, decisive cut 3 to 4 cm long at 45° angle towards the ischial tuberosity',
  1.5, true, 'both',
  '["cut at 45 degree angle","mediolateral incision","towards ischial tuberosity","3 to 4 cm decisive cut","single snip"]'::jsonb, 'Cut Mediolateral Episiotomy: Place one blade of blunt-ended episiotomy scissors inside vagina and other outside; make a single clean, decisive cut 3 to 4 cm long at 45° angle towards the ischial tuberosity'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '37f8c39f-415c-56de-8531-bc3f37374d0d', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 9, 'Procedure Execution', 'Name anatomical structures incised: Posterior vaginal wall/mucosa, perineal skin, subcutaneous tissue, bulbospongiosus, superficial and deep transverse perineal muscles',
  0.75, false, 'both',
  '["structures cut","vaginal mucosa","bulbospongiosus","transverse perineal muscles","perineal skin"]'::jsonb, 'Name anatomical structures incised: Posterior vaginal wall/mucosa, perineal skin, subcutaneous tissue, bulbospongiosus, superficial and deep transverse perineal muscles'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f9636a9e-3f6f-50e3-8e58-d1cd202fd214', '3963758e-dd16-5ba0-a4aa-54089959f3a7', 10, 'Post-Procedure & Documentation', 'Control delivery of fetal head by gentle counterpressure to avoid extension of the cut; apply sterile gauze pad with firm pressure to wound until repaired; document',
  0.25, false, 'both',
  '["control head delivery","pressure to episiotomy wound","document time and type of episiotomy"]'::jsonb, 'Control delivery of fetal head by gentle counterpressure to avoid extension of the cut; apply sterile gauze pad with firm pressure to wound until repaired; document'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Abdominal Palpation: Leopold's Maneuvers for Fetal Lie and Presentation (Station 13)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'c8f99b24-fa3f-5b6c-a20a-8996a64010dc', 'maternal-midwifery', 'Abdominal Palpation: Leopold''s Maneuvers for Fetal Lie and Presentation', 'abdominal-palpation-leopold',
  'Station 13', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery OSCE Station Examination',
  58, 58, 10, 5, 420,
  'Demonstrate systematic abdominal palpation using Leopold''s maneuvers on the pregnant abdomen model. Determine fundal height, fetal lie, presentation, position, and engagement.', 'A 36-week pregnant woman attends the antenatal clinic for third-trimester assessment. Perform Leopold''s 4 maneuvers systematically, reporting each finding to the examiner.', 'both',
  '["Antenatal abdominal palpation mannequin","Pinard fetal stethoscope / Doppler","Measuring tape (centimeters)","Warm hands","Screens for privacy"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('d6bb15ab-78ef-5c13-aea8-65cf35949f2f', 'c8f99b24-fa3f-5b6c-a20a-8996a64010dc', 1, true, 10)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'aeb4d842-fbd0-5728-aa37-3915e19d15ac', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 1, 'Preparation & Equipment', 'Greet woman, introduce self, explain procedure, ensure privacy, ask her to empty bladder, and warm hands before touching abdomen',
  0.5, false, 'both',
  '["greet woman","introduce self","empty bladder","warm hands","explain procedure"]'::jsonb, 'Greet woman, introduce self, explain procedure, ensure privacy, ask her to empty bladder, and warm hands before touching abdomen'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '703f82d5-4eda-5ad1-bf52-894db31d9d2b', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 2, 'Preparation & Equipment', 'Position woman in semi-recumbent position with knees slightly flexed to relax abdominal wall; expose abdomen from xiphisternum to pubic symphysis',
  0.5, false, 'both',
  '["semi recumbent","knees slightly flexed","relax abdominal muscles","expose abdomen"]'::jsonb, 'Position woman in semi-recumbent position with knees slightly flexed to relax abdominal wall; expose abdomen from xiphisternum to pubic symphysis'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '29a4f554-f230-5b76-97eb-d0cdb26cc62a', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 3, 'Procedure Execution', 'Inspect abdomen: Contour, scars (previous CS), linea nigra, striae gravidarum, fetal movements, and skin distension',
  0.5, false, 'both',
  '["inspect abdomen","contour and scars","linea nigra striae"]'::jsonb, 'Inspect abdomen: Contour, scars (previous CS), linea nigra, striae gravidarum, fetal movements, and skin distension'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6eb56175-92f3-5e4c-b2bc-cbe272d8352d', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 4, 'Procedure Execution', 'Assess Symphysis-Fundal Height (SFH): Palpate upper border of fundus with ulnar border of left hand; measure with tape from top of symphysis pubis to fundus in centimeters (gestational age correlation)',
  1, false, 'both',
  '["symphysis fundal height","sfh measurement in cm","tape reversed to avoid bias","correlate with gestational age"]'::jsonb, 'Assess Symphysis-Fundal Height (SFH): Palpate upper border of fundus with ulnar border of left hand; measure with tape from top of symphysis pubis to fundus in centimeters (gestational age correlation)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a8b3c0d1-4c4b-5186-a922-ec14cff3b8c3', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 5, 'Procedure Execution', 'First Maneuver (Fundal Palpation): Face woman''s head; palpate uterine fundus with both hands to determine which fetal pole occupies the fundus (Breech: soft, irregular, non-ballottable vs Head: hard, round, ballottable)',
  1.5, true, 'both',
  '["first maneuver fundal palpation","determine fetal pole in fundus","breech is soft and irregular","head is hard and ballottable"]'::jsonb, 'First Maneuver (Fundal Palpation): Face woman''s head; palpate uterine fundus with both hands to determine which fetal pole occupies the fundus (Breech: soft, irregular, non-ballottable vs Head: hard, round, ballottable)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c87c7b88-a378-5fcd-967e-20837738873d', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 6, 'Procedure Execution', 'Second Maneuver (Lateral / Umbilical Palpation): Place hands flat on both sides of uterus; support with one hand while palpating with other to locate fetal back (smooth, firm, continuous curve) vs limbs/extremities (knobby, irregular)',
  1.5, true, 'both',
  '["second maneuver lateral palpation","locate fetal back","smooth firm continuous curve","fetal limbs knobby","determines position"]'::jsonb, 'Second Maneuver (Lateral / Umbilical Palpation): Place hands flat on both sides of uterus; support with one hand while palpating with other to locate fetal back (smooth, firm, continuous curve) vs limbs/extremities (knobby, irregular)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cbad6da4-52c1-52c0-b65b-0f7c543b6a6e', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 7, 'Procedure Execution', 'Third Maneuver (Pawlik''s Grip / Pelvic Palpation): Grasp lower uterine segment just above symphysis pubis between thumb and four fingers of right hand; gently palpate to identify presenting part and mobility/ballottability',
  1.5, true, 'both',
  '["third maneuver pawlik grip","grasp presenting part","identify cephalic vs breech","assess mobility"]'::jsonb, 'Third Maneuver (Pawlik''s Grip / Pelvic Palpation): Grasp lower uterine segment just above symphysis pubis between thumb and four fingers of right hand; gently palpate to identify presenting part and mobility/ballottability'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '002c76cd-4995-5e8f-9945-77a52fc8be94', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 8, 'Procedure Execution', 'Fourth Maneuver (Deep Pelvic Palpation): Turn and face woman''s feet; place fingertips of both hands on either side of lower pole; press downward towards pelvic inlet to determine engagement (converging fingers = unengaged; diverging = engaged)',
  1.5, true, 'both',
  '["fourth maneuver pelvic palpation","face woman feet","determine engagement","converging vs diverging fingers"]'::jsonb, 'Fourth Maneuver (Deep Pelvic Palpation): Turn and face woman''s feet; place fingertips of both hands on either side of lower pole; press downward towards pelvic inlet to determine engagement (converging fingers = unengaged; diverging = engaged)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '04b36b90-64f1-5922-9944-37cd5f0956fb', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 9, 'Procedure Execution', 'Auscultate Fetal Heart Rate (FHR): Locate Pinard stethoscope or Doppler over fetal back; listen for 1 full minute; state normal rate (110-160 bpm) and rhythm',
  1, true, 'both',
  '["auscultate fetal heart rate","over fetal back","pinard stethoscope","normal 110 to 160 bpm"]'::jsonb, 'Auscultate Fetal Heart Rate (FHR): Locate Pinard stethoscope or Doppler over fetal back; listen for 1 full minute; state normal rate (110-160 bpm) and rhythm'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'aefa7d0e-9561-510f-b130-20a1c95d6449', 'd6bb15ab-78ef-5c13-aea8-65cf35949f2f', 10, 'Post-Procedure & Documentation', 'Help woman sit up, thank her, wash hands, and document fundal height, lie (longitudinal), presentation (cephalic), position (LOA/ROA), engagement (fifths palpable), and FHR',
  0.5, false, 'both',
  '["help woman sit up","wash hands","document complete findings in chart"]'::jsonb, 'Help woman sit up, thank her, wash hands, and document fundal height, lie (longitudinal), presentation (cephalic), position (LOA/ROA), engagement (fifths palpable), and FHR'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Visual Inspection of the Cervix with Acetic Acid (VIA) (Station 17)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '6e919842-c0af-5f46-a03e-3e71678d3355', 'reproductive-health', 'Visual Inspection of the Cervix with Acetic Acid (VIA)', 'via-cervical-cancer-screening',
  'Station 17', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery Licensing Examination',
  60, 60, 8, 4, 420,
  'Demonstrate cervical cancer screening using Visual Inspection with 3-5% Acetic Acid (VIA) on a pelvic/gynaecological model. Describe normal, positive (acetowhite), and suspicious lesions.', 'A 35-year-old woman presents at the reproductive health clinic for routine cervical screening. Demonstrate the complete VIA procedure following national cervical cancer screening protocols.', 'both',
  '["Gynaecological pelvic examination model with interchangeable cervices","Cusco bivalve speculum","3% - 5% freshly prepared Acetic Acid (dilute vinegar)","Large cotton swabs","Good directional halogen light / torch","Examining gloves","0.5% Chlorine decontamination bucket"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('c45a9b98-ee7e-558e-8bed-0e4c24eb2825', '6e919842-c0af-5f46-a03e-3e71678d3355', 1, true, 11)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9123ed29-1c1d-5815-af25-654b92274969', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 1, 'Preparation & Equipment', 'Greet woman, introduce self, confirm eligibility (not currently menstruating, no pregnancy), explain procedure, reassure and obtain consent',
  0.5, false, 'both',
  '["greet woman","introduce self","confirm eligibility","explain via","obtain consent"]'::jsonb, 'Greet woman, introduce self, confirm eligibility (not currently menstruating, no pregnancy), explain procedure, reassure and obtain consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4b8f244a-86cd-599d-99bb-eb306f0eb657', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 2, 'Preparation & Equipment', 'Ensure bright light source is positioned; arrange sterile speculum, freshly prepared 3-5% acetic acid, and large swabs on trolley; wash hands and don gloves',
  0.5, false, 'both',
  '["bright light source","3 to 5 percent acetic acid","speculum ready","don gloves"]'::jsonb, 'Ensure bright light source is positioned; arrange sterile speculum, freshly prepared 3-5% acetic acid, and large swabs on trolley; wash hands and don gloves'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5ff08690-1a30-5475-bbc5-0cd187485f14', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 3, 'Preparation & Equipment', 'Position woman in lithotomy/dorsal position with buttocks at edge of examination couch; drape for privacy',
  0.5, false, 'both',
  '["lithotomy position","drape for privacy","buttocks at edge"]'::jsonb, 'Position woman in lithotomy/dorsal position with buttocks at edge of examination couch; drape for privacy'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '07e35c96-f144-5274-87a8-5b1ac321334c', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 4, 'Procedure Execution', 'Inspect external genitalia; lubricate speculum with warm water (not gel); insert speculum gently into vagina, open blades and visualize entire cervix',
  1, false, 'both',
  '["inspect external genitalia","insert cusco speculum","visualize entire cervix","water lubricant"]'::jsonb, 'Inspect external genitalia; lubricate speculum with warm water (not gel); insert speculum gently into vagina, open blades and visualize entire cervix'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '43775b31-0355-5caf-b993-d49cd94024f6', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 5, 'Procedure Execution', 'Inspect cervix under bright light before applying acetic acid: Identify external os, squamocolumnar junction (SCJ), transformation zone; rule out cervical cancer / bleeding ulcer',
  1, false, 'both',
  '["inspect before acid","locate squamocolumnar junction scj","transformation zone","rule out frank growth"]'::jsonb, 'Inspect cervix under bright light before applying acetic acid: Identify external os, squamocolumnar junction (SCJ), transformation zone; rule out cervical cancer / bleeding ulcer'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7c2a854c-b218-58a2-a0b6-8e1cb51081d8', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 6, 'Procedure Execution', 'Soak large cotton swab in 3-5% acetic acid; apply generously to entire cervix, especially the transformation zone, for at least 1 full minute',
  1.25, true, 'both',
  '["apply 3 to 5 percent acetic acid","soak cervix with swab","wait 1 full minute","contact time 60 seconds"]'::jsonb, 'Soak large cotton swab in 3-5% acetic acid; apply generously to entire cervix, especially the transformation zone, for at least 1 full minute'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '3f24c04f-f394-58dd-bf11-5cb3e36a9cdb', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 7, 'Procedure Execution', 'Interpret VIA Result - Negative: Smooth pink cervix, faint/diffuse blue-white line at SCJ, or nabothian cysts (no distinct dense acetowhite lesions)',
  1, false, 'both',
  '["via negative","smooth pink cervix","no distinct acetowhite lesion","normal scj"]'::jsonb, 'Interpret VIA Result - Negative: Smooth pink cervix, faint/diffuse blue-white line at SCJ, or nabothian cysts (no distinct dense acetowhite lesions)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '29242248-a6bd-5578-9193-950b9bbf196b', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 8, 'Procedure Execution', 'Interpret VIA Result - Positive: Sharp, distinct, well-defined, opaque dense acetowhite lesion on or abutting the squamocolumnar junction within the transformation zone',
  1.25, true, 'both',
  '["via positive","sharp distinct acetowhite lesion","abutting the scj","opaque dense white area","precancerous lesion"]'::jsonb, 'Interpret VIA Result - Positive: Sharp, distinct, well-defined, opaque dense acetowhite lesion on or abutting the squamocolumnar junction within the transformation zone'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'bd27e297-5fee-580e-a0e1-d09a76af1f8c', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 9, 'Procedure Execution', 'Remove excess acid with clean dry swab; unlock and remove speculum gently while rotating slightly to inspect vaginal walls',
  0.5, false, 'both',
  '["remove excess acid","remove speculum gently","inspect vaginal walls"]'::jsonb, 'Remove excess acid with clean dry swab; unlock and remove speculum gently while rotating slightly to inspect vaginal walls'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '082bf18e-8dea-57da-9a5f-eb8c4c681dd7', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 10, 'Post-Procedure & Documentation', 'Decontaminate instruments in 0.5% chlorine solution for 10 minutes; remove gloves; wash hands',
  0.25, false, 'both',
  '["decontaminate in 0.5 percent chlorine","wash hands"]'::jsonb, 'Decontaminate instruments in 0.5% chlorine solution for 10 minutes; remove gloves; wash hands'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7a26def1-d046-55c8-83eb-7ba552247230', 'c45a9b98-ee7e-558e-8bed-0e4c24eb2825', 11, 'Post-Procedure & Documentation', 'Inform woman of results immediately: If negative, advise repeat screening in 3-5 years; if positive, counsel on single-visit cryotherapy / LEEP / colposcopy referral; document in register',
  0.25, false, 'both',
  '["inform woman immediately","single visit approach","cryotherapy or leep referral","repeat screening in 3 to 5 years","document in register"]'::jsonb, 'Inform woman of results immediately: If negative, advise repeat screening in 3-5 years; if positive, counsel on single-visit cryotherapy / LEEP / colposcopy referral; document in register'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Bimanual Uterine Compression for Postpartum Haemorrhage (PPH) (Station 9)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '781d2e90-8eb8-5cc8-a978-5ab74795aadf', 'maternal-midwifery', 'Bimanual Uterine Compression for Postpartum Haemorrhage (PPH)', 'bimanual-uterine-compression',
  'Station 9', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for Midwives',
  65, 65, 8, 4, 420,
  'Demonstrate both External and Internal Bimanual Uterine Compression on a postpartum obstetric mannequin model for severe atonic postpartum haemorrhage. State principles, pressure points, and safety measures.', 'Following delivery of the placenta, the mother has sudden severe postpartum bleeding. The uterus is soft, boggy, and does not respond to fundal massage or uterotonics. Demonstrate bimanual compression to arrest the bleeding.', 'both',
  '["Postpartum birthing simulator with bleeding reservoir","Sterile elbow-length gloves","Antiseptic solution (Savlon / Chlorhexidine)","Urinary catheter (Foley 16 Fr) and bag","IV cannulae and normal saline","Screens for privacy"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('8706d989-58a4-5eff-9a9e-4e7f46deea6f', '781d2e90-8eb8-5cc8-a978-5ab74795aadf', 1, true, 9)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '06ee0999-0f03-5d57-aff2-04c11463ec12', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 1, 'Preparation & Equipment', 'Recognize severe atonic PPH: Call for help immediately, assign roles, notify doctor/obstetrician, and alert blood bank',
  0.5, false, 'both',
  '["call for help","atonic pph","emergency team alert"]'::jsonb, 'Recognize severe atonic PPH: Call for help immediately, assign roles, notify doctor/obstetrician, and alert blood bank'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b52d18ec-a323-5857-979a-54cf3883ef0a', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 2, 'Preparation & Equipment', 'Explain emergency action to mother/family; check IV access (two large-bore lines) and insert Foley catheter to empty bladder (distended bladder prevents contraction)',
  0.75, true, 'both',
  '["explain to mother","two large bore iv lines","empty bladder with foley catheter","empty bladder crucial"]'::jsonb, 'Explain emergency action to mother/family; check IV access (two large-bore lines) and insert Foley catheter to empty bladder (distended bladder prevents contraction)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c5d1b7bd-b30f-58db-aca5-fb4505ca59fc', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 3, 'Procedure Execution', 'Demonstrate External Bimanual Compression: Place one hand flat on mother''s lower abdomen behind the fundus; place other hand flat above pubic bone in front of uterus; press both hands firmly together to compress the uterine body',
  1.5, false, 'both',
  '["external bimanual compression","one hand behind fundus","other hand above pubis","compress uterus between hands"]'::jsonb, 'Demonstrate External Bimanual Compression: Place one hand flat on mother''s lower abdomen behind the fundus; place other hand flat above pubic bone in front of uterus; press both hands firmly together to compress the uterine body'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8e8e3658-b224-5790-85d1-40e1da69837a', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 4, 'Procedure Execution', 'Transition to Internal Bimanual Compression: Wash hands quickly with antiseptic and don sterile long elbow-length gloves',
  0.5, false, 'both',
  '["sterile elbow length gloves","surgical asepsis","don gloves quickly"]'::jsonb, 'Transition to Internal Bimanual Compression: Wash hands quickly with antiseptic and don sterile long elbow-length gloves'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '88f4788a-3ea9-52dc-aed1-cacf9c8b3077', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 5, 'Procedure Execution', 'Form cone shape with gloved dominant hand and gently insert into vagina until reaching the anterior fornix',
  1, false, 'both',
  '["insert cone shaped hand","reach anterior fornix","internal hand"]'::jsonb, 'Form cone shape with gloved dominant hand and gently insert into vagina until reaching the anterior fornix'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd3f4f05b-cee4-50ce-863f-2ed0c1d79600', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 6, 'Procedure Execution', 'Form a closed fist inside the anterior vaginal fornix with dorsal surface of fingers pressing firmly against anterior uterine wall',
  1.25, true, 'both',
  '["make a fist inside vagina","fist in anterior fornix","press against anterior uterine wall"]'::jsonb, 'Form a closed fist inside the anterior vaginal fornix with dorsal surface of fingers pressing firmly against anterior uterine wall'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '12ab4ea4-bf83-5f07-ba2e-5fd6949f593f', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 7, 'Procedure Execution', 'Place non-dominant hand flat over the posterior abdominal wall of the uterus, reaching deeply behind fundus; press both hands firmly toward each other to compress uterine corpus between internal fist and external hand',
  1.5, true, 'both',
  '["compress uterus between fist and external hand","external hand behind fundus","occlude uterine blood vessels","firm continuous pressure"]'::jsonb, 'Place non-dominant hand flat over the posterior abdominal wall of the uterus, reaching deeply behind fundus; press both hands firmly toward each other to compress uterine corpus between internal fist and external hand'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ac0a4861-11df-590d-8419-6280b547a937', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 8, 'Procedure Execution', 'Maintain firm, continuous pressure for at least 5 to 10 minutes until uterus contracts firmly and bleeding is arrested; do not release prematurely',
  0.75, true, 'both',
  '["maintain pressure 5 to 10 minutes","wait until uterus contracts firmly","continuous compression"]'::jsonb, 'Maintain firm, continuous pressure for at least 5 to 10 minutes until uterus contracts firmly and bleeding is arrested; do not release prematurely'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c2036947-f5c1-54e3-91b6-ba351b08cf06', '8706d989-58a4-5eff-9a9e-4e7f46deea6f', 9, 'Post-Procedure & Documentation', 'Once uterus is firm, withdraw internal hand slowly; continue uterotonic infusion (Oxytocin 20-40 IU in 1L saline at 60 drops/min), monitor vitals and lochia, document blood loss and procedure',
  0.25, false, 'both',
  '["withdraw hand slowly","oxytocin infusion","monitor vitals","document in delivery register"]'::jsonb, 'Once uterus is firm, withdraw internal hand slowly; continue uterotonic infusion (Oxytocin 20-40 IU in 1L saline at 60 drops/min), monitor vitals and lochia, document blood loss and procedure'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Delivery of the Placenta by Controlled Cord Traction (CCT) (Station 27)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '4c395db2-afcf-5619-9bf6-42f50ede26b0', 'maternal-midwifery', 'Delivery of the Placenta by Controlled Cord Traction (CCT)', 'controlled-cord-traction-placenta',
  'Station 27', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery OSCE Station Examination',
  66, 66, 8, 4, 420,
  'Demonstrate Controlled Cord Traction (Brandt-Andrews technique) for delivery of the placenta on an obstetric mannequin. Observe signs of separation, countertraction, and membrane preservation.', 'Oxytocin 10 IU IM has been given. The uterus contracts firmly and signs of placental separation are noted. Demonstrate safe delivery of the placenta using controlled cord traction.', 'both',
  '["Obstetric delivery model with placenta and cord","Sterile artery forceps / Kocher clamp","Placenta receiver / basin","Sterile gloves"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('84b88a69-e136-5b48-befa-d2e8bc675a71', '4c395db2-afcf-5619-9bf6-42f50ede26b0', 1, true, 8)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a61f24f2-0bfb-5e05-b01e-b807996c5a48', '84b88a69-e136-5b48-befa-d2e8bc675a71', 1, 'Preparation & Equipment', 'Greet examiner, introduce self, verify that uterotonic has been administered and uterus is contracted',
  0.5, false, 'both',
  '["greet examiner","introduce self","confirm uterotonic given","uterus contracted"]'::jsonb, 'Greet examiner, introduce self, verify that uterotonic has been administered and uterus is contracted'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '50c8eca4-6171-5d5e-a27f-d7381c5594e0', '84b88a69-e136-5b48-befa-d2e8bc675a71', 2, 'Procedure Execution', 'Observe for signs of placental separation: Gush of blood, lengthening of the umbilical cord, uterus rises in abdomen and becomes globoid and firm',
  1, false, 'both',
  '["signs of placental separation","cord lengthening","gush of blood","globoid firm uterus"]'::jsonb, 'Observe for signs of placental separation: Gush of blood, lengthening of the umbilical cord, uterus rises in abdomen and becomes globoid and firm'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8311c459-aecb-5366-a52e-992d4b8873b4', '84b88a69-e136-5b48-befa-d2e8bc675a71', 3, 'Procedure Execution', 'Move clamp along the cord to within 2 to 3 cm of the perineum to ensure firm grip and control',
  0.5, false, 'both',
  '["clamp 2 to 3 cm from perineum","move clamp close to vulva"]'::jsonb, 'Move clamp along the cord to within 2 to 3 cm of the perineum to ensure firm grip and control'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4eb8a87f-f7ee-59ee-b120-150a5e9818bd', '84b88a69-e136-5b48-befa-d2e8bc675a71', 4, 'Procedure Execution', 'Place the cupped palm of the non-dominant hand on the lower abdomen just above the pubic bone to stabilize and push the uterus upward (counter-traction)',
  1.5, true, 'both',
  '["hand above pubic bone","suprapubic counter traction","push uterus upward","prevent uterine inversion"]'::jsonb, 'Place the cupped palm of the non-dominant hand on the lower abdomen just above the pubic bone to stabilize and push the uterus upward (counter-traction)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1e65acb3-5dbe-5855-b75f-f8cec2b570ac', '84b88a69-e136-5b48-befa-d2e8bc675a71', 5, 'Procedure Execution', 'With dominant hand holding clamp, apply steady, gentle downward traction on the cord during a uterine contraction, following the curve of the birth canal',
  1.5, true, 'both',
  '["gentle downward traction","during contraction","follow curve of carus","steady traction"]'::jsonb, 'With dominant hand holding clamp, apply steady, gentle downward traction on the cord during a uterine contraction, following the curve of the birth canal'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ca501a16-0084-5e3c-9ecf-dd3ec7fda88d', '84b88a69-e136-5b48-befa-d2e8bc675a71', 6, 'Procedure Execution', 'Never apply cord traction without counter-traction or when uterus is relaxed (prevents uterine inversion)',
  1, true, 'both',
  '["never pull without countertraction","prevent uterine inversion","safety rule"]'::jsonb, 'Never apply cord traction without counter-traction or when uterus is relaxed (prevents uterine inversion)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '147a5750-87c9-5ba9-a090-838a0b1d433e', '84b88a69-e136-5b48-befa-d2e8bc675a71', 7, 'Procedure Execution', 'As the placenta delivers through the introitus, support and catch it with both hands; gently twist and rotate to roll membranes into a rope so they separate intact',
  1.25, true, 'both',
  '["catch placenta with both hands","twist and rotate","roll membranes into rope","complete membranes"]'::jsonb, 'As the placenta delivers through the introitus, support and catch it with both hands; gently twist and rotate to roll membranes into a rope so they separate intact'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '48306e00-ffeb-537c-9d4d-4b8d05e17bf5', '84b88a69-e136-5b48-befa-d2e8bc675a71', 8, 'Post-Procedure & Documentation', 'Immediately massage the fundus until hard; place placenta in receiver for examination; wash hands and document time and method of delivery',
  0.75, false, 'both',
  '["fundal massage immediately","place in receiver","wash hands","document delivery"]'::jsonb, 'Immediately massage the fundus until hard; place placenta in receiver for examination; wash hands and document time and method of delivery'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Health Education on Modern Family Planning Methods (Station 15)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '5bf5a99f-e500-50d4-9af1-981ac85faf01', 'health-education', 'Health Education on Modern Family Planning Methods', 'health-education-family-planning',
  'Station 15', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Professional Examination for Midwives - September 2019',
  67, 67, 7.5, 3.75, 420,
  'Provide comprehensive counseling on modern contraceptive methods to a client using the REDI / GATHER counseling framework. Cover hormonal, barrier, IUD, and permanent methods.', 'A 28-year-old Para 2 woman attends the family planning clinic 6 weeks postpartum. Provide structured counseling on modern contraceptive choices, helping her make an informed voluntary choice.', 'oral',
  '["Contraceptive samples tray (Pills, Injectable Depo, Norplant/Implanon model, Copper IUD, Male/Female Condoms)","Counseling flipchart","Pelvic model"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('cf378bfc-d1c1-5450-abaf-2f146e82a67b', '5bf5a99f-e500-50d4-9af1-981ac85faf01', 1, true, 9)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b0521826-d93a-566b-b88e-2010d4ba6a59', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 1, 'Preparation & Equipment', 'Greet client warmly, introduce self, assure confidentiality, establish rapport, and ask about her reproductive goals',
  0.5, false, 'oral',
  '["greet client","introduce self","assure confidentiality","gather framework","reproductive goals"]'::jsonb, 'Greet client warmly, introduce self, assure confidentiality, establish rapport, and ask about her reproductive goals'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5c1480f8-0f72-55d7-a97e-7905f408933c', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 2, 'Procedure Execution', 'Classify modern contraceptive methods: Barrier methods, Hormonal methods, Intrauterine devices, Permanent surgical methods, and Natural / FAB methods',
  0.75, false, 'oral',
  '["classify family planning","barrier hormonal iud permanent","modern contraceptive methods"]'::jsonb, 'Classify modern contraceptive methods: Barrier methods, Hormonal methods, Intrauterine devices, Permanent surgical methods, and Natural / FAB methods'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ef6f2502-2daf-5b49-9cca-ff4de554348b', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 3, 'Procedure Execution', 'Explain Barrier Methods: Male and female condoms; dual protection against unintended pregnancy and Sexually Transmitted Infections including HIV',
  1, true, 'oral',
  '["condoms male and female","dual protection against stis and hiv","barrier methods"]'::jsonb, 'Explain Barrier Methods: Male and female condoms; dual protection against unintended pregnancy and Sexually Transmitted Infections including HIV'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'b488d439-8240-5f74-a703-62e8b4ea1aa8', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 4, 'Procedure Execution', 'Explain Combined Oral Contraceptive Pills (COCs): Take one pill daily at the same time; inhibits ovulation; contraindicated in uncontrolled hypertension, smoking over 35, and breastfeeding under 6 weeks',
  1, false, 'oral',
  '["combined oral contraceptives","one pill daily same time","inhibits ovulation","contraindications in hypertension"]'::jsonb, 'Explain Combined Oral Contraceptive Pills (COCs): Take one pill daily at the same time; inhibits ovulation; contraindicated in uncontrolled hypertension, smoking over 35, and breastfeeding under 6 weeks'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'df1f86b9-59ce-5ad2-ad8f-f9ae55c6c693', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 5, 'Procedure Execution', 'Explain Progestin-Only Methods: POPs (Mini-pill), Injectables (DMPA / Depo-Provera given IM every 3 months), and Implants (Jadelle 5 yrs / Implanon 3 yrs); ideal for lactating mothers',
  1.25, true, 'oral',
  '["progestin only methods","depo provera every 3 months","implants jadelle implanon","safe in breastfeeding"]'::jsonb, 'Explain Progestin-Only Methods: POPs (Mini-pill), Injectables (DMPA / Depo-Provera given IM every 3 months), and Implants (Jadelle 5 yrs / Implanon 3 yrs); ideal for lactating mothers'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4ecc61a4-49a3-568f-a358-91f9be82a05e', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 6, 'Procedure Execution', 'Explain Intrauterine Contraceptive Device (Copper T380A): Inserted into uterine cavity; prevents fertilization; effective for 10-12 years; completely reversible',
  1, false, 'oral',
  '["copper t iud","effective for 10 to 12 years","non hormonal","rapid return to fertility"]'::jsonb, 'Explain Intrauterine Contraceptive Device (Copper T380A): Inserted into uterine cavity; prevents fertilization; effective for 10-12 years; completely reversible'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '132a4fc0-eade-5d55-b9b5-f184437bc2e3', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 7, 'Procedure Execution', 'Explain Permanent Surgical Methods: Bilateral Tubal Ligation (BTL) for women and Vasectomy for men; irreversible, suitable when family is complete',
  0.75, false, 'oral',
  '["permanent methods","bilateral tubal ligation","vasectomy","family size complete"]'::jsonb, 'Explain Permanent Surgical Methods: Bilateral Tubal Ligation (BTL) for women and Vasectomy for men; irreversible, suitable when family is complete'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '92fadd03-b83e-578f-92e9-7f237bc24a55', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 8, 'Procedure Execution', 'Explain Emergency Contraception: Levonorgestrel 1.5mg taken within 72-120 hours of unprotected intercourse; not an abortifacient, not for regular use',
  0.5, false, 'oral',
  '["emergency contraception","postinor levonorgestrel","within 72 hours","not for regular use"]'::jsonb, 'Explain Emergency Contraception: Levonorgestrel 1.5mg taken within 72-120 hours of unprotected intercourse; not an abortifacient, not for regular use'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8915e076-e23d-5201-8c32-1ec3af5f557d', 'cf378bfc-d1c1-5450-abaf-2f146e82a67b', 9, 'Post-Procedure & Documentation', 'Allow client to choose voluntarily based on her lifestyle; explain common side effects, provide appointment for initiation, and document in FP register',
  0.75, false, 'oral',
  '["informed voluntary choice","explain side effects","schedule follow up","document in register"]'::jsonb, 'Allow client to choose voluntarily based on her lifestyle; explain common side effects, provide appointment for initiation, and document in FP register'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Health Education on Uterine Fibroids (Leiomyoma) (Station 11)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'a03fad73-608a-5b59-a4fd-4d0e7e0b0a92', 'health-education', 'Health Education on Uterine Fibroids (Leiomyoma)', 'health-education-uterine-fibroids',
  'Station 11', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery Licensing Examination',
  68, 68, 8, 4, 420,
  'Counsel a woman diagnosed with uterine fibroids. Explain the nature of fibroids, anatomical types, symptoms, complications, diagnostic investigations, and treatment options.', 'A 34-year-old nulliparous woman has just been diagnosed with multiple uterine fibroids on pelvic ultrasound. She is anxious about surgery and infertility. Provide comprehensive health education.', 'oral',
  '["Uterine anatomical diagram showing fibroid locations","Patient counseling desk and chairs"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 'a03fad73-608a-5b59-a4fd-4d0e7e0b0a92', 1, true, 8)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9e27a517-00b3-50c6-9e87-4e1fa13c357a', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 1, 'Preparation & Equipment', 'Candidate greets examiner/client, introduces self, establishes empathetic rapport, and assesses client''s emotional state and concerns',
  0.5, false, 'oral',
  '["greet client","introduce self","empathetic rapport","assess concerns"]'::jsonb, 'Candidate greets examiner/client, introduces self, establishes empathetic rapport, and assesses client''s emotional state and concerns'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '49452492-88b6-56ac-a656-0163d1effd19', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 2, 'Procedure Execution', 'Define Uterine Fibroid: A benign (non-cancerous) monoclonal tumor of uterine smooth muscle (myometrium) and fibrous connective tissue; estrogen and progesterone dependent',
  0.75, false, 'oral',
  '["benign tumor of myometrium","non cancerous","estrogen dependent","smooth muscle tumor"]'::jsonb, 'Define Uterine Fibroid: A benign (non-cancerous) monoclonal tumor of uterine smooth muscle (myometrium) and fibrous connective tissue; estrogen and progesterone dependent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '07c3f897-176c-51c4-b470-9316d94b8a05', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 3, 'Procedure Execution', 'Describe Anatomical Classifications: 1. Submucosal (protrudes into uterine cavity, causes heavy bleeding/infertility); 2. Intramural (within muscle wall, most common); 3. Subserosal (on outer surface, causes bulk symptoms)',
  1.25, true, 'oral',
  '["submucosal cavity protruding","intramural in muscle wall","subserosal outer wall","pedunculated fibroid"]'::jsonb, 'Describe Anatomical Classifications: 1. Submucosal (protrudes into uterine cavity, causes heavy bleeding/infertility); 2. Intramural (within muscle wall, most common); 3. Subserosal (on outer surface, causes bulk symptoms)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7f12c2b0-8cab-5ce0-a6f2-4dbb334d4eee', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 4, 'Procedure Execution', 'Describe Clinical Manifestations: Heavy prolonged menstrual bleeding (menorrhagia), severe dysmenorrhea, pelvic fullness/pressure, urinary frequency (bladder compression), constipation, anemia',
  1.25, true, 'oral',
  '["menorrhagia heavy bleeding","dysmenorrhea","pelvic pressure","urinary frequency","iron deficiency anemia"]'::jsonb, 'Describe Clinical Manifestations: Heavy prolonged menstrual bleeding (menorrhagia), severe dysmenorrhea, pelvic fullness/pressure, urinary frequency (bladder compression), constipation, anemia'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'c51707b5-a08c-5fd7-a189-7c4cc31537a9', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 5, 'Procedure Execution', 'Explain Effects on Reproduction: Infertility, recurrent miscarriage, preterm labour, malpresentation, obstructed labour, red degeneration during pregnancy, postpartum haemorrhage (PPH)',
  1.25, true, 'oral',
  '["infertility","recurrent miscarriage","red degeneration","malpresentation","postpartum hemorrhage"]'::jsonb, 'Explain Effects on Reproduction: Infertility, recurrent miscarriage, preterm labour, malpresentation, obstructed labour, red degeneration during pregnancy, postpartum haemorrhage (PPH)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a71f5e5f-7430-51f3-ac22-4dd92e3a648e', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 6, 'Procedure Execution', 'Explain Diagnostic Investigations: Complete blood count (anemia), Transabdominal and transvaginal ultrasound scan (number, size, location of fibroids), MRI or hysteroscopy',
  0.75, false, 'oral',
  '["pelvic ultrasound scan","complete blood count for anemia","hysteroscopy or mri"]'::jsonb, 'Explain Diagnostic Investigations: Complete blood count (anemia), Transabdominal and transvaginal ultrasound scan (number, size, location of fibroids), MRI or hysteroscopy'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9a7fa308-a936-50eb-8809-04dd3f5c99e6', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 7, 'Procedure Execution', 'Explain Management Options: Medical (Tranexamic acid, GnRH analogues, iron supplements); Surgical: Myomectomy (preserves uterus for future childbearing) vs Hysterectomy; Uterine Artery Embolization',
  1.5, true, 'oral',
  '["myomectomy preserves fertility","hysterectomy when family complete","medical management gnrh","iron supplementation for anemia"]'::jsonb, 'Explain Management Options: Medical (Tranexamic acid, GnRH analogues, iron supplements); Surgical: Myomectomy (preserves uterus for future childbearing) vs Hysterectomy; Uterine Artery Embolization'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e31c1b60-d4c4-5e8d-9ff8-3bbb53aced55', '089a3c54-dce1-5e32-bfae-2bdc90ab1e89', 8, 'Post-Procedure & Documentation', 'Reassure client that fibroids rarely become cancerous (< 0.5%), answer questions, encourage adherence to follow-up, and document counseling',
  0.75, false, 'oral',
  '["rarely cancerous","reassure client","answer questions","document in clinic notes"]'::jsonb, 'Reassure client that fibroids rarely become cancerous (< 0.5%), answer questions, encourage adherence to follow-up, and document counseling'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Manual Vacuum Aspiration (MVA) for Incomplete Abortion (Station 3)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '3d719e01-b8c7-52be-ae4f-e29732a65eb9', 'reproductive-health', 'Manual Vacuum Aspiration (MVA) for Incomplete Abortion', 'manual-vacuum-aspiration-mva',
  'Station 3', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Post-Abortion Care (PAC) Practicum',
  69, 69, 10, 5, 480,
  'Demonstrate uterine evacuation using the Ipas double-valve Manual Vacuum Aspiration (MVA) apparatus on a pelvic simulator. Follow No-Touch technique, vacuum creation, cannula insertion, evacuation signs, and tissue inspection.', 'A client presents with an incomplete abortion at 9 weeks gestation with active bleeding. Resuscitation has commenced. Demonstrate uterine evacuation using MVA following standard PAC protocol.', 'both',
  '["Pelvic trainer / simulator with cervix","Ipas double-valve MVA aspirator (60ml)","Flexible Karman cannulae (sizes 6-10 mm)","Graves / Cusco speculum","Tenaculum / vulsellum forceps","Sponge-holding forceps","1% Lignocaine for paracervical block","Antiseptic solution (Betadine / Chlorhexidine)","Sterile gloves","Clear glass bowl with water and strainer for tissue inspection"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('8cd13ee6-caf4-581b-b6cf-058f393e4767', '3d719e01-b8c7-52be-ae4f-e29732a65eb9', 1, true, 12)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '670e14d0-7628-59fc-88f8-000aafc65363', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 1, 'Preparation & Equipment', 'Greet client, introduce self, confirm incomplete abortion (< 12 weeks), verify stable vitals, explain procedure and obtain informed consent',
  0.5, false, 'both',
  '["greet client","introduce self","confirm incomplete abortion","gain consent"]'::jsonb, 'Greet client, introduce self, confirm incomplete abortion (< 12 weeks), verify stable vitals, explain procedure and obtain informed consent'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'fa2c6b4a-ebae-57db-9034-950547f3d1c5', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 2, 'Preparation & Equipment', 'Assemble and inspect MVA aspirator: Check O-ring lubrication, ensure valves and plunger operate smoothly, and select correct cannula size (size matching weeks of gestation)',
  0.75, false, 'both',
  '["inspect mva aspirator","check o-ring","select cannula size matching gestation"]'::jsonb, 'Assemble and inspect MVA aspirator: Check O-ring lubrication, ensure valves and plunger operate smoothly, and select correct cannula size (size matching weeks of gestation)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '1cb33e2c-4a64-58ac-a629-9dd18de34eb4', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 3, 'Procedure Execution', 'Create Vacuum in Aspirator: Close both valve buttons until they click and lock; push plunger fully into barrel; pull plunger back until retaining tabs snap out to collar, locking vacuum (generates 24-26 inches Hg)',
  1, true, 'both',
  '["close valve buttons","pull plunger back to lock tabs","create 24 to 26 inches hg vacuum","vacuum locked"]'::jsonb, 'Create Vacuum in Aspirator: Close both valve buttons until they click and lock; push plunger fully into barrel; pull plunger back until retaining tabs snap out to collar, locking vacuum (generates 24-26 inches Hg)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '0f6adcb0-5350-5883-baae-166286e95724', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 4, 'Procedure Execution', 'Position client in lithotomy position, perform bimanual examination to assess uterine size and version (anteverted/retroverted), clean perineum and don sterile gloves',
  0.75, false, 'both',
  '["bimanual exam to confirm size and version","lithotomy position","aseptic perineal prep"]'::jsonb, 'Position client in lithotomy position, perform bimanual examination to assess uterine size and version (anteverted/retroverted), clean perineum and don sterile gloves'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd89aed5c-3e1a-5cc3-ad4b-2a454805572a', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 5, 'Procedure Execution', 'Insert speculum to expose cervix; perform antiseptic swab of cervix and vagina; perform paracervical block using 1% Lignocaine if indicated',
  0.75, false, 'both',
  '["expose cervix with speculum","antiseptic swab of cervix","paracervical block"]'::jsonb, 'Insert speculum to expose cervix; perform antiseptic swab of cervix and vagina; perform paracervical block using 1% Lignocaine if indicated'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '18d951ff-058a-5548-870a-f55dcefec8e4', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 6, 'Procedure Execution', 'Grasp anterior lip of cervix with tenaculum to stabilize and straighten the cervical canal',
  0.75, false, 'both',
  '["tenaculum on anterior lip","straighten cervical canal","gentle traction"]'::jsonb, 'Grasp anterior lip of cervix with tenaculum to stabilize and straighten the cervical canal'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '60135921-963d-55a4-b8ee-e69e0984e550', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 7, 'Procedure Execution', 'Insert Cannula with No-Touch Technique: Holding cannula by base without touching the tip, gently introduce through cervix into uterine cavity until fundus is touched, then withdraw 1 cm',
  1.25, true, 'both',
  '["no touch technique","introduce cannula gently","touch fundus then withdraw 1 cm","avoid touching cannula tip"]'::jsonb, 'Insert Cannula with No-Touch Technique: Holding cannula by base without touching the tip, gently introduce through cervix into uterine cavity until fundus is touched, then withdraw 1 cm'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a6ef7f16-980a-50bd-8fb3-f5573a4e8f18', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 8, 'Procedure Execution', 'Attach Aspirator and Evacuate: Connect primed aspirator to cannula base; release valve buttons to initiate vacuum; rotate cannula gently 180° in both directions while moving gently back and forth',
  1.25, true, 'both',
  '["attach aspirator","release valve buttons","rotate cannula 180 degrees","gentle back and forth strokes"]'::jsonb, 'Attach Aspirator and Evacuate: Connect primed aspirator to cannula base; release valve buttons to initiate vacuum; rotate cannula gently 180° in both directions while moving gently back and forth'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '243f16ee-0cb6-5f2f-b106-9941d0769831', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 9, 'Procedure Execution', 'Recognize Signs of Complete Evacuation: 1. Red/pink foam with no more tissue in cannula; 2. Gritty sensation against uterine wall; 3. Uterine cramping/gripping around cannula; 4. Uterus contracts firmly',
  1, true, 'both',
  '["signs of completion","red pink foam","gritty sensation against walls","uterus grips cannula","cervix contracts"]'::jsonb, 'Recognize Signs of Complete Evacuation: 1. Red/pink foam with no more tissue in cannula; 2. Gritty sensation against uterine wall; 3. Uterine cramping/gripping around cannula; 4. Uterus contracts firmly'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '50a9e6f5-c3fc-554e-b2ca-c38e84499c28', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 10, 'Procedure Execution', 'Depress valve buttons to release vacuum before withdrawing cannula; withdraw cannula and speculum',
  0.5, false, 'both',
  '["release vacuum before withdrawal","withdraw cannula smoothly"]'::jsonb, 'Depress valve buttons to release vacuum before withdrawing cannula; withdraw cannula and speculum'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '85a62907-3ca0-5462-a16a-16ef0adf29c6', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 11, 'Post-Procedure & Documentation', 'Inspect Evacuated Products of Conception: Empty contents into strainer, rinse with water, inspect in clear water against light to identify chorionic villi, fetal parts, and exclude molar tissue',
  1, true, 'both',
  '["inspect products of conception","float in water","identify chorionic villi","exclude complete molar pregnancy","ensure complete evacuation"]'::jsonb, 'Inspect Evacuated Products of Conception: Empty contents into strainer, rinse with water, inspect in clear water against light to identify chorionic villi, fetal parts, and exclude molar tissue'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a61e3ae4-a615-57dd-8298-bc3f3fab05d3', '8cd13ee6-caf4-581b-b6cf-058f393e4767', 12, 'Post-Procedure & Documentation', 'Decontaminate instruments in 0.5% chlorine solution; offer immediate post-abortion contraception; document procedure and blood loss',
  0.5, false, 'both',
  '["decontaminate in 0.5 percent chlorine","post abortion contraception","document in pac register"]'::jsonb, 'Decontaminate instruments in 0.5% chlorine solution; offer immediate post-abortion contraception; document procedure and blood loss'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Counseling on Birth Preparedness and Complication Readiness (BPCR) (Station 11)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '6fc73ae6-a311-597a-9d59-9396856bc804', 'health-education', 'Counseling on Birth Preparedness and Complication Readiness (BPCR)', 'birth-preparedness-complication-readiness',
  'Station 11', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery Licensing Examination',
  72, 72, 8, 4, 420,
  'Counsel an antenatal client and her partner on developing a comprehensive Birth Preparedness and Complication Readiness (BPCR) plan. Cover key components and obstetric danger signs.', 'A 24-year-old primigravida at 28 weeks gestation attends the antenatal clinic with her spouse. Develop an individualized birth and emergency preparedness plan.', 'oral',
  '["BPCR counseling flipchart / plan template","Antenatal card","Counseling desk and chairs"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('9f7eab0f-e738-5abd-840c-6b0054268e5b', '6fc73ae6-a311-597a-9d59-9396856bc804', 1, true, 9)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6e5fdef7-800f-55c6-a1ed-51cf4f0f05aa', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 1, 'Preparation & Equipment', 'Greet woman and partner, introduce self, explain concept and importance of BPCR in preventing the Three Delays in maternal mortality',
  0.75, false, 'oral',
  '["greet client and partner","introduce self","three delays in maternal mortality","importance of bpcr"]'::jsonb, 'Greet woman and partner, introduce self, explain concept and importance of BPCR in preventing the Three Delays in maternal mortality'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'cf02d385-6fdb-5fa4-b722-9fb13e9b306a', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 2, 'Procedure Execution', 'Plan 1 - Choice of Skilled Birth Attendant and Health Facility: Assist couple to choose an accredited health facility staffed by skilled midwives/doctors for delivery',
  1, true, 'oral',
  '["skilled birth attendant","accredited health facility","plan delivery location"]'::jsonb, 'Plan 1 - Choice of Skilled Birth Attendant and Health Facility: Assist couple to choose an accredited health facility staffed by skilled midwives/doctors for delivery'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'df1a07bc-e608-54d1-994c-7dc830cf3640', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 3, 'Procedure Execution', 'Plan 2 - Emergency Transport Arrangement: Identify reliable 24-hour transportation to the health facility (and designated driver/contact)',
  1, true, 'oral',
  '["emergency transport","24 hour vehicle arranged","designated driver contact"]'::jsonb, 'Plan 2 - Emergency Transport Arrangement: Identify reliable 24-hour transportation to the health facility (and designated driver/contact)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e0bd926b-c98b-582e-96b0-b5f0ca047325', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 4, 'Procedure Execution', 'Plan 3 - Emergency Financial Savings: Arrange dedicated savings / funds set aside for delivery fees, unexpected complications, and medication',
  1, false, 'oral',
  '["emergency funds","financial savings","money set aside for delivery"]'::jsonb, 'Plan 3 - Emergency Financial Savings: Arrange dedicated savings / funds set aside for delivery fees, unexpected complications, and medication'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '6fe6ad5c-b30c-5768-bcbd-6d479019f3a5', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 5, 'Procedure Execution', 'Plan 4 - Designated Blood Donor: Identify two compatible, healthy blood donors who agree to be on standby in case of postpartum haemorrhage',
  1, true, 'oral',
  '["designated blood donor","standby blood donors","screened compatible donors"]'::jsonb, 'Plan 4 - Designated Blood Donor: Identify two compatible, healthy blood donors who agree to be on standby in case of postpartum haemorrhage'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '89a6b3be-1dc2-52a7-b474-b9810809c3d0', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 6, 'Procedure Execution', 'Plan 5 - Designated Decision Maker: Designate a trusted family member empowered to make medical decisions if the woman or primary partner is unavailable',
  0.75, false, 'oral',
  '["designated decision maker","empowered to decide","avoid delay in seeking care"]'::jsonb, 'Plan 5 - Designated Decision Maker: Designate a trusted family member empowered to make medical decisions if the woman or primary partner is unavailable'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd7036133-baee-5b95-bf56-6cc42b42d174', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 7, 'Procedure Execution', 'Plan 6 - Essential Delivery Supplies (Clean Delivery Kit): Assemble baby clothes, clean towels, sanitary pads, chlorhexidine 7.1% for cord care, and maternal items',
  0.75, false, 'oral',
  '["mama kit","clean delivery kit","chlorhexidine for cord","baby clothing and pads"]'::jsonb, 'Plan 6 - Essential Delivery Supplies (Clean Delivery Kit): Assemble baby clothes, clean towels, sanitary pads, chlorhexidine 7.1% for cord care, and maternal items'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '7f195aee-5b74-5359-b262-2f81cfc24539', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 8, 'Procedure Execution', 'Teach Danger Signs in Pregnancy, Labour and Postpartum: Vaginal bleeding, severe headache/blurred vision (preeclampsia), convulsions, severe abdominal pain, high fever, foul lochia, reduced fetal movements',
  1.25, true, 'oral',
  '["danger signs","vaginal bleeding","severe headache blurred vision","convulsions","reduced fetal movements","fever"]'::jsonb, 'Teach Danger Signs in Pregnancy, Labour and Postpartum: Vaginal bleeding, severe headache/blurred vision (preeclampsia), convulsions, severe abdominal pain, high fever, foul lochia, reduced fetal movements'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'fc92939d-390d-5499-90d7-4a6cb40aaa9f', '9f7eab0f-e738-5abd-840c-6b0054268e5b', 9, 'Post-Procedure & Documentation', 'Summarize plan, write down emergency phone numbers on antenatal card, encourage birth companion involvement, and document in maternal record',
  0.5, false, 'oral',
  '["record on antenatal card","emergency phone numbers","document in record","encourage partner support"]'::jsonb, 'Summarize plan, write down emergency phone numbers on antenatal card, encourage birth companion involvement, and document in maternal record'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Umbilical Cord Dressing and Omphalitis Prevention (Station 3)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'b0240092-1f69-5a85-aab2-8d407afa6af2', 'neonatal-pediatric', 'Umbilical Cord Dressing and Omphalitis Prevention', 'newborn-cord-dressing-care',
  'Station 3', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery Practical Examination',
  74, 74, 8, 4, 360,
  'Demonstrate proper umbilical cord care and dressing on a newborn mannequin according to national guidelines (application of 7.1% Chlorhexidine digluconate gel). Explain omphalitis prevention.', 'You are caring for a 12-hour-old newborn on the postnatal ward. Demonstrate proper umbilical cord care using 7.1% Chlorhexidine gel and teach the mother how to prevent neonatal sepsis.', 'both',
  '["Newborn mannequin with umbilical cord stump","7.1% Chlorhexidine digluconate gel / solution","Sterile cotton wool balls / gauze","Clean water / normal saline","Clean examination gloves","Diaper / nappy"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 'b0240092-1f69-5a85-aab2-8d407afa6af2', 1, true, 9)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '196c0a28-5585-5cfe-bd19-380ea897bca8', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 1, 'Preparation & Equipment', 'Greet mother, introduce self, explain procedure, and explain rationale: prevent bacterial infection (omphalitis) and neonatal tetanus',
  0.5, false, 'both',
  '["greet mother","introduce self","prevent omphalitis","neonatal tetanus"]'::jsonb, 'Greet mother, introduce self, explain procedure, and explain rationale: prevent bacterial infection (omphalitis) and neonatal tetanus'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a247ae50-f219-5caf-8f1a-3729643fa92d', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 2, 'Preparation & Equipment', 'Wash hands thoroughly with soap and water, dry with clean towel, and assemble clean equipment on tray',
  0.5, false, 'both',
  '["wash hands with soap","dry hands","assemble equipment"]'::jsonb, 'Wash hands thoroughly with soap and water, dry with clean towel, and assemble clean equipment on tray'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f0efc450-ba93-5ed4-a2b4-fbde3ed3fe4a', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 3, 'Preparation & Equipment', 'Position infant comfortably on back; expose abdominal area while keeping rest of infant warm and draft-free',
  0.5, false, 'both',
  '["position infant on back","expose abdomen only","keep baby warm"]'::jsonb, 'Position infant comfortably on back; expose abdominal area while keeping rest of infant warm and draft-free'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '998126fe-7146-54d8-b634-2373d5c54e3a', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 4, 'Procedure Execution', 'Inspect umbilical cord stump: Check for bleeding, foul odor, redness/swelling around umbilical base, purulent discharge, or delayed separation',
  1, true, 'both',
  '["inspect cord stump","check for bleeding","signs of omphalitis","redness or foul odor"]'::jsonb, 'Inspect umbilical cord stump: Check for bleeding, foul odor, redness/swelling around umbilical base, purulent discharge, or delayed separation'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8c7d27dc-3e0d-55b1-bc03-72ab76199259', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 5, 'Procedure Execution', 'If cord is soiled with stool/urine, clean gently using cotton ball moistened with clean water from base to tip in a single circular motion; pat dry',
  1, false, 'both',
  '["clean with clean water if soiled","from base to tip","pat dry","single stroke"]'::jsonb, 'If cord is soiled with stool/urine, clean gently using cotton ball moistened with clean water from base to tip in a single circular motion; pat dry'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9a0c4ff6-0a1a-5702-8cb0-e7aa11480bd7', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 6, 'Procedure Execution', 'Apply 7.1% Chlorhexidine digluconate gel (delivering 4% chlorhexidine): Apply clean dollop of gel to cord stump, cord cut tip, and 2.5 cm radius around umbilical base',
  1.75, true, 'both',
  '["apply 7.1 percent chlorhexidine gel","apply to cord tip and stump","apply around umbilical base","daily chlorhexidine application"]'::jsonb, 'Apply 7.1% Chlorhexidine digluconate gel (delivering 4% chlorhexidine): Apply clean dollop of gel to cord stump, cord cut tip, and 2.5 cm radius around umbilical base'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '658e2571-7b92-5180-b39b-202c56495988', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 7, 'Procedure Execution', 'Leave cord uncovered and exposed to air; do not apply bandages, binders, cow dung, charcoal, sand, or traditional concoctions',
  1, true, 'both',
  '["leave uncovered to air","no binders or bandages","prohibit cow dung or charcoal","dry cord care"]'::jsonb, 'Leave cord uncovered and exposed to air; do not apply bandages, binders, cow dung, charcoal, sand, or traditional concoctions'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9006504f-043d-5ce3-9a17-800ec28fe8ce', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 8, 'Procedure Execution', 'Fold nappy / diaper down below the level of the umbilical stump to prevent contamination with urine or feces and allow air drying',
  0.75, false, 'both',
  '["fold diaper below cord","keep diaper away from stump","prevent urine contamination"]'::jsonb, 'Fold nappy / diaper down below the level of the umbilical stump to prevent contamination with urine or feces and allow air drying'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2eba41ae-2d93-5310-b6e7-44c914494708', '9b0e45e8-94c7-541a-b4d7-2a71629a0c03', 9, 'Post-Procedure & Documentation', 'Teach mother danger signs of cord infection: Pus, redness spreading to abdominal wall, fever, lethargy, poor feeding, foul odor; wash hands and document care',
  1, true, 'both',
  '["teach mother danger signs","redness spreading to skin","poor feeding lethargy","wash hands","document cord care"]'::jsonb, 'Teach mother danger signs of cord infection: Pus, redness spreading to abdominal wall, fever, lethargy, poor feeding, foul odor; wash hands and document care'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Artificial Rupture of Membranes (ARM / Amniotomy) (Station 7)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'e33cea36-ca9b-5dfd-981f-71e8be715f0f', 'maternal-midwifery', 'Artificial Rupture of Membranes (ARM / Amniotomy)', 'artificial-rupture-of-membranes',
  'Station 7', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery OSCE Station Examination',
  76, 76, 8, 4, 420,
  'Demonstrate Artificial Rupture of Membranes (ARM) on an obstetric delivery model. Explain indications, prerequisites, procedure with an amnihook, liquor assessment, and post-procedure monitoring.', 'A multigravida in active labour at 5 cm cervical dilatation has sluggish contractions. The fetal head is well engaged (station 0). An ARM is indicated to augment labour. Demonstrate the procedure.', 'both',
  '["Obstetric mannequin with dilating cervix and amniotic sac","Sterile Amnihook / Amnicot","Sterile gloves","Antiseptic solution and gauze swabs","Pinard stethoscope / CTG monitor","Sanitary pad and receiver"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('9956729f-581c-5054-bc54-aec7fa8bfa72', 'e33cea36-ca9b-5dfd-981f-71e8be715f0f', 1, true, 10)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4a932a10-b4b8-566a-a3ed-d0bd714015a6', '9956729f-581c-5054-bc54-aec7fa8bfa72', 1, 'Preparation & Equipment', 'State indications: Augment sluggish labour, induce labour (with oxytocin), attach scalp electrode, or inspect liquor for meconium; state prerequisites: head engaged, no cord presentation',
  1, true, 'both',
  '["indications for arm","augment labour","prerequisites head engaged","exclude cord prolapse"]'::jsonb, 'State indications: Augment sluggish labour, induce labour (with oxytocin), attach scalp electrode, or inspect liquor for meconium; state prerequisites: head engaged, no cord presentation'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'fd89f251-a32a-572e-8c46-5535a96e69bc', '9956729f-581c-5054-bc54-aec7fa8bfa72', 2, 'Preparation & Equipment', 'Explain procedure to woman, obtain informed consent, ensure bladder is empty, provide privacy, and auscultate baseline Fetal Heart Rate',
  0.75, false, 'both',
  '["explain to woman","informed consent","empty bladder","baseline fetal heart rate"]'::jsonb, 'Explain procedure to woman, obtain informed consent, ensure bladder is empty, provide privacy, and auscultate baseline Fetal Heart Rate'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '80acdd6d-c722-5cd6-9f9b-5e259ba5f5b1', '9956729f-581c-5054-bc54-aec7fa8bfa72', 3, 'Preparation & Equipment', 'Wash hands, clean perineum with antiseptic lotion, and don sterile examination gloves using aseptic technique',
  0.5, false, 'both',
  '["wash hands","clean perineum","sterile gloves"]'::jsonb, 'Wash hands, clean perineum with antiseptic lotion, and don sterile examination gloves using aseptic technique'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '4ed4dd6f-f5a7-5dd7-80ec-4a4d4ce459d9', '9956729f-581c-5054-bc54-aec7fa8bfa72', 4, 'Procedure Execution', 'Perform vaginal examination: Verify cervical dilatation, confirm presentation (vertex), assess station (must be at or below ischial spines), and exclude cord presentation / vasa previa',
  1, true, 'both',
  '["verify station at ischial spines","confirm vertex","rule out cord presentation","cervical dilatation"]'::jsonb, 'Perform vaginal examination: Verify cervical dilatation, confirm presentation (vertex), assess station (must be at or below ischial spines), and exclude cord presentation / vasa previa'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2bb9cc35-56d1-5fe7-983a-f81e333e58ab', '9956729f-581c-5054-bc54-aec7fa8bfa72', 5, 'Procedure Execution', 'Insert two fingers of dominant hand into vagina with tips touching the bulging forewaters; guide the sterile Amnihook along the groove between fingers with hook facing away from maternal tissues',
  1, true, 'both',
  '["guide amnihook along fingers","hook protected by fingers","touch bulging forewaters","protect maternal vagina"]'::jsonb, 'Insert two fingers of dominant hand into vagina with tips touching the bulging forewaters; guide the sterile Amnihook along the groove between fingers with hook facing away from maternal tissues'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a56f7e96-35c6-5712-ab54-a14cfc4f1330', '9956729f-581c-5054-bc54-aec7fa8bfa72', 6, 'Procedure Execution', 'Rupture membranes: During a contraction (or between contractions if high tension), snag and puncture the membranes with the hook point; keep examining fingers in place as liquor drains slowly',
  1, true, 'both',
  '["snag membranes with hook","puncture forewaters","slow controlled liquor release","keep fingers in place to prevent cord rush"]'::jsonb, 'Rupture membranes: During a contraction (or between contractions if high tension), snag and puncture the membranes with the hook point; keep examining fingers in place as liquor drains slowly'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f5e386ea-6254-5e10-8d77-8d334b482015', '9956729f-581c-5054-bc54-aec7fa8bfa72', 7, 'Procedure Execution', 'Assess Liquor: Note color (clear, meconium-stained grade 1/2/3, blood-stained, or foul smelling) and quantity',
  1, true, 'both',
  '["assess liquor color","clear vs meconium stained","grade of meconium","liquor volume"]'::jsonb, 'Assess Liquor: Note color (clear, meconium-stained grade 1/2/3, blood-stained, or foul smelling) and quantity'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd507393c-5985-5697-9bab-2afc9f5e4346', '9956729f-581c-5054-bc54-aec7fa8bfa72', 8, 'Procedure Execution', 'Withdraw amnihook and examining fingers while confirming fetal head remains applied against cervix and excluding cord prolapse',
  0.75, true, 'both',
  '["rule out cord prolapse after arm","fetal head applied to cervix","withdraw hook safely"]'::jsonb, 'Withdraw amnihook and examining fingers while confirming fetal head remains applied against cervix and excluding cord prolapse'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '935c5228-0d95-5d5b-8c2c-7df6d905bc96', '9956729f-581c-5054-bc54-aec7fa8bfa72', 9, 'Post-Procedure & Documentation', 'Immediately auscultate Fetal Heart Rate for 1 full minute following ARM to rule out cord compression or bradycardia',
  0.5, true, 'both',
  '["auscultate fhr immediately","check for fetal bradycardia","rule out cord compression"]'::jsonb, 'Immediately auscultate Fetal Heart Rate for 1 full minute following ARM to rule out cord compression or bradycardia'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ed1d5fd1-6d2d-528a-a44b-59d1c9b05185', '9956729f-581c-5054-bc54-aec7fa8bfa72', 10, 'Post-Procedure & Documentation', 'Clean and dry woman, apply clean pad, wash hands, and document time of ARM, liquor characteristics, FHR, and cervical findings in partograph',
  0.5, false, 'both',
  '["apply clean pad","wash hands","document in partograph","time of arm recorded"]'::jsonb, 'Clean and dry woman, apply clean pad, wash hands, and document time of ARM, liquor characteristics, FHR, and cervical findings in partograph'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Manual Removal of Retained Placenta (MROP) (Station 13)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  'f4bc9438-9a32-5791-88ab-d44cf20d17c2', 'maternal-midwifery', 'Manual Removal of Retained Placenta (MROP)', 'manual-removal-retained-placenta',
  'Station 13', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery Emergency Licensing Examination',
  82, 82, 8, 4, 480,
  'Demonstrate Manual Removal of the Placenta on an obstetric simulator. Explain pre-procedure requirements (consent, IV access, anesthesia, bladder catheterization), separation technique, and post-procedure care.', 'A patient who delivered 45 minutes ago has a retained placenta despite active management and controlled cord traction. Bleeding is starting to increase. Demonstrate manual removal of the placenta.', 'both',
  '["Obstetric mannequin with retained placenta","Long sterile elbow-length gauntlet gloves","Antiseptic solution (Betadine/Savlon)","Foley catheter and bag","Two wide-bore IV lines with normal saline","Prophylactic IV antibiotic (Ampicillin 2g / Cefazolin)","Uterotonic infusion"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('c40e90bc-a88d-5abc-80c0-3b272702c224', 'f4bc9438-9a32-5791-88ab-d44cf20d17c2', 1, true, 10)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '9b382f9f-def0-5b71-b092-139e1c8e86f9', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 1, 'Preparation & Equipment', 'Recognize retained placenta (> 30 min post delivery), explain urgency to mother and partner, obtain informed consent, and notify theater/anesthetist',
  0.5, false, 'both',
  '["retained placenta definition","explain to mother","informed consent","call team"]'::jsonb, 'Recognize retained placenta (> 30 min post delivery), explain urgency to mother and partner, obtain informed consent, and notify theater/anesthetist'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '16e042ee-2844-5402-8048-c62ca04e577b', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 2, 'Preparation & Equipment', 'Ensure adequate intravenous access (two wide-bore 16G/18G lines), commence IV fluid resuscitation, and administer IV prophylactic antibiotics',
  0.75, false, 'both',
  '["two wide bore iv lines","iv fluid resuscitation","prophylactic antibiotics"]'::jsonb, 'Ensure adequate intravenous access (two wide-bore 16G/18G lines), commence IV fluid resuscitation, and administer IV prophylactic antibiotics'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2bb75514-ae09-5e29-8098-ddbdcc6c8d44', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 3, 'Preparation & Equipment', 'Catheterize bladder with Foley catheter to ensure bladder is completely empty (empty bladder allows proper uterine access)',
  0.5, true, 'both',
  '["catheterize bladder","foley catheter","empty bladder completely"]'::jsonb, 'Catheterize bladder with Foley catheter to ensure bladder is completely empty (empty bladder allows proper uterine access)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '34810432-6e99-5740-b559-f532b2e2b05f', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 4, 'Procedure Execution', 'Don sterile elbow-length gloves; wash vulva and vagina with antiseptic solution; administer adequate anesthesia / analgesia (sedation or spinal)',
  0.75, false, 'both',
  '["sterile elbow length gloves","antiseptic vaginal wash","adequate analgesia anesthesia"]'::jsonb, 'Don sterile elbow-length gloves; wash vulva and vagina with antiseptic solution; administer adequate anesthesia / analgesia (sedation or spinal)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '477e0d86-16bf-5dfb-bd0b-926176aeb586', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 5, 'Procedure Execution', 'Insert hand into vagina: Form a cone shape with dominant gloved hand; insert through vagina and dilated cervix, guided along the umbilical cord into the uterine cavity',
  1, true, 'both',
  '["cone shaped hand","follow umbilical cord","enter uterine cavity through cervix","hand inside uterus"]'::jsonb, 'Insert hand into vagina: Form a cone shape with dominant gloved hand; insert through vagina and dilated cervix, guided along the umbilical cord into the uterine cavity'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'a89433b0-9209-58f4-929d-79352aa555dd', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 6, 'Procedure Execution', 'Stabilize Fundus: Place non-dominant hand firmly on maternal abdominal wall over the fundus of the uterus, holding fundus down against internal hand',
  1, true, 'both',
  '["support fundus with external hand","abdominal hand holds fundus","prevents uterine rupture","counter pressure"]'::jsonb, 'Stabilize Fundus: Place non-dominant hand firmly on maternal abdominal wall over the fundus of the uterus, holding fundus down against internal hand'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2c518ba6-2017-544c-b94e-3d551176722e', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 7, 'Procedure Execution', 'Locate and Separate Placental Edge: Locate cleavage plane between placenta and uterine wall; insert fingers with hand kept flat; use gentle sawing / slicing motion with ulnar border of hand to shear placenta off wall',
  1.25, true, 'both',
  '["locate cleavage plane","ulnar border of hand","sawing slicing motion","shear placenta off uterine wall","do not pull with fingertips"]'::jsonb, 'Locate and Separate Placental Edge: Locate cleavage plane between placenta and uterine wall; insert fingers with hand kept flat; use gentle sawing / slicing motion with ulnar border of hand to shear placenta off wall'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '8a58986c-06cb-5572-8d2e-bf28f7c07c22', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 8, 'Procedure Execution', 'When placenta is completely detached, grasp whole placenta in internal hand and withdraw hand slowly from uterine cavity into vagina, while external hand rubs up fundal contraction',
  1, true, 'both',
  '["whole placenta detached","withdraw slowly with placenta","rub up contraction externally"]'::jsonb, 'When placenta is completely detached, grasp whole placenta in internal hand and withdraw hand slowly from uterine cavity into vagina, while external hand rubs up fundal contraction'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'd1e7f62c-a11a-55d4-8b98-0bda4057e43d', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 9, 'Procedure Execution', 'Re-enter uterus once to palpate uterine cavity smoothly to confirm no retained cotyledons, succenturiate lobes, or uterine rupture',
  0.75, true, 'both',
  '["explore cavity for remnants","confirm complete removal","check for uterine rupture"]'::jsonb, 'Re-enter uterus once to palpate uterine cavity smoothly to confirm no retained cotyledons, succenturiate lobes, or uterine rupture'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'e47cb156-3c60-5903-9aa0-f50d68412d3c', 'c40e90bc-a88d-5abc-80c0-3b272702c224', 10, 'Post-Procedure & Documentation', 'Commence Oxytocin infusion (20-40 IU in 1L saline at 60 drops/min), inspect placenta for completeness, monitor lochia and vital signs, document procedure and blood loss',
  0.5, false, 'both',
  '["oxytocin infusion","inspect placenta cotyledons","monitor vitals","document mrop in delivery notes"]'::jsonb, 'Commence Oxytocin infusion (20-40 IU in 1L saline at 60 drops/min), inspect placenta for completeness, monitor lochia and vital signs, document procedure and blood loss'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;

-- Procedure: Health Education on Common Minor Disorders of Pregnancy and Management (Station 25)
INSERT INTO public.osce_procedures (
  id, category_id, title, slug, station_number, examining_body, session_label,
  page_start, page_end, total_marks, pass_mark, time_limit_seconds,
  instructions, scenario_prompt, assessment_mode, equipment_list, is_published
) VALUES (
  '9d343173-d68b-580c-b8f7-05a2fd746649', 'health-education', 'Health Education on Common Minor Disorders of Pregnancy and Management', 'minor-disorders-of-pregnancy',
  'Station 25', 'Nursing & Midwifery Council of Nigeria (NMCN)', 'Midwifery Licensing Examination',
  84, 84, 8, 4, 420,
  'Counsel an antenatal client experiencing common minor discomforts of pregnancy. Explain causes and non-pharmacological and pharmacological management of morning sickness, heartburn, constipation, backache, and varicose veins.', 'A 22-year-old primigravida at 14 weeks gestation complains of distressing morning sickness, heartburn, and constipation. Deliver structured reassuring counseling on managing these common discomforts.', 'oral',
  '["Antenatal educational flipchart","Dietary samples list","Counseling table and chairs"]'::jsonb, true
) ON CONFLICT (id) DO UPDATE SET
  category_id = EXCLUDED.category_id,
  title = EXCLUDED.title,
  slug = EXCLUDED.slug,
  station_number = EXCLUDED.station_number,
  examining_body = EXCLUDED.examining_body,
  session_label = EXCLUDED.session_label,
  page_start = EXCLUDED.page_start,
  page_end = EXCLUDED.page_end,
  total_marks = EXCLUDED.total_marks,
  pass_mark = EXCLUDED.pass_mark,
  time_limit_seconds = EXCLUDED.time_limit_seconds,
  instructions = EXCLUDED.instructions,
  scenario_prompt = EXCLUDED.scenario_prompt,
  assessment_mode = EXCLUDED.assessment_mode,
  equipment_list = EXCLUDED.equipment_list,
  is_published = EXCLUDED.is_published;

INSERT INTO public.osce_checklists (id, procedure_id, version, is_active, total_items)
VALUES ('eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', '9d343173-d68b-580c-b8f7-05a2fd746649', 1, true, 9)
ON CONFLICT (procedure_id, version) DO UPDATE SET
  is_active = EXCLUDED.is_active,
  total_items = EXCLUDED.total_items;

INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '78afff4f-c500-51f2-95b6-0ee42acc8bae', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 1, 'Preparation & Equipment', 'Greet client warmly, introduce self, establish rapport, explain that minor disorders are common physiological adaptations, and reassure her',
  0.75, false, 'oral',
  '["greet client","introduce self","reassure mother","physiological adaptations"]'::jsonb, 'Greet client warmly, introduce self, establish rapport, explain that minor disorders are common physiological adaptations, and reassure her'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '5124b481-00a8-5ac7-bc58-40b4d5e05435', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 2, 'Procedure Execution', 'Morning Sickness (Nausea & Vomiting) - Cause: Rising hCG and estrogen levels, altered carbohydrate metabolism; peak at 8-12 weeks',
  0.5, false, 'oral',
  '["morning sickness causes","hcg and estrogen","peaks at 8 to 12 weeks"]'::jsonb, 'Morning Sickness (Nausea & Vomiting) - Cause: Rising hCG and estrogen levels, altered carbohydrate metabolism; peak at 8-12 weeks'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'f4860892-2249-546d-9e7e-5d00417642ca', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 3, 'Procedure Execution', 'Morning Sickness - Management: Eat small, frequent bland meals (dry toast, crackers before rising from bed), avoid spicy/greasy foods, drink fluids between meals, ginger tea, Vitamin B6 (pyridoxine)',
  1.25, true, 'oral',
  '["dry crackers before getting up","small frequent meals","avoid greasy spicy foods","ginger and vitamin b6"]'::jsonb, 'Morning Sickness - Management: Eat small, frequent bland meals (dry toast, crackers before rising from bed), avoid spicy/greasy foods, drink fluids between meals, ginger tea, Vitamin B6 (pyridoxine)'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'aa871c22-4a85-51a8-9e54-ef6bfdcd4bdf', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 4, 'Procedure Execution', 'Heartburn (Pyrosis) - Cause: Progesterone relaxes lower esophageal sphincter, coupled with upward displacement of stomach by gravid uterus',
  0.5, false, 'oral',
  '["heartburn causes","progesterone relaxes sphincter","stomach displacement"]'::jsonb, 'Heartburn (Pyrosis) - Cause: Progesterone relaxes lower esophageal sphincter, coupled with upward displacement of stomach by gravid uterus'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '49d83633-0de9-550a-9d62-febba4ea0424', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 5, 'Procedure Execution', 'Heartburn - Management: Eat small frequent meals, avoid lying down immediately after meals (wait 2 hours), sleep with head elevated on pillows, avoid fatty/acidic foods, use antacids if prescribed',
  1.25, true, 'oral',
  '["avoid lying down after meals","elevate head with pillows","avoid fatty acidic foods","antacids after meals"]'::jsonb, 'Heartburn - Management: Eat small frequent meals, avoid lying down immediately after meals (wait 2 hours), sleep with head elevated on pillows, avoid fatty/acidic foods, use antacids if prescribed'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '11719d20-b46e-539b-ad81-e09009499c54', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 6, 'Procedure Execution', 'Constipation - Cause: Progesterone slows gastrointestinal motility, increased water reabsorption in colon, oral iron supplementation, pressure of uterus on rectum',
  0.5, false, 'oral',
  '["constipation causes","progesterone reduces peristalsis","iron supplements"]'::jsonb, 'Constipation - Cause: Progesterone slows gastrointestinal motility, increased water reabsorption in colon, oral iron supplementation, pressure of uterus on rectum'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  '2a89d956-109e-5553-9501-70c7aa3c5e4f', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 7, 'Procedure Execution', 'Constipation - Management: Increase dietary fiber (whole grains, vegetables, fruits, beans), drink 2.5-3 liters of water daily, gentle regular exercise (walking), avoid straining; stool softeners if needed',
  1.25, true, 'oral',
  '["high fiber diet","drink 2.5 to 3 liters of water","regular walking","avoid straining"]'::jsonb, 'Constipation - Management: Increase dietary fiber (whole grains, vegetables, fruits, beans), drink 2.5-3 liters of water daily, gentle regular exercise (walking), avoid straining; stool softeners if needed'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'ff7fa393-21f5-5e27-8863-9970099b731c', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 8, 'Procedure Execution', 'Backache and Varicose Veins - Management: Good posture, low-heeled shoes, pelvic tilt exercises, supportive maternity belt, avoid prolonged standing, elevate legs when sitting, wear compression stockings',
  1.25, false, 'oral',
  '["low heeled shoes","pelvic tilt exercises","elevate legs","avoid prolonged standing","supportive stockings"]'::jsonb, 'Backache and Varicose Veins - Management: Good posture, low-heeled shoes, pelvic tilt exercises, supportive maternity belt, avoid prolonged standing, elevate legs when sitting, wear compression stockings'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;
INSERT INTO public.osce_checklist_items (
  id, checklist_id, step_order, section, description, allocated_marks,
  is_critical, assessment_mode, clinical_synonyms, verification_criteria
) VALUES (
  'db546901-88f5-55eb-b0fc-2afc2590f850', 'eee1cf85-bc3b-57d0-8f53-c8bd8973d56b', 9, 'Post-Procedure & Documentation', 'Differentiate minor disorders from red flag danger signs (hyperemesis gravidarum with ketonuria, severe epigastric pain of preeclampsia); answer questions and document counseling',
  0.75, true, 'oral',
  '["differentiate danger signs","hyperemesis gravidarum","epigastric pain of preeclampsia","document in record"]'::jsonb, 'Differentiate minor disorders from red flag danger signs (hyperemesis gravidarum with ketonuria, severe epigastric pain of preeclampsia); answer questions and document counseling'
) ON CONFLICT (checklist_id, step_order) DO UPDATE SET
  section = EXCLUDED.section,
  description = EXCLUDED.description,
  allocated_marks = EXCLUDED.allocated_marks,
  is_critical = EXCLUDED.is_critical,
  assessment_mode = EXCLUDED.assessment_mode,
  clinical_synonyms = EXCLUDED.clinical_synonyms,
  verification_criteria = EXCLUDED.verification_criteria;


-- ============================================================================
-- VERIFICATION QUERY
-- Displays the populated row counts in the Supabase SQL Editor results grid
-- ============================================================================
SELECT 'osce_categories' AS table_name, count(*) AS total_rows FROM public.osce_categories
UNION ALL
SELECT 'osce_procedures', count(*) FROM public.osce_procedures
UNION ALL
SELECT 'osce_checklists', count(*) FROM public.osce_checklists
UNION ALL
SELECT 'osce_checklist_items', count(*) FROM public.osce_checklist_items;
