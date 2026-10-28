const npbPostseasonCodes = {'CS1', 'CS2', 'CSF', 'CS', 'FS', 'NS', 'JS', 'SM', 'S1', 'S2'};

/// Number this game's homers after all earlier CS/Japan Series homers.
/// Keep inning, direction and encoded flags for the existing chip renderer.
String numberPostseasonHomers(String plays, int before) {
  var number = before;
  return plays.split(' ').map((part) {
    final bar = part.lastIndexOf('|');
    if (bar < 0 || part.substring(bar + 1).split('/').first != 'hr') return part;
    number++;
    var label = part.substring(0, bar);
    final inning = RegExp(r'^\d+回[表裏]').firstMatch(label)?.group(0) ?? '';
    label = label.substring(inning.length).replaceAll(RegExp(r'(?:PS)?\d+号'), '');
    return '${inning}PS$number号$label${part.substring(bar)}';
  }).join(' ');
}
