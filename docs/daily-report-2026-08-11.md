# Nenjam Matrimony — Daily Work Report (11 Aug 2026)

| Field | Value |
|---|---|
| **Project** | Nenjam Matrimony — AI-powered matrimonial platform |
| **Report date** | 11 August 2026 |
| **Prepared by** | Dhatripatel06 |
| **Branch** | `feat/profile-views-and-notification-deep-links` |
| **Workstream** | Android build toolchain upgrade · Build environment diagnostics · Multilingual content architecture |
| **Frontend** | Flutter (Dart SDK ^3.9.2) · Riverpod · Android target |
| **Backend** | NestJS · PostgreSQL · Prisma |
| **Auth** | Firebase Auth only (no Firestore) |

---

## Summary

The Android build toolchain was upgraded to current versions — Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.20, and Java 17 — clearing all three of the deprecation warnings that had been appearing on every build. The upgrade was verified end-to-end: the analyzer reports no issues and a debug APK builds successfully for all three ABIs.

Reaching that verified state required diagnosing a series of build failures that were **environmental rather than code-related**. The root cause was concurrent Gradle processes — the IDE's Gradle extension running project syncs while a terminal build was in flight — which corrupted native build state and produced duplicate CMake configuration. A stable rebuild procedure was established and documented.

Separately, the multilingual strategy for Tamil and English users was reviewed, and an architecture was defined that separates static UI localization from user-generated content translation.

---

## Tasks Completed

- **Upgraded and verified the Android build toolchain** — Gradle 8.12 → 8.14.3, AGP 8.9.1 → 8.11.1, Kotlin 2.1.0 → 2.2.20, Java 11 → 17. Migrated the deprecated `android.kotlinOptions {}` DSL to the `kotlin.compilerOptions {}` extension required by Kotlin 2.2.
- **Ran the full verification sequence** — `flutter clean`, `flutter pub get`, `gradlew clean`, `flutter analyze`, `flutter build apk --debug`.
- **Verified the analyzer reports no issues** — `flutter analyze` returns *No issues found*.
- **Investigated an APK build failure related to CMake/NDK configuration** — failure surfaced at `:app:configureCMakeDebug[arm64-v8a]` with `CXX1429`, reporting that clang++ could not open its output file.
- **Diagnosed duplicate CMake configuration caused by concurrent Gradle/IDE processes** — every line of CMake configure output was emitted twice, confirming two configure processes operating in the same directory; one removed the temporary compile directory while the other was mid-write.
- **Removed stale native build directories** (`.cxx`, `build/app/intermediates`) to clear poisoned CMake and incremental-merge state.
- **Documented a stable rebuild procedure** (see *Next Actions*).
- **Reviewed the multilingual dynamic-data strategy** for Tamil and English users.
- **Defined structured-field localization using IDs/enums** rather than stored display strings.
- **Defined an optional translation flow for free-text profile fields.**
- **Recommended English as the pivot language for MVP** to avoid N×N translation pairs.

---

## Technical Findings

| Check | Result | Notes |
|---|---|---|
| Flutter analyze | ✅ PASS | No issues found |
| Gradle clean | ✅ PASS | Build successful |
| Dependency resolution | ✅ PASS | Toolchain verified |
| APK build | ✅ PASS | Debug APK generated successfully |
| Root cause of earlier failures | Concurrent Gradle/CMake processes | Environmental only |
| Code issue | NO | No application defect |
| NDK/CMake issue | RESOLVED | Environmental contention fixed |

### Deprecation warnings — before vs. after

| Warning | Status |
|---|---|
| `source value 8` / `target value 8` obsolete | ✅ Eliminated (0 occurrences) |
| `kotlinOptions` DSL deprecated | ✅ Eliminated (0 occurrences) |
| Gradle version deprecation | ✅ Resolved via 8.14.3 |

Verified with `gradlew assembleDebug --warning-mode all`. Remaining warnings originate exclusively from third-party pub.dev packages (Groovy space-assignment syntax) and require upstream package updates; they are not actionable from this repository.

### Ruled out during diagnosis

- **`MAX_PATH` limit** — long paths are enabled system-wide and the deepest path measured 145 characters, well within limits.
- **Network/proxy misconfiguration** — no proxy configured; an initial distribution-download timeout was transient and did not recur.
- **Toolchain incompatibility** — every plugin subproject compiled cleanly under the new AGP and Kotlin versions.

---

## Multilingual Architecture Decision

The application must serve Tamil and English users. Two distinct problems were separated, because they demand different solutions:

- **UI localization handles static strings.** All fixed interface text — labels, buttons, validation messages, screen titles — is resolved through the existing localization layer with per-locale resource files. This content is known at build time.

- **User-generated content requires a separate translation system.** Profile text written by one user must be readable by another whose language differs. Localization files cannot address this, since the content does not exist at build time.

- **Structured fields are stored as IDs.** Enumerable attributes — religion, caste, education, occupation, marital status, diet — are persisted as stable IDs or enum values, never as display strings. Each ID maps to a per-language label resolved at render time, so the same record renders correctly in Tamil or English with no translation cost and no data duplication. This covers the majority of profile data.

- **Free-text fields are stored in the original language.** Genuinely open content — the "About Me" biography, partner preferences, custom notes — is persisted exactly as the author wrote it, with a recorded source-language tag. The original is always preserved as the source of truth.

- **Translation is optional and on-demand.** Free-text translation is invoked only when a reader explicitly requests it, not eagerly on write or on read. Results are cached per (field, target language) to avoid repeat cost. **English is the pivot language for MVP**, keeping the matrix to Tamil↔English rather than N×N pairs as further languages are added.

---

## Blockers

- **Windows Gradle/CMake race condition.** Concurrent processes writing to `Frontend/build` cause non-deterministic failures. The symptom varies by which task loses the race — missing AAR metadata, a locked ZIP cache entry, or a vanished CMake temp directory — which makes the failures appear unrelated at first glance.

- **IDE Gradle sync interfering with terminal builds.** The `vscjava.vscode-gradle` extension runs its own Gradle server that syncs the project independently of the terminal. Terminating the process is not durable — the IDE respawns it on demand. Until the extension is disabled, any IDE-triggered sync overlapping a terminal build can reintroduce the fault.

---

## Next Actions

1. **Build from terminal only.** Do not trigger IDE Gradle syncs or IDE-initiated builds while a terminal build is running. For a durable fix, disable the *Gradle for Java* (`vscjava.vscode-gradle`) extension.
2. **Kill Java/Gradle processes before rebuilding.** Run `gradlew --stop`, then confirm no orphaned `java.exe` processes remain — including the IDE Gradle server, which `--stop` does not terminate.
3. **Rebuild the APK after clearing native caches.** Remove `Frontend/build/.cxx` and stale `intermediates` directories before rebuilding when a native-configuration failure has occurred.
4. **Implement a language-aware profile text API.** Return structured fields as IDs with resolved labels for the requested locale, and free-text fields with their source-language tag.
5. **Add "View original / View translation" UI.** Give readers an explicit, reversible toggle on translated free-text fields, with the original always reachable.

### Optional follow-ups

- Evaluate removing `android.enableJetifier=true` from `gradle.properties` — run `gradlew checkJetifier` to confirm no dependency still requires it.
- `google-services` remains at 4.3.15; it builds correctly against AGP 8.11.1, with 4.4.4 available should issues arise.

---

## Status

🟢 Build verified successfully; earlier environmental issue was diagnosed and resolved.

