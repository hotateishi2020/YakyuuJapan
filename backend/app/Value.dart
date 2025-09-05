class Value {
  static const SystemCode = _SystemCode();
}

class _SystemCode {
  const _SystemCode();

  final Log = const _Log();
  final Key = const _Key();
}

class _Key {
  const _Key();

  final String NPB = 'NPB';
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
