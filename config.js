/* TryTap public configuration.
   These two values are SAFE to be public: the anon/publishable key can only do what
   your Row Level Security policies allow (read published data). NEVER put the
   service_role / secret key here or anywhere in this project. */
window.TRYTAP_CONFIG = {
  SUPABASE_URL: 'https://iyszjzzqtckvbngdzkiu.supabase.co',
  SUPABASE_ANON_KEY: 'ap-northeast-1'
};
