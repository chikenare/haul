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

const _iso6391 = {
  'af': 'afr', 'am': 'amh', 'ar': 'ara', 'az': 'aze', 'be': 'bel', //
  'bg': 'bul', 'bn': 'ben', 'bs': 'bos', 'ca': 'cat', 'cs': 'ces',
  'cy': 'cym', 'da': 'dan', 'de': 'deu', 'el': 'ell', 'en': 'eng',
  'es': 'spa', 'et': 'est', 'eu': 'eus', 'fa': 'fas', 'fi': 'fin',
  'fr': 'fra', 'ga': 'gle', 'gl': 'glg', 'gu': 'guj',
  'he': 'heb', 'hi': 'hin', 'hr': 'hrv', 'hu': 'hun', 'hy': 'hye',
  'id': 'ind', 'is': 'isl', 'it': 'ita', 'iw': 'heb', 'ja': 'jpn',
  'ka': 'kat', 'kk': 'kaz', 'km': 'khm', 'kn': 'kan', 'ko': 'kor',
  'lo': 'lao', 'lt': 'lit', 'lv': 'lav', 'mk': 'mkd', 'ml': 'mal',
  'mn': 'mon', 'mr': 'mar', 'ms': 'msa', 'my': 'mya', 'nb': 'nob',
  'ne': 'nep', 'nl': 'nld', 'nn': 'nno', 'no': 'nor', 'pa': 'pan',
  'pl': 'pol', 'pt': 'por', 'ro': 'ron', 'ru': 'rus', 'si': 'sin',
  'sk': 'slk', 'sl': 'slv', 'sq': 'sqi', 'sr': 'srp', 'sv': 'swe',
  'sw': 'swa', 'ta': 'tam', 'te': 'tel', 'th': 'tha', 'tl': 'tgl',
  'tr': 'tur', 'uk': 'ukr', 'ur': 'urd', 'uz': 'uzb', 'vi': 'vie',
  'zh': 'zho', 'zu': 'zul',
};

/// No language, several, or none: they identify nothing.
const _unknown = {'und', 'mul', 'zxx', 'mis'};

/// Bibliographic → terminologic, for the ones that differ.
const _bibliographic = {
  'alb': 'sqi', 'arm': 'hye', 'baq': 'eus', 'bur': 'mya', 'chi': 'zho', //
  'cze': 'ces', 'dut': 'nld', 'fre': 'fra', 'geo': 'kat', 'ger': 'deu',
  'gre': 'ell', 'ice': 'isl', 'mac': 'mkd', 'may': 'msa', 'per': 'fas',
  'rum': 'ron', 'slo': 'slk', 'tib': 'bod', 'wel': 'cym',
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
};

/// Other names a language is labelled with.
const _aliases = {
  'es': ['castellano', 'latino'],
};

/// Variants labels spell out in words: `Español (Latino)`,
/// `Portuguese (Brazil)`. Looked for anywhere in the label.
const _labelRegions = {
  'es': {
    '419': ['latino', 'latinoam', 'latam', 'latin america', 'méxico'],
    'ES': ['castellano', 'castilian', 'españa', 'spain', 'european'],
  },
  'pt': {
    'BR': ['brasil', 'brazil'],
    'PT': ['portugal', 'european'],
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
        in (_labelRegions[code] ?? const <String, List<String>>{}).entries) {
      if (words.any(value.contains)) return '$code-$region';
    }
    return code;
  }
  return null;
}

/// A track's language: the declared one or, without it, the label's. When
/// the code carries no variant and the label does, the label's wins:
/// `es` + `Español (Latino)` → `es-419`.
String? trackLanguage(String? declared, String? label) {
  final fromLabel = languageOfLabel(label);
  if (declared == null) return fromLabel;
  if (fromLabel != null &&
      regionOf(declared) == null &&
      regionOf(fromLabel) != null &&
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

/// For dubbing, the Spanish of any country in the Americas is the Latin
/// American one (`es-MX` counts as `es-419`); other regions stay as they are.
String? _variantOf(String tag) {
  final region = regionOf(tag);
  if (region == null) return null;
  if (iso6392(tag) == 'spa' && !_spainRegions.contains(region)) return '419';
  return region;
}

/// Spain, Ceuta and Melilla, and the Canaries.
const _spainRegions = {'ES', 'EA', 'IC'};
