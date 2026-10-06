class Value {
  static const SystemCode = _SystemCode();
  static const CodeGameResult = _CodeGameResult();
  static const CodeGameResultCategory = _CodeGameResultCategory();
  static const CodeStateScore = _CodeStateScore();
  static const CodePosition = _CodePosition();
  static const CodeGameResultPitcher = _CodeGameResultPitcher();
}

class _CodeGameResultPitcher {
  const _CodeGameResultPitcher();

  final String WIN = 'WIN';
  final String LOSE = 'LOSE';
  final String HOLD = 'HOLD';
  final String SAVE = 'SAVE';
}

class _CodePosition {
  const _CodePosition();

  final String RF = 'RIGHT';
  final String LF = 'LEFT';
  final String CF = 'CENTER';
  final String FIRST = 'FIRST';
  final String SECOND = 'SECOND';
  final String THIRD = 'THIRD';
  final String SS = 'SS';
  final String C = 'C';
  final String P = 'P';
  final String DH = 'DH';
  final String OUT_FIELD = 'OUT_FIELD';
  final String IN_FIELD = 'IN_FIELD';
}

class _SystemCode {
  const _SystemCode();

  final Log = const _Log();
  final Key = const _Key();
  final Code = const _Code();
}

class _Code {
  const _Code();

  final String NPB = 'NPB';
  final String ADMIN = 'ADMIN';
}

class _Key {
  const _Key();

  final String NPB = 'NPB';
  final String DATE_FINAL_GAME = 'DATE_FINAL_GAME';
  final String DATE_OPEN_GAME = 'DATE_OPEN_GAME';
}

class _Log {
  const _Log();

  final Fetch = const _CategoryFetch();
  final Prediction = const _CategoryPrediction();
  final Error = const _CategoryError();
}

class _CategoryError {
  const _CategoryError();

  final String NAME = 'ERROR';
  final Codes = const _CodeError();
}

class _CodeError {
  const _CodeError();

  final String MAIL = 'ERROR_MAIL';
  final String DB = 'ERROR_DB';
  final String PROGRAM = 'ERROR_PROGRAM';
}

class _CategoryFetch {
  const _CategoryFetch();

  final String NAME = 'FETCH';
  final Codes = const _CodeFetch();
}

class _CodeFetch {
  const _CodeFetch();

  final String GAMES = 'FETCH_GAMES';
  final String STATS_PLAYER = 'FETCH_STATS_PLAYER';
  final String STATS_TEAM = 'FETCH_STATS_TEAM';
}

class _CategoryPrediction {
  const _CategoryPrediction();

  final String NAME = 'PREDICTION';
  final Codes = const _CodePrediction();
}

class _CodePrediction {
  const _CodePrediction();

  final String ENTER_NPB = 'ENTER_NPB';
}

class _CodeGameResultCategory {
  const _CodeGameResultCategory();

  final String BATTING = 'BATTING';
  final String PITCHING = 'PITCHING';
  final String RUNNING_BASE = 'RUNNING_BASE';
  final String CHANGE_PLAYER = 'CHANGE_PLAYER';
  final String CHANGE_POSITION = 'CHANGE_POSITION';
  final String INJURED = 'INJURED';
  final String EXIT = 'EXIT';
  final String ERROR = 'ERROR';
  final String OTHER = 'OTHER';
}

class _CodeGameResult {
  const _CodeGameResult();

  final String HIT_SINGLE = 'HIT1';
  final String HIT_DOUBLE = 'HIT2';
  final String HIT_TRIPLE = 'HIT3';
  final String HOME_RUN = 'HOMERUN';
  final String OUT_FLY = 'OUT_FLY';
  final String OUT_GROUND = 'OUT_GROUND';
  final String OUT_POP_UP = 'OUT_POP_UP';
  final String OUT_DOUBLE_PLAY = 'OUT_DOUBLE_PLAY';
  final String OUT_LINE_DRIVE = 'OUT_LINE_DRIVE';
  final String SACRIFICE_BUNT = 'SACRIFICE_BUNT';
  final String SACRIFICE_FLY = 'SACRIFICE_FLY';
  final String SQUEEZE = 'SQUEEZE';
  final String STRIKE_OUT = 'STRIKE_OUT';
  final String DROPPED_THIRD = 'DROPPED_THIRD';
  final String WALK_ERROR = 'ERROR';
  final String WALK_BALL = 'WALK';
  final String WALK_DEAD = 'WALK_DEAD';
  final String STEAL_BASE_SAFE = 'STEAL_BASE_SAFE';
  final String STEAL_BASE_OUT = 'STEAL_BASE_OUT';
  final String RUN_DEAD = 'RUN_DEAD';
  final String PINCH_RUNNER = 'PINCH_RUNNER';
  final String PINCH_HITTER = 'PINCH_HITTER';
  final String PINCH_FIELDER = 'PINCH_FIELDER';
  final String ERROR_FIELDING = 'ERROR_FIELDING';
  final String WILD_PITCH = 'WILD_PITCH';
  final String PASS_BALL = 'PASS_BALL';
  final String INTERFERENCE_BATTING = 'INTERFERENCE_BATTING';
  final String INTERFERENCE_RUNNING = 'INTERFERENCE_RUNNING';
  final String INTERFERENCE_FIELDING = 'INTERFERENCE_FIELDING';
  final String FIELDERS_CHOICE = 'FIELDERS_CHOICE';
  final String CHANGE_POSITION = 'CHANGE_POSITION';
  final String CHANGE_PITCHER = 'CHANGE_PITCHER';
  final String EXIT = 'EXIT';
}

class _CodeStateScore {
  const _CodeStateScore();

  final String FIRST = 'FIRST';
  final String TIE = 'TIE';
  final String REVERSE = 'REVERSE';
  final String GO_AHEAD = 'GO_AHEAD';
  final String DECISIVE = 'DECISIVE';
}
