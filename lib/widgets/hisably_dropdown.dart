import 'package:flutter/material.dart';

import '../theme/hisably_theme.dart';

class HisablyDropdownItem<T> {
  const HisablyDropdownItem({required this.value, required this.label, this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// Custom dropdown in the shadcn style (v0.6.8): a quiet outlined
/// trigger with a label above it, and a floating popover — soft border,
/// rounded corners, deep shadow, a check mark on the selected row —
/// that grows out of the field with a short fade/scale animation.
/// Replaces the stock Material dropdowns across the app.
class HisablyDropdown<T> extends StatefulWidget {
  const HisablyDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.hint = 'Select',
  });

  final String label;
  final T? value;
  final List<HisablyDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool enabled;
  final String hint;

  @override
  State<HisablyDropdown<T>> createState() => _HisablyDropdownState<T>();
}

class _HisablyDropdownState<T> extends State<HisablyDropdown<T>>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _triggerKey = GlobalKey();
  double _triggerWidth = 0;
  bool _flipUp = false;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  HisablyDropdownItem<T>? get _selected {
    for (final item in widget.items) {
      if (item.value == widget.value) return item;
    }
    return null;
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (_portal.isShowing) {
      _close();
      return;
    }
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _triggerWidth = box.size.width;
    final topLeft = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(context).size.height;
    final menuH = (widget.items.length * 44.0 + 8).clamp(0, 264.0);
    final spaceBelow = screenH - (topLeft.dy + box.size.height);
    _flipUp = spaceBelow < menuH + 24 && topLeft.dy > spaceBelow;
    setState(() {});
    _portal.show();
    _anim.forward(from: 0);
  }

  void _close() {
    _anim.reverse().whenComplete(() {
      if (mounted) _portal.hide();
    });
  }

  void _pick(HisablyDropdownItem<T> item) {
    widget.onChanged?.call(item.value);
    _close();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: HisablyColors.text,
            ),
          ),
          const SizedBox(height: 6),
          CompositedTransformTarget(
            link: _link,
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.45,
              child: Material(
                color: HisablyColors.input,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: _triggerKey,
                  onTap: widget.enabled ? _toggle : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _portal.isShowing
                            ? HisablyColors.textSecondary
                            : HisablyColors.border,
                      ),
                      boxShadow: _portal.isShowing
                          ? [
                              BoxShadow(
                                color:
                                    Colors.white.withValues(alpha: 0.07),
                                blurRadius: 0,
                                spreadRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        if (selected?.icon != null) ...[
                          Icon(selected!.icon,
                              size: 19, color: HisablyColors.textSecondary),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            selected?.label ?? widget.hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: selected != null
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected != null
                                  ? HisablyColors.text
                                  : HisablyColors.textTertiary,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: _portal.isShowing ? 0.5 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: HisablyColors.textSecondary,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _close,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor:
              _flipUp ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor:
              _flipUp ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, _flipUp ? -6 : 6),
          // NOTE: no Align wrapper here (v0.6.10 fix). An Align inside
          // the follower expands to the full overlay size, so in flip-up
          // mode the follower box became screen-sized and the menu was
          // anchored a full screen above the field.
          child: AnimatedBuilder(
              animation: _anim,
              builder: (context, child) {
                final t = Curves.easeOutCubic.transform(_anim.value);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (_flipUp ? 4 : -4) * (1 - t)),
                    child: Transform.scale(
                      scale: 0.97 + 0.03 * t,
                      alignment:
                          _flipUp ? Alignment.bottomCenter : Alignment.topCenter,
                      child: child,
                    ),
                  ),
                );
              },
              child: SizedBox(
                width: _triggerWidth,
                child: Material(
                  color: HisablyColors.elevated,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 18,
                  shadowColor: Colors.black.withValues(alpha: 0.55),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: HisablyColors.border),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 264),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final item in widget.items)
                            _itemRow(item),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ),
      ],
    );
  }

  Widget _itemRow(HisablyDropdownItem<T> item) {
    final isSelected = item.value == widget.value;
    return Material(
      color: isSelected ? HisablyColors.pressed : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _pick(item),
        borderRadius: BorderRadius.circular(8),
        splashColor: Colors.white.withValues(alpha: 0.06),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon,
                    size: 19,
                    color: isSelected
                        ? HisablyColors.text
                        : HisablyColors.textSecondary),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: HisablyColors.text,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_rounded,
                    size: 19, color: HisablyColors.text),
            ],
          ),
        ),
      ),
    );
  }
}
