import '../models/expense.dart';

/// Turns expenses into a spreadsheet-ready CSV, newest first.
///
/// Excel and Google Sheets both open this directly. Fields are quoted and inner
/// quotes doubled, so a note containing a comma or a quote cannot break a row.
String expensesToCsv(List<Expense> expenses) {
  String cell(Object? value) {
    final text = '$value';
    if (text.contains(RegExp('[",\n\r]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  final rows = <String>['Date,Item,Category,Amount,Note'];
  for (final expense in expenses) {
    rows.add(
      [
        cell(date(expense.date)),
        cell(expense.item),
        cell(expense.category.label),
        // Unformatted so a spreadsheet reads it as a number.
        cell(expense.amount.toStringAsFixed(2)),
        cell(expense.note),
      ].join(','),
    );
  }
  return rows.join('\n');
}
