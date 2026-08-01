import '../providers/language_provider.dart';

// Hardcoded UI strings for 8 languages. No ARB/intl toolchain.
// Add new strings as static fields; keep all 8 language entries in sync.
class S {
  final String langCode;
  const S._(this.langCode);

  static const _strings = <String, Map<String, String>>{
    // ── Auth ──────────────────────────────────────────────────────────────────
    'chooseLanguage': {
      'en': 'Choose your language',
      'hi': 'अपनी भाषा चुनें',
      'bn': 'আপনার ভাষা বেছে নিন',
      'te': 'మీ భాషను ఎంచుకోండి',
      'mr': 'तुमची भाषा निवडा',
      'ta': 'உங்கள் மொழியை தேர்ந்தெடுக்கவும்',
      'gu': 'તમારી ભાષા પસંદ કરો',
      'kn': 'ನಿಮ್ಮ ಭಾಷೆಯನ್ನು ಆರಿಸಿ',
    },
    'continueBtn': {
      'en': 'Continue',
      'hi': 'जारी रखें',
      'bn': 'চালিয়ে যান',
      'te': 'కొనసాగించు',
      'mr': 'पुढे जा',
      'ta': 'தொடரவும்',
      'gu': 'ચાલુ રાખો',
      'kn': 'ಮುಂದುವರಿಸಿ',
    },
    'back': {
      'en': 'Back',
      'hi': 'वापस',
      'bn': 'ফিরে যান',
      'te': 'వెనక్కి',
      'mr': 'मागे',
      'ta': 'திரும்பு',
      'gu': 'પાછળ',
      'kn': 'ಹಿಂದೆ',
    },
    'next': {
      'en': 'Next',
      'hi': 'अगला',
      'bn': 'পরবর্তী',
      'te': 'తదుపరి',
      'mr': 'पुढील',
      'ta': 'அடுத்து',
      'gu': 'આગળ',
      'kn': 'ಮುಂದೆ',
    },
    'signUp': {
      'en': 'Sign Up',
      'hi': 'साइन अप करें',
      'bn': 'নিবন্ধন করুন',
      'te': 'సైన్ అప్ చేయండి',
      'mr': 'साइन अप करा',
      'ta': 'பதிவு செய்க',
      'gu': 'સાઇન અપ કરો',
      'kn': 'ಸೈನ್ ಅಪ್ ಮಾಡಿ',
    },
    'login': {
      'en': 'Log In',
      'hi': 'लॉग इन करें',
      'bn': 'লগ ইন করুন',
      'te': 'లాగిన్ అవ్వండి',
      'mr': 'लॉग इन करा',
      'ta': 'உள்நுழைக',
      'gu': 'લૉગ ઇન કરો',
      'kn': 'ಲಾಗಿನ್ ಮಾಡಿ',
    },
    'email': {
      'en': 'Email',
      'hi': 'ईमेल',
      'bn': 'ইমেইল',
      'te': 'ఇమెయిల్',
      'mr': 'ईमेल',
      'ta': 'மின்னஞ்சல்',
      'gu': 'ઈમેઈલ',
      'kn': 'ಇಮೇಲ್',
    },
    'password': {
      'en': 'Password',
      'hi': 'पासवर्ड',
      'bn': 'পাসওয়ার্ড',
      'te': 'పాస్‌వర్డ్',
      'mr': 'पासवर्ड',
      'ta': 'கடவுச்சொல்',
      'gu': 'પાસવર્ડ',
      'kn': 'ಪಾಸ್ವರ್ಡ್',
    },
    'name': {
      'en': 'Name',
      'hi': 'नाम',
      'bn': 'নাম',
      'te': 'పేరు',
      'mr': 'नाव',
      'ta': 'பெயர்',
      'gu': 'નામ',
      'kn': 'ಹೆಸರು',
    },
    'username': {
      'en': 'Username',
      'hi': 'यूज़रनेम',
      'bn': 'ব্যবহারকারীর নাম',
      'te': 'యూజర్‌నేమ్',
      'mr': 'वापरकर्तानाव',
      'ta': 'பயனர் பெயர்',
      'gu': 'વપરાશકર્તા નામ',
      'kn': 'ಬಳಕೆದಾರ ಹೆಸರು',
    },
    'gender': {
      'en': 'Gender',
      'hi': 'लिंग',
      'bn': 'লিঙ্গ',
      'te': 'లింగం',
      'mr': 'लिंग',
      'ta': 'பாலினம்',
      'gu': 'જાતિ',
      'kn': 'ಲಿಂಗ',
    },
    // ── Feed ──────────────────────────────────────────────────────────────────
    'feed': {
      'en': 'Feed',
      'hi': 'फ़ीड',
      'bn': 'ফিড',
      'te': 'ఫీడ్',
      'mr': 'फीड',
      'ta': 'ஊட்டம்',
      'gu': 'ફીડ',
      'kn': 'ಫೀಡ್',
    },
    'explore': {
      'en': 'Explore',
      'hi': 'एक्सप्लोर',
      'bn': 'অন্বেষণ',
      'te': 'అన్వేషించు',
      'mr': 'एक्सप्लोर',
      'ta': 'ஆராயுங்கள்',
      'gu': 'અન્વેષણ',
      'kn': 'ಅನ್ವೇಷಿಸಿ',
    },
    'earn': {
      'en': 'Earn',
      'hi': 'कमाएं',
      'bn': 'উপার্জন',
      'te': 'సంపాదించు',
      'mr': 'कमाई',
      'ta': 'சம்பாதி',
      'gu': 'કમાઓ',
      'kn': 'ಸಂಪಾದಿಸಿ',
    },
    'connect': {
      'en': 'Connect',
      'hi': 'कनेक्ट',
      'bn': 'সংযোগ',
      'te': 'కనెక్ట్',
      'mr': 'कनेक्ट',
      'ta': 'இணைக்க',
      'gu': 'કનેક્ટ',
      'kn': 'ಸಂಪರ್ಕಿಸಿ',
    },
    'chitchat': {
      'en': 'ChitChat',
      'hi': 'चिटचैट',
      'bn': 'চিটচ্যাট',
      'te': 'చిట్‌చాట్',
      'mr': 'चिटचॅट',
      'ta': 'சிட்சாட்',
      'gu': 'ચિટચેટ',
      'kn': 'ಚಿಟ್‌ಚಾಟ್',
    },
    'postNeed': {
      'en': 'Post a Need',
      'hi': 'एक ज़रूरत पोस्ट करें',
      'bn': 'একটি প্রয়োজন পোস্ট করুন',
      'te': 'ఒక అవసరం పోస్ట్ చేయండి',
      'mr': 'एक गरज पोस्ट करा',
      'ta': 'ஒரு தேவையை இடுங்கள்',
      'gu': 'એક જરૂરિયાત પોસ્ট કરો',
      'kn': 'ಒಂದು ಅಗತ್ಯ ಪೋಸ್ಟ್ ಮಾಡಿ',
    },
    'nearby': {
      'en': 'Nearby',
      'hi': 'पास में',
      'bn': 'কাছাকাছি',
      'te': 'సమీపంలో',
      'mr': 'जवळपास',
      'ta': 'அருகில்',
      'gu': 'નજીકમાં',
      'kn': 'ಹತ್ತಿರದಲ್ಲಿ',
    },
    'budget': {
      'en': 'Budget',
      'hi': 'बजट',
      'bn': 'বাজেট',
      'te': 'బడ్జెట్',
      'mr': 'बजेट',
      'ta': 'பட்ஜெட்',
      'gu': 'બજેટ',
      'kn': 'ಬಜೆಟ್',
    },
    'offers': {
      'en': 'offers',
      'hi': 'ऑफ़र',
      'bn': 'অফার',
      'te': 'ఆఫర్లు',
      'mr': 'ऑफर',
      'ta': 'சலுகைகள்',
      'gu': 'ઓફર',
      'kn': 'ಆಫರ್‌ಗಳು',
    },
    'respond': {
      'en': 'Respond',
      'hi': 'जवाब दें',
      'bn': 'সাড়া দিন',
      'te': 'స్పందించు',
      'mr': 'प्रतिसाद द्या',
      'ta': 'பதிலளிக்கவும்',
      'gu': 'જવાબ આપો',
      'kn': 'ಪ್ರತಿಕ್ರಿಯಿಸಿ',
    },
    'applied': {
      'en': 'Applied',
      'hi': 'आवेदन किया',
      'bn': 'আবেদন করা হয়েছে',
      'te': 'దరఖాస్తు చేశారు',
      'mr': 'अर्ज केला',
      'ta': 'விண்ணப்பிக்கப்பட்டது',
      'gu': 'અરજી કરી',
      'kn': 'ಅರ್ಜಿ ಸಲ್ಲಿಸಿದ್ದಾರೆ',
    },
    // ── Navigation ────────────────────────────────────────────────────────────
    'hub': {
      'en': 'Hub',
      'hi': 'हब',
      'bn': 'হাব',
      'te': 'హబ్',
      'mr': 'हब',
      'ta': 'ஹப்',
      'gu': 'હબ',
      'kn': 'ಹಬ್',
    },
    'chats': {
      'en': 'Chats',
      'hi': 'चैट्स',
      'bn': 'চ্যাটস',
      'te': 'చాట్‌లు',
      'mr': 'चॅट्स',
      'ta': 'அரட்டைகள்',
      'gu': 'ચેટ્સ',
      'kn': 'ಚಾಟ್‌ಗಳು',
    },
    'you': {
      'en': 'You',
      'hi': 'आप',
      'bn': 'আপনি',
      'te': 'మీరు',
      'mr': 'तुम्ही',
      'ta': 'நீங்கள்',
      'gu': 'તમે',
      'kn': 'ನೀವು',
    },
    // ── Messages / Conversation ───────────────────────────────────────────────
    'translate': {
      'en': 'Translate',
      'hi': 'अनुवाद करें',
      'bn': 'অনুবাদ করুন',
      'te': 'అనువదించు',
      'mr': 'भाषांतर करा',
      'ta': 'மொழிபெயர்க்க',
      'gu': 'અનુવાદ કરો',
      'kn': 'ಅನುವಾದಿಸಿ',
    },
    'translating': {
      'en': 'Translating…',
      'hi': 'अनुवाद हो रहा है…',
      'bn': 'অনুবাদ করা হচ্ছে…',
      'te': 'అనువదిస్తోంది…',
      'mr': 'भाषांतर होत आहे…',
      'ta': 'மொழிபெயர்க்கப்படுகிறது…',
      'gu': 'અનુવાદ થઈ રહ્યો છે…',
      'kn': 'ಅನುವಾದಿಸಲಾಗುತ್ತಿದೆ…',
    },
    'showOriginal': {
      'en': 'Show original',
      'hi': 'मूल दिखाएं',
      'bn': 'মূল দেখান',
      'te': 'అసలు చూపించు',
      'mr': 'मूळ दाखवा',
      'ta': 'அசல் காட்டு',
      'gu': 'મૂળ બતાવો',
      'kn': 'ಮೂಲ ತೋರಿಸಿ',
    },
    'translateTo': {
      'en': 'Translate to',
      'hi': 'इसमें अनुवाद करें',
      'bn': 'এই ভাষায় অনুবাদ করুন',
      'te': 'ఇందులో అనువదించు',
      'mr': 'यात भाषांतर करा',
      'ta': 'இதற்கு மொழிபெயர்',
      'gu': 'આ ભાષામાં અનુવાદ કરો',
      'kn': 'ಇದಕ್ಕೆ ಅನುವಾದಿಸಿ',
    },
    // ── Voice / STT ───────────────────────────────────────────────────────────
    'tapToSpeak': {
      'en': 'Tap to speak',
      'hi': 'बोलने के लिए टैप करें',
      'bn': 'বলতে ট্যাপ করুন',
      'te': 'మాట్లాడటానికి నొక్కండి',
      'mr': 'बोलण्यासाठी टॅप करा',
      'ta': 'பேச தட்டவும்',
      'gu': 'બોલવા ટૅપ કરો',
      'kn': 'ಮಾತಾಡಲು ಟ್ಯಾಪ್ ಮಾಡಿ',
    },
    'listening': {
      'en': 'Listening…',
      'hi': 'सुन रहा है…',
      'bn': 'শুনছি…',
      'te': 'వింటోంది…',
      'mr': 'ऐकत आहे…',
      'ta': 'கேட்கிறது…',
      'gu': 'સાંભળી રહ્યા છે…',
      'kn': 'ಕೇಳುತ್ತಿದ್ದಾರೆ…',
    },
    'voiceNotAvailable': {
      'en': 'Voice input not available',
      'hi': 'वॉइस इनपुट उपलब्ध नहीं',
      'bn': 'ভয়েস ইনপুট পাওয়া যাচ্ছে না',
      'te': 'వాయిస్ ఇన్‌పుట్ అందుబాటులో లేదు',
      'mr': 'व्हॉइस इनपुट उपलब्ध नाही',
      'ta': 'குரல் உள்ளீடு கிடைக்கவில்லை',
      'gu': 'વૉઇસ ઇનપુટ ઉપલબ્ધ નથી',
      'kn': 'ಧ್ವನಿ ಇನ್‌ಪುಟ್ ಲಭ್ಯವಿಲ್ಲ',
    },
    // ── Profile / You screen ──────────────────────────────────────────────────
    'profile': {
      'en': 'Profile',
      'hi': 'प्रोफाइल',
      'bn': 'প্রোফাইল',
      'te': 'ప్రొఫైల్',
      'mr': 'प्रोफाइल',
      'ta': 'சுயவிவரம்',
      'gu': 'પ્રોફાઇલ',
      'kn': 'ಪ್ರೊಫೈಲ್',
    },
    'settings': {
      'en': 'Settings',
      'hi': 'सेटिंग्स',
      'bn': 'সেটিংস',
      'te': 'సెట్టింగ్స్',
      'mr': 'सेटिंग्ज',
      'ta': 'அமைப்புகள்',
      'gu': 'સેટિંગ્સ',
      'kn': 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು',
    },
    'logout': {
      'en': 'Log Out',
      'hi': 'लॉग आउट',
      'bn': 'লগ আউট',
      'te': 'లాగ్ అవుట్',
      'mr': 'लॉग आउट',
      'ta': 'வெளியேறு',
      'gu': 'લૉગ આઉટ',
      'kn': 'ಲಾಗ್ ಔಟ್',
    },
    'points': {
      'en': 'Points',
      'hi': 'पॉइंट्स',
      'bn': 'পয়েন্ট',
      'te': 'పాయింట్లు',
      'mr': 'पॉइंट्स',
      'ta': 'புள்ளிகள்',
      'gu': 'પૉઇન્ટ',
      'kn': 'ಅಂಕಗಳು',
    },
    'language': {
      'en': 'Language',
      'hi': 'भाषा',
      'bn': 'ভাষা',
      'te': 'భాష',
      'mr': 'भाषा',
      'ta': 'மொழி',
      'gu': 'ભાષા',
      'kn': 'ಭಾಷೆ',
    },
    // ── Post Need sheet ───────────────────────────────────────────────────────
    'whatDoYouNeed': {
      'en': 'What do you need?',
      'hi': 'आपको क्या चाहिए?',
      'bn': 'আপনার কী দরকার?',
      'te': 'మీకు ఏమి కావాలి?',
      'mr': 'तुम्हाला काय हवे आहे?',
      'ta': 'உங்களுக்கு என்ன வேண்டும்?',
      'gu': 'તમને શું જોઈએ છે?',
      'kn': 'ನಿಮಗೆ ಏನು ಬೇಕು?',
    },
    'title': {
      'en': 'Title',
      'hi': 'शीर्षक',
      'bn': 'শিরোনাম',
      'te': 'శీర్షిక',
      'mr': 'शीर्षक',
      'ta': 'தலைப்பு',
      'gu': 'શીર્ષક',
      'kn': 'ಶೀರ್ಷಿಕೆ',
    },
    'description': {
      'en': 'Description',
      'hi': 'विवरण',
      'bn': 'বিবরণ',
      'te': 'వివరణ',
      'mr': 'वर्णन',
      'ta': 'விளக்கம்',
      'gu': 'વર્ણન',
      'kn': 'ವಿವರಣೆ',
    },
    'post': {
      'en': 'Post',
      'hi': 'पोस्ट करें',
      'bn': 'পোস্ট করুন',
      'te': 'పోస్ట్ చేయి',
      'mr': 'पोस्ट करा',
      'ta': 'இடுக',
      'gu': 'પોસ્ট કરો',
      'kn': 'ಪೋಸ್ಟ್ ಮಾಡಿ',
    },
    // ── OTP / Verification ────────────────────────────────────────────────────
    'verifyEmail': {
      'en': 'Verify your email',
      'hi': 'अपना ईमेल सत्यापित करें',
      'bn': 'আপনার ইমেইল যাচাই করুন',
      'te': 'మీ ఇమెయిల్‌ను ధృవీకరించండి',
      'mr': 'तुमचा ईमेल सत्यापित करा',
      'ta': 'உங்கள் மின்னஞ்சலை சரிபார்க்கவும்',
      'gu': 'તમારી ઈમેઈલ ચકાસો',
      'kn': 'ನಿಮ್ಮ ಇಮೇಲ್ ಪರಿಶೀಲಿಸಿ',
    },
    'resendOtp': {
      'en': 'Resend OTP',
      'hi': 'OTP दोबारा भेजें',
      'bn': 'OTP পুনরায় পাঠান',
      'te': 'OTP మళ్ళీ పంపించు',
      'mr': 'OTP पुन्हा पाठवा',
      'ta': 'OTP மீண்டும் அனுப்பவும்',
      'gu': 'OTP ફરીથી મોકલો',
      'kn': 'OTP ಮತ್ತೆ ಕಳುಹಿಸಿ',
    },
    // ── General ───────────────────────────────────────────────────────────────
    'loading': {
      'en': 'Loading…',
      'hi': 'लोड हो रहा है…',
      'bn': 'লোড হচ্ছে…',
      'te': 'లోడ్ అవుతోంది…',
      'mr': 'लोड होत आहे…',
      'ta': 'ஏற்றுகிறது…',
      'gu': 'લોડ થઈ રહ્યું છે…',
      'kn': 'ಲೋಡ್ ಆಗುತ್ತಿದೆ…',
    },
    'error': {
      'en': 'Something went wrong',
      'hi': 'कुछ गलत हो गया',
      'bn': 'কিছু একটা ভুল হয়েছে',
      'te': 'ఏదో తప్పు జరిగింది',
      'mr': 'काहीतरी चुकले',
      'ta': 'ஏதோ தவறு நடந்தது',
      'gu': 'કંઈક ખોટું થઈ ગયું',
      'kn': 'ಏನೋ ತಪ್ಪಾಯಿತು',
    },
    'retry': {
      'en': 'Retry',
      'hi': 'पुनः प्रयास करें',
      'bn': 'আবার চেষ্টা করুন',
      'te': 'మళ్ళీ ప్రయత్నించు',
      'mr': 'पुन्हा प्रयत्न करा',
      'ta': 'மீண்டும் முயற்சிக்கவும்',
      'gu': 'ફરી પ્રયાસ કરો',
      'kn': 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ',
    },
    'cancel': {
      'en': 'Cancel',
      'hi': 'रद्द करें',
      'bn': 'বাতিল করুন',
      'te': 'రద్దు చేయి',
      'mr': 'रद्द करा',
      'ta': 'ரத்து செய்',
      'gu': 'રદ કરો',
      'kn': 'ರದ್ದುಮಾಡಿ',
    },
    'save': {
      'en': 'Save',
      'hi': 'सहेजें',
      'bn': 'সংরক্ষণ করুন',
      'te': 'సేవ్ చేయి',
      'mr': 'जतन करा',
      'ta': 'சேமி',
      'gu': 'સાચવો',
      'kn': 'ಉಳಿಸಿ',
    },
    'done': {
      'en': 'Done',
      'hi': 'हो गया',
      'bn': 'সম্পন্ন',
      'te': 'పూర్తయింది',
      'mr': 'झाले',
      'ta': 'முடிந்தது',
      'gu': 'થઈ ગયું',
      'kn': 'ಮುಗಿಯಿತು',
    },
    'search': {
      'en': 'Search',
      'hi': 'खोजें',
      'bn': 'অনুসন্ধান করুন',
      'te': 'శోధించు',
      'mr': 'शोधा',
      'ta': 'தேடுக',
      'gu': 'શોધો',
      'kn': 'ಹುಡುಕಿ',
    },
    'myNeeds': {
      'en': 'My Needs',
      'hi': 'मेरी ज़रूरतें',
      'bn': 'আমার প্রয়োজনীয়তা',
      'te': 'నా అవసరాలు',
      'mr': 'माझ्या गरजा',
      'ta': 'என் தேவைகள்',
      'gu': 'મારી જરૂરિયાતો',
      'kn': 'ನನ್ನ ಅಗತ್ಯಗಳು',
    },
    'interests': {
      'en': 'Interests',
      'hi': 'रुचियां',
      'bn': 'আগ্রহ',
      'te': 'ఆసక్తులు',
      'mr': 'आवडी',
      'ta': 'ஆர்வங்கள்',
      'gu': 'રુચિઓ',
      'kn': 'ಆಸಕ್ತಿಗಳು',
    },
    'skills': {
      'en': 'Skills',
      'hi': 'कौशल',
      'bn': 'দক্ষতা',
      'te': 'నైపుణ్యాలు',
      'mr': 'कौशल्ये',
      'ta': 'திறன்கள்',
      'gu': 'કૌشल',
      'kn': 'ಕೌಶಲ್ಯಗಳು',
    },
    'location': {
      'en': 'Location',
      'hi': 'स्थान',
      'bn': 'অবস্থান',
      'te': 'స్థానం',
      'mr': 'स्थान',
      'ta': 'இடம்',
      'gu': 'સ્થાન',
      'kn': 'ಸ್ಥಳ',
    },
    'feedLanguage': {
      'en': 'Feed language',
      'hi': 'फ़ीड भाषा',
      'bn': 'ফিড ভাষা',
      'te': 'ఫీడ్ భాష',
      'mr': 'फीड भाषा',
      'ta': 'ஊட்ட மொழி',
      'gu': 'ફીડ ભાષા',
      'kn': 'ಫೀಡ್ ಭಾಷೆ',
    },
    'translateNeeds': {
      'en': 'Translate needs to',
      'hi': 'ज़रूरतें इसमें अनुवाद करें',
      'bn': 'প্রয়োজনীয়তাগুলি অনুবাদ করুন',
      'te': 'అవసరాలు అనువదించు',
      'mr': 'गरजा भाषांतरित करा',
      'ta': 'தேவைகளை மொழிபெயர்க்க',
      'gu': 'જરૂરિયાતો અનુવાદ કરો',
      'kn': 'ಅಗತ್ಯಗಳನ್ನು ಅನುವಾದಿಸಿ',
    },
    // ── Navigation labels ──────────────────────────────────────────────────────
    'home': {
      'en': 'Home',
      'hi': 'होम',
      'bn': 'হোম',
      'te': 'హోమ్',
      'mr': 'होम',
      'ta': 'முகப்பு',
      'gu': 'હોમ',
      'kn': 'ಹೋಮ್',
    },
    'alerts': {
      'en': 'Alerts',
      'hi': 'अलर्ट',
      'bn': 'অ্যালার্ট',
      'te': 'అలెర్ట్‌లు',
      'mr': 'अलर्ट',
      'ta': 'அலர்ட்கள்',
      'gu': 'ચેतावणी',
      'kn': 'ಎಚ್ಚರಿಕೆಗಳು',
    },
    // ── Home tab ──────────────────────────────────────────────────────────────
    'welcomeBack': {
      'en': 'Welcome back',
      'hi': 'वापसी पर स्वागत है',
      'bn': 'আবার স্বাগতম',
      'te': 'మళ్ళీ స్వాగతం',
      'mr': 'पुन्हा स्वागत',
      'ta': 'மீண்டும் வரவேற்கிறோம்',
      'gu': 'ફरी આवकार',
      'kn': 'ಮತ್ತೆ ಸ್ವಾಗತ',
    },
    'hiGreeting': {
      'en': 'Hi {name}, great to see you!',
      'hi': 'नमस्ते {name}, आपसे मिलकर अच्छा लगा!',
      'bn': 'হ্যালো {name}, আপনাকে দেখে ভালো লাগলো!',
      'te': 'హాయ్ {name}, మిమ్మల్ని చూసి సంతోషం!',
      'mr': 'नमस्ते {name}, भेटून आनंद झाला!',
      'ta': 'வணக்கம் {name}, உங்களை பார்த்து மகிழ்ச்சி!',
      'gu': 'નmaste {name}, tamne joi khushi!',
      'kn': 'ಹಾಯ್ {name}, ನಿಮ್ಮನ್ನು ನೋಡಿ ಸಂತೋಷ!',
    },
    'addANeed': {
      'en': 'Add a need',
      'hi': 'ज़रूरत जोड़ें',
      'bn': 'প্রয়োজন যোগ করুন',
      'te': 'అవసరం జోడించు',
      'mr': 'गरज जोडा',
      'ta': 'தேவை சேர்க்க',
      'gu': 'zarūrat umero',
      'kn': 'ಅಗತ್ಯ ಸೇರಿಸಿ',
    },
    'addANeedSubtitle': {
      'en': 'Post what you need — offers roll in',
      'hi': 'क्या चाहिए बताएं — ऑफ़र आएंगे',
      'bn': 'কী দরকার জানান — অফার আসবে',
      'te': 'ఏమి కావాలో చెప్పండి — ఆఫర్లు వస్తాయి',
      'mr': 'काय हवे ते सांगा — ऑफर येतात',
      'ta': 'என்ன வேண்டும் சொல்லுங்கள் — சலுகைகள் வரும்',
      'gu': 'shu joīe te batavo — offers avase',
      'kn': 'ಏನು ಬೇಕೋ ಹೇಳಿ — ಆಫರ್ ಬರುತ್ತದೆ',
    },
    'exploreNeeds': {
      'en': 'Explore needs',
      'hi': 'ज़रूरतें एक्सप्लोर करें',
      'bn': 'প্রয়োজনীয়তা অন্বেষণ',
      'te': 'అవసరాలు అన్వేషించు',
      'mr': 'गरजा एक्सप्लोर करा',
      'ta': 'தேவைகளை ஆராயுங்கள்',
      'gu': 'zarūriyato explore karo',
      'kn': 'ಅಗತ್ಯಗಳನ್ನು ಅನ್ವೇಷಿಸಿ',
    },
    'helpEarnSubtitle': {
      'en': 'Help out nearby & earn',
      'hi': 'पास में मदद करें और कमाएं',
      'bn': 'কাছাকাছি সাহায্য করুন ও উপার্জন করুন',
      'te': 'సమీపంలో సహాయం చేసి సంపాదించు',
      'mr': 'जवळपास मदत करा आणि कमाई करा',
      'ta': 'அருகில் உதவி சம்பாதியுங்கள்',
      'gu': 'najik madad karo ane kamao',
      'kn': 'ಹತ್ತಿರ ಸಹಾಯ ಮಾಡಿ ಮತ್ತು ಸಂಪಾದಿಸಿ',
    },
    // ── Login screen ──────────────────────────────────────────────────────────
    'newToNeedHub': {
      'en': 'new to NeedHub?',
      'hi': 'NeedHub में नए हैं?',
      'bn': 'NeedHub-এ নতুন?',
      'te': 'NeedHub లో కొత్తవారా?',
      'mr': 'NeedHub ला नवीन आहात?',
      'ta': 'NeedHub-க்கு புதியவரா?',
      'gu': 'NeedHub par nava cho?',
      'kn': 'NeedHub ನಲ್ಲಿ ಹೊಸಬರಾ?',
    },
    'createProfile': {
      'en': 'Create your profile',
      'hi': 'प्रोफ़ाइल बनाएं',
      'bn': 'প্রোফাইল তৈরি করুন',
      'te': 'ప్రొఫైల్ సృష్టించండి',
      'mr': 'प्रोफाइल तयार करा',
      'ta': 'சுயவிவரம் உருவாக்குங்கள்',
      'gu': 'tamari profile banavo',
      'kn': 'ನಿಮ್ಮ ಪ್ರೊಫೈಲ್ ರಚಿಸಿ',
    },
    // ── Feed tab ──────────────────────────────────────────────────────────────
    'filter': {
      'en': 'Filter',
      'hi': 'फ़िल्टर',
      'bn': 'ফিল্টার',
      'te': 'ఫిల్టర్',
      'mr': 'फिल्टर',
      'ta': 'வடிகட்டு',
      'gu': 'Filter',
      'kn': 'ಫಿಲ್ಟರ್',
    },
    'needsNearYou': {
      'en': 'needs near you',
      'hi': 'पास में ज़रूरतें',
      'bn': 'কাছের প্রয়োজনীয়তা',
      'te': 'సమీపంలో అవసరాలు',
      'mr': 'जवळच्या गरजा',
      'ta': 'அருகில் தேவைகள்',
      'gu': 'najik ni zarūriyato',
      'kn': 'ಹತ್ತಿರದ ಅಗತ್ಯಗಳು',
    },
    'peopleNearYou': {
      'en': 'people near you',
      'hi': 'पास के लोग',
      'bn': 'কাছের মানুষ',
      'te': 'సమీపంలో ప్రజలు',
      'mr': 'जवळचे लोक',
      'ta': 'அருகில் மக்கள்',
      'gu': 'najik na logo',
      'kn': 'ಹತ್ತಿರದ ಜನರು',
    },
    'casualChats': {
      'en': 'Casual chats nearby',
      'hi': 'पास में आरामदायक बातचीत',
      'bn': 'কাছে আড্ডা',
      'te': 'సమీపంలో సాధారణ చాట్',
      'mr': 'जवळपास साध्या गप्पा',
      'ta': 'அருகில் சாதாரண அரட்டை',
      'gu': 'najik ni casual chat',
      'kn': 'ಹತ್ತಿರ ಸಾಮಾನ್ಯ ಚಾಟ್',
    },
    'aiRanked': {
      'en': 'AI-ranked',
      'hi': 'AI-रैंक्ड',
      'bn': 'AI-র‍্যাংকড',
      'te': 'AI-ర్యాంక్డ్',
      'mr': 'AI-रँक्ड',
      'ta': 'AI-தரவரிசை',
      'gu': 'AI-ranked',
      'kn': 'AI-ಶ್ರೇಣೀಕೃತ',
    },
    // ── Post need sheet ───────────────────────────────────────────────────────
    'minBudget': {
      'en': 'MIN BUDGET',
      'hi': 'न्यूनतम बजट',
      'bn': 'সর্বনিম্ন বাজেট',
      'te': 'కనిష్ట బడ్జెట్',
      'mr': 'किमान बजेट',
      'ta': 'குறைந்தபட்ச பட்ஜெட்',
      'gu': 'nyūnatam budget',
      'kn': 'ಕನಿಷ್ಠ ಬಜೆಟ್',
    },
    'maxBudget': {
      'en': 'MAX BUDGET',
      'hi': 'अधिकतम बजट',
      'bn': 'সর্বোচ্চ বাজেট',
      'te': 'గరిష్ట బడ్జెట్',
      'mr': 'कमाल बजेट',
      'ta': 'அதிகபட்ச பட்ஜெட்',
      'gu': 'adhiktam budget',
      'kn': 'ಗರಿಷ್ಠ ಬಜೆಟ್',
    },
    // ── Chats tab ─────────────────────────────────────────────────────────────
    'noChatsYet': {
      'en': 'No conversations yet',
      'hi': 'अभी कोई बातचीत नहीं',
      'bn': 'এখনো কোনো কথোপকথন নেই',
      'te': 'ఇంకా సంభాషణలు లేవు',
      'mr': 'अजून कोणतेही संभाषण नाही',
      'ta': 'இன்னும் உரையாடல்கள் இல்லை',
      'gu': 'abhi koi vat nathi',
      'kn': 'ಇನ್ನೂ ಯಾವುದೇ ಸಂಭಾಷಣೆಗಳಿಲ್ಲ',
    },
    'noChatsSubtitle': {
      'en': 'Accept a friend request or connect with someone to start chatting',
      'hi': 'बात शुरू करने के लिए किसी की फ्रेंड रिक्वेस्ट स्वीकार करें',
      'bn': 'চ্যাট শুরু করতে বন্ধু অনুরোধ গ্রহণ করুন',
      'te': 'చాట్ ప్రారంభించడానికి ఫ్రెండ్ రిక్వెస్ట్ అంగీకరించండి',
      'mr': 'चॅट सुरू करण्यासाठी मित्र विनंती स्वीकारा',
      'ta': 'அரட்டையை தொடங்க நட்பு கோரிக்கையை ஏற்கவும்',
      'gu': 'chat shuru karva mitra vinati svikaro',
      'kn': 'ಚಾಟ್ ಪ್ರಾರಂಭಿಸಲು ಸ್ನೇಹ ವಿನಂತಿ ಸ್ವೀಕರಿಸಿ',
    },
    // ── You / Profile screen ──────────────────────────────────────────────────
    'edit': {
      'en': 'Edit',
      'hi': 'संपादित करें',
      'bn': 'সম্পাদনা করুন',
      'te': 'సవరించు',
      'mr': 'संपादित करा',
      'ta': 'திருத்து',
      'gu': 'Edit karo',
      'kn': 'ಸಂಪಾದಿಸಿ',
    },
    'changeLanguage': {
      'en': 'Change language',
      'hi': 'भाषा बदलें',
      'bn': 'ভাষা পরিবর্তন করুন',
      'te': 'భాష మార్చండి',
      'mr': 'भाषा बदला',
      'ta': 'மொழி மாற்றவும்',
      'gu': 'bhasha badlo',
      'kn': 'ಭಾಷೆ ಬದಲಿಸಿ',
    },
    // ── Alerts tab ────────────────────────────────────────────────────────────
    'markAllRead': {
      'en': 'Mark all read',
      'hi': 'सभी पढ़े हुए करें',
      'bn': 'সব পঠিত চিহ্নিত করুন',
      'te': 'అన్నీ చదివినట్లు గుర్తించు',
      'mr': 'सर्व वाचलेले करा',
      'ta': 'அனைத்தும் படிக்கப்பட்டதாக குறிக்கவும்',
      'gu': 'badha vanchela karo',
      'kn': 'ಎಲ್ಲವನ್ನೂ ಓದಿದ ಎಂದು ಗುರುತಿಸಿ',
    },
    'selectAll': {
      'en': 'Select all',
      'hi': 'सभी चुनें',
      'bn': 'সব নির্বাচন করুন',
      'te': 'అన్నీ ఎంచుకో',
      'mr': 'सर्व निवडा',
      'ta': 'அனைத்தையும் தேர்ந்தெடு',
      'gu': 'badha select karo',
      'kn': 'ಎಲ್ಲವನ್ನೂ ಆಯ್ಕೆಮಾಡಿ',
    },
    'delete': {
      'en': 'Delete',
      'hi': 'हटाएं',
      'bn': 'মুছুন',
      'te': 'తొలగించు',
      'mr': 'हटवा',
      'ta': 'அழி',
      'gu': 'Delete karo',
      'kn': 'ಅಳಿಸಿ',
    },
    'clear': {
      'en': 'Clear',
      'hi': 'साफ़ करें',
      'bn': 'পরিষ্কার করুন',
      'te': 'క్లియర్ చేయి',
      'mr': 'साफ करा',
      'ta': 'அழி',
      'gu': 'Clear karo',
      'kn': 'ತೆರವುಗೊಳಿಸಿ',
    },
    'selected': {
      'en': 'selected',
      'hi': 'चुने हुए',
      'bn': 'নির্বাচিত',
      'te': 'ఎంచుకున్నవి',
      'mr': 'निवडलेले',
      'ta': 'தேர்ந்தெடுக்கப்பட்டவை',
      'gu': 'pasand karela',
      'kn': 'ಆಯ್ಕೆಯಾಗಿದೆ',
    },
    'noNotificationsYet': {
      'en': 'No notifications yet',
      'hi': 'अभी कोई सूचना नहीं',
      'bn': 'এখনো কোনো বিজ্ঞপ্তি নেই',
      'te': 'ఇంకా నోటిఫికేషన్‌లు లేవు',
      'mr': 'अजून कोणत्याही सूचना नाहीत',
      'ta': 'இன்னும் அறிவிப்புகள் இல்லை',
      'gu': 'abhi koi notification nathi',
      'kn': 'ಇನ್ನೂ ಯಾವುದೇ ಅಧಿಸೂಚನೆಗಳಿಲ್ಲ',
    },
  };

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
  String get hub => _get('hub');
  String get chats => _get('chats');
  String get you => _get('you');
  String get translate => _get('translate');
  String get translating => _get('translating');
  String get showOriginal => _get('showOriginal');
  String get translateTo => _get('translateTo');
  String get tapToSpeak => _get('tapToSpeak');
  String get listening => _get('listening');
  String get voiceNotAvailable => _get('voiceNotAvailable');
  String get profile => _get('profile');
  String get settings => _get('settings');
  String get logout => _get('logout');
  String get points => _get('points');
  String get language => _get('language');
  String get whatDoYouNeed => _get('whatDoYouNeed');
  String get title => _get('title');
  String get description => _get('description');
  String get post => _get('post');
  String get verifyEmail => _get('verifyEmail');
  String get resendOtp => _get('resendOtp');
  String get loading => _get('loading');
  String get error => _get('error');
  String get retry => _get('retry');
  String get cancel => _get('cancel');
  String get save => _get('save');
  String get done => _get('done');
  String get search => _get('search');
  String get myNeeds => _get('myNeeds');
  String get interests => _get('interests');
  String get skills => _get('skills');
  String get location => _get('location');
  String get feedLanguage => _get('feedLanguage');
  String get translateNeeds => _get('translateNeeds');
  // New getters
  String get home => _get('home');
  String get alerts => _get('alerts');
  String get welcomeBack => _get('welcomeBack');
  String hiGreeting(String firstName) => _get('hiGreeting').replaceAll('{name}', firstName);
  String get addANeed => _get('addANeed');
  String get addANeedSubtitle => _get('addANeedSubtitle');
  String get exploreNeeds => _get('exploreNeeds');
  String get helpEarnSubtitle => _get('helpEarnSubtitle');
  String get newToNeedHub => _get('newToNeedHub');
  String get createProfile => _get('createProfile');
  String get filter => _get('filter');
  String get needsNearYou => _get('needsNearYou');
  String get peopleNearYou => _get('peopleNearYou');
  String get casualChats => _get('casualChats');
  String get aiRanked => _get('aiRanked');
  String get minBudget => _get('minBudget');
  String get maxBudget => _get('maxBudget');
  String get noChatsYet => _get('noChatsYet');
  String get noChatsSubtitle => _get('noChatsSubtitle');
  String get edit => _get('edit');
  String get changeLanguage => _get('changeLanguage');
  String get markAllRead => _get('markAllRead');
  String get selectAll => _get('selectAll');
  String get delete => _get('delete');
  String get clear => _get('clear');
  String get selected => _get('selected');
  String get noNotificationsYet => _get('noNotificationsYet');

  String _get(String key) => _strings[key]?[langCode] ?? _strings[key]?['en'] ?? key;

  static S of(String langCode) => S._(langCode);
  static S get current => S._(uiLanguageNotifier.value);
}
