/// MKV tags the language in ISO 639-2; manifests use BCP-47 and sometimes
/// ISO 639-2 itself, bibliographic (`fre`) or terminologic (`fra`). The
/// terminologic form always comes out — it is what current players read.
/// Anything not in the table is `und`.
String iso6392(String? bcp47) {
  final primary = bcp47?.split(RegExp('[-_]')).first.toLowerCase();
  if (primary == null) return 'und';
  if (primary.length == 3) return _bibliographic[primary] ?? primary;
  return _iso6391[primary] ?? 'und';
}

// Every ISO 639-1 code (all 183) with its ISO 639-2/T form, plus the
// withdrawn ones that still turn up in old manifests (`iw`, `in`, `ji`,
// `mo`). Fixed by the standard: it does not grow.
const _iso6391 = {
  'aa': 'aar', 'ab': 'abk', 'ae': 'ave', 'af': 'afr', 'ak': 'aka', //
  'am': 'amh', 'an': 'arg', 'ar': 'ara', 'as': 'asm', 'av': 'ava',
  'ay': 'aym', 'az': 'aze', 'ba': 'bak', 'be': 'bel', 'bg': 'bul',
  'bi': 'bis', 'bm': 'bam', 'bn': 'ben', 'bo': 'bod', 'br': 'bre',
  'bs': 'bos', 'ca': 'cat', 'ce': 'che', 'ch': 'cha', 'co': 'cos',
  'cr': 'cre', 'cs': 'ces', 'cu': 'chu', 'cv': 'chv', 'cy': 'cym',
  'da': 'dan', 'de': 'deu', 'dv': 'div', 'dz': 'dzo', 'ee': 'ewe',
  'el': 'ell', 'en': 'eng', 'eo': 'epo', 'es': 'spa', 'et': 'est',
  'eu': 'eus', 'fa': 'fas', 'ff': 'ful', 'fi': 'fin', 'fj': 'fij',
  'fo': 'fao', 'fr': 'fra', 'fy': 'fry', 'ga': 'gle', 'gd': 'gla',
  'gl': 'glg', 'gn': 'grn', 'gu': 'guj', 'gv': 'glv', 'ha': 'hau',
  'he': 'heb', 'hi': 'hin', 'ho': 'hmo', 'hr': 'hrv', 'ht': 'hat',
  'hu': 'hun', 'hy': 'hye', 'hz': 'her', 'ia': 'ina', 'id': 'ind',
  'ie': 'ile', 'ig': 'ibo', 'ii': 'iii', 'ik': 'ipk', 'io': 'ido',
  'is': 'isl', 'it': 'ita', 'iu': 'iku', 'ja': 'jpn', 'jv': 'jav',
  'ka': 'kat', 'kg': 'kon', 'ki': 'kik', 'kj': 'kua', 'kk': 'kaz',
  'kl': 'kal', 'km': 'khm', 'kn': 'kan', 'ko': 'kor', 'kr': 'kau',
  'ks': 'kas', 'ku': 'kur', 'kv': 'kom', 'kw': 'cor', 'ky': 'kir',
  'la': 'lat', 'lb': 'ltz', 'lg': 'lug', 'li': 'lim', 'ln': 'lin',
  'lo': 'lao', 'lt': 'lit', 'lu': 'lub', 'lv': 'lav', 'mg': 'mlg',
  'mh': 'mah', 'mi': 'mri', 'mk': 'mkd', 'ml': 'mal', 'mn': 'mon',
  'mr': 'mar', 'ms': 'msa', 'mt': 'mlt', 'my': 'mya', 'na': 'nau',
  'nb': 'nob', 'nd': 'nde', 'ne': 'nep', 'ng': 'ndo', 'nl': 'nld',
  'nn': 'nno', 'no': 'nor', 'nr': 'nbl', 'nv': 'nav', 'ny': 'nya',
  'oc': 'oci', 'oj': 'oji', 'om': 'orm', 'or': 'ori', 'os': 'oss',
  'pa': 'pan', 'pi': 'pli', 'pl': 'pol', 'ps': 'pus', 'pt': 'por',
  'qu': 'que', 'rm': 'roh', 'rn': 'run', 'ro': 'ron', 'ru': 'rus',
  'rw': 'kin', 'sa': 'san', 'sc': 'srd', 'sd': 'snd', 'se': 'sme',
  'sg': 'sag', 'si': 'sin', 'sk': 'slk', 'sl': 'slv', 'sm': 'smo',
  'sn': 'sna', 'so': 'som', 'sq': 'sqi', 'sr': 'srp', 'ss': 'ssw',
  'st': 'sot', 'su': 'sun', 'sv': 'swe', 'sw': 'swa', 'ta': 'tam',
  'te': 'tel', 'tg': 'tgk', 'th': 'tha', 'ti': 'tir', 'tk': 'tuk',
  'tl': 'tgl', 'tn': 'tsn', 'to': 'ton', 'tr': 'tur', 'ts': 'tso',
  'tt': 'tat', 'tw': 'twi', 'ty': 'tah', 'ug': 'uig', 'uk': 'ukr',
  'ur': 'urd', 'uz': 'uzb', 've': 'ven', 'vi': 'vie', 'vo': 'vol',
  'wa': 'wln', 'wo': 'wol', 'xh': 'xho', 'yi': 'yid', 'yo': 'yor',
  'za': 'zha', 'zh': 'zho', 'zu': 'zul',
  // Withdrawn, still in the wild.
  'iw': 'heb', 'in': 'ind', 'ji': 'yid', 'mo': 'ron',
};

/// No language, several, or none: they identify nothing.
const _unknown = {'und', 'mul', 'zxx', 'mis'};

/// Bibliographic → terminologic: the twenty ISO 639-2 languages with two
/// codes. Players read the terminologic one.
const _bibliographic = {
  'alb': 'sqi', 'arm': 'hye', 'baq': 'eus', 'bur': 'mya', 'chi': 'zho', //
  'cze': 'ces', 'dut': 'nld', 'fre': 'fra', 'geo': 'kat', 'ger': 'deu',
  'gre': 'ell', 'ice': 'isl', 'mac': 'mkd', 'mao': 'mri', 'may': 'msa',
  'per': 'fas', 'rum': 'ron', 'slo': 'slk', 'tib': 'bod', 'wel': 'cym',
};

/// Whether [a] and [b] are the same language however they are written
/// (`es`, `es-419`, `spa`). Two unknown languages do not count as equal.
bool sameLanguage(String? a, String? b) {
  if (a == null || b == null) return false;
  final codeA = iso6392(a);
  return !_unknown.contains(codeA) && codeA == iso6392(b);
}

/// Native names, which is how many manifests label their tracks.
const _nativeNames = {
  'es': 'español',
  'en': 'english',
  'pt': 'português',
  'fr': 'français',
  'it': 'italiano',
  'de': 'deutsch',
  'ja': '日本語',
  'ko': '한국어',
  'zh': '中文',
};

/// English names, the other common way to label them.
const _englishNames = {
  'es': 'spanish',
  'en': 'english',
  'pt': 'portuguese',
  'fr': 'french',
  'it': 'italian',
  'de': 'german',
  'ja': 'japanese',
  'ko': 'korean',
  'zh': 'chinese',
};

/// Other names a language is labelled with.
const _aliases = {
  'es': ['castellano', 'latino'],
  'zh': [
    'mandarin', 'cantonese', '普通话', '國語', '粵語', '粤语', //
    '繁體中文', '繁体中文', '简体中文', '簡體中文',
  ],
};

/// Variants labels spell out in words: `Español (Latino)`,
/// `Portuguese (Brazil)`, `Chinese (Traditional)`. Looked for anywhere in
/// the label; for Chinese the variant is the script, not a country.
const _labelVariants = {
  'es': {
    '419': ['latino', 'latinoam', 'latam', 'latin america', 'méxico'],
    'ES': ['castellano', 'castilian', 'españa', 'spain', 'european'],
  },
  'pt': {
    'BR': ['brasil', 'brazil'],
    'PT': ['portugal', 'european'],
  },
  'zh': {
    'Hant': ['traditional', '繁體', '繁体', 'cantonese', '粵語', '粤语'],
    'Hans': ['simplified', '简体', '簡體', 'mandarin', '普通话'],
  },
};

/// The language of a label like `Español (Latinoamérica)` or `English SDH`,
/// with the variant when the label says it (`es-419`). Null when the label
/// is not recognised.
String? languageOfLabel(String? label) {
  final value = label?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  for (final code in _nativeNames.keys) {
    final names = [
      _nativeNames[code]!,
      _englishNames[code]!,
      ...?_aliases[code],
    ];
    if (!names.any(value.startsWith)) continue;

    for (final MapEntry(key: region, value: words)
        in (_labelVariants[code] ?? const <String, List<String>>{}).entries) {
      if (words.any(value.contains)) return '$code-$region';
    }
    return code;
  }
  return null;
}

/// A track's language: the declared one or, without it, the label's. When
/// the code carries no variant and the label does, the label's wins:
/// `es` + `Español (Latino)` → `es-419`, `zh` + `繁體中文` → `zh-Hant`.
String? trackLanguage(String? declared, String? label) {
  final fromLabel = languageOfLabel(label);
  if (declared == null) return fromLabel;
  if (fromLabel != null &&
      _variantOf(declared) == null &&
      _variantOf(fromLabel) != null &&
      sameLanguage(declared, fromLabel)) {
    return fromLabel;
  }
  return declared;
}

/// The region of a BCP-47 tag (`419` in `es-419`, `MX` in `es-Latn-MX`), or
/// null.
String? regionOf(String tag) {
  for (final part in tag.split(RegExp('[-_]')).skip(1)) {
    if (_region.hasMatch(part)) return part.toUpperCase();
  }
  return null;
}

final _region = RegExp(r'^([a-zA-Z]{2}|\d{3})$');

/// How close a track's language is to [wanted]: 0 when it is another
/// language, 1 when it is the same, 2 when it is also the variant [wanted]
/// asks for. When [wanted] asks for no variant, every track of the language
/// scores 1.
int languageMatch(String? track, String wanted) {
  if (!sameLanguage(track, wanted)) return 0;
  final variant = _variantOf(wanted);
  if (variant == null) return 1;
  return _variantOf(track!) == variant ? 2 : 1;
}

/// The variant that tells two tracks of one language apart:
///
/// - Spanish: any country in the Americas is the Latin American dub
///   (`es-MX` counts as `es-419`); Spain is Castilian.
/// - Chinese: the script, which is what a reader cares about — `zh-Hant`,
///   and `zh-TW`/`zh-HK`/`zh-MO` that write it, against `zh-Hans`,
///   `zh-CN`/`zh-SG`.
/// - Anything else: its region as it is.
String? _variantOf(String tag) {
  final code = iso6392(tag);
  if (code == 'zho') return _chineseScript(tag);

  final region = regionOf(tag);
  if (region == null) return null;
  if (code == 'spa' && !_spainRegions.contains(region)) return '419';
  return region;
}

String? _chineseScript(String tag) {
  final subtags = tag.split(RegExp('[-_]')).skip(1).map((s) => s.toLowerCase());
  if (subtags.contains('hant')) return 'Hant';
  if (subtags.contains('hans')) return 'Hans';
  return switch (regionOf(tag)) {
    'TW' || 'HK' || 'MO' => 'Hant',
    'CN' || 'SG' => 'Hans',
    _ => null,
  };
}

/// Spain, Ceuta and Melilla, and the Canaries.
const _spainRegions = {'ES', 'EA', 'IC'};
