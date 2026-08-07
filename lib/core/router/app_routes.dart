/// Every navigable location in LifeOS.
///
/// Paths are declared once here so deep links, widgets, notifications and the
/// assistant's "take me there" actions all agree on the same strings.
abstract final class Routes {
  const Routes._();

  // Pre-authentication
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String lock = '/lock';

  // Shell tabs
  static const String dashboard = '/home';
  static const String journal = '/journal';
  static const String plan = '/plan';
  static const String money = '/money';
  static const String insights = '/insights';

  // Pushed destinations
  static const String journalEntry = '/journal/entry';
  static const String journalCompose = '/journal/compose';
  static const String mood = '/mood';
  static const String habits = '/habits';
  static const String habitDetail = '/habits/detail';
  static const String goals = '/goals';
  static const String goalDetail = '/goals/detail';
  static const String tasks = '/tasks';
  static const String calendar = '/calendar';
  static const String health = '/health';
  static const String people = '/people';
  static const String personDetail = '/people/detail';
  static const String timeline = '/timeline';
  static const String search = '/search';
  static const String chat = '/chat';
  static const String review = '/insights/review';
  static const String settings = '/settings';
  static const String settingsAi = '/settings/ai';
  static const String settingsPrivacy = '/settings/privacy';
  static const String settingsNotifications = '/settings/notifications';
  static const String settingsData = '/settings/data';

  /// Destinations a notification payload may open.
  ///
  /// A push message is remote input, so this is an allow-list rather than a
  /// pattern match: a payload either names a screen LifeOS is willing to be
  /// sent to, or it is ignored. Detail routes are absent on purpose — they
  /// need an id, and a bad one lands the user on an error page.
  static const Set<String> deepLinkTargets = <String>{
    dashboard,
    journal,
    journalCompose,
    mood,
    habits,
    goals,
    tasks,
    calendar,
    health,
    people,
    timeline,
    search,
    chat,
    insights,
    money,
    plan,
    settings,
  };

  static bool isDeepLinkable(String path) => deepLinkTargets.contains(path);

  static String journalEntryFor(String id) => '$journalEntry/$id';
  static String habitDetailFor(String id) => '$habitDetail/$id';
  static String goalDetailFor(String id) => '$goalDetail/$id';
  static String personDetailFor(String id) => '$personDetail/$id';
  static String reviewFor(String period) => '$review/$period';
}
