import '../providers/language_provider.dart';
import '../services/translate_api.dart';

// English-only source strings. All non-English translations are handled by
// Groq via translateBatch() — see language_provider.dart loadUiTranslations().
class S {
  const S._();

  static const _en = <String, String>{
    // Auth
    'chooseLanguage': 'Choose your language',
    'continueBtn': 'Continue',
    'back': 'Back',
    'next': 'Next',
    'signUp': 'Sign Up',
    'login': 'Log In',
    'email': 'Email',
    'password': 'Password',
    'name': 'Name',
    'username': 'Username',
    'gender': 'Gender',
    'verifyEmail': 'Verify your email',
    'resendOtp': 'Resend OTP',
    'newToNeedHub': 'new to NeedHub?',
    'createProfile': 'Create your profile',
    // Feed / surfaces
    'feed': 'Feed',
    'explore': 'Explore',
    'earn': 'Earn',
    'connect': 'Connect',
    'chitchat': 'ChitChat',
    'postNeed': 'Post a Need',
    'nearby': 'Nearby',
    'budget': 'Budget',
    'offers': 'offers',
    'respond': 'Respond',
    'applied': 'Applied',
    'filter': 'Filter',
    'needsNearYou': 'needs near you',
    'peopleNearYou': 'people near you',
    'casualChats': 'Casual chats nearby',
    'aiRanked': 'AI-ranked',
    // Navigation
    'hub': 'Hub',
    'home': 'Home',
    'chats': 'Chats',
    'alerts': 'Alerts',
    'you': 'You',
    // Post need sheet
    'whatDoYouNeed': 'What do you need?',
    'title': 'Title',
    'description': 'Description',
    'post': 'Post',
    'minBudget': 'MIN BUDGET',
    'maxBudget': 'MAX BUDGET',
    // Home tab
    'welcomeBack': 'Welcome back',
    'hiGreeting': 'Hi {name}, great to see you!',
    'addANeed': 'Add a need',
    'addANeedSubtitle': 'Post what you need — offers roll in',
    'exploreNeeds': 'Explore needs',
    'helpEarnSubtitle': 'Help out nearby & earn',
    // Chats tab
    'noChatsYet': 'No conversations yet',
    'noChatsSubtitle': 'Accept a friend request or connect with someone to start chatting',
    'friendRequests': 'FRIEND REQUESTS',
    'wantsToConnect': 'wants to connect',
    'accept': 'Accept',
    'decline': 'Decline',
    'markAvailableForChitchat': 'Mark yourself available for Chit-chat',
    // Alerts tab
    'markAllRead': 'Mark all read',
    'selectAll': 'Select all',
    'delete': 'Delete',
    'clear': 'Clear',
    'selected': 'selected',
    'noNotificationsYet': 'No notifications yet',
    // You / Profile screen
    'settings': 'Settings',
    'edit': 'Edit',
    'logout': 'Log Out',
    'profile': 'Profile',
    'points': 'Points',
    'myNeeds': 'My Needs',
    'myPostedNeeds': 'MY POSTED NEEDS & HISTORY',
    'noPostedNeeds': 'No posted needs in this category',
    'noPostedNeedsSubtitle': 'Needs you post will appear here with status, offers & feedback',
    'trustScore': 'TRUST SCORE',
    'shownOnConnectCards': 'Shown on your Connect cards',
    'trustScoreGrows': 'Also grows with approved certificates, fulfilled needs, and review ratings.',
    'faceVerification': 'FACE VERIFICATION',
    'verifyYourFace': 'Verify Your Face',
    'faceVerified': 'Face Verified',
    'verifyFaceDesc': 'Upload a clear photo of your face to get a verified badge on your connect needs',
    'takeSelfie': 'Take selfie',
    'verifyYourPhone': 'Verify Your Phone',
    'phoneVerified': 'Phone Verified',
    'verifyPhoneDesc': 'Adds the biggest boost to your trust score',
    'verify': 'Verify',
    'sustainabilityCerts': 'SUSTAINABILITY CERTIFICATES',
    'noCertificates': 'No certificates yet — tap Add to upload one.',
    'badges': 'BADGES',
    'badgesDesc': 'Earned automatically from what you actually do. Each one adds to your Trust Score.',
    'achievements': 'ACHIEVEMENTS',
    'achievementsDesc': 'Earned through doing — not spendable.',
    'nothingSubmitted': 'Nothing submitted yet — add a certificate or competition win above.',
    'pastWorkHistory': 'Past Work & Review History',
    'referAFriend': 'Refer a Friend',
    'referralDesc': 'Both of you earn 15 points when they post their first need.',
    'shareYourCode': 'Share your code',
    'peopleYouveHelped': 'People you\'ve helped — history & ratings',
    'reliabilityPoints': 'RELIABILITY POINTS',
    'needsDone': 'Needs done',
    'reviews': 'Reviews',
    'redeemPoints': 'Redeem points',
    'personality': 'PERSONALITY',
    'takePersonalityTest': 'Take the personality test',
    'poweredByLyzr': 'Powered by Lyzr AI · ~2 min',
    'tapToAnswerPrompt': 'Tap to answer this prompt…',
    'aboutMe': 'ABOUT ME',
    'skillIdLoveToTeach': 'THE SKILL I\'D LOVE TO TEACH',
    'myIdealCollab': 'MY IDEAL COLLAB',
    'needIdPostRightNow': 'THE NEED I\'D POST RIGHT NOW',
    'ratingsAndReviews': 'Ratings & Reviews',
    'interests': 'Interests',
    'skills': 'Skills',
    'location': 'Location',
    // Messages / Conversation
    'translate': 'Translate',
    'translating': 'Translating…',
    'showOriginal': 'Show original',
    'translateTo': 'Translate to',
    // Voice / STT
    'tapToSpeak': 'Tap to speak',
    'listening': 'Listening…',
    'voiceNotAvailable': 'Voice input not available',
    // Settings
    'language': 'Language',
    'feedLanguage': 'Feed language',
    'translateNeeds': 'Translate needs to',
    'changeLanguage': 'Change language',
    // General
    'loading': 'Loading…',
    'error': 'Something went wrong',
    'retry': 'Retry',
    'cancel': 'Cancel',
    'save': 'Save',
    'done': 'Done',
    'search': 'Search',
    'report': 'Report',
    'block': 'Block',
    'unblock': 'Unblock',
    'addFriend': 'Add friend',
    'removeFriend': 'Remove friend',
    'acceptRequest': 'Accept Request',
    // Impact screen
    'impact': 'Impact',
    'certificates': 'Certificates',
  };

  /// Live Groq-translated cache for the current language.
  static Map<String, String> _cache = {};
  static String _cacheFor = 'en';

  static void updateCache(String langCode, Map<String, String> translated) {
    _cache = translated;
    _cacheFor = langCode;
  }

  static String _get(String key) {
    final lang = uiLanguageNotifier.value;
    if (lang != 'en' && _cacheFor == lang && _cache.containsKey(key)) {
      return _cache[key]!;
    }
    return _en[key] ?? key;
  }

  static S get current => const S._();

  // All string getters
  String get chooseLanguage => _get('chooseLanguage');
  String get continueBtn => _get('continueBtn');
  String get back => _get('back');
  String get next => _get('next');
  String get signUp => _get('signUp');
  String get login => _get('login');
  String get email => _get('email');
  String get password => _get('password');
  String get name => _get('name');
  String get username => _get('username');
  String get gender => _get('gender');
  String get verifyEmail => _get('verifyEmail');
  String get resendOtp => _get('resendOtp');
  String get newToNeedHub => _get('newToNeedHub');
  String get createProfile => _get('createProfile');
  String get feed => _get('feed');
  String get explore => _get('explore');
  String get earn => _get('earn');
  String get connect => _get('connect');
  String get chitchat => _get('chitchat');
  String get postNeed => _get('postNeed');
  String get nearby => _get('nearby');
  String get budget => _get('budget');
  String get offers => _get('offers');
  String get respond => _get('respond');
  String get applied => _get('applied');
  String get filter => _get('filter');
  String get needsNearYou => _get('needsNearYou');
  String get peopleNearYou => _get('peopleNearYou');
  String get casualChats => _get('casualChats');
  String get aiRanked => _get('aiRanked');
  String get hub => _get('hub');
  String get home => _get('home');
  String get chats => _get('chats');
  String get alerts => _get('alerts');
  String get you => _get('you');
  String get whatDoYouNeed => _get('whatDoYouNeed');
  String get title => _get('title');
  String get description => _get('description');
  String get post => _get('post');
  String get minBudget => _get('minBudget');
  String get maxBudget => _get('maxBudget');
  String get welcomeBack => _get('welcomeBack');
  String hiGreeting(String firstName) => _get('hiGreeting').replaceAll('{name}', firstName);
  String get addANeed => _get('addANeed');
  String get addANeedSubtitle => _get('addANeedSubtitle');
  String get exploreNeeds => _get('exploreNeeds');
  String get helpEarnSubtitle => _get('helpEarnSubtitle');
  String get noChatsYet => _get('noChatsYet');
  String get noChatsSubtitle => _get('noChatsSubtitle');
  String get friendRequests => _get('friendRequests');
  String get wantsToConnect => _get('wantsToConnect');
  String get accept => _get('accept');
  String get decline => _get('decline');
  String get markAvailableForChitchat => _get('markAvailableForChitchat');
  String get markAllRead => _get('markAllRead');
  String get selectAll => _get('selectAll');
  String get delete => _get('delete');
  String get clear => _get('clear');
  String get selected => _get('selected');
  String get noNotificationsYet => _get('noNotificationsYet');
  String get settings => _get('settings');
  String get edit => _get('edit');
  String get logout => _get('logout');
  String get profile => _get('profile');
  String get points => _get('points');
  String get myNeeds => _get('myNeeds');
  String get myPostedNeeds => _get('myPostedNeeds');
  String get noPostedNeeds => _get('noPostedNeeds');
  String get noPostedNeedsSubtitle => _get('noPostedNeedsSubtitle');
  String get trustScore => _get('trustScore');
  String get shownOnConnectCards => _get('shownOnConnectCards');
  String get trustScoreGrows => _get('trustScoreGrows');
  String get faceVerification => _get('faceVerification');
  String get verifyYourFace => _get('verifyYourFace');
  String get faceVerified => _get('faceVerified');
  String get verifyFaceDesc => _get('verifyFaceDesc');
  String get takeSelfie => _get('takeSelfie');
  String get verifyYourPhone => _get('verifyYourPhone');
  String get phoneVerified => _get('phoneVerified');
  String get verifyPhoneDesc => _get('verifyPhoneDesc');
  String get verify => _get('verify');
  String get sustainabilityCerts => _get('sustainabilityCerts');
  String get noCertificates => _get('noCertificates');
  String get badges => _get('badges');
  String get badgesDesc => _get('badgesDesc');
  String get achievements => _get('achievements');
  String get achievementsDesc => _get('achievementsDesc');
  String get nothingSubmitted => _get('nothingSubmitted');
  String get pastWorkHistory => _get('pastWorkHistory');
  String get referAFriend => _get('referAFriend');
  String get referralDesc => _get('referralDesc');
  String get shareYourCode => _get('shareYourCode');
  String get peopleYouveHelped => _get('peopleYouveHelped');
  String get reliabilityPoints => _get('reliabilityPoints');
  String get needsDone => _get('needsDone');
  String get reviews => _get('reviews');
  String get redeemPoints => _get('redeemPoints');
  String get personality => _get('personality');
  String get takePersonalityTest => _get('takePersonalityTest');
  String get poweredByLyzr => _get('poweredByLyzr');
  String get tapToAnswerPrompt => _get('tapToAnswerPrompt');
  String get aboutMe => _get('aboutMe');
  String get skillIdLoveToTeach => _get('skillIdLoveToTeach');
  String get myIdealCollab => _get('myIdealCollab');
  String get needIdPostRightNow => _get('needIdPostRightNow');
  String get ratingsAndReviews => _get('ratingsAndReviews');
  String get interests => _get('interests');
  String get skills => _get('skills');
  String get location => _get('location');
  String get translate => _get('translate');
  String get translating => _get('translating');
  String get showOriginal => _get('showOriginal');
  String get translateTo => _get('translateTo');
  String get tapToSpeak => _get('tapToSpeak');
  String get listening => _get('listening');
  String get voiceNotAvailable => _get('voiceNotAvailable');
  String get language => _get('language');
  String get feedLanguage => _get('feedLanguage');
  String get translateNeeds => _get('translateNeeds');
  String get changeLanguage => _get('changeLanguage');
  String get loading => _get('loading');
  String get error => _get('error');
  String get retry => _get('retry');
  String get cancel => _get('cancel');
  String get save => _get('save');
  String get done => _get('done');
  String get search => _get('search');
  String get report => _get('report');
  String get block => _get('block');
  String get unblock => _get('unblock');
  String get addFriend => _get('addFriend');
  String get removeFriend => _get('removeFriend');
  String get acceptRequest => _get('acceptRequest');
  String get impact => _get('impact');
  String get certificates => _get('certificates');

  /// Load all UI strings for [langCode] from Groq and store in cache.
  static Future<void> loadTranslations(String langCode) async {
    if (langCode == 'en') {
      _cache = {};
      _cacheFor = 'en';
      return;
    }
    final keys = _en.keys.toList();
    final values = _en.values.toList();
    final translated = await translateBatch(values, langCode);
    final map = <String, String>{};
    for (int i = 0; i < keys.length; i++) {
      map[keys[i]] = translated[i];
    }
    _cache = map;
    _cacheFor = langCode;
  }
}
