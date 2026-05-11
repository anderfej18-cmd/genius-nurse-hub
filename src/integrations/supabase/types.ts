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
          bank_account: string
          bank_account_name: string
          bank_name: string
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
          bank_account?: string
          bank_account_name?: string
          bank_name?: string
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
          bank_account?: string
          bank_account_name?: string
          bank_name?: string
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
      exam_answers: {
        Row: {
          exam_id: string
          flagged: boolean
          id: string
          is_correct: boolean | null
          position: number
          question_id: string
          user_answer: string | null
        }
        Insert: {
          exam_id: string
          flagged?: boolean
          id?: string
          is_correct?: boolean | null
          position: number
          question_id: string
          user_answer?: string | null
        }
        Update: {
          exam_id?: string
          flagged?: boolean
          id?: string
          is_correct?: boolean | null
          position?: number
          question_id?: string
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
          category: string
          completed_at: string | null
          correct_count: number | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id: string
          score_pct: number | null
          started_at: string
          status: string
          time_limit_minutes: number
          total_questions: number
          user_id: string
        }
        Insert: {
          category?: string
          completed_at?: string | null
          correct_count?: number | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id?: string
          score_pct?: number | null
          started_at?: string
          status?: string
          time_limit_minutes: number
          total_questions: number
          user_id: string
        }
        Update: {
          category?: string
          completed_at?: string | null
          correct_count?: number | null
          exam_type?: Database["public"]["Enums"]["exam_type"]
          id?: string
          score_pct?: number | null
          started_at?: string
          status?: string
          time_limit_minutes?: number
          total_questions?: number
          user_id?: string
        }
        Relationships: []
      }
      payment_receipts: {
        Row: {
          amount: number | null
          created_at: string
          file_path: string
          id: string
          notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["receipt_status"]
          target_tier: Database["public"]["Enums"]["user_tier"]
          user_id: string
        }
        Insert: {
          amount?: number | null
          created_at?: string
          file_path: string
          id?: string
          notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["receipt_status"]
          target_tier: Database["public"]["Enums"]["user_tier"]
          user_id: string
        }
        Update: {
          amount?: number | null
          created_at?: string
          file_path?: string
          id?: string
          notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["receipt_status"]
          target_tier?: Database["public"]["Enums"]["user_tier"]
          user_id?: string
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
      questions: {
        Row: {
          correct_answer: string
          created_at: string
          created_by: string | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id: string
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          question_text: string
          rationale: string | null
          topic: string
          year: number | null
        }
        Insert: {
          correct_answer: string
          created_at?: string
          created_by?: string | null
          exam_type: Database["public"]["Enums"]["exam_type"]
          id?: string
          option_a: string
          option_b: string
          option_c: string
          option_d: string
          question_text: string
          rationale?: string | null
          topic?: string
          year?: number | null
        }
        Update: {
          correct_answer?: string
          created_at?: string
          created_by?: string | null
          exam_type?: Database["public"]["Enums"]["exam_type"]
          id?: string
          option_a?: string
          option_b?: string
          option_c?: string
          option_d?: string
          question_text?: string
          rationale?: string | null
          topic?: string
          year?: number | null
        }
        Relationships: []
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
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      approve_receipt: { Args: { _receipt_id: string }; Returns: undefined }
      check_expire_tier: { Args: { _user_id: string }; Returns: undefined }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_any_admin: { Args: { _user_id: string }; Returns: boolean }
      redeem_admin_code: { Args: { _code: string }; Returns: boolean }
      reset_user_to_novice: { Args: { _user_id: string }; Returns: undefined }
    }
    Enums: {
      app_role: "central_admin" | "admin" | "user"
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
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
      exam_type: ["RN", "RM"],
      receipt_status: ["pending", "approved", "rejected"],
      user_tier: ["novice", "erudite", "scholar"],
    },
  },
} as const
