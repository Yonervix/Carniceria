import { Injectable } from '@angular/core';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class SupabaseService {
  readonly client: SupabaseClient | null = environment.supabaseUrl
    ? createClient(environment.supabaseUrl, environment.supabaseAnonKey)
    : null;
}