# Article read-aloud

The article reader's player follows the behavior of `BrainEno/red-room-archive`'s read-aloud implementation (reference revision `839912aba3a5997079fc5bbb0742531ff27ec90b`), adapted to Flutter's rendered Markdown and device speech engines.

## Reader behavior

- The player is shown only when the article body contains speakable text and the system speech engine initializes. It reads the title followed by the displayed body, including headings, lists, quotations, links' visible text and code. It does not read link destinations, image descriptions/URLs, article controls, recommendations or comments.
- Play, pause/resume, stop, a draggable percentage position and six speeds (0.5×, 0.75×, 1×, 1.25×, 1.5× and 2×) are available. A speed change while playing restarts at the current known word; a change while paused applies on resume. Seeking snaps out of the middle of a UTF-16 surrogate pair or Latin word. Scrubbing previews the percentage and commits on release.
- Follow defaults on. It underlines the current word and scrolls its visible position into view, including within long paragraphs. When a voice does not provide word boundaries, it underlines the current block and falls back to the beginning of the current speech chunk for progress/resume. With follow off, neither highlighting nor automatic scrolling occurs. Reduced-motion settings disable animated scrolling.
- Follow is a single device-local preference in the existing SQLite `metadata` table (`read_aloud_follow_v1`). It does not change the database schema or affect drafts, caches or account data. Rate and position are session-only.
- Text is split at paragraphs and natural punctuation into utterances of at most 220 Unicode code points. Each chunk independently selects Chinese or English based on its text, then an installed system voice with an exact language or matching language family; otherwise the platform default is used. The system's installed voices determine actual language availability and sound.
- A page stops when it is covered by another page, popped/disposed, the selected navigation tab changes, a root page such as login covers the shell, or the app becomes inactive. A transient control such as the speed menu does not stop it. A shared coordinator serializes platform commands and uses utterance IDs to ignore stale callbacks across pages, seeks, pauses and rate changes.
- Controls and terminal/error messages are localized in Chinese and English. The slider exposes its percentage to assistive technology; controls retain keyboard focus and large-text layout.

## Platform and privacy boundaries

Android uses `TextToSpeech`, iOS/macOS use `AVSpeechSynthesizer`, and Windows uses SAPI in plain-text mode. No additional TTS package or new permission is required; Android 11+ package visibility is declared for the installed TTS service. On Android, word callbacks generally require Android 8/API 26 or later **and** an engine that supports them; other engines fall back to block tracking. Platform speech rates and installed voices can differ in perceived sound. Unavailable engines hide the player; a playback failure shows a localized error and can be retried.

The app itself sends article text only to the selected platform speech API and does not upload it to the app backend or save synthesized audio. A device's chosen speech engine is outside the app's control and may use a network service; do not assume every voice works offline. The player deliberately stops on backgrounding rather than providing background audio controls.

The repository has Android, iOS, macOS and Windows runners. A platform without this channel (including unsupported builds) hides the player. CI compiles the native runners and exercises Dart logic with a fake engine, but compilation and mocked callbacks do **not** establish real-device audio, actual voice availability, audio interruptions, operating-system networking behavior, or screen-reader quality. Those require the manual checks below.

## Manual device checklist

On each supported platform, using installed Chinese and English voices:

1. Read a mixed-language article with headings, nested lists, inline/fenced code and a long paragraph; confirm the correct visible text, voice, word/block underline and scrolling.
2. Exercise all speeds while playing and paused, seek at the beginning/middle/end and across emoji/Latin words, and rapidly pause, resume, stop and switch articles. Check for repeated/missing speech or stale highlights.
3. Toggle follow, restart the app and verify the preference; confirm turning it off stops scrolling. Repeat with the platform's reduced-motion option.
4. Switch tabs, push another article/author, open login, background the app and return. Verify speech stops and does not restart by itself. Verify opening the speed menu alone does not stop speech.
5. Check VoiceOver/TalkBack or the desktop screen reader, keyboard navigation, large text, dark/light themes, missing voices and denied/unavailable speech services. Confirm any engine-specific network behavior with device settings.
