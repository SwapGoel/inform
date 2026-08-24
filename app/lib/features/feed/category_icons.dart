import 'package:flutter/material.dart';

/// Maps the iconName strings published in theme.json to Flutter's built-in
/// Material Icons — avoids bundling any custom icon assets at all.
IconData iconForName(String name) => switch (name) {
      'newspaper' => Icons.newspaper,
      'history_edu' => Icons.history_edu,
      'public' => Icons.public,
      'account_balance' => Icons.account_balance,
      'trending_up' => Icons.trending_up,
      'eco' => Icons.eco,
      'science' => Icons.science,
      'calculate' => Icons.calculate,
      _ => Icons.lightbulb_outline,
    };
