# Czech terminology — DropStation translation glossary

Cross-cutting terminology decisions for the Czech localization so
the translation pass (PR 2) lands consistent. Every term has a
short English source, a Czech rendering, and a one-line *why* so a
future contributor (or a different translator) can second-guess
the choice with context.

The list is not exhaustive — only terms that are reused across
screens or could plausibly be translated multiple ways. Single-use
strings live in `Localizable.xcstrings` and don't need to be
catalogued here.

---

## Core vocabulary

| English source | Czech | Why |
|---|---|---|
| Download Station | **Download Station** | Synology product name. Stays English everywhere; translating to "Stanice stahování" reads as a generic noun and breaks brand recognition. Same rule as DSM, Mac, App Store. |
| Synology | **Synology** | Brand. Never translated. |
| DropStation | **DropStation** | App name. Never translated. |
| NAS | **NAS** | Universal acronym in Czech tech writing. "Síťové úložiště" is correct but verbose; we use NAS for inline copy and only spell it out in the very first onboarding sentence. |
| Sign in | **Přihlásit se** (verb) / **Přihlášení** (noun) | Action vs label. Verb form for buttons ("Přihlásit se"), noun form for screen titles ("Přihlášení"). |
| Sign out | **Odhlásit se** | Same verb/noun split as sign in. |
| Session | **relace** | Standard Czech for a system session. Avoid "sezení" (sounds like a meeting). |
| Session expired | **Relace vypršela** | The "expired" sense is `vypršela`, not `vyprchala` or `skončila`. |
| Verification code | **ověřovací kód** | Standard for TOTP / 2FA codes. Avoid "verifikační kód" (anglicism). |
| 2-step verification | **dvoufázové ověření** | Apple's own Czech translation of two-factor / two-step. Stays consistent with iOS system UI. |
| Connection lost | **Připojení ztraceno** | Past participle, matches the "the connection has been lost" sense. |
| Reconnect | **Znovu připojit** | Verb form, used on retry buttons. |
| Remember session | **Zapamatovat relaci** | Used for the privacy toggle that keeps the SID across launches. |

## Download Station vocabulary

| English source | Czech | Why |
|---|---|---|
| Download | **stahování** (noun) / **stáhnout** (verb) | Noun for the row label, verb for the action button. |
| Downloads | **Stahování** | Tab label, plural-as-collective. Czech doesn't distinguish singular/plural here the way English does, so the same form covers both. |
| Task | **úloha** | DSM's own Czech UI uses "úloha", we match it for cross-app consistency. Avoid "úkol" (sounds like a chore). |
| Active | **aktivní** | Adjective form, used in filter labels. |
| Paused | **pozastaveno** | Past participle, matches the status pill convention. |
| Finished / Ended | **dokončeno** | DropStation uses "Ended" as a UX-friendly folding of finished + paused-at-100%; the Czech word `dokončeno` covers both sensibly. |
| Seeding | **sdílení** | The Czech BT community standardises on "seedování" colloquially, but `sdílení` (sharing) reads cleaner in a calm-utility UI. |
| Hash checking | **kontrola hashe** | DSM CZ uses this form. |
| Speed | **rychlost** | Singular, used for both download and upload directions. |
| Destination | **cíl** | Short, unambiguous in the folder-picker context. |

## UI surfaces

| English source | Czech | Why |
|---|---|---|
| Settings | **Nastavení** | Standard iOS / Apple Czech. |
| Dashboard | **Přehled** | Already seeded in the catalog. "Dashboard" is technical jargon; "Přehled" (overview) is the calm-utility translation. |
| Cancel | **Zrušit** | iOS-standard. |
| Done | **Hotovo** | iOS-standard. |
| Save | **Uložit** | iOS-standard. |
| Delete | **Smazat** | iOS-standard. Reserve `Odstranit` for "remove" actions that don't destroy data. |
| Add | **Přidat** | iOS-standard. |
| Edit | **Upravit** | iOS-standard. |
| Report a bug | **Nahlásit chybu** | Match iOS/Apple convention. Avoid "Reportovat" (anglicism). |
| Suggest a feature | **Navrhnout funkci** | "Funkci" not "feature" — feature is unmistakably English. |

## Style rules for the translator

A few things that come up often and are easy to get wrong on
auto-translate:

1. **Diacritics are mandatory.** Never strip them for "compactness".
   `prihlasit` / `pripojeni` look like a typo in any modern Czech
   text. The String Catalog stores UTF-8; no character is too
   exotic.
2. **Inflect for context, not for source-word-count.** English uses
   the same word in many grammatical roles ("Settings" = title /
   menu item / verb-noun). Czech needs the right case. Pick the
   form that fits where the string lands, not what's shortest.
3. **Imperative for buttons, infinitive for menu items.**
   - Button (user clicks it now): `Přihlásit se` (imperative-style
     infinitive)
   - Menu item or screen title: `Přihlášení` (nominal)
4. **Czech word order ≠ English word order.** Don't translate
   "Sign in to your Synology Download Station" as "Přihlásit se k
   vašemu Synology Download Station". The natural Czech is
   "Přihlásit se k vašemu Download Station" (drop redundant
   "Synology" — the user already knows what they're using).
5. **Length budget.** Czech is on average 20-30% longer than
   English. Watch button labels in particular — verify they don't
   wrap or truncate when running cs locale in the simulator before
   declaring the translation pass complete.
6. **Plural rules** — Czech has three plural forms (1, 2-4, 5+).
   Use String Catalog's plural-rule UI (`%lld download` → `%lld
   stahování` / `%lld stahování` / `%lld stahování` — Czech happens
   to collapse all three to the same word, but other strings like
   `%lld file` / `%lld soubor` / `%lld soubory` / `%lld souborů`
   need three distinct forms).
7. **DSM error code messages** stay close to DSM's own Czech
   wording where it exists. "Session timeout." → "Relace vypršela.",
   not "Časový limit relace." — the DSM UI says the former.

## When to break the rules

If a string lands wrong despite following this list, change the
table here *first*, then the catalog. Future translation passes
read this doc; commit-history reasoning is fine for individual
strings but doesn't survive a fresh translator picking up the work.
