export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      admin_codes: {
        Row: {
          code: string
          created_at: string
          id: string
          used_at: string | null
          used_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          used_at?: string | null
          used_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          used_at?: string | null
          used_by?: string | null
        }
        Relationships: []
      }
      app_settings: {
        Row: {
          erudite_daily_limit: number
          erudite_days: number
          erudite_price: number
          id: number
          novice_daily_limit: number
          scholar_daily_limit: number
          scholar_days: number
          scholar_price: number
        }
        Insert: {
          erudite_daily_limit?: number
          erudite_days?: number
          erudite_price?: number
          id?: number
          novice_daily_limit?: number
          scholar_daily_limit?: number
          scholar_days?: number
          scholar_price?: number
        }
        Update: {
          erudite_daily_limit?: number
          erudite_days?: number
          erudite_price?: number
          id?: number
          novice_daily_limit?: number
          scholar_daily_limit?: number
          scholar_days?: number
          scholar_price?: number
        }
        Relationships: []
      }
      bookmarks: {
        Row: {
          created_at: string
          id: string
          note: string | null
          question_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          note?: string | null
          question_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          note?: string | null
          question_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "bookmarks_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_test_attempt_answers: {
        Row: {
          attempt_id: string
          custom_test_question_id: string
          id: string
          is_correct: boolean
          position: number
          user_answer: string | null
        }
        Insert: {
          attempt_id: string
          custom_test_question_id: string
          id?: string
          is_correct?: boolean
          position: number
          user_answer?: string | null
        }
        Update: {
          attempt_id?: string
          custom_test_question_id?: string
          id?: string
          is_correct?: boolean
          position?: number
          user_answer?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "custom_test_attempt_answers_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: false
            referencedRelation: "custom_test_attempts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_test_attempt_answers_custom_test_question_id_fkey"
            columns: ["custom_test_question_id"]
            isOneToOne: false
            referencedRelation: "custom_test_questions"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_test_attempts: {
        Row: {
          access_hash: string
          completed_at: string | null
          correct_count: number | null
          custom_test_id: string
          email: string
          id: string
          score_pct: number | null
          started_at: string
          status: string
          total_questions: number
          user_id: string | null
        }
        Insert: {
          access_hash: string
          completed_at?: string | null
          correct_count?: number | null
          custom_test_id: string
          email: string
          id?: string
          score_pct?: number | null
          started_at?: string
          status?: string
          total_questions: number
          user_id?: string | null
        }
        Update: {
          access_hash?: string
          completed_at?: string | null
          correct_count?: number | null
          custom_test_id?: string
          email?: string
          id?: string
          score_pct?: number | null
          started_at?: string
          status?: string
          total_questions?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "custom_test_attempts_custom_test_id_fkey"
            columns: ["custom_test_id"]
            isOneToOne: false
            referencedRelation: "custom_tests"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_test_questions: {
        Row: {
          correct_answer: string
          custom_test_id: string
          id: string
          imported_at: string | null
          imported_to_bank: boolean
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          position: number
          question_text: string
          rationale: string | null
          source_kind: string
          source_question_id: string | null
        }
        Insert: {
          correct_answer: string
          custom_test_id: string
          id?: string
          imported_at?: string | null
          imported_to_bank?: boolean
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          position: number
          question_text: string
          rationale?: string | null
          source_kind?: string
          source_question_id?: string | null
        }
        Update: {
          correct_answer?: string
          custom_test_id?: string
          id?: string
          imported_at?: string | null
          imported_to_bank?: boolean
          option_a?: string
          option_b?: string
          option_c?: string
          option_d?: string
          position?: number
          question_text?: string
          rationale?: string | null
          source_kind?: string
          source_question_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "custom_test_questions_custom_test_id_fkey"
            columns: ["custom_test_id"]
            isOneToOne: false
            referencedRelation: "custom_tests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_test_questions_source_question_id_fkey"
            columns: ["source_question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_tests: {
        Row: {
          created_at: string
          description: string | null
          duration_minutes: number
          exam_type: Database["public"]["Enums"]["exam_type"]
          expires_at: string
          id: string
          owner_id: string
          source_mode: string
          status: Database["public"]["Enums"]["custom_test_status"]
          title: string
          token_hash: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          duration_minutes: number
          exam_type: Database["public"]["Enums"]["exam_type"]
          expires_at: string
          id?: string
          owner_id: string
          source_mode?: string
          status?: Database["public"]["Enums"]["custom_test_status"]
          title: string
          token_hash: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          duration_minutes?: number
          exam_type?: Database["public"]["Enums"]["exam_type"]
          expires_at?: string
          id?: string
          owner_id?: string
          source_mode?: string
          status?: Database["public"]["Enums"]["custom_test_status"]
          title?: string
          token_hash?: string
          updated_at?: string
        }
        Relationships: []
      }
      daily_challenges: {
        Row: {
          challenge_date: string
          created_at: string
          exam_id: string | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id: string
          question_ids: string[]
          started_at: string | null
          user_id: string
        }
        Insert: {
          challenge_date: string
          created_at?: string
          exam_id?: string | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id?: string
          question_ids: string[]
          started_at?: string | null
          user_id: string
        }
        Update: {
          challenge_date?: string
          created_at?: string
          exam_id?: string | null
          exam_type?: Database["public"]["Enums"]["exam_type"]
          id?: string
          question_ids?: string[]
          started_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "daily_challenges_exam_id_fkey"
            columns: ["exam_id"]
            isOneToOne: false
            referencedRelation: "exams"
            referencedColumns: ["id"]
          },
        ]
      }
      exam_answers: {
        Row: {
          answer_changes: number
          answered_at: string | null
          attempt_number: number | null
          confidence: string | null
          exam_id: string
          first_answer: string | null
          flagged: boolean
          id: string
          is_correct: boolean | null
          position: number
          question_id: string
          time_spent_ms: number | null
          topic: string | null
          user_answer: string | null
        }
        Insert: {
          answer_changes?: number
          answered_at?: string | null
          attempt_number?: number | null
          confidence?: string | null
          exam_id: string
          first_answer?: string | null
          flagged?: boolean
          id?: string
          is_correct?: boolean | null
          position: number
          question_id: string
          time_spent_ms?: number | null
          topic?: string | null
          user_answer?: string | null
        }
        Update: {
          answer_changes?: number
          answered_at?: string | null
          attempt_number?: number | null
          confidence?: string | null
          exam_id?: string
          first_answer?: string | null
          flagged?: boolean
          id?: string
          is_correct?: boolean | null
          position?: number
          question_id?: string
          time_spent_ms?: number | null
          topic?: string | null
          user_answer?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "exam_answers_exam_id_fkey"
            columns: ["exam_id"]
            isOneToOne: false
            referencedRelation: "exams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "exam_answers_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      exams: {
        Row: {
          auto_submitted: boolean
          category: string
          completed_at: string | null
          correct_count: number | null
          deadline_at: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          id: string
          score_pct: number | null
          session_type: string
          started_at: string
          status: string
          submitted_at: string | null
          time_limit_minutes: number
          time_spent_ms: number | null
          topics: string[]
          total_questions: number
          user_id: string
        }
        Insert: {
          auto_submitted?: boolean
          category?: string
          completed_at?: string | null
          correct_count?: number | null
          deadline_at: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          id?: string
          score_pct?: number | null
          session_type?: string
          started_at?: string
          status?: string
          submitted_at?: string | null
          time_limit_minutes: number
          time_spent_ms?: number | null
          topics?: string[]
          total_questions: number
          user_id: string
        }
        Update: {
          auto_submitted?: boolean
          category?: string
          completed_at?: string | null
          correct_count?: number | null
          deadline_at?: string
          exam_type?: Database["public"]["Enums"]["exam_type"]
          id?: string
          score_pct?: number | null
          session_type?: string
          started_at?: string
          status?: string
          submitted_at?: string | null
          time_limit_minutes?: number
          time_spent_ms?: number | null
          topics?: string[]
          total_questions?: number
          user_id?: string
        }
        Relationships: []
      }
      payment_receipts: {
        Row: {
          amount: number | null
          auto_approved: boolean
          created_at: string
          extracted_text: string | null
          file_path: string
          flag_reason: string | null
          id: string
          notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["receipt_status"]
          target_tier: Database["public"]["Enums"]["user_tier"]
          user_id: string
          verified_at: string | null
        }
        Insert: {
          amount?: number | null
          auto_approved?: boolean
          created_at?: string
          extracted_text?: string | null
          file_path: string
          flag_reason?: string | null
          id?: string
          notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["receipt_status"]
          target_tier: Database["public"]["Enums"]["user_tier"]
          user_id: string
          verified_at?: string | null
        }
        Update: {
          amount?: number | null
          auto_approved?: boolean
          created_at?: string
          extracted_text?: string | null
          file_path?: string
          flag_reason?: string | null
          id?: string
          notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["receipt_status"]
          target_tier?: Database["public"]["Enums"]["user_tier"]
          user_id?: string
          verified_at?: string | null
        }
        Relationships: []
      }
      plans: {
        Row: {
          created_at: string
          duration_days: number
          id: string
          is_active: boolean
          name: string
          price_ngn: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          duration_days?: number
          id?: string
          is_active?: boolean
          name: string
          price_ngn?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          duration_days?: number
          id?: string
          is_active?: boolean
          name?: string
          price_ngn?: number
          updated_at?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          email: string | null
          exam_date: string | null
          exam_preference: string | null
          expiry_date: string | null
          first_name: string | null
          id: string
          last_name: string | null
          last_question_date: string | null
          onboarded: boolean
          questions_today: number
          tier: Database["public"]["Enums"]["user_tier"]
          username: string | null
        }
        Insert: {
          created_at?: string
          email?: string | null
          exam_date?: string | null
          exam_preference?: string | null
          expiry_date?: string | null
          first_name?: string | null
          id: string
          last_name?: string | null
          last_question_date?: string | null
          onboarded?: boolean
          questions_today?: number
          tier?: Database["public"]["Enums"]["user_tier"]
          username?: string | null
        }
        Update: {
          created_at?: string
          email?: string | null
          exam_date?: string | null
          exam_preference?: string | null
          expiry_date?: string | null
          first_name?: string | null
          id?: string
          last_name?: string | null
          last_question_date?: string | null
          onboarded?: boolean
          questions_today?: number
          tier?: Database["public"]["Enums"]["user_tier"]
          username?: string | null
        }
        Relationships: []
      }
      question_reports: {
        Row: {
          created_at: string
          details: string | null
          id: string
          question_id: string
          reason: string
          reporter_id: string
          resolution_note: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: string
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: string
          question_id: string
          reason: string
          reporter_id: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: string
          question_id?: string
          reason?: string
          reporter_id?: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_reports_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      questions: {
        Row: {
          correct_answer: string
          created_at: string
          created_by: string | null
          difficulty: string | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id: string
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          question_text: string
          rationale: string | null
          source: string | null
          status: string
          subtopic_id: string | null
          tags: string[]
          topic: string
          updated_at: string
          year: number | null
        }
        Insert: {
          correct_answer: string
          created_at?: string
          created_by?: string | null
          difficulty?: string | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id?: string
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          question_text: string
          rationale?: string | null
          source?: string | null
          status?: string
          subtopic_id?: string | null
          tags?: string[]
          topic?: string
          updated_at?: string
          year?: number | null
        }
        Update: {
          correct_answer?: string
          created_at?: string
          created_by?: string | null
          difficulty?: string | null
          exam_type?: Database["public"]["Enums"]["exam_type"]
          id?: string
          option_a?: string
          option_b?: string
          option_c?: string
          option_d?: string
          question_text?: string
          rationale?: string | null
          source?: string | null
          status?: string
          subtopic_id?: string | null
          tags?: string[]
          topic?: string
          updated_at?: string
          year?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "questions_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
        ]
      }
      receipt_fingerprints: {
        Row: {
          created_at: string
          extracted_text: string | null
          fingerprint: string
          id: string
          receipt_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          extracted_text?: string | null
          fingerprint: string
          id?: string
          receipt_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          extracted_text?: string | null
          fingerprint?: string
          id?: string
          receipt_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "receipt_fingerprints_receipt_id_fkey"
            columns: ["receipt_id"]
            isOneToOne: false
            referencedRelation: "payment_receipts"
            referencedColumns: ["id"]
          },
        ]
      }
      study_plans: {
        Row: {
          created_at: string
          daily_minutes: number
          days_per_week: number
          exam_date: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          plan: Json
          questions_per_day: number
          starts_on: string
          target_score: number
          user_id: string
        }
        Insert: {
          created_at?: string
          daily_minutes: number
          days_per_week: number
          exam_date: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          plan: Json
          questions_per_day: number
          starts_on: string
          target_score: number
          user_id: string
        }
        Update: {
          created_at?: string
          daily_minutes?: number
          days_per_week?: number
          exam_date?: string
          exam_type?: Database["public"]["Enums"]["exam_type"]
          plan?: Json
          questions_per_day?: number
          starts_on?: string
          target_score?: number
          user_id?: string
        }
        Relationships: []
      }
      subscription_payments: {
        Row: {
          amount_ngn: number
          created_at: string
          duration_days: number
          id: string
          plan_name: string
          reference: string | null
          user_id: string
        }
        Insert: {
          amount_ngn: number
          created_at?: string
          duration_days: number
          id?: string
          plan_name: string
          reference?: string | null
          user_id: string
        }
        Update: {
          amount_ngn?: number
          created_at?: string
          duration_days?: number
          id?: string
          plan_name?: string
          reference?: string | null
          user_id?: string
        }
        Relationships: []
      }
      subtopics: {
        Row: {
          created_at: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          id: string
          name: string
          topic: string
        }
        Insert: {
          created_at?: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          id?: string
          name: string
          topic: string
        }
        Update: {
          created_at?: string
          exam_type?: Database["public"]["Enums"]["exam_type"]
          id?: string
          name?: string
          topic?: string
        }
        Relationships: []
      }
      user_achievements: {
        Row: {
          code: string
          unlocked_at: string
          user_id: string
          xp_awarded: number
        }
        Insert: {
          code: string
          unlocked_at?: string
          user_id: string
          xp_awarded?: number
        }
        Update: {
          code?: string
          unlocked_at?: string
          user_id?: string
          xp_awarded?: number
        }
        Relationships: []
      }
      user_question_stats: {
        Row: {
          attempts: number
          correct: number
          corrected_at: string | null
          ease: number
          interval_days: number
          last_answer: string | null
          last_attempt_at: string | null
          last_correct_at: string | null
          last_missed_at: string | null
          last_reviewed_at: string | null
          misses: number
          next_review_at: string | null
          question_id: string
          review_count: number
          review_stale: boolean | null
          review_status: string
          unresolved: boolean | null
          updated_at: string
          user_id: string
        }
        Insert: {
          attempts?: number
          correct?: number
          corrected_at?: string | null
          ease?: number
          interval_days?: number
          last_answer?: string | null
          last_attempt_at?: string | null
          last_correct_at?: string | null
          last_missed_at?: string | null
          last_reviewed_at?: string | null
          misses?: number
          next_review_at?: string | null
          question_id: string
          review_count?: number
          review_stale?: boolean | null
          review_status?: string
          unresolved?: boolean | null
          updated_at?: string
          user_id: string
        }
        Update: {
          attempts?: number
          correct?: number
          corrected_at?: string | null
          ease?: number
          interval_days?: number
          last_answer?: string | null
          last_attempt_at?: string | null
          last_correct_at?: string | null
          last_missed_at?: string | null
          last_reviewed_at?: string | null
          misses?: number
          next_review_at?: string | null
          question_id?: string
          review_count?: number
          review_stale?: boolean | null
          review_status?: string
          unresolved?: boolean | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_question_stats_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      xp_events: {
        Row: {
          created_at: string
          id: string
          occurred_at: string
          source_id: string
          source_type: string
          user_id: string
          xp: number
        }
        Insert: {
          created_at?: string
          id?: string
          occurred_at?: string
          source_id: string
          source_type: string
          user_id: string
          xp: number
        }
        Update: {
          created_at?: string
          id?: string
          occurred_at?: string
          source_id?: string
          source_type?: string
          user_id?: string
          xp?: number
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      activate_subscription: {
        Args: {
          _amount: number
          _reference: string
          _tier: Database["public"]["Enums"]["user_tier"]
        }
        Returns: string
      }
      activate_verified_subscription: {
        Args: {
          _amount: number
          _reference: string
          _tier: Database["public"]["Enums"]["user_tier"]
          _user_id: string
        }
        Returns: string
      }
      add_custom_test_to_question_bank: {
        Args: {
          _custom_test_id: string
          _exam_type: Database["public"]["Enums"]["exam_type"]
          _topic: string
        }
        Returns: number
      }
      apply_review_states: {
        Args: { _states: Json; _user_id: string }
        Returns: number
      }
      approve_receipt: { Args: { _receipt_id: string }; Returns: undefined }
      assign_user_tier: {
        Args: {
          _days: number
          _tier: Database["public"]["Enums"]["user_tier"]
          _user_id: string
        }
        Returns: undefined
      }
      auto_upgrade_from_receipt: {
        Args: {
          _amount: number
          _file_path: string
          _tier: Database["public"]["Enums"]["user_tier"]
        }
        Returns: string
      }
      central_admin_search_users: {
        Args: { _search: string }
        Returns: {
          email: string
          is_admin: boolean
          tier: Database["public"]["Enums"]["user_tier"]
          user_id: string
          username: string
        }[]
      }
      check_expire_tier: { Args: { _user_id: string }; Returns: undefined }
      claim_custom_test_attempt: {
        Args: { _access_hash: string; _attempt_id: string }
        Returns: boolean
      }
      create_daily_challenge: {
        Args: {
          _date: string
          _exam_type: Database["public"]["Enums"]["exam_type"]
          _question_ids: string[]
          _user_id: string
        }
        Returns: string
      }
      daily_reset: { Args: never; Returns: undefined }
      flag_receipt_and_revoke: {
        Args: { _reason: string; _receipt_id: string }
        Returns: undefined
      }
      get_custom_test_analytics: {
        Args: { _custom_test_id: string }
        Returns: {
          average_score: number
          fail_count: number
          participant_count: number
          pass_count: number
          pass_pct: number
        }[]
      }
      get_custom_test_attempt_results: {
        Args: { _access_hash: string; _attempt_id: string }
        Returns: {
          correct_answer: string
          is_correct: boolean
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          question_id: string
          question_position: number
          question_text: string
          rationale: string
          user_answer: string
        }[]
      }
      get_custom_test_by_token: {
        Args: { _token_hash: string }
        Returns: {
          description: string
          duration_minutes: number
          exam_type: Database["public"]["Enums"]["exam_type"]
          expires_at: string
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          question_id: string
          question_position: number
          question_text: string
          test_id: string
          title: string
        }[]
      }
      get_daily_challenge_view: {
        Args: { _date: string; _user_id: string }
        Returns: {
          challenge_date: string
          completed_at: string
          correct_count: number
          exam_id: string
          exam_status: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          id: string
          score_pct: number
          total_questions: number
        }[]
      }
      get_daily_leaderboard: {
        Args: never
        Returns: {
          attempted: number
          avg_score: number
          correct: number
          user_id: string
          username: string
        }[]
      }
      get_engagement_snapshot: {
        Args: {
          _perfect_min_answered: number
          _topic_min_attempts: number
          _user_id: string
        }
        Returns: Json
      }
      get_question_difficulty_stats: {
        Args: { _question_ids: string[] }
        Returns: {
          attempts: number
          correct: number
          question_id: string
        }[]
      }
      get_question_topic_counts: {
        Args: { _exam_type: Database["public"]["Enums"]["exam_type"] }
        Returns: {
          topic: string
          total: number
        }[]
      }
      get_student_attempts: {
        Args: {
          _limit?: number
          _question_ids?: string[]
          _since?: string
          _user_id: string
        }
        Returns: {
          answered_at: string
          confidence: string
          correct: boolean
          difficulty: string
          exam_type: Database["public"]["Enums"]["exam_type"]
          question_id: string
          session_id: string
          session_type: string
          time_spent_ms: number
          topic: string
        }[]
      }
      get_study_days: {
        Args: { _since?: string; _user_id: string }
        Returns: {
          answered: number
          study_day: string
        }[]
      }
      get_subadmin_user_directory: {
        Args: never
        Returns: {
          tier: Database["public"]["Enums"]["user_tier"]
          username: string
        }[]
      }
      get_unawarded_sessions: {
        Args: { _limit?: number; _user_id: string }
        Returns: {
          answered: number
          completed_at: string
          correct: number
          exam_id: string
          first_correct: number
          session_type: string
        }[]
      }
      get_unpaid_daily_challenges: {
        Args: { _limit?: number; _user_id: string }
        Returns: {
          challenge_id: string
          completed_at: string
          correct_count: number
          score_pct: number
          total_questions: number
        }[]
      }
      get_weekly_leaderboard: {
        Args: never
        Returns: {
          active_days: number
          attempted: number
          avg_score: number
          correct: number
          user_id: string
          username: string
        }[]
      }
      get_xp_total: { Args: { _user_id: string }; Returns: number }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_any_admin: { Args: { _user_id: string }; Returns: boolean }
      record_receipt_fingerprint: {
        Args: {
          _extracted_text: string
          _fingerprint: string
          _receipt_id: string
        }
        Returns: boolean
      }
      record_xp_events: {
        Args: { _events: Json; _user_id: string }
        Returns: number
      }
      redeem_admin_code: { Args: { _code: string }; Returns: boolean }
      republish_custom_test: {
        Args: { _custom_test_id: string; _expires_at: string }
        Returns: string
      }
      reset_user_to_novice: { Args: { _user_id: string }; Returns: undefined }
      save_exam_answer: {
        Args: {
          _answer?: string
          _confidence?: string
          _exam_id: string
          _flagged?: boolean
          _grace_seconds: number
          _question_id: string
          _time_spent_ms?: number
          _user_id: string
        }
        Returns: string
      }
      start_challenge_session: {
        Args: {
          _challenge_id: string
          _time_limit_minutes: number
          _today: string
          _user_id: string
        }
        Returns: string
      }
      start_custom_test_attempt: {
        Args: { _access_hash: string; _email: string; _token_hash: string }
        Returns: {
          attempt_id: string
          duration_minutes: number
          expires_at: string
          total_questions: number
        }[]
      }
      start_exam_session: {
        Args: {
          _category: string
          _exam_type: Database["public"]["Enums"]["exam_type"]
          _question_ids: string[]
          _session_type: string
          _time_limit_minutes: number
          _today: string
          _topics: string[]
          _user_id: string
        }
        Returns: string
      }
      submit_custom_test_attempt: {
        Args: { _access_hash: string; _answers: Json; _attempt_id: string }
        Returns: {
          correct_count: number
          score_pct: number
          total_questions: number
        }[]
      }
      submit_exam_session: {
        Args: { _exam_id: string; _user_id: string }
        Returns: Json
      }
      unlock_achievements: {
        Args: { _unlocks: Json; _user_id: string }
        Returns: string[]
      }
    }
    Enums: {
      app_role: "central_admin" | "admin" | "user"
      custom_test_status: "draft" | "published" | "archived"
      exam_type: "RN" | "RM"
      receipt_status: "pending" | "approved" | "rejected"
      user_tier: "novice" | "erudite" | "scholar"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["central_admin", "admin", "user"],
      custom_test_status: ["draft", "published", "archived"],
      exam_type: ["RN", "RM"],
      receipt_status: ["pending", "approved", "rejected"],
      user_tier: ["novice", "erudite", "scholar"],
    },
  },
} as const
