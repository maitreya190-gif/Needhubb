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
    'chitchatLabel': 'Chit-Chat',
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
    'nearYouRankedByInterests': 'Near you, ranked by shared interests',
    'freeNeedsNearYou': 'Free needs near you',
    'closestMatches': 'CLOSEST MATCHES',
    'matchesSomeFilters': 'MATCHES SOME FILTERS',
    'youBothLike': 'YOU BOTH LIKE',
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
    // Signup step counter
    'stepXofY': 'Step {step} of {total}',
    // Signup headings
    'yourIdentity': 'YOUR IDENTITY',
    'whatsYourName': "What's your name?",
    'yourNameDesc': 'Your name is how others find and recognise you on NeedHub.',
    'yourInterests': 'YOUR INTERESTS',
    'whatAreYouInto': 'What are you into?',
    'pickWhatYouEnjoy': "Pick what you genuinely enjoy. This is how you'll find people near you.",
    'addYourOwn': 'Add your own…',
    'yourSkills': 'YOUR SKILLS',
    'whatCanYouHelpWith': 'What can you help with?',
    'skillsYoureWilling': "Skills you're willing to offer on NeedHub.",
    'yourLocation': 'YOUR LOCATION',
    'whereAreYouBased': 'Where are you based?',
    'locationDesc': "NeedHub surfaces needs near you. Your exact address is never shared — only your city or neighbourhood.",
    'continueLabel': 'Continue',
    'alreadyHaveAccount': 'Already have an account? Log in',
    'add': 'Add',
    'aboutYou': 'ABOUT YOU',
    'bioHint': 'A short bio about yourself',
    'rulesTitle': "Before you dive in",
    'rulesSubtitle': 'A few things that make NeedHub work well for everyone.',
    'verifyEmailKicker': 'VERIFY YOUR EMAIL',
    'weSentYouACode': 'We sent you a code',
    // Signup field labels / hints / body text
    'chooseLanguageKicker': 'CHOOSE LANGUAGE',
    'needhubIn8Languages': 'NeedHub works in 8 Indian languages. You can change this anytime.',
    'nameHint': 'Your display name (min 2 characters)',
    'usernameHint': '@yourusername',
    'uniqueVisibleToOthers': 'Unique · visible to others',
    'passwordHint': 'At least 8 characters',
    'passwordEncrypted': 'Your password is encrypted and never shared with anyone.',
    'referralCodeLabel': 'Referral code (optional)',
    'referralCodeDesc': 'Have a friend\'s code? Both of you earn 15 points when you post your first need.',
    'enterOtpSentTo': 'Enter the 6-digit code we sent to',
    'didntGetItResend': "Didn't get it? Resend code",
    'cityOrNeighbourhood': 'City or neighbourhood (e.g. Koramangala)',
    'helpRadius': 'Help radius',
    'onlyCityVisible': 'Only your city or area is visible to others. Never your precise address.',
    'locationPrecision': 'Location Precision',
    'locationPrecisionDesc': 'Do you want to share your exact location or an approximate 2km radius?',
    'twoKmRadius': '2km Radius',
    'exactLocation': 'Exact Location',
    // Signup About You step
    'tellPeopleWhoYouAre': 'Tell people who you are',
    'theseShowOnProfile': 'These show on your profile and help people decide to connect. You can edit them anytime.',
    'aLineAboutYouBio': 'A LINE ABOUT YOU (BIO)',
    'bioPromptHint': 'e.g. Frontend dev, coffee snob, weekend trekker.',
    'skillPromptHint': 'e.g. DSA — I love breaking down complex algorithms…',
    'collabPromptHint': 'e.g. Someone who ships fast and loves late-night brainstorming.',
    'needPromptHint': 'e.g. A designer for my side project.',
    // Signup Rules step
    'almostDone': 'ALMOST DONE',
    'fewThingsBeforeWeStart': 'A few things before we start',
    'enableNotifications': 'Enable notifications',
    'stayInLoopWhenResponds': 'Stay in the loop when someone responds',
    'youBrowseYouChoose': 'You browse. You choose.',
    'needhubNeverAutoMatches': 'NeedHub never auto-matches you with anyone. You browse people nearby who share your interests and choose who you reach out to — fully on your terms.',
    'startExploring': 'Start exploring',
    // Signup snackbar / error messages
    'enableLocationServices': 'Please enable location services.',
    'locationPermissionDenied': 'Location permission was denied.',
    'couldntGetGpsFix': "Couldn't get GPS fix. Try picking on the map instead.",
    'gotYourLocation': 'Got your location — you can replace with a city name if you like.',
    'couldNotFetchLocation': 'Could not fetch location',
    'usernameAlreadyTaken': 'That username is already taken. Try another.',
    'emailAlreadyRegistered': 'That email is already registered. Try logging in instead.',
    'nameTooShort': 'Name must be at least 2 characters.',
    'invalidEmail': 'Please enter a valid email address.',
    'passwordTooShort': 'Password must be at least 8 characters.',
    'checkDetails': 'Check your details and try again.',
    'serverError': 'Server error. Please try again.',
    'couldNotReachServer': 'Could not reach the server. Check your connection.',
    // Connect request sheet
    'sendConnectRequest': 'Send a connect request',
    'suggestAnActivity': 'SUGGEST AN ACTIVITY',
    'addANote': 'ADD A NOTE',
    'connectNoteHint': 'Hey! I noticed we both like',
    'connectSafetyTip': 'For your first meet-up, suggest a public place. NeedHub never shares your exact location.',
    'sendRequest': 'Send request',
    'requestSent': 'Request sent!',
    'requestSentDesc': 'will be notified. Chat unlocks when they accept.',
    'activityStudy': 'Study together',
    'activityCoffee': 'Grab a coffee',
    'activityPairUp': 'Pair up',
    'activityTrek': 'Trek',
    // Connect detail screen
    'theOverlap': 'THE OVERLAP',
    'overlapDesc': 'Filled tags are interests you share. Reach out because of what you both do — not how you look.',
    'fewPhotosSection': 'A FEW PHOTOS · OPTIONAL, NEVER RANKED',
    'noPhotosYet': 'No photos added yet',
    // Rating screen
    'taskComplete': 'TASK COMPLETE',
    'ratingHelpsTrust': 'Your rating helps everyone trust who they meet — honest and specific.',
    'tapAStarToRate': 'Tap a star to rate',
    'quickNoteOptional': 'A QUICK NOTE (OPTIONAL)',
    'ratingNoteHint': 'Showed up on time, explained clearly…',
    'submitRating': 'Submit rating',
    'notGreat': 'Not great',
    'itWasOkay': 'It was okay',
    'prettyGood': 'Pretty good',
    'reallyHelpful': 'Really helpful',
    'absolutelyBrilliant': 'Absolutely brilliant!',
    'thanksForReview': 'Thanks for your review!',
    'feedbackBuildsTrust': 'Your feedback helps build trust on NeedHub.',
    'theyEarned': 'They earned',
    // Post need sheet
    'earnTitleHint': 'e.g., Need calculus tutor for 2 weeks',
    'connectTitleHint': 'e.g., Looking for hackathon teammate',
    'describeNeedHint': 'Describe what you need in detail...',
    'titleAndDetailsRequired': 'Title (min 5) & details (min 10) required to post',
    'readyToPost': 'Ready to post!',
    'markAsUrgent': 'Mark as Urgent',
    'urgentDesc': 'Boosts visibility as your deadline nears',
    'setDeadline': 'Set a deadline (required)',
    'decomposeWithAi': 'Decompose with AI',
    'decomposingWithAi': 'Decomposing with AI...',
    'addMoreDetailToDecompose': 'Add at least 20 characters of detail to decompose',
    'selectNone': 'Select None',
    'useOriginalNeed': 'Use Original Need',
    'needPostedSuccess': 'Need posted successfully!',
    'needsPostedSuccess': 'needs posted!',
    'aiDecomposedInto': 'AI decomposed into',
    'recommendations': 'recommendations',
    // Alerts tab
    'clearNotificationsTitle': 'Clear Notifications',
    'chooseWhichToRemove': 'Choose which notifications to remove',
    'last24Hours': 'Last 24 hours',
    'last24HoursDesc': 'Clear notifications from today',
    'last7Days': 'Last 7 days',
    'last7DaysDesc': 'Clear notifications from this week',
    'allTime': 'All time',
    'allTimeDesc': 'Clear all notifications permanently',
    'selectManually': 'Select manually',
    'selectManuallyDesc': 'Pick specific notifications to clear',
    'clearAllNotificationsTitle': 'Clear all notifications?',
    'clearAllNotificationsBody': 'This will permanently delete all your notifications. This action cannot be undone.',
    'clearAll': 'Clear all',
    'notificationCleared': 'notification cleared',
    'notificationsCleared': 'notifications cleared',
    'connectGroup': 'Connect',
    'earnGroup': 'Earn',
    'chatGroup': 'Chat',
    'impactGroup': 'Impact',
    'otherGroup': 'Other',
    // Filter sheet
    'filterAndSort': 'Filter & Sort',
    'filterSubtitle': 'Adjust feasibility, interests, skills & gender',
    'resetAll': 'Reset All',
    'feasibilityAndLocation': 'FEASIBILITY & LOCATION',
    'feasibilitySubtitle': 'Set maximum distance radius and budget limits',
    'budgetRange': 'BUDGET RANGE (₹)',
    'minBudgetLabel': 'Min budget',
    'maxBudgetLabel': 'Max budget',
    'interestsFilterSubtitle': 'Filter profiles and needs matching topics you care about',
    'skillsFilterSubtitle': 'Filter by specific expertise and practical skills',
    'genderPreference': 'GENDER PREFERENCE',
    'genderFilterSubtitle': 'Show profiles or posters of specific gender',
    'sortOrder': 'SORT ORDER',
    'sortSubtitle': 'Arrange items by recency, distance, or reward',
    'newestFirst': 'Newest first',
    'nearestFirst': 'Nearest first',
    'highestReward': 'Highest reward/points',
    'applyFilters': 'Apply Filters',
    'anyDistance': '50+ km (Any)',
    // Gender options (display only — API values stay English)
    'genderFemale': 'Female',
    'genderMale': 'Male',
    'genderNonBinary': 'Non-binary',
    // Report sheet
    'reportReasonInappropriate': 'Inappropriate content or behaviour',
    'reportReasonFake': 'Fake or misleading profile',
    'reportReasonHarassment': 'Harassment or hate speech',
    'reportReasonSpam': 'Spam or scam',
    'reportReasonUnderage': 'Underage user',
    'reportReasonOther': 'Something else',
    'alreadyReported': 'You already reported this recently.',
    'cantReportSelf': "You can't report yourself.",
    'contentNotFound': 'That user or content no longer exists.',
    'reportSubmitFailed': 'Could not submit — please retry.',
    'reportedAndBlocked': 'Reported and blocked',
    'reportSubmitted': 'Report submitted',
    'reportBlockedDesc': 'has been blocked and our team will review your report shortly.',
    'reportedDesc': 'Thanks — our trust & safety team will review your report shortly.',
    'reportReason': 'REASON',
    'reportSheetSubtitle': 'Tell us what happened. Reports are anonymous and reviewed by our team.',
    'reportAndBlock': 'Report and block',
    // Redeem screen
    'yourBalance': 'YOUR BALANCE',
    'availableRewards': 'AVAILABLE REWARDS',
    'noRewardsAvailable': 'No rewards available right now',
    'pointsEarnedInfo': 'Points are earned by completing needs, receiving 4★+ reviews, and getting certificates approved.',
    'soldOut': 'Sold out',
    'locked': 'Locked',
    'redeemed': 'Redeemed!',
    'yourCode': 'YOUR CODE',
    'balanceAfter': 'Balance after',
    // Impact screen
    'verified': 'Verified',
    'inReview': 'In Review',
    'uploadRequired': 'Upload required',
    'boostANeed': 'BOOST A NEED',
    'profileBoostSection': 'PROFILE BOOST',
    'confirmBoost': 'Confirm Boost',
    'boostDuration': 'Boost duration',
    'cost': 'Cost',
    'boostNow': 'Boost Now',
    'selectNeedToBoost': 'Select a Need to Boost',
    'pickOpenNeed': 'Pick one of your open needs',
    'boostingLabel': 'Boosting…',
    'upload': 'Upload',
    // History screen
    'feedbackGivenToYou': 'FEEDBACK GIVEN TO YOU',
    'hideFeedback': 'Hide feedback',
    'tapToSeeFeedback': 'Tap to see feedback',
    'rateThem': 'Rate them',
    'youveHelped': 'You\'ve helped',
    'completedTasks': 'Completed',
    'tasks': 'tasks',
    'people': 'people',
    // Edit profile
    'editProfile': 'Edit profile',
    'displayName': 'Display Name',
    'saveChanges': 'Save changes',
    'addOther': 'Add other',
    'gettingLocation': 'Getting location…',
    'useMyCurrentLocation': 'Use my current location',
    'pickOnMap': 'Pick on map',
    // Settings
    'appearance': 'APPEARANCE',
    'privacyAlerts': 'PRIVACY & ALERTS',
    'activitySection': 'ACTIVITY',
    'accountSection': 'ACCOUNT',
    'notificationsLabel': 'Notifications',
    'alertsWhenResponds': 'Alerts when someone responds',
    'hidePreciseLocation': 'Hide precise location',
    'showNeighbourhoodOnly': 'Show only neighbourhood level',
    'blockedUsers': 'Blocked users',
    'logOut': 'Log out',
    'noOneIsBlocked': 'No one is blocked',
    // ChitChat
    'youreAvailableForChat': "You're available for a chat right now",
    'markYourselfAvailableChat': 'Mark yourself available',
    'upForAChatRightNow': 'UP FOR A CHAT RIGHT NOW',
    'visibleFor24h': 'You (visible for 24h)',
    'nearbyWillSeeYouFirst': 'Nearby people will see you first',
    'live': 'Live',
    'chitchatInfoText': 'Chit-chat is for casual hellos only. Each session is visible for 24 hours. You can turn it off anytime.',
    'noOneElseUpForChat': 'No one else is up for a chat right now',
    'friendsDMs': "FRIENDS' DMs",
    'directMessages': 'Direct Messages',
    'tapToChat': 'Tap to chat',
    // Personality test
    'personalityQuizTitle': 'PERSONALITY QUIZ · POWERED BY LYZR',
    'submitTest': 'Submit test',
    'yourPersonalityTitle': 'Your Personality',
    'youAre': 'YOU ARE',
    'traitProfile': 'TRAIT PROFILE',
    'backToNeedHub': 'Back to NeedHub',
    'pickAnAnswer': 'Pick an answer to continue.',
    'yourProfileHelps': 'Your profile helps us surface a compatibility % on Connect. You can retake anytime from your You tab.',
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
  // Compatibility alias — langCode ignored; translations come from the global cache
  static S of(String langCode) => const S._();

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
  String get chitchatLabel => _get('chitchatLabel');
  String get nearYouRankedByInterests => _get('nearYouRankedByInterests');
  String get freeNeedsNearYou => _get('freeNeedsNearYou');
  String get closestMatches => _get('closestMatches');
  String get matchesSomeFilters => _get('matchesSomeFilters');
  String get youBothLike => _get('youBothLike');
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
  String get yourIdentity => _get('yourIdentity');
  String get whatsYourName => _get('whatsYourName');
  String get yourNameDesc => _get('yourNameDesc');
  String get yourInterests => _get('yourInterests');
  String get whatAreYouInto => _get('whatAreYouInto');
  String get pickWhatYouEnjoy => _get('pickWhatYouEnjoy');
  String get addYourOwn => _get('addYourOwn');
  String get yourSkills => _get('yourSkills');
  String get whatCanYouHelpWith => _get('whatCanYouHelpWith');
  String get skillsYoureWilling => _get('skillsYoureWilling');
  String get yourLocation => _get('yourLocation');
  String get whereAreYouBased => _get('whereAreYouBased');
  String get locationDesc => _get('locationDesc');
  String get continueLabel => _get('continueLabel');
  String get alreadyHaveAccount => _get('alreadyHaveAccount');
  String get add => _get('add');
  String get aboutYou => _get('aboutYou');
  String get bioHint => _get('bioHint');
  String get rulesTitle => _get('rulesTitle');
  String get rulesSubtitle => _get('rulesSubtitle');
  String get verifyEmailKicker => _get('verifyEmailKicker');
  String get weSentYouACode => _get('weSentYouACode');
  String stepXofY(int step, int total) => _get('stepXofY').replaceAll('{step}', '$step').replaceAll('{total}', '$total');
  String get chooseLanguageKicker => _get('chooseLanguageKicker');
  String get needhubIn8Languages => _get('needhubIn8Languages');
  String get nameHint => _get('nameHint');
  String get usernameHint => _get('usernameHint');
  String get uniqueVisibleToOthers => _get('uniqueVisibleToOthers');
  String get passwordHint => _get('passwordHint');
  String get passwordEncrypted => _get('passwordEncrypted');
  String get referralCodeLabel => _get('referralCodeLabel');
  String get referralCodeDesc => _get('referralCodeDesc');
  String get enterOtpSentTo => _get('enterOtpSentTo');
  String get didntGetItResend => _get('didntGetItResend');
  String get cityOrNeighbourhood => _get('cityOrNeighbourhood');
  String get helpRadius => _get('helpRadius');
  String get onlyCityVisible => _get('onlyCityVisible');
  String get locationPrecision => _get('locationPrecision');
  String get locationPrecisionDesc => _get('locationPrecisionDesc');
  String get twoKmRadius => _get('twoKmRadius');
  String get exactLocation => _get('exactLocation');
  String get tellPeopleWhoYouAre => _get('tellPeopleWhoYouAre');
  String get theseShowOnProfile => _get('theseShowOnProfile');
  String get aLineAboutYouBio => _get('aLineAboutYouBio');
  String get bioPromptHint => _get('bioPromptHint');
  String get skillPromptHint => _get('skillPromptHint');
  String get collabPromptHint => _get('collabPromptHint');
  String get needPromptHint => _get('needPromptHint');
  String get almostDone => _get('almostDone');
  String get fewThingsBeforeWeStart => _get('fewThingsBeforeWeStart');
  String get enableNotifications => _get('enableNotifications');
  String get stayInLoopWhenResponds => _get('stayInLoopWhenResponds');
  String get youBrowseYouChoose => _get('youBrowseYouChoose');
  String get needhubNeverAutoMatches => _get('needhubNeverAutoMatches');
  String get startExploring => _get('startExploring');
  String get enableLocationServices => _get('enableLocationServices');
  String get locationPermissionDenied => _get('locationPermissionDenied');
  String get couldntGetGpsFix => _get('couldntGetGpsFix');
  String get gotYourLocation => _get('gotYourLocation');
  String get couldNotFetchLocation => _get('couldNotFetchLocation');
  String get usernameAlreadyTaken => _get('usernameAlreadyTaken');
  String get emailAlreadyRegistered => _get('emailAlreadyRegistered');
  String get nameTooShort => _get('nameTooShort');
  String get invalidEmail => _get('invalidEmail');
  String get passwordTooShort => _get('passwordTooShort');
  String get checkDetails => _get('checkDetails');
  String get serverError => _get('serverError');
  String get couldNotReachServer => _get('couldNotReachServer');
  String get sendConnectRequest => _get('sendConnectRequest');
  String get suggestAnActivity => _get('suggestAnActivity');
  String get addANote => _get('addANote');
  String get connectNoteHint => _get('connectNoteHint');
  String get connectSafetyTip => _get('connectSafetyTip');
  String get sendRequest => _get('sendRequest');
  String get requestSent => _get('requestSent');
  String get requestSentDesc => _get('requestSentDesc');
  String get activityStudy => _get('activityStudy');
  String get activityCoffee => _get('activityCoffee');
  String get activityPairUp => _get('activityPairUp');
  String get activityTrek => _get('activityTrek');
  String get theOverlap => _get('theOverlap');
  String get overlapDesc => _get('overlapDesc');
  String get fewPhotosSection => _get('fewPhotosSection');
  String get noPhotosYet => _get('noPhotosYet');
  String get taskComplete => _get('taskComplete');
  String get ratingHelpsTrust => _get('ratingHelpsTrust');
  String get tapAStarToRate => _get('tapAStarToRate');
  String get quickNoteOptional => _get('quickNoteOptional');
  String get ratingNoteHint => _get('ratingNoteHint');
  String get submitRating => _get('submitRating');
  String get notGreat => _get('notGreat');
  String get itWasOkay => _get('itWasOkay');
  String get prettyGood => _get('prettyGood');
  String get reallyHelpful => _get('reallyHelpful');
  String get absolutelyBrilliant => _get('absolutelyBrilliant');
  String get thanksForReview => _get('thanksForReview');
  String get feedbackBuildsTrust => _get('feedbackBuildsTrust');
  String get theyEarned => _get('theyEarned');
  String get earnTitleHint => _get('earnTitleHint');
  String get connectTitleHint => _get('connectTitleHint');
  String get describeNeedHint => _get('describeNeedHint');
  String get titleAndDetailsRequired => _get('titleAndDetailsRequired');
  String get readyToPost => _get('readyToPost');
  String get markAsUrgent => _get('markAsUrgent');
  String get urgentDesc => _get('urgentDesc');
  String get setDeadline => _get('setDeadline');
  String get decomposeWithAi => _get('decomposeWithAi');
  String get decomposingWithAi => _get('decomposingWithAi');
  String get addMoreDetailToDecompose => _get('addMoreDetailToDecompose');
  String get selectNone => _get('selectNone');
  String get useOriginalNeed => _get('useOriginalNeed');
  String get needPostedSuccess => _get('needPostedSuccess');
  String get needsPostedSuccess => _get('needsPostedSuccess');
  String get aiDecomposedInto => _get('aiDecomposedInto');
  String get recommendations => _get('recommendations');
  String get clearNotificationsTitle => _get('clearNotificationsTitle');
  String get chooseWhichToRemove => _get('chooseWhichToRemove');
  String get last24Hours => _get('last24Hours');
  String get last24HoursDesc => _get('last24HoursDesc');
  String get last7Days => _get('last7Days');
  String get last7DaysDesc => _get('last7DaysDesc');
  String get allTime => _get('allTime');
  String get allTimeDesc => _get('allTimeDesc');
  String get selectManually => _get('selectManually');
  String get selectManuallyDesc => _get('selectManuallyDesc');
  String get clearAllNotificationsTitle => _get('clearAllNotificationsTitle');
  String get clearAllNotificationsBody => _get('clearAllNotificationsBody');
  String get clearAll => _get('clearAll');
  String get notificationCleared => _get('notificationCleared');
  String get notificationsCleared => _get('notificationsCleared');
  String get connectGroup => _get('connectGroup');
  String get earnGroup => _get('earnGroup');
  String get chatGroup => _get('chatGroup');
  String get impactGroup => _get('impactGroup');
  String get otherGroup => _get('otherGroup');
  String get filterAndSort => _get('filterAndSort');
  String get filterSubtitle => _get('filterSubtitle');
  String get resetAll => _get('resetAll');
  String get feasibilityAndLocation => _get('feasibilityAndLocation');
  String get feasibilitySubtitle => _get('feasibilitySubtitle');
  String get budgetRange => _get('budgetRange');
  String get minBudgetLabel => _get('minBudgetLabel');
  String get maxBudgetLabel => _get('maxBudgetLabel');
  String get interestsFilterSubtitle => _get('interestsFilterSubtitle');
  String get skillsFilterSubtitle => _get('skillsFilterSubtitle');
  String get genderPreference => _get('genderPreference');
  String get genderFilterSubtitle => _get('genderFilterSubtitle');
  String get sortOrder => _get('sortOrder');
  String get sortSubtitle => _get('sortSubtitle');
  String get newestFirst => _get('newestFirst');
  String get nearestFirst => _get('nearestFirst');
  String get highestReward => _get('highestReward');
  String get applyFilters => _get('applyFilters');
  String get anyDistance => _get('anyDistance');
  String get genderFemale => _get('genderFemale');
  String get genderMale => _get('genderMale');
  String get genderNonBinary => _get('genderNonBinary');
  String get reportReasonInappropriate => _get('reportReasonInappropriate');
  String get reportReasonFake => _get('reportReasonFake');
  String get reportReasonHarassment => _get('reportReasonHarassment');
  String get reportReasonSpam => _get('reportReasonSpam');
  String get reportReasonUnderage => _get('reportReasonUnderage');
  String get reportReasonOther => _get('reportReasonOther');
  String get alreadyReported => _get('alreadyReported');
  String get cantReportSelf => _get('cantReportSelf');
  String get contentNotFound => _get('contentNotFound');
  String get reportSubmitFailed => _get('reportSubmitFailed');
  String get reportedAndBlocked => _get('reportedAndBlocked');
  String get reportSubmitted => _get('reportSubmitted');
  String get reportBlockedDesc => _get('reportBlockedDesc');
  String get reportedDesc => _get('reportedDesc');
  String get reportReason => _get('reportReason');
  String get reportSheetSubtitle => _get('reportSheetSubtitle');
  String get reportAndBlock => _get('reportAndBlock');
  String get yourBalance => _get('yourBalance');
  String get availableRewards => _get('availableRewards');
  String get noRewardsAvailable => _get('noRewardsAvailable');
  String get pointsEarnedInfo => _get('pointsEarnedInfo');
  String get soldOut => _get('soldOut');
  String get locked => _get('locked');
  String get redeemed => _get('redeemed');
  String get yourCode => _get('yourCode');
  String get balanceAfter => _get('balanceAfter');
  String get verified => _get('verified');
  String get inReview => _get('inReview');
  String get uploadRequired => _get('uploadRequired');
  String get boostANeed => _get('boostANeed');
  String get profileBoostSection => _get('profileBoostSection');
  String get confirmBoost => _get('confirmBoost');
  String get boostDuration => _get('boostDuration');
  String get cost => _get('cost');
  String get boostNow => _get('boostNow');
  String get selectNeedToBoost => _get('selectNeedToBoost');
  String get pickOpenNeed => _get('pickOpenNeed');
  String get boostingLabel => _get('boostingLabel');
  String get upload => _get('upload');
  String get feedbackGivenToYou => _get('feedbackGivenToYou');
  String get hideFeedback => _get('hideFeedback');
  String get tapToSeeFeedback => _get('tapToSeeFeedback');
  String get rateThem => _get('rateThem');
  String get youveHelped => _get('youveHelped');
  String get completedTasks => _get('completedTasks');
  String get tasks => _get('tasks');
  String get people => _get('people');
  String get editProfile => _get('editProfile');
  String get displayName => _get('displayName');
  String get saveChanges => _get('saveChanges');
  String get addOther => _get('addOther');
  String get gettingLocation => _get('gettingLocation');
  String get useMyCurrentLocation => _get('useMyCurrentLocation');
  String get pickOnMap => _get('pickOnMap');
  String get appearance => _get('appearance');
  String get privacyAlerts => _get('privacyAlerts');
  String get activitySection => _get('activitySection');
  String get accountSection => _get('accountSection');
  String get notificationsLabel => _get('notificationsLabel');
  String get alertsWhenResponds => _get('alertsWhenResponds');
  String get hidePreciseLocation => _get('hidePreciseLocation');
  String get showNeighbourhoodOnly => _get('showNeighbourhoodOnly');
  String get blockedUsers => _get('blockedUsers');
  String get logOut => _get('logOut');
  String get noOneIsBlocked => _get('noOneIsBlocked');
  String get youreAvailableForChat => _get('youreAvailableForChat');
  String get markYourselfAvailableChat => _get('markYourselfAvailableChat');
  String get upForAChatRightNow => _get('upForAChatRightNow');
  String get visibleFor24h => _get('visibleFor24h');
  String get nearbyWillSeeYouFirst => _get('nearbyWillSeeYouFirst');
  String get live => _get('live');
  String get chitchatInfoText => _get('chitchatInfoText');
  String get noOneElseUpForChat => _get('noOneElseUpForChat');
  String get friendsDMs => _get('friendsDMs');
  String get directMessages => _get('directMessages');
  String get tapToChat => _get('tapToChat');
  String get personalityQuizTitle => _get('personalityQuizTitle');
  String get submitTest => _get('submitTest');
  String get yourPersonalityTitle => _get('yourPersonalityTitle');
  String get youAre => _get('youAre');
  String get traitProfile => _get('traitProfile');
  String get backToNeedHub => _get('backToNeedHub');
  String get pickAnAnswer => _get('pickAnAnswer');
  String get yourProfileHelps => _get('yourProfileHelps');

  /// Load all UI strings for [langCode] from Groq and store in cache.
  static Future<void> loadTranslations(String langCode) async {
    if (langCode == 'en') {
      _cache = {};
      _cacheFor = 'en';
      return;
    }
    final keys = _en.keys.toList();
    final values = _en.values.toList();

    // Pre-populate the cache with English so any chunk that fails still has a
    // usable fallback for its keys.
    final map = <String, String>{};
    for (int i = 0; i < keys.length; i++) {
      map[keys[i]] = values[i];
    }

    // Chunk the strings into small batches. One giant Groq call is fragile —
    // if the LLM returns even one malformed element, the whole batch is
    // rejected and every UI string falls back to English. Small chunks in
    // parallel isolate failures and stay well under any server-side cap.
    const chunkSize = 40;
    final futures = <Future<void>>[];
    for (int start = 0; start < values.length; start += chunkSize) {
      final end = (start + chunkSize > values.length) ? values.length : start + chunkSize;
      final chunkValues = values.sublist(start, end);
      futures.add(() async {
        final translated = await translateBatch(chunkValues, langCode);
        if (translated.length == chunkValues.length) {
          for (int j = 0; j < chunkValues.length; j++) {
            map[keys[start + j]] = translated[j];
          }
        }
      }());
    }
    await Future.wait(futures);

    _cache = map;
    _cacheFor = langCode;
  }
}
