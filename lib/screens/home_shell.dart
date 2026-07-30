import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../widgets/entrance.dart';
import 'dashboard_screen.dart';
import 'expense_editor_sheet.dart';
import 'expenses_screen.dart';
import 'insights_screen.dart';

/// Lets a card deep-link to another tab ("See all" -> Expenses).
typedef TabOpener = void Function(int index);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _open(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkMode
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: viz.surface,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: viz.surface,
            ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              ScreenIntro(child: DashboardScreen(onOpenTab: _open)),
              const ScreenIntro(child: InsightsScreen()),
              const ExpensesScreen(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => ExpenseEditorSheet.show(context),
          backgroundColor: viz.series,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          tooltip: 'Add expense',
          child: const Icon(Icons.add_rounded, size: 28),
        ),
        bottomNavigationBar: _BottomBar(index: _index, onChanged: _open),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (icon: Icons.pie_chart_rounded, label: 'Overview'),
    (icon: Icons.insights_rounded, label: 'Insights'),
    (icon: Icons.receipt_long_rounded, label: 'Expenses'),
  ];

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      decoration: BoxDecoration(
        color: viz.surface,
        border: Border(top: BorderSide(color: viz.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    key: ValueKey('nav_$i'),
                    icon: _items[i].icon,
                    label: _items[i].label,
                    selected: i == index,
                    onTap: () => onChanged(i),
                  ),
                ),
              // Keeps the row clear of the floating action button.
              const SizedBox(width: 64),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final color = selected ? viz.series : viz.inkMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.20 : 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
