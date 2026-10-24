# Keep Windows folders local

Open **OneDrive folders** in the toolkit and refresh status before removing OneDrive. This page checks Desktop, Documents, Pictures, Music and Videos, including their modern local aliases. Other synced folders need a separate check. It reads locations; it does not move, delete or download files.

## Folders already on this PC

No OneDrive sign-in is needed. Keep any custom local folder you intentionally chose. The optional lock saves Microsoft's `KFMBlockOptIn=1` policy for Desktop, Documents and Pictures; it does not relocate folders or certify policy enforcement on every Windows/OneDrive edition. If OneDrive is installed, the uninstall shortcut rechecks locations before opening Windows Installed apps. You perform the uninstall there.

## Folders still in OneDrive

Keep OneDrive installed while settling backup. Use **OneDrive Settings > Sync and backup > Manage backup**, turn off backup for the affected folders, and choose **Only on my PC**. If you are signed out, reconnect the account that owns those files so the sync app can complete that operation. Download online-only files first if OneDrive requests it. Wait for completion, verify your files locally, and refresh the toolkit before uninstalling.

Microsoft's choice keeps the files locally and removes their OneDrive copies. Keep an independent backup if you need both. A green local path alone does not verify every file from your cloud account was downloaded. The toolkit's metadata scan is bounded; linked, virtual or inaccessible directories are skipped and reported as incomplete. Zero found is not a download guarantee.

## OneDrive already removed, folders inaccessible or locations uncertain

Keep the original OneDrive directory and any existing toolkit journals. Do not delete either to clear a warning. Reinstall/reconnect Microsoft's sync app when necessary to recover cloud-only data and use its supported stop-backup workflow. Verify the account, local files and current Windows folder locations before further cleanup. A missing drive, invalid path or linked directory also needs resolving before the toolkit can call it local.

The registry-only automatic restore from 3.1.0 has been withdrawn. It could point applications at a nonexistent directory and did not establish that all Windows shell locations agreed. Old restore requests now refuse before changing anything. Existing 3.1.0 reports remain available for inspecting prior locations; their automatic undo remains disabled.

The **Recovery instructions** button opens [Microsoft's folder backup guide](https://support.microsoft.com/en-us/onedrive/back-up-your-folders-with-onedrive). Also see [turn off, disable or uninstall OneDrive](https://support.microsoft.com/en-us/onedrive/turn-off-disable-or-uninstall-onedrive). These actions are yours to review in Windows; the toolkit does not run them automatically.
