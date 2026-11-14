# Privacy and age rating: Relics: Games 1.0

## App Privacy (App Store Connect › App Privacy)
**Data Not Collected.** Answer "No, we do not collect data from this app."

Why that is true:
- No network code: no URLSession, web views, analytics, crash reporting SDKs, ads or accounts. The app never connects.
- Games, saves, save states and layouts live in the app's own Documents / Application Support folders on the device.
  (Documents is visible in Files because file sharing is on; nothing leaves the device unless the user moves it.)
- `App/Resources/PrivacyInfo.xcprivacy`: tracking false, no tracking domains, no collected data types; required-reason
  APIs declared: UserDefaults (CA92.1), file timestamps (C617.1) and system boot time (35F9.1, frame pacing).

Privacy policy URL: ASC requires one even for "Data Not Collected". Use the Relics privacy page pattern of the other
Relics apps ("Relics: Games collects no data. It has no accounts, ads or analytics and never connects to the
internet."), plus the contact email once Gordon supplies it.

## Age rating (suggested: 4+)
Answers for the age rating questionnaire, based on what ships (the app plus the five bundled demos):

| Question | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | Infrequent/Mild | Thwaite: abstract missiles and explosions over pixel towns; Alex vs Bus: none |
| Realistic violence | None | |
| Prolonged graphic or sadistic violence | None | |
| Profanity or crude humour | None | |
| Mature or suggestive themes | None | |
| Horror or fear themes | None | |
| Medical or treatment information | None | |
| Alcohol, tobacco or drug use or references | None | |
| Simulated gambling | None | |
| Sexual content or nudity | None | |
| Contests | None | |
| Unrestricted web access | No | No browser, no network |
| User-generated content / messaging / chat | No | Nothing is shared between users |
| Advertising | No | |
| Parental controls / age assurance | No | |
| Made for Kids | No | Don't opt into the Kids category (an emulator opens arbitrary user files) |

Expected outcome: 4+ (mild cartoon violence is allowed at 4+). If ASC's calculator returns 9+ for "Infrequent/Mild",
accept 9+; don't under-answer.

What users import is their own content and isn't rated by Apple; that's normal for emulators. Thwaite's flicker
warning is shown in its credits (About › Free demos).
