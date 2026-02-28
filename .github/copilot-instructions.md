Purpose
This file gives concise, repo-specific guidance for AI coding agents working on the ai_diet_app Flutter project.

**Overview**
- Flutter mobile/web/desktop app. UI and core state live in `lib/main.dart`. Additional screens under `lib/screens/`.
- Integrates with an LLM via the `google_generative_ai` package (model: `gemini-pro`).
- Local persistence uses `shared_preferences` (stringified JSON for history).
- Charts use `fl_chart` and many UI strings/prompts are Korean.

**Key files**
- Dependencies & packages: [pubspec.yaml](pubspec.yaml#L1-L40)
- App entry & core logic: [lib/main.dart](lib/main.dart#L1-L80)
- Chat / conversational prompts: [lib/screens/chat_screen.dart](lib/screens/chat_screen.dart#L1-L40)
- Reports (charts): [lib/screens/report_screen.dart](lib/screens/report_screen.dart#L1-L30)
- User settings & SharedPreferences usage: [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart#L1-L30)
- Tests: [test/widget_test.dart](test/widget_test.dart#L1-L40)

**Big-picture architecture & data flow**
- Single-page-style Flutter app with multiple routed screens. `DietScreen` (in `main.dart`) keeps the canonical state: `_history`, user profile and goals.
- User input -> `analyzeDiet()` (in `main.dart`) calls the LLM and expects a JSON array like: [{"food","amount","kcal","carbs","protein","fat"}]. The result is appended to `_history` and saved to SharedPreferences under key `diet_history_v2`.
- Chat and MealPlan screens build contextual prompts from `currentHistory` and user profile, then call `GenerativeModel.generateContent(...)`.
- Reporting uses date keys in the format `YYYY-MM-DD` to aggregate calories for plotting with `fl_chart`.

**Project-specific conventions & gotchas**
- SharedPreferences keys (search and reuse): `diet_history_v2`, `targetKcal`, `currentWeight`, `userHeight`, `userAge`, `userGender`.
- AI output contract: `analyzeDiet()` expects the model to return strict JSON. The current code performs lightweight cleaning (naive replace/trim) before `jsonDecode` — this is fragile. When modifying prompts, preserve the JSON-only contract or centralize parsing in a helper function.
- API key handling: an `apiKey` string is present in `lib/main.dart`. Currently embedded in source — treat as a secret to rotate and move to env/config for production.
- Language: UI text and prompts are in Korean. Keep prompts and user-facing messages in Korean unless you intentionally change app language.

**Dependencies & integration points**
- `google_generative_ai` — used in `main.dart` and `lib/screens/*` for generation. Calls use `GenerativeModel(model: 'gemini-pro', apiKey: apiKey)` and `model.generateContent([Content.text(prompt)])`.
- `shared_preferences` — used to persist and load JSON-encoded `_history` and simple numeric prefs.
- `fl_chart` — used in `report_screen.dart` for time-series charts; expects `FlSpot` series and numeric ranges.

**Developer workflows & common commands**
- Install deps: `flutter pub get`
- Run (device selector optional): `flutter run` or `flutter run -d <device-id>`
- Run tests: `flutter test`
- Build APK: `flutter build apk`
- iOS: open Xcode workspace `ios/Runner.xcworkspace` before building in Xcode

**Editing guidance for AI agents (how to make safe, compatible changes)**
- When changing LLM prompts or the expected response format, update both `analyzeDiet()` (parsing expectations) and every screen that constructs prompts (`chat_screen.dart`, meal plan in `main.dart`). Keep JSON vs natural-language contracts consistent.
- If adding new persistent fields, update `_loadData()` and `_saveData()` in `main.dart` and provide backward-compatible migration (remove or reset malformed pref entries if `jsonDecode` fails).
- Prefer extracting parsing logic from `main.dart` into a pure helper (unit-testable) before changing behavior. Example: move the JSON-clean-and-parse steps into `lib/utils/ai_parsing.dart` and add tests that cover edge cases where model returns non-JSON chatter.
- Avoid committing secrets. Replace the hardcoded `apiKey` with a config injection (CI secrets, `.env`, or platform-specific secure storage) and document how to set it locally.

**Examples from codebase**
- JSON parsing in `analyzeDiet()` (fragile cleaning + `jsonDecode`) — inspect [lib/main.dart](lib/main.dart#L1-L200).
- Chat context assembly (uses `currentHistory` to list today's foods) — see [lib/screens/chat_screen.dart](lib/screens/chat_screen.dart#L1-L80).
- Chart x-axis uses `YYYY-MM-DD` keys — see [lib/screens/report_screen.dart](lib/screens/report_screen.dart#L1-L80).

If anything above is unclear or you want more detail (for example: extract parsing helper, add tests for AI output, or a migration path for SharedPreferences), tell me which area to expand and I will update this file.
