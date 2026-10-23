/* Configuração pública do dashboard.
 * A chave abaixo é a chave ANON (pública) do Supabase. Ela não dá acesso de
 * administrador: o RLS + a tabela public.admins controlam o que pode ser feito.
 * NUNCA coloque a service_role key aqui.
 */
window.DASHBOARD_CONFIG = {
  supabaseUrl: 'https://pfpmizermpxhwaekoylq.supabase.co',
  supabaseAnonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBmcG1pemVybXB4aHdhZWtveWxxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyNDk3ODIsImV4cCI6MjEwNDgyNTc4Mn0.Bu9cr3bhTFhc92Ilbz0UVWEPiD55Yi3TBU2VvI_sw70',
  auditPageSize: 500,
  pollIntervalMs: 20000
};
