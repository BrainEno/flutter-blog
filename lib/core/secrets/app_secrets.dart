class AppSecrets {
  static String? get supabaseUrl => String.fromEnvironment('SUPABASE_URL');
  static String? get supabaseKey => String.fromEnvironment('SUPABASE_KEY');
}
