import 'package:intl/intl.dart';

// Resolve macros de data em textos.
//
// O número somado é sempre em DIAS.
//
// Macros suportadas (sem sufixo = data da seção):
//   <DD/MM/YYYY>       -> data completa (ex.: 19/10/2025)
//   <DD/MM/YYYY + 30>  -> data + 30 dias
//   <DD/MM/YYYY - 5>   -> data - 5 dias
//   <DD>               -> dia com zero à esquerda (ex.: 05, 19)
//   <DD + 9>           -> dia após somar 9 dias, com zero (ex.: 28)
//   <D>                -> dia sem zero (ex.: 5, 19)
//   <D + 9>            -> dia após somar 9 dias, sem zero
//   <MM>               -> mês com zero (ex.: 06)
//   <MM + 30>          -> mês da data após somar 30 dias
//   <M>                -> mês sem zero (ex.: 6)
//   <M + 30>           -> mês da data após somar 30 dias, sem zero
//   <YYYY>             -> ano (ex.: 2025)
//   <YYYY + 365>       -> ano da data após somar 365 dias
//
// Com sufixo AI = data de início da atividade:
//   <DD>AI, <DD/MM/YYYY>AI, <MM>AI, etc.
//
// Com sufixo AF = data de fim da atividade:
//   <DD>AF, <DD/MM/YYYY>AF, <MM>AF, etc.
class MacroResolver {
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static final _pattern = RegExp(
      r'<(DD/MM/YYYY|DD|D|MM|M|YYYY)\s*([+-]\s*\d+)?>(AI|AF)?',
      caseSensitive: false);

  // Retorna [text] com todas as macros resolvidas.
  // [baseDate] é a data base (semesterStart).
  // [contextDate] é a data de referência da seção (se fornecida, usa como ref padrão).
  // [activityOpenDate] e [activityCloseDate] são usados com sufixos AI e AF.
  static String resolve(String text, DateTime baseDate,
      [DateTime? contextDate,
      DateTime? activityOpenDate,
      DateTime? activityCloseDate]) {
    final sectionRef = contextDate ?? baseDate;
    return text.replaceAllMapped(_pattern, (m) {
      final token = m.group(1)!.toUpperCase();
      final offsetStr = m.group(2);
      final suffix = m.group(3)?.toUpperCase();
      final offset =
          offsetStr != null ? int.parse(offsetStr.replaceAll(' ', '')) : 0;

      // Escolher a data base conforme o sufixo
      DateTime? ref;
      if (suffix == 'AI') {
        ref = activityOpenDate;
      } else if (suffix == 'AF') {
        ref = activityCloseDate;
      } else {
        ref = sectionRef;
      }

      // Se a data não está disponível, manter o placeholder original
      if (ref == null) return m.group(0)!;

      final adjusted = ref.add(Duration(days: offset));

      switch (token) {
        case 'DD/MM/YYYY':
          return _dateFormat.format(adjusted);
        case 'DD':
          return adjusted.day.toString().padLeft(2, '0');
        case 'D':
          return adjusted.day.toString();
        case 'MM':
          return adjusted.month.toString().padLeft(2, '0');
        case 'M':
          return adjusted.month.toString();
        case 'YYYY':
          return adjusted.year.toString();
        default:
          return m.group(0)!;
      }
    });
  }
}
