import 'package:supabase_flutter/supabase_flutter.dart';

/// Короткий доступ к единственному клиенту Supabase.
/// Инициализация — в main.dart через Supabase.initialize(...).
SupabaseClient get supabase => Supabase.instance.client;
