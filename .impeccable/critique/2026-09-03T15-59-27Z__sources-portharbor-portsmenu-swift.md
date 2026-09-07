---
target: Port Harbor menu bar UI (PortsMenu.swift)
total_score: 13
p0_count: 2
p1_count: 2
timestamp: 2026-09-03T15-59-27Z
slug: sources-portharbor-portsmenu-swift
---
# Design Critique — Port Harbor (`Sources/PortHarbor/PortsMenu.swift`)

Method: dual-agent (A: 80fc601d-1790-44d1-a7d4-8f4bd167f9a8 · B: 231b2842-6d8b-479b-b968-0a66f28da574)

## Design Health Score

| # | Heuristik | Score | Kernproblem |
|---|-----------|-------|-------------|
| 1 | Sichtbarkeit des Systemstatus | 1 | `isRefreshing` ist nicht `@Published` (`PortsStore.swift:28`) → Scan-State nicht renderbar. Kein Feedback nach Open/Cursor/Terminal/Stop. Der grüne Punkt ist hart `.fill(.green)` (`PortsMenu.swift:104`). |
| 2 | Übereinstimmung mit der realen Welt | 2 | `Framework.unknown.rawValue == "Server"` (`FrameworkDetector.swift:26`) erzeugt „Server ·" — beschreibt die Kategorie, die man ohnehin sieht. Drei Icons für ein Konzept. |
| 3 | Nutzerkontrolle und Freiheit | 1 | Stop → SIGTERM, 0,4 s, SIGKILL (`Actions.swift:50-58`) ohne Bestätigung, ohne Undo. |
| 4 | Konsistenz und Standards | 2 | `showsIndicators: true` (`:23`) statt Overlay-Scroller; `.buttonStyle(.plain)` überall entfernt Focus-Ring; 0 Shortcuts, 0 Kontextmenü. |
| 5 | Fehlervermeidung | 1 | Stop unbestätigt. `PortsStore.swift:91/96` prüfen nur auf nil/leer — bei `cwd == "/"` öffnen Cursor/Terminal das Root-Verzeichnis. |
| 6 | Wiedererkennen statt Erinnern | 2 | `lineLimit(1)` (`:122`) schneidet die PID ab, die der Restart-Dialog (`:64`) als Identifikator nutzt. |
| 7 | Flexibilität und Effizienz | 1 | 0 `keyboardShortcut`, keine Suche/Filter/Sortierung, keine `Settings`-Scene. |
| 8 | Ästhetik und minimalistisches Design | 2 | Header-Titel redundant, Footer-Count dupliziert das Menüleisten-Badge, 5 gleichwertige Aktionen pro Zeile. |
| 9 | Fehlerdiagnose und -behebung | 0 | Alle Pfade verschluckt: `PortScanner.swift:26`, `Actions.swift:22`, `:189`, `PortsStore.swift:114`. |
| 10 | Hilfe und Dokumentation | 1 | 0 `.help(`, kein About, keine Legende für den grünen Punkt. |
| **Total** | | **13/40** | **Poor — massive UX-Überarbeitung nötig** |

## Anti-Patterns Verdict

**LLM-Bewertung**: Ja, sofort als generiert erkennbar. Tells: die 5-spaltige Aktionsleiste mit `frame(maxWidth: .infinity)` für alle (`:203`), einzige Differenzierung `tint: .red` (`:164`); der immer grüne Statuspunkt; `circle.fill` als Framework-Icon für `.unknown`; App-Titel und Server-Titel beide 13pt semibold; Magic Number `110` als Zeilenhöhe; keine einzige Animation im Repo.

**Deterministischer Scan**: `detect.mjs` lief mit Exit 0 und leerem Ergebnis — aber als False Negative: `.swift` fehlt in der `SCANNABLE_EXTENSIONS`-Liste, 0 von 7 Dateien wurden gelesen. Ersatzweise verifizierte Zählungen via ripgrep über `Sources/`: accessibilityLabel 0, accessibilityHint 0, accessibilityValue 0, `.help(` 0, keyboardShortcut 0, focusable 0, withAnimation 0, `.animation(` 0, transition 0, textSelection 0, contextMenu 0, Settings 0, LocalizedStringKey 0, onHover 1, `role: .destructive` 1. Build kompiliert warnungsfrei.

**Visuelle Overlays**: Nicht anwendbar — natives SwiftUI, kein HTML/DOM, keine Browser-Injektion möglich.

## Overall Impression

Die Engine ist gut, die Oberfläche ist Platzhalter. `PortScanner.swift` (lsof `-F`, Ephemeral-Cutoff bei 49152, System-Denylist) und `Actions.swift` (absolute Binärpfade, argv-Tokenizer, Metazeichen-Ablehnung) zeigen echtes Denken. Das UI hat davon nichts abbekommen: es zählt Aktionen auf statt sie zu priorisieren, und die gefährlichste Aktion der App ist die ungeschützteste.

## What's Working

1. Die Kernschleife: `MenuBarExtra` mit Live-Count (`PortHarborApp.swift:11-18`) + 3-s-Polling beantwortet „Was läuft?" vor der ersten Interaktion.
2. `Actions.swift` hat eine kohärente Sicherheitshaltung — die das UI vollständig verschweigt.
3. Die Layout-Knochen sind korrektes macOS-Idiom: 8pt Continuous Radius, 0.5pt Hairline, `controlBackgroundColor` (`:172-179`).

## Priority Issues

### [P0] Stop ist irreversibel, unbestätigt, unquittiert — auf einem beweglichen Ziel
`PortsMenu.swift:160-167` → `PortsStore.swift:100-108` → `Actions.swift:50-58`. Kein Gate, kein Undo, kein Feedback; `PortsStore.swift:79-82` ersetzt und sortiert die Liste alle 3 s neu.
**Fix**: Per-Row `ActionState` publishen, Karte inline auf `Stopping…` → `Stopped · Undo` (5 s Fenster, nutzt den Relaunch-Pfad aus `Actions.restart`). Auto-Refresh-Reorder pausieren, solange der Zeiger im ScrollView ist. Bestätigung nur für die riskante Teilmenge (cwd unbekannt / Binary nicht in der Allowlist).
**Command**: `/impeccable harden`

### [P0] Jeder Fehler ist stumm — ein fehlgeschlagener Restart lässt den Prozess tot zurück
`Actions.swift:95` killt, `:110` `try task.run()` kann werfen, `PortsStore.swift:112-117` fängt in `// Best-effort`. Zusätzlich: `PortScanner.swift:22-28` macht aus einem lsof-Fehler `[]` — nicht unterscheidbar von „keine Server".
**Fix**: `@Published var failures` pro Row-ID, Inline-Banner mit echtem Grund + „Copy command". Empty State (`:84-95`) in drei Zustände auftrennen: scanning / leer / Scan fehlgeschlagen mit Grund.
**Command**: `/impeccable harden`

### [P1] Die Zeile hat keine Hierarchie
`:124-168` (5 Aufrufe), `:192-216` (identische Behandlung), `:103-105` (Deko-Punkt), `:107-109` + `FrameworkDetector.swift:52` (schwarzer Blob bei `.unknown`), `:119-122` (PID weggeschnitten).
**Fix**: Ganze Karte klickbar → Open. Cursor/Terminal als Icon-only Trailing-Buttons bei Hover. Restart/Stop ins Kontextmenü plus `…`-Menü. Grünen Punkt löschen oder mit echtem HTTP-Liveness-Probe füllen. Framework-Glyph bei `.unknown` unterdrücken. Subtitle mit `vite dev · PID 41732` beginnen, `"Server ·"` streichen, vollen Pfad in `.help()` + `.textSelection(.enabled)`.
**Command**: `/impeccable layout`

### [P1] Die hartkodierte Zeilenhöhe 110 schneidet die letzte Karte ab
`:32-35` (`minHeight: min(count * 110, 420)`), `:23` (`showsIndicators: true`), `:25`/`:29-30` (2pt Spacing + 12pt Padding fehlen in der Rechnung). Bei n=2: Viewport 220pt, Inhalt ~234pt → Überlauf, sichtbarer Scrollbalken und abgeschnittener Rand im Screenshot bei nur zwei Servern.
**Fix**: `showsIndicators: false`. Höhe aus gemessenem Inhalt (`onGeometryChange`) statt Magic Number, Cap bei 420.
**Command**: `/impeccable polish`

### [P2] Null Tastatur, null Accessibility
0 Treffer für accessibilityLabel/Hint/Value, `.help(`, keyboardShortcut, focusable, textSelection im ganzen Repo. `.buttonStyle(.plain)` (`:207`, `:245`, `:254`) entfernt Focus-Ringe. Disabled = `Color.gray.opacity(0.35)` (`:198-201`), ca. 1.5:1.
**Fix**: `.keyboardShortcut("r")`/`("q")`, ⌘1–⌘9 für Open. `.accessibilityElement(children: .contain)` mit Row-Label pro Karte, Aktionslabels wie `"Stop \(row.displayTitle)"`. `.help()` auf jeden Icon-Button. Nicht-farbliches Statusmerkmal. Relative Textstile statt fixer `.system(size:)`.
**Command**: `/impeccable audit`

## Cognitive Load: 8 von 8 Checks fallen durch

Sichtbare Entscheidungsoptionen pro Zeile: 5 Aktionen (Limit 4) plus 2 nicht-aktionierbare Aufmerksamkeitsfänger. Bei 2 Servern: 12 interaktive Ziele; bei 5 Servern: 27.

1. Single focus — FAIL: drei gleichgewichtige Blöcke pro Karte.
2. Chunking — FAIL: 5 Aktionen in einem `HStack(spacing: 0)` (`:125`).
3. Grouping — FAIL: 3 sichere Navigations- und 2 destruktive Lifecycle-Aktionen ohne Trenner in derselben Leiste.
4. Visual hierarchy — FAIL: größtes, dunkelstes Objekt der Zeile ist ein dekoratives `circle.fill`.
5. One thing at a time — FAIL: alle Aktionen für alle Server permanent sichtbar.
6. Minimal choices — FAIL: 5 pro Zeile.
7. Working memory — FAIL: abgeschnittener Pfad nicht wiederherstellbar; Liste sortiert alle 3 s neu.
8. Progressive disclosure — FAIL und invertiert: das Rauschen ist sichtbar, das Signal (Command, cwd, PID, Framework) versteckt.

## Emotional Journey

**Peak** in den ersten 500 ms: Badge zeigt die Zahl, ein Klick zeigt die Liste.
**Tal 1** nach ~2 s: Vertrauensbruch. Im Screenshot sind beide Zeilen Raycast und Spotify — keine Dev-Server. `PortScanner.swift:66-73` sperrt Chrome, Safari, Firefox, mDNSResponder, aber nicht Raycast oder Spotify. Das Badge sagt „2" und beide sind falsch.
**Tal 2**, der Hochrisikomoment: rote 10pt-Schrift bei ~3.4:1, kein Rahmen, keine Bestätigung, SIGTERM→SIGKILL, auf eine Liste gerichtet, die alle 3 s umsortiert. Danach: nichts. Die Zeile verschwindet beim nächsten Poll — visuell identisch dazu, dass die App den Prozess aus den Augen verliert. Für bis zu 3 s bleibt ein toter Server mit aktivem Stop-Button gelistet.
**Tal 3**: Die einzige Absicherung sitzt auf der falschen Aktion. Restart (wiederherstellend) hat einen Dialog, Stop (irreversibel) nicht. Der Dialogtext ist `String(row.fullCommand.prefix(120))` (`:64`) — ein roher argv-Schnitt mitten im Token.
**End**: redundanter Count, ein durch das Polling sinnloses Refresh, Quit 12pt daneben ohne Bestätigung. Peak-End fällt negativ aus.

## Persona Red Flags

**Alex (Power User)**: 0 Shortcuts im Repo; ~50 % Rauschanteil auf der eigenen Maschine ohne Möglichkeit, Prozesse auszublenden (keine `Settings`-Scene); Muskelgedächtnis bildet sich nie, weil `PortsStore.swift:79-82` alle 3 s neu sortiert; keine Suche bei 15 Ports; „Refresh" belegt eines von drei globalen Controls, obwohl gepollt wird.

**Jordan (Erstnutzerin)**: `Server · /Applications/Raycast.app/Contents/Ma…` sagt nichts und ist nicht aufklappbar; „PID" erscheint erstmals im Restart-Dialog; der grüne Punkt wird nirgends erklärt; `cursorarrow` (`:136`) ist das macOS-Mauszeiger-Symbol und wird als „hier klicken" gelesen; vor dem Hover sieht nichts klickbar aus (Hover-Highlight `Color.primary.opacity(0.05)`, `:214`); der Empty State ist eine Sackgasse.

**Sam (Accessibility)**: Alle Row-Controls sind per Tastatur unerreichbar; VoiceOver liest „Open, Button, Cursor, Button…" identisch für jede Zeile, ohne zu sagen welcher Server — Stop ist damit nicht sicher benutzbar; Bedeutung doppelt nur über Farbe (grüner Punkt, `tint: .red`); Kontrastfehler bei Disabled (~1.5:1), 10pt `.secondary` (~3.95:1 nominal) und rotem Stop-Text (~3.4:1); „Größerer Text" wird ignoriert, und die fixe 110pt-Höhe würde skalierten Text abschneiden.

## Minor Observations

- Drei Icons für ein Konzept: `server.rack` (`PortHarborApp.swift:13`), `network` (`:73`), `server.rack` (`:224`).
- Footer-Count dupliziert das Menüleisten-Badge, ~30pt entfernt.
- Monospace auf dem Server-Count (`:228`) ist Code-Ästhetik-Tic; `.monospacedDigit()` ist das richtige Werkzeug und wird in `PortHarborApp.swift:15` bereits korrekt genutzt.
- Doppelte Kürzung ohne Nutzen: `FrameworkDetector.swift:221` schneidet auf 50 Zeichen, `:183` hängt danach die PID an, `PortsMenu.swift:122` kürzt auf eine Zeile.
- `hoveredButton` ist ein einzelner `String?` für die gesamte Liste (`:8`).
- `detect(from:)` ist naives Substring-Matching: `contains("next")` trifft „nextcloud", `contains("vite")` trifft „invite", `contains("php") && contains("-s")` trifft fast jedes `-s`-Flag.
- `.alert` an MenuBarExtra-Content (`:46`) ist fragil — das Popover kann unter dem Modal wegklappen.
- Feste 380pt Breite (`:45`) garantiert Pfad-Truncation für reale Projektpfade.
- Quit: ~28×13pt Ziel, 12pt neben Refresh, ohne Bestätigung.

## Questions to Consider

1. Wenn jede Zeile per Definition ein Socket im LISTEN-Zustand ist — was sagt der grüne Punkt, das die Existenz der Zeile nicht schon sagt?
2. Das README-Headline-Feature ist Framework-Erkennung für 20+ Frameworks. Im eigenen Screenshot rendert es als schwarzer Kreis und das Wort „Server". Existiert ein Feature, das nur im Changelog vorkommt?
3. Warum bekommt Restart — das wiederherstellt — einen Bestätigungsdialog, und Stop — irreversibel, mit SIGKILL nach 400 ms — keinen?
4. Wenn du Platz für genau eine Aktion pro Zeile hättest: welche? Und warum ist die Zeile nicht längst diese Aktion?
5. Für wen ist das? Der Power User bekommt keine Tastatur, die Anfängerin keine Erklärung.
