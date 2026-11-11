import 'line_break_data.dart';

final Map<String, int> _ids = {
  for (var i = 0; i < lineBreakClassNames.length; i++)
    lineBreakClassNames[i]: i,
};

int _id(String name) => _ids[name]!;

final int _bk = _id('BK');
final int _cr = _id('CR');
final int _lf = _id('LF');
final int _cm = _id('CM');
final int _nl = _id('NL');
final int _sg = _id('SG');
final int _wj = _id('WJ');
final int _zw = _id('ZW');
final int _gl = _id('GL');
final int _sp = _id('SP');
final int _zwj = _id('ZWJ');
final int _b2 = _id('B2');
final int _ba = _id('BA');
final int _bb = _id('BB');
final int _hy = _id('HY');
final int _cb = _id('CB');
final int _cl = _id('CL');
final int _cp = _id('CP');
final int _ex = _id('EX');
final int _in = _id('IN');
final int _ns = _id('NS');
final int _op = _id('OP');
final int _qu = _id('QU');
final int _is = _id('IS');
final int _nu = _id('NU');
final int _po = _id('PO');
final int _pr = _id('PR');
final int _sy = _id('SY');
final int _ai = _id('AI');
final int _al = _id('AL');
final int _cj = _id('CJ');
final int _eb = _id('EB');
final int _em = _id('EM');
final int _h2 = _id('H2');
final int _h3 = _id('H3');
final int _hl = _id('HL');
final int _id_ = _id('ID');
final int _jl = _id('JL');
final int _jv = _id('JV');
final int _jt = _id('JT');
final int _ri = _id('RI');
final int _sa = _id('SA');
final int _xx = _id('XX');
final int _ak = _id('AK');
final int _ap = _id('AP');
final int _as = _id('AS');
final int _hh = _id('HH');
final int _vf = _id('VF');
final int _vi = _id('VI');

/// the line break class of [rune]
int _classOf(int rune) {
  var low = 0;
  var high = lineBreakStarts.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (rune < lineBreakStarts[middle]) {
      high = middle - 1;
    } else if (rune > lineBreakEnds[middle]) {
      low = middle + 1;
    } else {
      return lineBreakKinds[middle];
    }
  }
  return _xx;
}

/// the quotation marks that open and close, which the rules treat as
/// brackets
bool _isInitialQuote(int r) =>
    r == 0xAB ||
    r == 0x2018 ||
    r == 0x201B ||
    r == 0x201C ||
    r == 0x201F ||
    r == 0x2039 ||
    r == 0x2E02 ||
    r == 0x2E04 ||
    r == 0x2E09 ||
    r == 0x2E0C ||
    r == 0x2E1C ||
    r == 0x2E20;

bool _isFinalQuote(int r) =>
    r == 0xBB ||
    r == 0x2019 ||
    r == 0x201D ||
    r == 0x203A ||
    r == 0x2E03 ||
    r == 0x2E05 ||
    r == 0x2E0A ||
    r == 0x2E0D ||
    r == 0x2E1D ||
    r == 0x2E21;

/// whether [r] is fullwidth, wide or halfwidth in East Asian text
bool _isEastAsian(int r) =>
    (r >= 0x1100 && r <= 0x115F) ||
    r == 0x2329 ||
    r == 0x232A ||
    (r >= 0x2E80 && r <= 0x303E) ||
    (r >= 0x3041 && r <= 0x33FF) ||
    (r >= 0x3400 && r <= 0x4DBF) ||
    (r >= 0x4E00 && r <= 0xA4CF) ||
    (r >= 0xA960 && r <= 0xA97F) ||
    (r >= 0xAC00 && r <= 0xD7A3) ||
    (r >= 0xF900 && r <= 0xFAFF) ||
    (r >= 0xFE10 && r <= 0xFE19) ||
    (r >= 0xFE30 && r <= 0xFE6F) ||
    (r >= 0xFF00 && r <= 0xFF60) ||
    (r >= 0xFF61 && r <= 0xFFDC) ||
    (r >= 0xFFE0 && r <= 0xFFE6) ||
    (r >= 0x1F300 && r <= 0x1F64F) ||
    (r >= 0x1F900 && r <= 0x1F9FF) ||
    (r >= 0x20000 && r <= 0x3FFFD);

/// one character of the text with the characters that go with it: marks and
/// joiners have no break before them, so they belong to the character before
class _Unit {
  _Unit(this.start, this.rune, this.cls, this.nextStart);

  /// where it starts in the text, in UTF-16 code units
  final int start;
  final int rune;

  /// the class the rules see
  int cls;

  /// where the unit after it starts
  int nextStart;

  /// whether the last character that goes with it is a joiner
  bool endsWithJoiner = false;
}

/// the places in [text] where a line may be broken, by the rules of Unicode
/// Standard Annex 14: each is the offset, in UTF-16 code units, of the first
/// character after the break. a break at the end of the text is not given;
/// the breaks that must be made are in [mandatory].
class LineBreaks {
  LineBreaks._(this.allowed, this.mandatory);

  /// the places a break may be made, which include the ones it must be
  final Set<int> allowed;
  final Set<int> mandatory;

  bool canBreakAt(int index) => allowed.contains(index);

  factory LineBreaks.of(String text) {
    final units = <_Unit>[];
    var i = 0;
    while (i < text.length) {
      var rune = text.codeUnitAt(i);
      var length = 1;
      if (rune >= 0xD800 &&
          rune <= 0xDBFF &&
          i + 1 < text.length &&
          text.codeUnitAt(i + 1) >= 0xDC00 &&
          text.codeUnitAt(i + 1) <= 0xDFFF) {
        rune =
            0x10000 +
            ((rune - 0xD800) << 10) +
            (text.codeUnitAt(i + 1) - 0xDC00);
        length = 2;
      }
      var cls = _classOf(rune);
      // LB1: classes that depend on the language are letters here
      if (cls == _ai || cls == _sg || cls == _xx || cls == _sa) {
        cls = _al;
      } else if (cls == _cj) {
        cls = _ns;
      }
      final start = i;
      i += length;
      final previous = units.isEmpty ? null : units.last;
      final previousIsBase =
          previous != null &&
          previous.cls != _bk &&
          previous.cls != _cr &&
          previous.cls != _lf &&
          previous.cls != _nl &&
          previous.cls != _sp &&
          previous.cls != _zw;
      if ((cls == _cm || cls == _zwj) && previousIsBase) {
        // LB9: marks and joiners go with the character before them
        previous.nextStart = i;
        previous.endsWithJoiner = cls == _zwj;
        continue;
      }
      // LB10: marks and joiners left over are letters
      if (cls == _cm || cls == _zwj) {
        cls = _al;
      }
      final unit = _Unit(start, rune, cls, i);
      if (rune == 0x25CC) {
        unit.endsWithJoiner = false;
      }
      units.add(unit);
    }

    final allowed = <int>{};
    final mandatory = <int>{};
    var riRun = 0;
    // the class before the spaces that end at the unit being looked at
    int? beforeSpaces;
    bool afterOpeningQuote = false;
    var spaceRun = false;

    for (var u = 0; u + 1 < units.length; u++) {
      final a = units[u];
      final b = units[u + 1];
      final c = a.cls;
      final d = b.cls;
      final at = b.start;

      // what comes before the spaces that a is the last of
      if (c == _sp) {
        spaceRun = true;
      } else {
        spaceRun = false;
        beforeSpaces = c;
        final preceding = u > 0 ? units[u - 1].cls : null;
        afterOpeningQuote =
            c == _qu &&
            _isInitialQuote(a.rune) &&
            (preceding == null ||
                {
                  _bk,
                  _cr,
                  _lf,
                  _nl,
                  _op,
                  _qu,
                  _gl,
                  _sp,
                  _zw,
                }.contains(preceding));
      }
      riRun = c == _ri ? riRun + 1 : 0;
      final before = spaceRun ? beforeSpaces : c;
      final beforeIsOpeningQuote = (spaceRun || c == _qu) && afterOpeningQuote;

      final decision = _decide(
        units,
        u,
        c: c,
        d: d,
        before: before,
        beforeIsOpeningQuote: beforeIsOpeningQuote,
        riRun: riRun,
      );
      if (decision == _Break.mandatory) {
        allowed.add(at);
        mandatory.add(at);
      } else if (decision == _Break.allowed) {
        allowed.add(at);
      }
    }
    return LineBreaks._(allowed, mandatory);
  }
}

enum _Break { none, allowed, mandatory }

_Break _decide(
  List<_Unit> units,
  int u, {
  required int c,
  required int d,
  required int? before,
  required bool beforeIsOpeningQuote,
  required int riRun,
}) {
  final a = units[u];
  final b = units[u + 1];

  // LB4, LB5: hard line breaks
  if (c == _bk) {
    return _Break.mandatory;
  }
  if (c == _cr && d == _lf) {
    return _Break.none;
  }
  if (c == _cr || c == _lf || c == _nl) {
    return _Break.mandatory;
  }
  // LB6
  if (d == _bk || d == _cr || d == _lf || d == _nl) {
    return _Break.none;
  }
  // LB7
  if (d == _sp || d == _zw) {
    return _Break.none;
  }
  // LB8
  if (c == _zw || (c == _sp && before == _zw)) {
    return _Break.allowed;
  }
  // LB8a
  if (a.endsWithJoiner) {
    return _Break.none;
  }
  // LB11
  if (c == _wj || d == _wj) {
    return _Break.none;
  }
  // LB12, LB12a
  if (c == _gl) {
    return _Break.none;
  }
  if (d == _gl && c != _sp && c != _ba && c != _hy && c != _hh) {
    return _Break.none;
  }
  // LB13
  if (d == _cl || d == _cp || d == _ex || d == _sy) {
    return _Break.none;
  }
  // LB14
  if (before == _op && (c == _sp || c == _op)) {
    return _Break.none;
  }
  // LB15a: after an opening quotation mark
  if (beforeIsOpeningQuote) {
    return _Break.none;
  }
  // LB15b: before a closing quotation mark
  if (d == _qu && _isFinalQuote(b.rune)) {
    final following = u + 2 < units.length ? units[u + 2].cls : null;
    if (following == null ||
        {
          _sp, _gl, _wj, _cl, _qu, _cp, _ex, _is, _sy, //
          _bk, _cr, _lf, _nl, _zw,
        }.contains(following)) {
      return _Break.none;
    }
  }
  // LB15c, LB15d
  if (c == _sp && d == _is) {
    final following = u + 2 < units.length ? units[u + 2].cls : null;
    return following == _nu ? _Break.allowed : _Break.none;
  }
  if (d == _is) {
    return _Break.none;
  }
  // LB16
  if ((before == _cl || before == _cp) &&
      (c == _sp || c == _cl || c == _cp) &&
      d == _ns) {
    return _Break.none;
  }
  // LB17
  if (before == _b2 && (c == _sp || c == _b2) && d == _b2) {
    return _Break.none;
  }
  // LB18
  if (c == _sp) {
    return _Break.allowed;
  }
  // LB19
  if (d == _qu || c == _qu) {
    return _Break.none;
  }
  // LB20
  if (d == _cb || c == _cb) {
    return _Break.allowed;
  }
  // LB20a
  if ((c == _hy || c == _hh) && d != _sp) {
    final preceding = u > 0 ? units[u - 1].cls : null;
    if ((preceding == null ||
            {_bk, _cr, _lf, _nl, _sp, _zw, _cb, _gl}.contains(preceding)) &&
        (d == _al || d == _hl)) {
      return _Break.none;
    }
  }
  // LB21
  if (d == _ba || d == _hh || d == _hy || d == _ns || c == _bb) {
    return _Break.none;
  }
  // LB21a
  if (u > 0 &&
      units[u - 1].cls == _hl &&
      (c == _hy || c == _hh || (c == _ba && !_isEastAsian(a.rune))) &&
      d != _hl) {
    return _Break.none;
  }
  // LB21b
  if (c == _sy && d == _hl) {
    return _Break.none;
  }
  // LB22
  if (d == _in) {
    return _Break.none;
  }
  // LB23
  if ((c == _al || c == _hl) && d == _nu) {
    return _Break.none;
  }
  if (c == _nu && (d == _al || d == _hl)) {
    return _Break.none;
  }
  // LB23a
  if (c == _pr && (d == _id_ || d == _eb || d == _em)) {
    return _Break.none;
  }
  if ((c == _id_ || c == _eb || c == _em) && d == _po) {
    return _Break.none;
  }
  // LB24
  if ((c == _pr || c == _po) && (d == _al || d == _hl)) {
    return _Break.none;
  }
  if ((c == _al || c == _hl) && (d == _pr || d == _po)) {
    return _Break.none;
  }
  // LB25
  if ((c == _cl || c == _cp || c == _nu) && (d == _po || d == _pr)) {
    return _Break.none;
  }
  if ((c == _po || c == _pr) && (d == _op || d == _nu)) {
    return _Break.none;
  }
  if ((c == _hy || c == _is || c == _nu || c == _sy) && d == _nu) {
    return _Break.none;
  }
  // LB26
  if (c == _jl && (d == _jl || d == _jv || d == _h2 || d == _h3)) {
    return _Break.none;
  }
  if ((c == _jv || c == _h2) && (d == _jv || d == _jt)) {
    return _Break.none;
  }
  if ((c == _jt || c == _h3) && d == _jt) {
    return _Break.none;
  }
  // LB27
  if ((c == _jl || c == _jv || c == _jt || c == _h2 || c == _h3) && d == _po) {
    return _Break.none;
  }
  if (c == _pr && (d == _jl || d == _jv || d == _jt || d == _h2 || d == _h3)) {
    return _Break.none;
  }
  // LB28
  if ((c == _al || c == _hl) && (d == _al || d == _hl)) {
    return _Break.none;
  }
  // LB28a: syllables of scripts with a virama
  final dotted = a.rune == 0x25CC;
  final nextDotted = b.rune == 0x25CC;
  if (c == _ap && (d == _ak || d == _as || nextDotted)) {
    return _Break.none;
  }
  if ((c == _ak || c == _as || dotted) && (d == _vf || d == _vi)) {
    return _Break.none;
  }
  if (c == _vi && u > 0) {
    final head = units[u - 1];
    if ((head.cls == _ak || head.cls == _as || head.rune == 0x25CC) &&
        (d == _ak || nextDotted)) {
      return _Break.none;
    }
  }
  if ((c == _ak || c == _as || dotted) &&
      (d == _ak || d == _as || nextDotted)) {
    if (u + 2 < units.length && units[u + 2].cls == _vf) {
      return _Break.none;
    }
  }
  // LB29
  if (c == _is && (d == _al || d == _hl)) {
    return _Break.none;
  }
  // LB30
  if ((c == _al || c == _hl || c == _nu) && d == _op && !_isEastAsian(b.rune)) {
    return _Break.none;
  }
  if (c == _cp && !_isEastAsian(a.rune) && (d == _al || d == _hl || d == _nu)) {
    return _Break.none;
  }
  // LB30a: flags are pairs of regional indicators
  if (c == _ri && d == _ri && riRun.isOdd) {
    return _Break.none;
  }
  // LB30b
  if (c == _eb && d == _em) {
    return _Break.none;
  }
  // LB31
  return _Break.allowed;
}
