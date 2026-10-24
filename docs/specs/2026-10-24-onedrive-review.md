# OneDrive 3.1.0 verification and patch plan

The goal is a safe preflight for fresh Windows and existing installs, preserving files, custom local folders and the configured host. Keep the existing PowerShell 5.1/WPF architecture and the 3.0.2 release copy intact.

## Evidence and scope

The starting checkout is clean at `3a590b7`; the 3.1.0 release commit is `fb98d61`. Its exact CI/Actions analysis runs passed, all three public asset hashes match, and all 614 native regression assertions pass again. Review nevertheless found missing boundary cases in the new OneDrive implementation.

1. A cloud placeholder with ReparsePoint is skipped before recall flags are examined. Directory scans can also be incomplete without saying so.
2. Nonempty relative, unresolved or missing folder paths pass as safe custom locations. Modern LocalDocuments/LocalPictures/LocalMusic/LocalVideos aliases also need checking. Their GUIDs were read from this Windows installation's FolderDescriptions registry, not guessed.
3. The uninstall shortcut trusts cached status after the user can change OneDrive settings externally.
4. Automatic registry restoration creates no destination and bypasses supported shell migration. The old tests pre-create destinations and conceal this defect.

## Chosen changes

- Add fixture regressions first, retaining real registry/file boundaries and using in-memory metadata only for cloud attributes that user-mode files cannot set.
- Classify only verified existing absolute local directories as local/custom; unresolved, inaccessible, linked and malformed locations block the gate. Check optional modern local aliases without creating or altering them.
- Count cloud-file recall attributes before skipping links; never recurse into linked or virtual directories. Report skipped, denied and capped scans as incomplete. Count all examined entries toward the bound.
- Re-read the gate when uninstall is clicked. Keep confirmation and the Windows Installed apps handoff.
- Withdraw the unsafe automatic path rewrite; retain an explicit refusal for old worker/API requests, and show supported recovery instructions. Existing journals and user files remain untouched.
- Correct guidance so already-local folders never require a new OneDrive sign-in. Explain that Only on my PC removes the OneDrive copy through Microsoft's UI, so users should keep an independent backup if they need both copies.

The alternatives were to retain a partly verified registry migration or build a full shell migration and file-transfer system. Guided recovery is the smallest complete safe choice for this patch; a full migration needs separate Explorer/OneDrive runtime proof.

## Validation and handoff

Run focused failing/passing cases, the complete native 5.1 STA suite, static validation, PSScriptAnalyzer and dashboard render. Verify canonical and friendly layouts in CI on the exact pushed SHA. Publish a forward patch release only after successful checks and security queries; build from that commit, compare every payload Git blob, test the extracted package, then download/hash-check all uploaded assets. Keep prior releases and the installed 3.0.2 copy intact. Record exact outcomes in STATE.md and VALIDATION_REPORT.md.

No live optimization, uninstall, folder redirection, app removal, Windows repair or DNS changes are authorized as validation on this configured host. The shared ChatGPT page returned only its title and shell, not conversation text; do not claim it was read. The user's supplied OneDrive account is sufficient for the patch requirements.
