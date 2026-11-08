# 007 · Remove shell command execution

*   **Status:** Built (steps 1 to 3). See "As built" at the end.
*   **Date:** 2026-11-06

## Goal

MDEdit stops being able to start a program. The shell feature (⌘R, the Run tab, saved scripts, history, the Shell section in Settings) is removed in full. It was a good-to-have, and it is the one place in the app that runs arbitrary programs. With it gone, the audit can say what the app does not do: **it starts no program**. That is simpler to state, to check and to explain than "it starts programs in exactly one place".

This plan removes code and keeps everything else working. It does not add a feature.

## Decisions

| Question | Decision |
|---|---|
| What goes | The whole feature: the runner, the Run tab and its panel logic, the command, the settings, the saved state, the manual section, the tests of the feature, and the audit exception. |
| Replacement | None. |
| Files people already have | `.mdedit/scripts` and `.mdedit/history` inside their folders are left alone. The app never deletes a person's files. The manual says they are no longer used and can be deleted. |
| Saved settings | The old settings keys in the app's own settings are removed once, on first launch after the change. |
| The feature's design notes | Deleted with the feature. Git history keeps them. |
| What other features borrowed from it | Three small things are kept and renamed: the confirmation prompt, the SHA-256 helper and the undoable text insertion. They move out of the shell files first (step 1), so nothing breaks when the feature goes. |
| ⌘R | Left unassigned. |

## What the shell feature touches today

Checked in source on 2026-11-06.

*   **Runner:** `Model/ShellRunner.swift` (343 lines): `ShellRequest`, `ShellResult`, `ShellJob`, `ShellEnvironment`. The only `posix_spawn` in the app.
*   **Window logic:** `Model/Workspace+Shell.swift` (233 lines): `ShellDestination`, `ShellLog`, `ShellSource`, `ShellPrompts`, `ShellFiles` (scripts folder, history, hash), the `Workspace` extension (`openShellBar`, `runShell`, approval of scripts, `finishShell`), and `EditorTextView.insertOutput`.
*   **Window state:** `Model/Workspace.swift`: `shellBarVisible`, `shellScripts`, `shellRecents`, `shellFocusTick`, `shellLog`, `shellJob`, `shellDestination`, `shellConfirm`, and `deinit { shellJob?.cancel() }`; `panel`'s save rule mentions `.run`.
*   **Panel logic:** `Model/Workspace+Find.swift`: `RightPanel.run`, `closeRun()`, the "visit" rule (`.find`, `.run`, `.review`) and `refreshShellLists()`.
*   **Interface:** `UI/ShellBarView.swift`, the Run tab and title in `UI/RightPanelView.swift`, the "Run Shell Command…" entry (⌘R) in `UI/Commands.swift`, the Shell section in `UI/SettingsView.swift`.
*   **Settings:** six properties in `Model/Preferences.swift` (`shellEnabled`, `shellPath`, `shellSearchPath`, `shellEnvironment`, `shellTimeout`, `shellHistory`), plus `shellDestination` and the `shellApproved:<folder>` records in the app's settings.
*   **Docs and checks:** the "Running shell commands" section, a Settings bullet and two troubleshooting entries in `Resources/Manual.md`; README's "Shell commands (⌘R)" section and its mentions; the spawn rule in `scripts/audit.sh` (lines 35 to 37).
*   **Tests:** `Features/ShellCommandTests.swift` (423 lines, 42 tests), `Security/ShellRunnerTests.swift` (193 lines, 22 tests), and one mention each in `Features/HelpTests.swift` and `Features/PreviewTests.swift`.

## What stays, and why

*   **`EditorTextView.insertOutput`** is also used by Find & Replace (`Workspace+Find.swift`, three calls). It moves to the editor's own file and keeps its name and behaviour: one undo step, caret after the text.
*   **`ShellPrompts.confirm`** is a plain `NSAlert` with a button and Cancel. It becomes `ConfirmPrompt.ask(_:_:_:)`. Plan 006 uses it for the template and link sheets.
*   **`ShellFiles.hash`** is a SHA-256 of a string. It becomes `ContentHash.sha256(_:)`. Plan 006 uses it for the template trust record.
*   **`LinkPolicy`** keeps refusing links to programs and scripts (`isProgram`): that protects against a note opening an executable, and has nothing to do with running shell commands.
*   **The "visit" panel logic** stays, minus `.run`. The Find and Review tabs use it, so `panelBefore`, `leaveVisit()` and the save rule stay.

## Implementation steps

Each step is its own commit and ends with `make check` green.

1.  **Keep what others need.** Create `ConfirmPrompt` and `ContentHash`, move `insertOutput`, point every caller at the new names, and port the tests that cover them. No behaviour changes, and the feature still works.
2.  **Remove the feature.** Delete the runner, the window logic, the interface, the settings and the tests; take `.run` out of the panel logic; remove the old saved settings once; change the audit; update the manual page list and the two tests that name it.
3.  **Docs.** README, TESTING.md, the manual's remaining mentions, and `docs/features/features.md`.

### Target Files to Create/Modify/Delete

#### Step 1

##### 1. `Sources/MDEdit/Model/ConfirmPrompt.swift` (Create)

*   **Proposed Changes**: `enum ConfirmPrompt { static func ask(_ title: String, _ detail: String, _ button: String) -> Bool }`, the body of `ShellPrompts.confirm` unchanged.

##### 2. `Sources/MDEdit/Model/ContentHash.swift` (Create)

*   **Proposed Changes**: `enum ContentHash { static func sha256(_ text: String) -> String }`, the body of `ShellFiles.hash` unchanged (lowercase hex).

##### 3. `Sources/MDEdit/Editor/EditorTextView.swift` (Modify)

*   **Proposed Changes**: Add `insertOutput(_:at:)` from `Workspace+Shell.swift`, unchanged apart from its comment ("Replaces `range` with `output` as one undo step; the caret lands after it"). Find & Replace keeps calling it.

##### 4. `Sources/MDEdit/Model/Workspace+Shell.swift` and `Sources/MDEdit/Model/Workspace.swift` (Modify)

*   **Proposed Changes**: Remove `ShellPrompts`, `ShellFiles.hash` and `insertOutput` from `Workspace+Shell.swift`; `ShellFiles` calls `ContentHash.sha256`, `Workspace.shellConfirm` defaults to `ConfirmPrompt.ask`. The file is deleted in step 2.

##### 5. `Tests/MDEditTests/Features/EditorInsertTests.swift` (Create)

*   **Type / Scope**: Unit tests ported from `ShellCommandTests`.
*   **Proposed Changes**: The tests of `insertOutput` that do not need a shell: inserting at the caret, inserting after a selection, replacing only the selection, replacing the whole note, and that a replace and an insert are each one undo step (today `testInsertPutsTheOutputAtTheCaret`, `testInsertWithASelectionKeepsTheSelectionAndInsertsAfterIt`, `testReplaceChangesOnlyTheSelection`, `testReplaceWithoutASelectionTakesTheWholeNote`, `testReplaceIsASingleUndoStep`, `testInsertIsASingleUndoStep`), rewritten to call `insertOutput` directly.

##### 6. Panel tests (Check, then Modify)

*   **Proposed Changes**: `ShellCommandTests` has five tests of the Run tab as a "visit" (`testTheRunTabOpensOnCommandRAndEscGoesBackToWhereThePanelWas`, `testTheRunTabIsAVisitTheToolbarAndTheNextLaunchDoNotOpenOn`, and the three that follow). Before deleting them, check that `FindPanelTests` and `ReviewPanelTests` cover the same behaviour for Find and Review (Esc returns to the earlier panel, the toolbar and the next launch do not open on a visit tab). Port any behaviour that is only tested through Run into `RightPanelTests`.

#### Step 2

##### 7. Delete

*   `Sources/MDEdit/Model/ShellRunner.swift`
*   `Sources/MDEdit/Model/Workspace+Shell.swift`
*   `Sources/MDEdit/UI/ShellBarView.swift`
*   `Tests/MDEditTests/Features/ShellCommandTests.swift`
*   `Tests/MDEditTests/Security/ShellRunnerTests.swift`

##### 8. `Sources/MDEdit/Model/Workspace.swift` (Modify)

*   **Proposed Changes**: Remove the shell block (`shellBarVisible`, `shellScripts`, `shellRecents`, `shellFocusTick`, `shellLog`, `shellJob`, `shellDestination` and its `defaults.set`, `shellConfirm`), the line in `init` that reads `shellDestination`, and `deinit { shellJob?.cancel() }`. In the `panel` `didSet`, the save rule becomes `p != .review`.

##### 9. `Sources/MDEdit/Model/Workspace+Find.swift` (Modify)

*   **Proposed Changes**: Remove `case run` from `RightPanel`, `closeRun()`, `refreshShellLists()` and the `tab == .run` line in `openPanel`. The "visit" rule becomes `$0 == .find || $0 == .review`. A saved `rightPanelTab` that no longer maps to a case already falls back to the outline; a test confirms it.

##### 10. `Sources/MDEdit/UI/RightPanelView.swift`, `Sources/MDEdit/UI/Commands.swift`, `Sources/MDEdit/UI/SettingsView.swift` (Modify)

*   **Proposed Changes**: RightPanelView: remove the `.run` case, its title and its tab item. Commands: remove the "Run Shell Command…" entry, which frees ⌘R. SettingsView: remove the whole Shell section (the switch, shell program, search path, time limit, history and environment rows).

##### 11. `Sources/MDEdit/Model/Preferences.swift` (Modify)

*   **Proposed Changes**: Remove the six shell properties and their lines in `init`. Add one small clean-up in `init`, guarded by a flag key so it runs once: remove the keys `shellEnabled`, `shellPath`, `shellSearchPath`, `shellEnvironment`, `shellTimeout`, `shellHistory`, `shellDestination` and every key that starts with `shellApproved:`. Nothing in any folder is touched.

##### 12. `scripts/audit.sh` (Modify)

*   **Proposed Changes**: Delete the sentence and the two checks that make `ShellRunner` the one place that starts a program (lines 35 to 37). Add `posix_spawn` to the pattern on line 34, so the check reads: no `NSAppleScript`, `Process()`, `NSTask`, `popen`, `exec*`, `fork`, `system(` or `posix_spawn` anywhere in `Sources`. Result: the app starts no program, and the audit says so.

##### 13. `Resources/Manual.md`, `Tests/MDEditTests/Features/HelpTests.swift`, `Tests/MDEditTests/Features/PreviewTests.swift` (Modify)

*   **Proposed Changes**: Manual: delete the "Running shell commands" section, the Shell bullet in Settings, the two troubleshooting entries, "Run Shell Command" in the HTML-files sentence, the Run tab in the side-panel sentence, and change "except `.mdedit` if you use shell commands" to name what `.mdedit` still holds (`preview.css`) and say that older `scripts` and `history` files there are no longer used. HelpTests: drop "Running shell commands" from the expected pages and the ⌘R check. PreviewTests: drop `"shell"` from the list of commands that are disabled on an HTML file.

##### 14. `Tests/MDEditTests/Safety/RemovedShellTests.swift` (Create)

*   **Type / Scope**: Unit tests that the removal is complete.
*   **Proposed Changes**: A fresh `Preferences` over a settings suite that still holds the old keys removes them once and leaves other keys alone; a saved `rightPanelTab` of `"run"` restores to the outline; no command is bound to ⌘R; the built app's source has no program-starting call (the audit covers it; this test only checks the command list).

#### Step 3

##### 15. `README.md` and `TESTING.md` (Modify)

*   **Proposed Changes**: README: delete the "Shell commands (⌘R)" section; take "Shell" out of the HTML-files row; take `ShellRunner` and `ShellBarView` out of the source tree and rule texts; state "the app starts no program" where rule 4 or the entitlements are discussed; and any mention of the shell tests goes. TESTING.md: remove the shell rows from the folder table and any mention of `ShellRunnerTests`.

##### 16. `docs/features/features.md` (Modify)

*   **Proposed Changes**: In `features.md`, change the checked item to "Run shell commands from the editor: removed (plan 007)". Plans 003, 004 and 005 are history and are not edited.

##### 17. `docs/features/006-html-templates/PLAN.md` (Modify)

*   **Proposed Changes**: Replace `ShellPrompts.confirm` with `ConfirmPrompt.ask`, `ShellFiles.hash` with `ContentHash.sha256`, drop "the same way … the `shellApproved:` key work today", and drop "the shell feature" from its Unchanged list and the "existing spawn rule" from its audit item. Done together with step 1 of this plan so the two plans agree. Plan 006's step 3 must come after this plan's step 1.

## Tests

*   Ported: `EditorInsertTests` (insertion and undo) and any panel-visit behaviour found only in the Run tests.
*   Removed with the feature: 64 tests in `ShellCommandTests` and `ShellRunnerTests`. Everything they covered (spawn, kill, environment, scripts, history, approval, settings) exists only for the shell and has no other user.
*   New: `RemovedShellTests` (old keys removed once, a saved `"run"` tab restores to the outline, ⌘R unbound).
*   The audit now fails if any program-starting call appears in `Sources`.

## Verification

1.  After step 1: `make check` passes; ⌘R still works by hand; Find & Replace undo still works.
2.  After step 2: `make check` passes; `make audit` prints that no program-starting call exists; the built app has no Run tab, no ⌘R command and no Shell section in Settings; a folder that still has `.mdedit/scripts` opens normally and nothing in it changes (compare a listing before and after).
3.  `grep -ri shell Sources` returns only `LinkPolicy`'s unrelated type check and no feature code.

## Risks

*   **Lost feature.** Anyone using ⌘R loses it. Git history keeps the code, which keeps the design too. It was a good-to-have.
*   **Shared code.** Removing `Workspace+Shell.swift` also removes `insertOutput`, which Find & Replace uses, and the confirmation prompt and hash that plan 006 plans to use. Step 1 moves them first, and a test covers the insertion.
*   **Panel logic.** The Review tab was built on the Run tab's "visit" pattern. Step 1 checks that Find and Review tests cover the same behaviour before the Run tests are deleted, and `RightPanelTests` take any that are missing.
*   **Old data.** Folders keep their `.mdedit/scripts` and `.mdedit/history`. They are harmless files, and the manual says so.

## As built

*   Step 1 is commit `57d090c`, step 2 is `c61267f`, step 3 is the docs commit after them.
*   One piece the plan missed: the `pointerCursor()` view modifier lived in `ShellBarView.swift` and the Find panel uses it. It moved to `UI/PointerCursor.swift` in step 2.
*   The 64 shell tests were deleted (42 in `ShellCommandTests`, 22 in `ShellRunnerTests`); `EditorInsertTests` (8), one Review test and `RemovedShellTests` (3) were added. The suite went from 532 to 471 tests.
*   The audit now fails on any program-starting call anywhere in `Sources`.
*   `TESTING.md` had no shell mentions, so it was not changed. `grep -ri shell` over `Sources`, `Tests`, `scripts` and the docs finds only the one-time clean-up code and its test, a note in the agent settings text about the person's own terminal history, and `LinkPolicy`'s unrelated check for shell-script file types.

*Drafted with EGM*
