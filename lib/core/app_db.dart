import 'package:supabase_flutter/supabase_flutter.dart';

/// Global Supabase client. Call after [SupabaseEnv.initializeRequired] in main.
SupabaseClient get appDb => Supabase.instance.client;
