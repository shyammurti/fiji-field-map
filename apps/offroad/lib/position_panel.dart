import 'package:material_ui/material_ui.dart';
import 'package:offroad_core/position.dart';

const statusText = {
  FixStatus.idle: 'Location off',
  FixStatus.searching: 'Searching for a fix',
  FixStatus.live: 'Live position',
  FixStatus.manual: 'Manual position',
  FixStatus.stale: 'Last fix is stale',
  FixStatus.lost: 'GPS signal lost',
  FixStatus.disabled: 'Device location disabled',
  FixStatus.denied: 'Permission denied',
  FixStatus.blocked: 'Permission blocked',
  FixStatus.unavailable: 'Location unavailable',
};

class PositionPanel extends StatelessWidget {
  const PositionPanel({
    super.key,
    required this.state,
    required this.desktop,
    required this.wide,
    required this.picking,
    required this.onLocate,
    required this.onManual,
    required this.onSettings,
    required this.onStop,
  });
  final PositionState state;
  final bool desktop, wide, picking;
  final VoidCallback onLocate, onManual, onSettings, onStop;

  String _value(double? v, String unit, [int decimals = 0]) =>
      v == null ? '—' : '${v.toStringAsFixed(decimals)} $unit';

  @override
  Widget build(BuildContext context) {
    final fix = state.fix;
    final active = {
      FixStatus.live,
      FixStatus.stale,
      FixStatus.searching,
    }.contains(state.status);
    final last =
        state.status != FixStatus.live && state.status != FixStatus.manual;
    final colors = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant);
    final metrics = {
      'Speed': _value(fix?.speed == null ? null : fix!.speed! * 3.6, 'km/h', 1),
      'Altitude': _value(fix?.altitude, 'm'),
      'Accuracy': _value(fix?.accuracy, 'm'),
      'Heading': state.compass != null
          ? '${state.compass!.round()}° mag.'
          : _value(fix?.course, '° course'),
    };
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 20 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                state.status == FixStatus.manual
                    ? Icons.place_outlined
                    : Icons.gps_fixed,
                size: 20,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText[state.status]!,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (fix != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: SelectableText(
                '${fix.lat.toStringAsFixed(5)}, ${fix.lon.toStringAsFixed(5)}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          if (last && fix != null)
            Text(
              'Last observed ${fix.time.toLocal().toIso8601String().split(".").first.replaceFirst("T", " ")}',
              style: labelStyle,
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              FilledButton.icon(
                onPressed: active ? onStop : onLocate,
                icon: Icon(
                  active ? Icons.stop_circle_outlined : Icons.my_location,
                  size: 18,
                ),
                label: Text(active ? 'Stop GPS' : 'Use device GPS'),
              ),
              if (desktop)
                OutlinedButton(
                  onPressed: onManual,
                  child: Text(picking ? 'Cancel' : 'Set on map'),
                ),
              if (state.status == FixStatus.disabled ||
                  state.status == FixStatus.blocked)
                OutlinedButton(
                  onPressed: onSettings,
                  child: const Text('Location settings'),
                ),
            ],
          ),
          if (wide)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
          if (state.status != FixStatus.idle || wide)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: wide ? 12 : 16,
                runSpacing: 14,
                children: [
                  for (final m in metrics.entries)
                    SizedBox(
                      width: wide ? 104 : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.key, style: labelStyle),
                          Text(
                            m.value,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
