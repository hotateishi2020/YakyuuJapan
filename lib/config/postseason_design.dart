import 'package:flutter/material.dart';

const japanSeriesLabel = '日本シリーズ';
const japanSeriesHeaderColor = Color(0xFF004832);

const npbPostseasonGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [
    Color(0xFF8CFAF7), Color(0xFF2BCFAD), Color(0xFF14C4C0),
    Color(0xFF5AD8EA), Color(0xFF1E6FE0), Color(0xFF1F52EB),
  ],
  stops: [0.0, 0.22, 0.38, 0.52, 0.75, 1.0],
);

const mlbPostseasonGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [
    Color(0xFFE91E63), Color(0xFFD81B60), Color(0xFFAD1457),
    Color(0xFF5C6BC0), Color(0xFF283593), Color(0xFF0D1B4A),
  ],
  stops: [0.0, 0.18, 0.38, 0.62, 0.82, 1.0],
);
