import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('ja')];
  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final result = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(result != null, 'AppLocalizations not found in context.');
    return result!;
  }

  static Locale resolve(Locale? locale) {
    if (locale?.languageCode == 'ja') {
      return const Locale('ja');
    }
    return const Locale('en');
  }

  String get languageCode => resolve(locale).languageCode;
  bool get isJapanese => languageCode == 'ja';

  String tr(String key, [Map<String, String> args = const <String, String>{}]) {
    final translations = isJapanese ? appStringsJa : appStringsEn;
    var value = translations[key] ?? appStringsEn[key] ?? key;
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'en' || locale.languageCode == 'ja';
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
