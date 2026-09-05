import 'package:flutter/material.dart';

// 全体
const ALL_MARGIN_LEFT = 8.0;
const ALL_RATIO_BLOCK_H = [3, 11];
const ALL_RATIO_BLOCK_W = [5, 50, 75, 25];
final ALL_COLOR_APP = Colors.orange.shade200;
const ALL_SPACE_BLOCK = 5.0;
const ALL_CELL_RADIUS_MARGIN = 2.0;
const ALL_HEADER_H = 33.0;
double ALL_WIDTH = 0;

// 最上部ヘッダー
const HEADER_GLOBAL_H = 26.0;
const HEADER_PAD_VERTICAL = 5.0;
const HEADER_TITLE = 'Yakyuu! Japan';

// タブバー
const TAB_BAR_H = 26.0;
const TAB_PAD_HORIZONTAL = 15.0;
const TAB_PAD_VERTICAL = 2.0;
const TAB_RADIUS = 16.0;
const TAB_TITLES = ['侍', 'MLB', 'NPB', '2軍', '独立', '社会人', '大学', '高校'];
const TAB_COLOR_FONT = Colors.white;

// リーグサイドヘッダー
const LEAGUE_SIDEHEADER_W = 23;

// 予想ブロック
const PREDICTION_HEADER_PREDICTOR_W_PCT = 0.06;
const PREDICTION_HEADER_STANDINGS_W = 56;
final PREDICTION_HEADER_PREDICTOR_W = ALL_WIDTH * PREDICTION_HEADER_PREDICTOR_W_PCT;
final PREDICTION_BLOCK_W = LEAGUE_SIDEHEADER_W + PREDICTION_HEADER_STANDINGS_W + ((ALL_WIDTH * PREDICTION_HEADER_PREDICTOR_W_PCT) * 3);

// 個人成績
const STATS_PLAYER_RATIO_CELL_BLOCK_W = [1, 1, 5, 2];
