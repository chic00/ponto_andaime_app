// Vercel detecta automaticamente qualquer arquivo dentro de /api como uma
// função de backend — não precisa de nenhuma configuração extra.
// Ela lê as variáveis de ambiente (definidas no painel da Vercel, não aqui
// no código) e devolve pro app na hora em que ele carrega no navegador.
module.exports = (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({
    url: process.env.SUPABASE_URL || '',
    anonKey: process.env.SUPABASE_PUBLISHABLE_KEY || ''
  });
};
