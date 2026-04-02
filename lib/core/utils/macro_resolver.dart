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
    caseSensitive: false,
  );

  // Retorna [text] com todas as macros resolvidas.
  // [baseDate] é a data base (semesterStart).
  // [contextDate] é a data de referência da seção (se fornecida, usa como ref padrão).
  // [activityOpenDate] e [activityCloseDate] são usados com sufixos AI e AF.
  static String resolve(
    String text,
    DateTime baseDate, [
    DateTime? contextDate,
    DateTime? activityOpenDate,
    DateTime? activityCloseDate,
  ]) {
    final sectionRef = contextDate ?? baseDate;
    return text.replaceAllMapped(_pattern, (m) {
      final token = m.group(1)!.toUpperCase();
      final offsetStr = m.group(2);
      final suffix = m.group(3)?.toUpperCase();
      final offset = offsetStr != null
          ? int.parse(offsetStr.replaceAll(' ', ''))
          : 0;

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

  // ── Operação inversa: datas hardcoded → macros ──────────────────────────

  // Aceita dia/mês com 1 ou 2 dígitos e ano com 4 dígitos
  static final _dateReplacePattern = RegExp(r'\b(\d{1,2}/\d{1,2}/\d{4})\b');

  /// Substitui datas hardcoded (d/M/yyyy ou dd/MM/yyyy) no [text] por macros.
  ///
  /// Prioridade:
  ///  1. Se a data é exatamente igual à [activityOpenDate] → `<DD/MM/YYYY>AI`
  ///  2. Se a data é exatamente igual à [activityCloseDate] → `<DD/MM/YYYY>AF`
  ///  3. Caso contrário, calcula o offset em dias a partir de [sectionRefDate]
  ///     e gera `<DD/MM/YYYY>`, `<DD/MM/YYYY + N>` ou `<DD/MM/YYYY - N>`.
  static String replaceDatesWithMacros(
    String text,
    DateTime sectionRefDate, {
    DateTime? activityOpenDate,
    DateTime? activityCloseDate,
  }) {
    return text.replaceAllMapped(_dateReplacePattern, (match) {
      final dateStr = match.group(1)!;
      final parsed = _tryParseDate(dateStr);
      if (parsed == null) return dateStr;

      // Prioridade 1: data exata de início da atividade (AI)
      if (activityOpenDate != null && _sameDay(parsed, activityOpenDate)) {
        return '<DD/MM/YYYY>AI';
      }

      // Prioridade 2: data exata de fim da atividade (AF)
      if (activityCloseDate != null && _sameDay(parsed, activityCloseDate)) {
        return '<DD/MM/YYYY>AF';
      }

      // Prioridade 3: offset relativo à data de referência da seção
      final refNormalized = DateTime(
        sectionRefDate.year,
        sectionRefDate.month,
        sectionRefDate.day,
      );
      final offset = parsed.difference(refNormalized).inDays;
      if (offset == 0) {
        return '<DD/MM/YYYY>';
      } else if (offset > 0) {
        return '<DD/MM/YYYY + $offset>';
      } else {
        return '<DD/MM/YYYY - ${offset.abs()}>';
      }
    });
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Tenta parsear data nos formatos dd/MM/yyyy, d/M/yyyy e variações.
  static DateTime? _tryParseDate(String text) {
    final parts = text.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (day < 1 || day > 31 || month < 1 || month > 12 || year < 1900) {
      return null;
    }
    return DateTime(year, month, day);
  }
}
