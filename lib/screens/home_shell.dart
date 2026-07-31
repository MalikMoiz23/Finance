import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../state/expense_store.dart';
import '../widgets/entrance.dart';
import 'budgets_screen.dart';
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
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _open(int index) {
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    // A short slide between tabs reads as one surface moving, rather than
    // content being swapped underneath you.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Logs the most recent expense again, dated today.
  Future<void> _repeatLast() async {
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final last = store.mostRecent;
    if (last == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to repeat yet — add one first')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      await store.duplicate(last);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Added ${Money.format(last.amount)} · ${last.title} again',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
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
          child: PageView(
            controller: _pages,
            // Tabs are changed from the bar, not by swiping — a horizontal drag
            // inside a chart or a filter row should not change tab.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _Keep(
                child: ScreenIntro(child: DashboardScreen(onOpenTab: _open)),
              ),
              const _Keep(child: ScreenIntro(child: InsightsScreen())),
              const _Keep(child: ExpensesScreen()),
              const _Keep(child: ScreenIntro(child: BudgetsScreen())),
            ],
          ),
        ),
        // Long-press repeats the last expense outright — for the things bought
        // every day, that is the whole entry in one gesture.
        floatingActionButton: GestureDetector(
          onLongPress: _repeatLast,
          child: FloatingActionButton(
            onPressed: () => ExpenseEditorSheet.show(context),
            backgroundColor: viz.series,
            foregroundColor: Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            tooltip: 'Add expense · hold to repeat the last one',
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
        bottomNavigationBar: _BottomBar(index: _index, onChanged: _open),
      ),
    );
  }
}

/// Keeps a tab's state (scroll offset, search text) while another tab is shown.
class _Keep extends StatefulWidget {
  const _Keep({required this.child});

  final Widget child;

  @override
  State<_Keep> createState() => _KeepState();
}

class _KeepState extends State<_Keep> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
    (icon: Icons.savings_rounded, label: 'Budgets'),
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
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
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
            // The icon lifts slightly when its tab is active.
            AnimatedSlide(
              offset: Offset(0, selected ? -0.06 : 0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
