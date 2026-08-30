export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          archived_at: string | null
          cash_flow_section: Database["public"]["Enums"]["cash_flow_section"]
          code: string | null
          created_at: string
          created_by: string | null
          currency: string
          description: string | null
          id: string
          is_active: boolean
          is_archived: boolean
          is_liquid: boolean
          is_system: boolean
          name: string
          normal_balance: Database["public"]["Enums"]["normal_balance"]
          organization_id: string
          parent_account_id: string | null
          subtype: Database["public"]["Enums"]["account_subtype"]
          system_key: string | null
          type: Database["public"]["Enums"]["account_type"]
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          cash_flow_section?: Database["public"]["Enums"]["cash_flow_section"]
          code?: string | null
          created_at?: string
          created_by?: string | null
          currency: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_archived?: boolean
          is_liquid?: boolean
          is_system?: boolean
          name: string
          normal_balance?: Database["public"]["Enums"]["normal_balance"]
          organization_id: string
          parent_account_id?: string | null
          subtype: Database["public"]["Enums"]["account_subtype"]
          system_key?: string | null
          type: Database["public"]["Enums"]["account_type"]
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          cash_flow_section?: Database["public"]["Enums"]["cash_flow_section"]
          code?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_archived?: boolean
          is_liquid?: boolean
          is_system?: boolean
          name?: string
          normal_balance?: Database["public"]["Enums"]["normal_balance"]
          organization_id?: string
          parent_account_id?: string | null
          subtype?: Database["public"]["Enums"]["account_subtype"]
          system_key?: string | null
          type?: Database["public"]["Enums"]["account_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounts_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "accounts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounts_parent_same_org"
            columns: ["parent_account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "account_balances"
            referencedColumns: ["account_id", "organization_id"]
          },
          {
            foreignKeyName: "accounts_parent_same_org"
            columns: ["parent_account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      attachments: {
        Row: {
          checksum: string | null
          created_at: string
          entity_id: string
          entity_type: string
          file_name: string
          id: string
          mime_type: string
          organization_id: string
          size_bytes: number
          storage_bucket: string
          storage_key: string
          uploaded_by: string | null
        }
        Insert: {
          checksum?: string | null
          created_at?: string
          entity_id: string
          entity_type: string
          file_name: string
          id?: string
          mime_type: string
          organization_id: string
          size_bytes: number
          storage_bucket?: string
          storage_key: string
          uploaded_by?: string | null
        }
        Update: {
          checksum?: string | null
          created_at?: string
          entity_id?: string
          entity_type?: string
          file_name?: string
          id?: string
          mime_type?: string
          organization_id?: string
          size_bytes?: number
          storage_bucket?: string
          storage_key?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attachments_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs: {
        Row: {
          action: string
          actor_email: string | null
          actor_id: string | null
          after_state: Json | null
          before_state: Json | null
          created_at: string
          entity_id: string | null
          entity_type: string
          id: number
          ip_address: unknown
          metadata: Json
          organization_id: string
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_email?: string | null
          actor_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          id?: never
          ip_address?: unknown
          metadata?: Json
          organization_id: string
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_email?: string | null
          actor_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          id?: never
          ip_address?: unknown
          metadata?: Json
          organization_id?: string
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_events: {
        Row: {
          event_type: string
          id: string
          organization_id: string | null
          payload: Json
          processed_at: string | null
          processing_error: string | null
          provider: string
          provider_event_id: string
          received_at: string
          signature_verified: boolean
        }
        Insert: {
          event_type: string
          id?: string
          organization_id?: string | null
          payload: Json
          processed_at?: string | null
          processing_error?: string | null
          provider: string
          provider_event_id: string
          received_at?: string
          signature_verified?: boolean
        }
        Update: {
          event_type?: string
          id?: string
          organization_id?: string | null
          payload?: Json
          processed_at?: string | null
          processing_error?: string | null
          provider?: string
          provider_event_id?: string
          received_at?: string
          signature_verified?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "billing_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      capabilities: {
        Row: {
          description: string
          domain: string
          key: string
        }
        Insert: {
          description: string
          domain: string
          key: string
        }
        Update: {
          description?: string
          domain?: string
          key?: string
        }
        Relationships: []
      }
      categories: {
        Row: {
          color: string | null
          created_at: string
          created_by: string | null
          default_account_id: string | null
          icon: string | null
          id: string
          is_active: boolean
          is_system: boolean
          kind: Database["public"]["Enums"]["category_kind"]
          name: string
          organization_id: string
          parent_id: string | null
          sort_order: number
          updated_at: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          created_by?: string | null
          default_account_id?: string | null
          icon?: string | null
          id?: string
          is_active?: boolean
          is_system?: boolean
          kind: Database["public"]["Enums"]["category_kind"]
          name: string
          organization_id: string
          parent_id?: string | null
          sort_order?: number
          updated_at?: string
        }
        Update: {
          color?: string | null
          created_at?: string
          created_by?: string | null
          default_account_id?: string | null
          icon?: string | null
          id?: string
          is_active?: boolean
          is_system?: boolean
          kind?: Database["public"]["Enums"]["category_kind"]
          name?: string
          organization_id?: string
          parent_id?: string | null
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "categories_account_same_org"
            columns: ["default_account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "account_balances"
            referencedColumns: ["account_id", "organization_id"]
          },
          {
            foreignKeyName: "categories_account_same_org"
            columns: ["default_account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "categories_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "categories_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "categories_parent_same_org"
            columns: ["parent_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      counterparties: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          email: string | null
          id: string
          is_archived: boolean
          name: string
          notes: string | null
          organization_id: string
          phone: string | null
          tax_identifier: string | null
          type: Database["public"]["Enums"]["counterparty_type"]
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          id?: string
          is_archived?: boolean
          name: string
          notes?: string | null
          organization_id: string
          phone?: string | null
          tax_identifier?: string | null
          type?: Database["public"]["Enums"]["counterparty_type"]
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          id?: string
          is_archived?: boolean
          name?: string
          notes?: string | null
          organization_id?: string
          phone?: string | null
          tax_identifier?: string | null
          type?: Database["public"]["Enums"]["counterparty_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "counterparties_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "counterparties_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      currencies: {
        Row: {
          code: string
          created_at: string
          is_active: boolean
          minor_unit: number
          name: string
          symbol: string | null
        }
        Insert: {
          code: string
          created_at?: string
          is_active?: boolean
          minor_unit?: number
          name: string
          symbol?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          is_active?: boolean
          minor_unit?: number
          name?: string
          symbol?: string | null
        }
        Relationships: []
      }
      notifications: {
        Row: {
          action_url: string | null
          body: string | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          id: string
          metadata: Json
          organization_id: string
          read_at: string | null
          severity: string
          title: string
          type: string
          user_id: string | null
        }
        Insert: {
          action_url?: string | null
          body?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          organization_id: string
          read_at?: string | null
          severity?: string
          title: string
          type: string
          user_id?: string | null
        }
        Update: {
          action_url?: string | null
          body?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          organization_id?: string
          read_at?: string | null
          severity?: string
          title?: string
          type?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notifications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string | null
          organization_id: string
          role: Database["public"]["Enums"]["organization_role"]
          status: Database["public"]["Enums"]["invitation_status"]
          token_hash: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          organization_id: string
          role?: Database["public"]["Enums"]["organization_role"]
          status?: Database["public"]["Enums"]["invitation_status"]
          token_hash: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          organization_id?: string
          role?: Database["public"]["Enums"]["organization_role"]
          status?: Database["public"]["Enums"]["invitation_status"]
          token_hash?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_invitations_accepted_by_fkey"
            columns: ["accepted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_members: {
        Row: {
          created_at: string
          granted_capabilities: string[]
          id: string
          invited_by: string | null
          joined_at: string
          organization_id: string
          revoked_capabilities: string[]
          role: Database["public"]["Enums"]["organization_role"]
          status: Database["public"]["Enums"]["membership_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          granted_capabilities?: string[]
          id?: string
          invited_by?: string | null
          joined_at?: string
          organization_id: string
          revoked_capabilities?: string[]
          role?: Database["public"]["Enums"]["organization_role"]
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          granted_capabilities?: string[]
          id?: string
          invited_by?: string | null
          joined_at?: string
          organization_id?: string
          revoked_capabilities?: string[]
          role?: Database["public"]["Enums"]["organization_role"]
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_members_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_settings: {
        Row: {
          advanced_accounting_mode: boolean
          books_locked_until: string | null
          created_at: string
          default_transaction_currency: string | null
          duplicate_detection_enabled: boolean
          organization_id: string
          require_adjustment_approval: boolean
          updated_at: string
          week_starts_on: number
        }
        Insert: {
          advanced_accounting_mode?: boolean
          books_locked_until?: string | null
          created_at?: string
          default_transaction_currency?: string | null
          duplicate_detection_enabled?: boolean
          organization_id: string
          require_adjustment_approval?: boolean
          updated_at?: string
          week_starts_on?: number
        }
        Update: {
          advanced_accounting_mode?: boolean
          books_locked_until?: string | null
          created_at?: string
          default_transaction_currency?: string | null
          duplicate_detection_enabled?: boolean
          organization_id?: string
          require_adjustment_approval?: boolean
          updated_at?: string
          week_starts_on?: number
        }
        Relationships: [
          {
            foreignKeyName: "organization_settings_default_transaction_currency_fkey"
            columns: ["default_transaction_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "organization_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          archived_at: string | null
          base_currency: string
          country_code: string
          created_at: string
          created_by: string
          fiscal_year_start_month: number
          id: string
          legal_name: string | null
          logo_url: string | null
          name: string
          slug: string
          status: Database["public"]["Enums"]["organization_status"]
          tax_identifier: string | null
          timezone: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          base_currency: string
          country_code?: string
          created_at?: string
          created_by: string
          fiscal_year_start_month?: number
          id?: string
          legal_name?: string | null
          logo_url?: string | null
          name: string
          slug: string
          status?: Database["public"]["Enums"]["organization_status"]
          tax_identifier?: string | null
          timezone?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          base_currency?: string
          country_code?: string
          created_at?: string
          created_by?: string
          fiscal_year_start_month?: number
          id?: string
          legal_name?: string | null
          logo_url?: string | null
          name?: string
          slug?: string
          status?: Database["public"]["Enums"]["organization_status"]
          tax_identifier?: string | null
          timezone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organizations_base_currency_fkey"
            columns: ["base_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "organizations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          default_organization_id: string | null
          email: string
          full_name: string | null
          id: string
          locale: string
          timezone: string
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          default_organization_id?: string | null
          email: string
          full_name?: string | null
          id: string
          locale?: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          default_organization_id?: string | null
          email?: string
          full_name?: string | null
          id?: string
          locale?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_default_organization_id_fkey"
            columns: ["default_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      role_capabilities: {
        Row: {
          capability_key: string
          role: Database["public"]["Enums"]["organization_role"]
        }
        Insert: {
          capability_key: string
          role: Database["public"]["Enums"]["organization_role"]
        }
        Update: {
          capability_key?: string
          role?: Database["public"]["Enums"]["organization_role"]
        }
        Relationships: [
          {
            foreignKeyName: "role_capabilities_capability_key_fkey"
            columns: ["capability_key"]
            isOneToOne: false
            referencedRelation: "capabilities"
            referencedColumns: ["key"]
          },
        ]
      }
      saved_views: {
        Row: {
          created_at: string
          created_by: string
          filters: Json
          id: string
          name: string
          organization_id: string
          resource: string
          sort: Json
          updated_at: string
          visibility: Database["public"]["Enums"]["saved_view_visibility"]
        }
        Insert: {
          created_at?: string
          created_by: string
          filters?: Json
          id?: string
          name: string
          organization_id: string
          resource?: string
          sort?: Json
          updated_at?: string
          visibility?: Database["public"]["Enums"]["saved_view_visibility"]
        }
        Update: {
          created_at?: string
          created_by?: string
          filters?: Json
          id?: string
          name?: string
          organization_id?: string
          resource?: string
          sort?: Json
          updated_at?: string
          visibility?: Database["public"]["Enums"]["saved_view_visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "saved_views_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_views_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_customers: {
        Row: {
          billing_email: string | null
          created_at: string
          id: string
          organization_id: string
          provider: string
          provider_customer_id: string
          updated_at: string
        }
        Insert: {
          billing_email?: string | null
          created_at?: string
          id?: string
          organization_id: string
          provider: string
          provider_customer_id: string
          updated_at?: string
        }
        Update: {
          billing_email?: string | null
          created_at?: string
          id?: string
          organization_id?: string
          provider?: string
          provider_customer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscription_customers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_entitlements: {
        Row: {
          feature_key: string
          is_enabled: boolean
          limit_value: number | null
          plan_id: string
        }
        Insert: {
          feature_key: string
          is_enabled?: boolean
          limit_value?: number | null
          plan_id: string
        }
        Update: {
          feature_key?: string
          is_enabled?: boolean
          limit_value?: number | null
          plan_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscription_entitlements_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "subscription_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_plan_prices: {
        Row: {
          amount_minor: number
          created_at: string
          currency_code: string
          id: string
          interval: Database["public"]["Enums"]["billing_interval"]
          is_active: boolean
          plan_id: string
          provider: string | null
          provider_price_id: string | null
        }
        Insert: {
          amount_minor: number
          created_at?: string
          currency_code: string
          id?: string
          interval: Database["public"]["Enums"]["billing_interval"]
          is_active?: boolean
          plan_id: string
          provider?: string | null
          provider_price_id?: string | null
        }
        Update: {
          amount_minor?: number
          created_at?: string
          currency_code?: string
          id?: string
          interval?: Database["public"]["Enums"]["billing_interval"]
          is_active?: boolean
          plan_id?: string
          provider?: string | null
          provider_price_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "subscription_plan_prices_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "subscription_plan_prices_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "subscription_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_plans: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          is_public: boolean
          key: string
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_public?: boolean
          key: string
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_public?: boolean
          key?: string
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      subscriptions: {
        Row: {
          cancel_at_period_end: boolean
          cancelled_at: string | null
          created_at: string
          current_period_end: string | null
          current_period_start: string | null
          grace_period_ends_at: string | null
          id: string
          organization_id: string
          plan_id: string
          price_id: string | null
          provider: string | null
          provider_subscription_id: string | null
          status: Database["public"]["Enums"]["billing_status"]
          trial_ends_at: string | null
          trial_started_at: string | null
          updated_at: string
        }
        Insert: {
          cancel_at_period_end?: boolean
          cancelled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          grace_period_ends_at?: string | null
          id?: string
          organization_id: string
          plan_id: string
          price_id?: string | null
          provider?: string | null
          provider_subscription_id?: string | null
          status?: Database["public"]["Enums"]["billing_status"]
          trial_ends_at?: string | null
          trial_started_at?: string | null
          updated_at?: string
        }
        Update: {
          cancel_at_period_end?: boolean
          cancelled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          grace_period_ends_at?: string | null
          id?: string
          organization_id?: string
          plan_id?: string
          price_id?: string | null
          provider?: string | null
          provider_subscription_id?: string | null
          status?: Database["public"]["Enums"]["billing_status"]
          trial_ends_at?: string | null
          trial_started_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "subscription_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_price_id_fkey"
            columns: ["price_id"]
            isOneToOne: false
            referencedRelation: "subscription_plan_prices"
            referencedColumns: ["id"]
          },
        ]
      }
      tags: {
        Row: {
          color: string | null
          created_at: string
          created_by: string | null
          id: string
          name: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          color?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      transaction_entries: {
        Row: {
          account_id: string
          amount_minor: number
          base_amount_minor: number
          base_currency_code: string
          created_at: string
          currency_code: string
          dimensions: Json
          entry_date: string
          entry_index: number
          exchange_rate: number
          id: string
          memo: string | null
          organization_id: string
          posted_at: string | null
          side: Database["public"]["Enums"]["entry_side"]
          transaction_id: string
        }
        Insert: {
          account_id: string
          amount_minor: number
          base_amount_minor: number
          base_currency_code: string
          created_at?: string
          currency_code: string
          dimensions?: Json
          entry_date: string
          entry_index: number
          exchange_rate?: number
          id?: string
          memo?: string | null
          organization_id: string
          posted_at?: string | null
          side: Database["public"]["Enums"]["entry_side"]
          transaction_id: string
        }
        Update: {
          account_id?: string
          amount_minor?: number
          base_amount_minor?: number
          base_currency_code?: string
          created_at?: string
          currency_code?: string
          dimensions?: Json
          entry_date?: string
          entry_index?: number
          exchange_rate?: number
          id?: string
          memo?: string | null
          organization_id?: string
          posted_at?: string | null
          side?: Database["public"]["Enums"]["entry_side"]
          transaction_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "transaction_entries_account_same_org"
            columns: ["account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "account_balances"
            referencedColumns: ["account_id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_entries_account_same_org"
            columns: ["account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_entries_base_currency_code_fkey"
            columns: ["base_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "transaction_entries_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "transaction_entries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_entries_transaction_same_org"
            columns: ["transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_entries_transaction_same_org"
            columns: ["transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      transaction_tags: {
        Row: {
          created_at: string
          created_by: string | null
          organization_id: string
          tag_id: string
          transaction_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          organization_id: string
          tag_id: string
          transaction_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          organization_id?: string
          tag_id?: string
          transaction_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "transaction_tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_tags_tag_same_org"
            columns: ["tag_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_tags_transaction_same_org"
            columns: ["transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_tags_transaction_same_org"
            columns: ["transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      transactions: {
        Row: {
          adjustment_reason: string | null
          category_id: string | null
          correction_of_transaction_id: string | null
          counterparty_id: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          deleted_at: string | null
          description: string | null
          duplicate_of_transaction_id: string | null
          exchange_rate: number
          fingerprint: string | null
          id: string
          idempotency_key: string | null
          memo: string | null
          metadata: Json
          organization_id: string
          possible_duplicate: boolean
          posted_at: string | null
          posted_by: string | null
          posting_date: string | null
          reference: string | null
          reversed_by_transaction_id: string | null
          reverses_transaction_id: string | null
          source: Database["public"]["Enums"]["transaction_source"]
          status: Database["public"]["Enums"]["transaction_status"]
          transaction_date: string
          type: Database["public"]["Enums"]["transaction_type"]
          updated_at: string
          voided_at: string | null
          voided_by: string | null
        }
        Insert: {
          adjustment_reason?: string | null
          category_id?: string | null
          correction_of_transaction_id?: string | null
          counterparty_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code: string
          deleted_at?: string | null
          description?: string | null
          duplicate_of_transaction_id?: string | null
          exchange_rate?: number
          fingerprint?: string | null
          id?: string
          idempotency_key?: string | null
          memo?: string | null
          metadata?: Json
          organization_id: string
          possible_duplicate?: boolean
          posted_at?: string | null
          posted_by?: string | null
          posting_date?: string | null
          reference?: string | null
          reversed_by_transaction_id?: string | null
          reverses_transaction_id?: string | null
          source?: Database["public"]["Enums"]["transaction_source"]
          status?: Database["public"]["Enums"]["transaction_status"]
          transaction_date: string
          type: Database["public"]["Enums"]["transaction_type"]
          updated_at?: string
          voided_at?: string | null
          voided_by?: string | null
        }
        Update: {
          adjustment_reason?: string | null
          category_id?: string | null
          correction_of_transaction_id?: string | null
          counterparty_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          deleted_at?: string | null
          description?: string | null
          duplicate_of_transaction_id?: string | null
          exchange_rate?: number
          fingerprint?: string | null
          id?: string
          idempotency_key?: string | null
          memo?: string | null
          metadata?: Json
          organization_id?: string
          possible_duplicate?: boolean
          posted_at?: string | null
          posted_by?: string | null
          posting_date?: string | null
          reference?: string | null
          reversed_by_transaction_id?: string | null
          reverses_transaction_id?: string | null
          source?: Database["public"]["Enums"]["transaction_source"]
          status?: Database["public"]["Enums"]["transaction_status"]
          transaction_date?: string
          type?: Database["public"]["Enums"]["transaction_type"]
          updated_at?: string
          voided_at?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "transactions_category_same_org"
            columns: ["category_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_correction_of_same_org"
            columns: ["correction_of_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_correction_of_same_org"
            columns: ["correction_of_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_counterparty_same_org"
            columns: ["counterparty_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "counterparties"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "transactions_duplicate_of_same_org"
            columns: ["duplicate_of_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_duplicate_of_same_org"
            columns: ["duplicate_of_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_posted_by_fkey"
            columns: ["posted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_reversed_by_same_org"
            columns: ["reversed_by_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_reversed_by_same_org"
            columns: ["reversed_by_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_reverses_same_org"
            columns: ["reverses_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_reverses_same_org"
            columns: ["reverses_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_voided_by_fkey"
            columns: ["voided_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      account_balances: {
        Row: {
          account_id: string | null
          balance_minor: number | null
          code: string | null
          credit_minor: number | null
          currency: string | null
          debit_minor: number | null
          entry_count: number | null
          is_archived: boolean | null
          is_liquid: boolean | null
          name: string | null
          normal_balance: Database["public"]["Enums"]["normal_balance"] | null
          organization_id: string | null
          parent_account_id: string | null
          subtype: Database["public"]["Enums"]["account_subtype"] | null
          type: Database["public"]["Enums"]["account_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "accounts_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "accounts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounts_parent_same_org"
            columns: ["parent_account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "account_balances"
            referencedColumns: ["account_id", "organization_id"]
          },
          {
            foreignKeyName: "accounts_parent_same_org"
            columns: ["parent_account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      ledger_entries: {
        Row: {
          account_code: string | null
          account_id: string | null
          account_name: string | null
          account_type: Database["public"]["Enums"]["account_type"] | null
          amount_minor: number | null
          base_amount_minor: number | null
          base_currency_code: string | null
          category_id: string | null
          counterparty_id: string | null
          created_by: string | null
          currency_code: string | null
          description: string | null
          entry_date: string | null
          entry_id: string | null
          exchange_rate: number | null
          memo: string | null
          organization_id: string | null
          posted_at: string | null
          reference: string | null
          side: Database["public"]["Enums"]["entry_side"] | null
          transaction_id: string | null
          transaction_status:
            | Database["public"]["Enums"]["transaction_status"]
            | null
          transaction_type:
            | Database["public"]["Enums"]["transaction_type"]
            | null
        }
        Relationships: [
          {
            foreignKeyName: "transaction_entries_account_same_org"
            columns: ["account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "account_balances"
            referencedColumns: ["account_id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_entries_account_same_org"
            columns: ["account_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_entries_base_currency_code_fkey"
            columns: ["base_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "transaction_entries_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "transaction_entries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_entries_transaction_same_org"
            columns: ["transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transaction_entries_transaction_same_org"
            columns: ["transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      transaction_summaries: {
        Row: {
          adjustment_reason: string | null
          amount_minor: number | null
          attachment_count: number | null
          base_amount_minor: number | null
          category_id: string | null
          category_name: string | null
          counterparty_id: string | null
          counterparty_name: string | null
          created_at: string | null
          created_by: string | null
          created_by_email: string | null
          created_by_name: string | null
          currency_code: string | null
          description: string | null
          exchange_rate: number | null
          from_account_id: string | null
          from_account_name: string | null
          id: string | null
          line_count: number | null
          memo: string | null
          organization_id: string | null
          possible_duplicate: boolean | null
          posted_at: string | null
          posted_by: string | null
          posting_date: string | null
          reference: string | null
          reversed_by_transaction_id: string | null
          reverses_transaction_id: string | null
          source: Database["public"]["Enums"]["transaction_source"] | null
          status: Database["public"]["Enums"]["transaction_status"] | null
          tag_ids: string[] | null
          tags: string[] | null
          to_account_id: string | null
          to_account_name: string | null
          transaction_date: string | null
          type: Database["public"]["Enums"]["transaction_type"] | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "transactions_category_same_org"
            columns: ["category_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_counterparty_same_org"
            columns: ["counterparty_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "counterparties"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "transactions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_posted_by_fkey"
            columns: ["posted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_reversed_by_same_org"
            columns: ["reversed_by_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_reversed_by_same_org"
            columns: ["reversed_by_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_reverses_same_org"
            columns: ["reverses_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transaction_summaries"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "transactions_reverses_same_org"
            columns: ["reverses_transaction_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
    }
    Functions: {
      can_use_feature: {
        Args: { p_feature_key: string; p_organization_id: string }
        Returns: boolean
      }
      check_balance_sheet_integrity: {
        Args: { p_as_of_date?: string; p_organization_id: string }
        Returns: Json
      }
      create_adjustment: {
        Args: {
          p_currency_code?: string
          p_description: string
          p_exchange_rate?: number
          p_idempotency_key?: string
          p_lines: Json
          p_organization_id: string
          p_reason: string
          p_transaction_date: string
        }
        Returns: string
      }
      create_draft_transaction: {
        Args: {
          p_adjustment_reason?: string
          p_category_id?: string
          p_counterparty_id?: string
          p_currency_code?: string
          p_description?: string
          p_exchange_rate?: number
          p_idempotency_key?: string
          p_lines: Json
          p_memo?: string
          p_metadata?: Json
          p_organization_id: string
          p_reference?: string
          p_source?: Database["public"]["Enums"]["transaction_source"]
          p_transaction_date: string
          p_type: Database["public"]["Enums"]["transaction_type"]
        }
        Returns: string
      }
      create_organization: {
        Args: {
          p_base_currency?: string
          p_country_code?: string
          p_fiscal_year_start_month?: number
          p_legal_name?: string
          p_name: string
          p_timezone?: string
        }
        Returns: string
      }
      dashboard_summary: {
        Args: { p_as_of_date?: string; p_organization_id: string }
        Returns: Json
      }
      get_limit: {
        Args: { p_limit_key: string; p_organization_id: string }
        Returns: number
      }
      my_capabilities: {
        Args: { p_organization_id: string }
        Returns: string[]
      }
      post_opening_balance: {
        Args: {
          p_as_of_date: string
          p_balances: Json
          p_idempotency_key?: string
          p_notes?: string
          p_organization_id: string
        }
        Returns: string
      }
      post_transaction: { Args: { p_transaction_id: string }; Returns: string }
      record_asset_purchase: {
        Args: {
          p_amount_minor: number
          p_asset_account_id: string
          p_counterparty_id?: string
          p_description?: string
          p_exchange_rate?: number
          p_idempotency_key?: string
          p_organization_id: string
          p_payment_account_id: string
          p_reference?: string
          p_transaction_date?: string
          p_useful_life_months?: number
        }
        Returns: string
      }
      record_expense: {
        Args: {
          p_amount_minor: number
          p_category_id?: string
          p_counterparty_id?: string
          p_currency_code?: string
          p_description?: string
          p_exchange_rate?: number
          p_expense_account_id?: string
          p_idempotency_key?: string
          p_organization_id: string
          p_reference?: string
          p_source_account_id: string
          p_transaction_date?: string
        }
        Returns: string
      }
      record_income: {
        Args: {
          p_amount_minor: number
          p_category_id?: string
          p_counterparty_id?: string
          p_currency_code?: string
          p_description?: string
          p_destination_account_id: string
          p_exchange_rate?: number
          p_idempotency_key?: string
          p_organization_id: string
          p_reference?: string
          p_revenue_account_id?: string
          p_transaction_date?: string
        }
        Returns: string
      }
      record_liability_created: {
        Args: {
          p_amount_minor: number
          p_counterparty_id?: string
          p_description?: string
          p_destination_account_id: string
          p_due_date?: string
          p_exchange_rate?: number
          p_idempotency_key?: string
          p_liability_account_id: string
          p_organization_id: string
          p_reference?: string
          p_transaction_date?: string
        }
        Returns: string
      }
      record_liability_payment: {
        Args: {
          p_counterparty_id?: string
          p_description?: string
          p_exchange_rate?: number
          p_fee_account_id?: string
          p_fees_minor?: number
          p_idempotency_key?: string
          p_interest_account_id?: string
          p_interest_minor?: number
          p_liability_account_id: string
          p_organization_id: string
          p_payment_account_id: string
          p_principal_minor: number
          p_reference?: string
          p_transaction_date?: string
        }
        Returns: string
      }
      record_owner_contribution: {
        Args: {
          p_amount_minor: number
          p_description?: string
          p_destination_account_id: string
          p_equity_account_id?: string
          p_exchange_rate?: number
          p_idempotency_key?: string
          p_organization_id: string
          p_reference?: string
          p_transaction_date?: string
        }
        Returns: string
      }
      record_owner_withdrawal: {
        Args: {
          p_amount_minor: number
          p_description?: string
          p_drawings_account_id?: string
          p_exchange_rate?: number
          p_idempotency_key?: string
          p_organization_id: string
          p_reference?: string
          p_source_account_id: string
          p_transaction_date?: string
        }
        Returns: string
      }
      record_transfer: {
        Args: {
          p_amount_minor: number
          p_description?: string
          p_destination_amount_minor?: number
          p_destination_exchange_rate?: number
          p_exchange_rate?: number
          p_fee_account_id?: string
          p_fee_minor?: number
          p_from_account_id: string
          p_idempotency_key?: string
          p_organization_id: string
          p_reference?: string
          p_to_account_id: string
          p_transaction_date?: string
        }
        Returns: string
      }
      report_balance_sheet: {
        Args: { p_as_of_date?: string; p_organization_id: string }
        Returns: {
          account_id: string
          amount_minor: number
          code: string
          name: string
          section: string
        }[]
      }
      report_cash_flow: {
        Args: {
          p_from_date: string
          p_organization_id: string
          p_to_date: string
        }
        Returns: {
          amount_minor: number
          section: Database["public"]["Enums"]["cash_flow_section"]
        }[]
      }
      report_general_ledger: {
        Args: {
          p_account_id: string
          p_from_date: string
          p_organization_id: string
          p_to_date: string
        }
        Returns: {
          credit_minor: number
          debit_minor: number
          description: string
          entry_date: string
          entry_id: string
          memo: string
          reference: string
          running_balance_minor: number
          transaction_id: string
        }[]
      }
      report_monthly_series: {
        Args: {
          p_as_of_date?: string
          p_months?: number
          p_organization_id: string
        }
        Returns: {
          expense_minor: number
          month: string
          net_minor: number
          revenue_minor: number
        }[]
      }
      report_profit_and_loss: {
        Args: {
          p_from_date: string
          p_organization_id: string
          p_to_date: string
        }
        Returns: {
          account_id: string
          amount_minor: number
          code: string
          name: string
          section: string
        }[]
      }
      report_trial_balance: {
        Args: { p_as_of_date?: string; p_organization_id: string }
        Returns: {
          account_id: string
          code: string
          credit_minor: number
          debit_minor: number
          name: string
          type: Database["public"]["Enums"]["account_type"]
        }[]
      }
      reverse_transaction: {
        Args: {
          p_reason: string
          p_reversal_date?: string
          p_transaction_id: string
        }
        Returns: string
      }
      search_transactions: {
        Args: {
          p_account_ids?: string[]
          p_category_ids?: string[]
          p_counterparty_ids?: string[]
          p_created_by_ids?: string[]
          p_direction?: string
          p_from_date?: string
          p_limit?: number
          p_max_amount_minor?: number
          p_min_amount_minor?: number
          p_offset?: number
          p_organization_id: string
          p_search?: string
          p_sort?: string
          p_statuses?: Database["public"]["Enums"]["transaction_status"][]
          p_tag_ids?: string[]
          p_to_date?: string
          p_types?: Database["public"]["Enums"]["transaction_type"][]
        }
        Returns: {
          amount_minor: number
          attachment_count: number
          base_amount_minor: number
          category_name: string
          counterparty_name: string
          created_by_name: string
          currency_code: string
          description: string
          from_account_name: string
          id: string
          possible_duplicate: boolean
          reference: string
          reversed_by_transaction_id: string
          status: Database["public"]["Enums"]["transaction_status"]
          tags: string[]
          to_account_name: string
          total_count: number
          transaction_date: string
          type: Database["public"]["Enums"]["transaction_type"]
        }[]
      }
      void_transaction: {
        Args: { p_reason?: string; p_transaction_id: string }
        Returns: string
      }
    }
    Enums: {
      account_subtype:
        | "cash"
        | "bank"
        | "mobile_wallet"
        | "accounts_receivable"
        | "inventory"
        | "prepaid_expenses"
        | "equipment"
        | "vehicles"
        | "property"
        | "other_asset"
        | "accounts_payable"
        | "credit_card"
        | "loan"
        | "taxes_payable"
        | "accrued_expenses"
        | "other_liability"
        | "owner_capital"
        | "retained_earnings"
        | "owner_drawings"
        | "opening_balance_equity"
        | "other_equity"
        | "product_sales"
        | "service_revenue"
        | "commission"
        | "other_income"
        | "cost_of_sales"
        | "salaries"
        | "rent"
        | "utilities"
        | "marketing"
        | "transportation"
        | "software"
        | "professional_fees"
        | "bank_fees"
        | "interest_expense"
        | "depreciation"
        | "taxes"
        | "other_expense"
      account_type: "asset" | "liability" | "equity" | "revenue" | "expense"
      billing_interval: "monthly" | "yearly"
      billing_status:
        | "trialing"
        | "active"
        | "past_due"
        | "grace_period"
        | "suspended"
        | "cancelled"
      cash_flow_section: "operating" | "investing" | "financing" | "none"
      category_kind: "income" | "expense" | "asset" | "liability" | "other"
      counterparty_type:
        | "customer"
        | "vendor"
        | "lender"
        | "employee"
        | "government"
        | "other"
      entry_side: "debit" | "credit"
      invitation_status: "pending" | "accepted" | "revoked" | "expired"
      membership_status: "active" | "suspended"
      normal_balance: "debit" | "credit"
      organization_role:
        | "owner"
        | "admin"
        | "accountant"
        | "data_entry"
        | "viewer"
      organization_status:
        | "trial"
        | "active"
        | "past_due"
        | "suspended"
        | "cancelled"
        | "archived"
      saved_view_visibility: "private" | "organization"
      transaction_source:
        | "manual"
        | "import"
        | "recurring"
        | "commitment"
        | "reversal"
        | "opening_balance"
        | "api"
      transaction_status:
        | "draft"
        | "scheduled"
        | "pending"
        | "pending_approval"
        | "posted"
        | "voided"
        | "reversed"
        | "failed"
      transaction_type:
        | "income"
        | "expense"
        | "transfer"
        | "asset_purchase"
        | "liability_created"
        | "liability_payment"
        | "owner_contribution"
        | "owner_withdrawal"
        | "adjustment"
        | "opening_balance"
        | "reversal"
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
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      account_subtype: [
        "cash",
        "bank",
        "mobile_wallet",
        "accounts_receivable",
        "inventory",
        "prepaid_expenses",
        "equipment",
        "vehicles",
        "property",
        "other_asset",
        "accounts_payable",
        "credit_card",
        "loan",
        "taxes_payable",
        "accrued_expenses",
        "other_liability",
        "owner_capital",
        "retained_earnings",
        "owner_drawings",
        "opening_balance_equity",
        "other_equity",
        "product_sales",
        "service_revenue",
        "commission",
        "other_income",
        "cost_of_sales",
        "salaries",
        "rent",
        "utilities",
        "marketing",
        "transportation",
        "software",
        "professional_fees",
        "bank_fees",
        "interest_expense",
        "depreciation",
        "taxes",
        "other_expense",
      ],
      account_type: ["asset", "liability", "equity", "revenue", "expense"],
      billing_interval: ["monthly", "yearly"],
      billing_status: [
        "trialing",
        "active",
        "past_due",
        "grace_period",
        "suspended",
        "cancelled",
      ],
      cash_flow_section: ["operating", "investing", "financing", "none"],
      category_kind: ["income", "expense", "asset", "liability", "other"],
      counterparty_type: [
        "customer",
        "vendor",
        "lender",
        "employee",
        "government",
        "other",
      ],
      entry_side: ["debit", "credit"],
      invitation_status: ["pending", "accepted", "revoked", "expired"],
      membership_status: ["active", "suspended"],
      normal_balance: ["debit", "credit"],
      organization_role: [
        "owner",
        "admin",
        "accountant",
        "data_entry",
        "viewer",
      ],
      organization_status: [
        "trial",
        "active",
        "past_due",
        "suspended",
        "cancelled",
        "archived",
      ],
      saved_view_visibility: ["private", "organization"],
      transaction_source: [
        "manual",
        "import",
        "recurring",
        "commitment",
        "reversal",
        "opening_balance",
        "api",
      ],
      transaction_status: [
        "draft",
        "scheduled",
        "pending",
        "pending_approval",
        "posted",
        "voided",
        "reversed",
        "failed",
      ],
      transaction_type: [
        "income",
        "expense",
        "transfer",
        "asset_purchase",
        "liability_created",
        "liability_payment",
        "owner_contribution",
        "owner_withdrawal",
        "adjustment",
        "opening_balance",
        "reversal",
      ],
    },
  },
} as const

