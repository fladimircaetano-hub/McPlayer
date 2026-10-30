/// Regras de conteúdo adulto compartilhadas por TV ao vivo, Filmes e Séries.
///
/// O agrupamento é feito no NOME DA CATEGORIA do provedor (não no nome do
/// filme/canal), para não bloquear títulos comuns por engano — ex.: "Hot
/// Bird", "Essex" ou "Sex Education" não são conteúdo adulto.
///
/// As categorias adultas são renomeadas para `Adulto | <categoria original>`.
/// Com isso a árvore de categorias já existente (`buildCategoryTree`) mostra
/// um único pai "Adulto" e, ao entrar nele, as subcategorias originais.
library;

/// Nome do grupo único exibido nas três abas.
const String adultGroupName = 'Adulto';

/// Prefixo aplicado à categoria original: "Adulto | XXX".
const String adultCategoryPrefix = '$adultGroupName | ';

/// Minúsculas e sem acentos, para comparar categorias de provedores
/// diferentes ("Pornô", "PORNO", "Pôrno").
String foldForMatch(String value) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final index = from.indexOf(ch);
    buffer.write(index >= 0 ? to[index] : ch);
  }
  return buffer.toString();
}

/// Palavras que identificam categoria adulta. Usa limites de palavra para
/// não casar "Essex" (sex) nem "Hotel" (hot).
final RegExp _adultWords = RegExp(
  r'(^|[^a-z0-9])'
  r'(adulto|adultos|adulta|adult|xxx|x{3,}|porno|pornos|pornografia|porn|'
  r'erotico|eroticos|erotica|eroticas|erotismo|sexo|sex|sexy|sensual|'
  r'sensuais|hentai|brazzers|playboy|onlyfans|fetish|fetiche|taboo|putaria)'
  r'([^a-z0-9]|$)',
);

/// Faixa etária explícita: "+18", "18+", "18 anos", "18 e +".
final RegExp _ageRating = RegExp(
  r'(\+ ?18\b|\b18 ?\+|\b18 ?anos\b|\b18 ?e ?\+)',
);

/// Títulos que contêm palavras da lista mas NÃO são conteúdo adulto.
final RegExp _exceptions = RegExp(
  r'adult swim|sex education|sex and the city|sex/life',
);

/// A categoria (bruta ou já agrupada) é adulta?
bool isAdultCategoryName(String raw) {
  final text = foldForMatch(raw).trim();
  if (text.isEmpty) return false;
  if (_exceptions.hasMatch(text)) return false;
  return _adultWords.hasMatch(text) || _ageRating.hasMatch(text);
}

/// Já está no formato "Adulto | ..."?
bool isGroupedAdultCategory(String category) =>
    foldForMatch(category).trimLeft().startsWith('adulto |');

/// Nome exibido no agrupamento. Idempotente: não duplica o prefixo.
String groupedAdultCategory(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return adultGroupName;
  if (isGroupedAdultCategory(name)) return name;
  return '$adultCategoryPrefix$name';
}

/// Categoria que pertence ao grupo adulto (já agrupada ou ainda bruta).
bool isAdultCategory(String category) =>
    isGroupedAdultCategory(category) || isAdultCategoryName(category);

/// Nome curto para exibir no cartão/overlay: remove o prefixo "Adulto | ".
String displayCategoryName(String category) {
  final name = category.trim();
  if (isGroupedAdultCategory(name)) {
    final start = name.indexOf('|');
    if (start >= 0) return name.substring(start + 1).trim();
  }
  return name;
}
