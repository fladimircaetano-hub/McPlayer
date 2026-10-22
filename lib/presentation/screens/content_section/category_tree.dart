import '../../../data/models/iptv_category.dart';

/// Separadores usados pelos provedores para hierarquia de categorias
/// (ex.: "Filmes | Lancamentos" => categoria "Filmes", subcategoria
/// "Lancamentos").
const categorySeparators = ['|', '»', '>', '•', '·'];

/// Divide o nome bruto da categoria em [pai, filho...]. Sem separador,
/// devolve só o próprio nome.
List<String> splitCategoryPath(String raw) {
  final trimmed = raw.trim();
  for (final sep in categorySeparators) {
    if (trimmed.contains(sep)) {
      final parts = trimmed
          .split(sep)
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length >= 2) return parts;
    }
  }
  return [trimmed];
}

/// Nome do agrupamento (primeiro nível) de uma categoria bruta.
String categoryParent(String raw) => splitCategoryPath(raw).first;

/// Rótulo da subcategoria, sem repetir o nome do pai.
String categorySubLabel(String raw) {
  final parts = splitCategoryPath(raw);
  return parts.length >= 2 ? parts.sublist(1).join(' » ') : parts.first;
}

/// Nó de categoria: um pai (ex.: "Filmes") e suas folhas (categorias
/// reais do provedor, ex.: "Filmes | Lancamentos").
class CategoryNode {
  final String name;
  final List<IptvCategory> leaves;

  const CategoryNode(this.name, this.leaves);

  int get count => leaves.fold(0, (sum, c) => sum + c.count);

  /// Tem subcategorias quando agrupa mais de uma folha ou quando a única
  /// folha tem um nome diferente do pai (ex.: só "Filmes | Ação").
  bool get hasSubs =>
      leaves.length > 1 || (leaves.length == 1 && leaves.first.name != name);

  bool get isFlat => leaves.length == 1 && leaves.first.name == name;
}

/// Agrupa as categorias do provedor por pai. Mantém a ordem alfabética
/// dos pais e das folhas para a navegação ficar previsível.
List<CategoryNode> buildCategoryTree(List<IptvCategory> cats) {
  final map = <String, List<IptvCategory>>{};
  for (final c in cats) {
    final parent = categoryParent(c.name);
    map.putIfAbsent(parent, () => []).add(c);
  }
  final nodes = map.entries
      .map((e) => CategoryNode(
            e.key,
            e.value..sort((a, b) => a.name.compareTo(b.name)),
          ))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return nodes;
}

/// Nó com esse nome (comparação sem diferenciar maiúsculas/minúsculas).
CategoryNode? findCategoryNode(List<CategoryNode> tree, String name) {
  final target = name.trim().toLowerCase();
  for (final node in tree) {
    if (node.name.trim().toLowerCase() == target) return node;
  }
  return null;
}
