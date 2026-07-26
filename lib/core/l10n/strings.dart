import 'package:flutter/widgets.dart';

/// Lightweight localisation for app chrome.
///
/// LifeOS ships a table-based implementation rather than generated ARB
/// bundles so that a translator can add a language by appending one map — no
/// build step, no regeneration. Feature screens read user content (journal
/// text, habit names) which is never translated, so the surface that actually
/// needs translation is small.
///
/// Migrating to `flutter gen-l10n` later is mechanical: the keys below map 1:1
/// to ARB keys. See docs/ARCHITECTURE.md.
@immutable
class Strings {
  const Strings(this.locale);

  final Locale locale;

  static const List<Locale> supported = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('hi'),
    Locale('ar'),
  ];

  static const Map<String, String> languageNames = <String, String>{
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'hi': 'हिन्दी',
    'ar': 'العربية',
  };

  static Strings of(BuildContext context) =>
      Localizations.of<Strings>(context, Strings) ??
      const Strings(Locale('en'));

  static const Map<String, Map<String, String>> _table =
      <String, Map<String, String>>{
    'en': <String, String>{
      'app.name': 'LifeOS',
      'nav.home': 'Home',
      'nav.journal': 'Journal',
      'nav.plan': 'Plan',
      'nav.money': 'Money',
      'nav.insights': 'Insights',
      'greeting.morning': 'Good morning',
      'greeting.afternoon': 'Good afternoon',
      'greeting.evening': 'Good evening',
      'greeting.night': 'Still up?',
      'action.add': 'Add',
      'action.save': 'Save',
      'action.cancel': 'Cancel',
      'action.delete': 'Delete',
      'action.retry': 'Try again',
      'assistant.title': 'Assistant',
      'assistant.hint': 'Ask about your life…',
    },
    'es': <String, String>{
      'app.name': 'LifeOS',
      'nav.home': 'Inicio',
      'nav.journal': 'Diario',
      'nav.plan': 'Plan',
      'nav.money': 'Dinero',
      'nav.insights': 'Análisis',
      'greeting.morning': 'Buenos días',
      'greeting.afternoon': 'Buenas tardes',
      'greeting.evening': 'Buenas noches',
      'greeting.night': '¿Aún despierto?',
      'action.add': 'Añadir',
      'action.save': 'Guardar',
      'action.cancel': 'Cancelar',
      'action.delete': 'Eliminar',
      'action.retry': 'Reintentar',
      'assistant.title': 'Asistente',
      'assistant.hint': 'Pregunta sobre tu vida…',
    },
    'fr': <String, String>{
      'app.name': 'LifeOS',
      'nav.home': 'Accueil',
      'nav.journal': 'Journal',
      'nav.plan': 'Plan',
      'nav.money': 'Argent',
      'nav.insights': 'Analyses',
      'greeting.morning': 'Bonjour',
      'greeting.afternoon': 'Bon après-midi',
      'greeting.evening': 'Bonsoir',
      'greeting.night': 'Encore debout ?',
      'action.add': 'Ajouter',
      'action.save': 'Enregistrer',
      'action.cancel': 'Annuler',
      'action.delete': 'Supprimer',
      'action.retry': 'Réessayer',
      'assistant.title': 'Assistant',
      'assistant.hint': 'Posez une question…',
    },
    'de': <String, String>{
      'app.name': 'LifeOS',
      'nav.home': 'Start',
      'nav.journal': 'Journal',
      'nav.plan': 'Plan',
      'nav.money': 'Geld',
      'nav.insights': 'Einblicke',
      'greeting.morning': 'Guten Morgen',
      'greeting.afternoon': 'Guten Tag',
      'greeting.evening': 'Guten Abend',
      'greeting.night': 'Noch wach?',
      'action.add': 'Hinzufügen',
      'action.save': 'Speichern',
      'action.cancel': 'Abbrechen',
      'action.delete': 'Löschen',
      'action.retry': 'Erneut versuchen',
      'assistant.title': 'Assistent',
      'assistant.hint': 'Frag nach deinem Leben…',
    },
    'hi': <String, String>{
      'app.name': 'LifeOS',
      'nav.home': 'होम',
      'nav.journal': 'डायरी',
      'nav.plan': 'योजना',
      'nav.money': 'पैसा',
      'nav.insights': 'अंतर्दृष्टि',
      'greeting.morning': 'सुप्रभात',
      'greeting.afternoon': 'नमस्कार',
      'greeting.evening': 'शुभ संध्या',
      'greeting.night': 'अभी तक जाग रहे हैं?',
      'action.add': 'जोड़ें',
      'action.save': 'सहेजें',
      'action.cancel': 'रद्द करें',
      'action.delete': 'हटाएं',
      'action.retry': 'पुनः प्रयास करें',
      'assistant.title': 'सहायक',
      'assistant.hint': 'अपने जीवन के बारे में पूछें…',
    },
    'ar': <String, String>{
      'app.name': 'LifeOS',
      'nav.home': 'الرئيسية',
      'nav.journal': 'اليوميات',
      'nav.plan': 'الخطة',
      'nav.money': 'المال',
      'nav.insights': 'الرؤى',
      'greeting.morning': 'صباح الخير',
      'greeting.afternoon': 'مساء الخير',
      'greeting.evening': 'مساء الخير',
      'greeting.night': 'ما زلت مستيقظًا؟',
      'action.add': 'إضافة',
      'action.save': 'حفظ',
      'action.cancel': 'إلغاء',
      'action.delete': 'حذف',
      'action.retry': 'أعد المحاولة',
      'assistant.title': 'المساعد',
      'assistant.hint': 'اسأل عن حياتك…',
    },
  };

  /// Falls back to English, then to the key itself — a missing translation
  /// degrades to readable text instead of an exception.
  String call(String key) =>
      _table[locale.languageCode]?[key] ?? _table['en']![key] ?? key;
}

class StringsDelegate extends LocalizationsDelegate<Strings> {
  const StringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      Strings.supported.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<Strings> load(Locale locale) async => Strings(locale);

  @override
  bool shouldReload(StringsDelegate old) => false;
}
