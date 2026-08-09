import Foundation

/// Supabase project credentials. The publishable (anon) key is public by
/// design — it ships inside every client binary and grants nothing on its own;
/// row-level security on the server is the actual boundary. The service_role
/// key must never appear in this repo.
enum SupabaseConfig {
    static let url = URL(string: "https://dkjqbnuhwlzphucaazqd.supabase.co")!
    static let publishableKey = "sb_publishable_C-vnKjGWDfF75UqX39Gzbg_o8CeOXiA"
}
