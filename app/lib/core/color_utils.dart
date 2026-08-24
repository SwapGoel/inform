import 'package:flutter/material.dart';

/// Parses a "#RRGGBB" hex string (as published in theme.json) into a Color.
Color colorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}
