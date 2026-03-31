class DateCalculator {
  /// Recalcula datas a partir de uma nova data base, mantendo os offsets em dias.
  static DateTime applyOffset(DateTime baseDate, int offsetDays) {
    return baseDate.add(Duration(days: offsetDays));
  }

  /// Calcula offset em dias entre duas datas.
  static int calculateOffset(DateTime baseDate, DateTime targetDate) {
    return targetDate.difference(baseDate).inDays;
  }

  /// Recalcula uma lista de datas baseadas em offsets a partir de uma nova data base.
  static List<DateTime> recalculateAll(DateTime newBase, List<int> offsets) {
    return offsets.map((o) => applyOffset(newBase, o)).toList();
  }

  /// Converte serial number do Excel (dias desde 1899-12-30) para DateTime.
  static DateTime fromExcelSerial(double serial) {
    final base = DateTime(1899, 12, 30);
    return base.add(Duration(days: serial.round()));
  }

  /// Converte DateTime para serial number do Excel.
  static double toExcelSerial(DateTime date) {
    final base = DateTime(1899, 12, 30);
    return date.difference(base).inDays.toDouble();
  }
}
