# Explore files — slice 2: associated-app opening

Binary 7ef47e2 was installed and J passed slice 2. Checkpointed locally before
selection/copy work; not pushed. Baseline d472c0f
is J's accepted first browsing slice; final baseline binary d405e49 also includes
the requested lowercase “files”. Rollback targets that slice, not App-only Tette.

Files remain tap-to-select, folders tap-to-navigate. Open button, double-tap/click
and Enter from selected-grid focus dispatch a selected local listing item to
KIO::OpenUrlJob. Search Enter also routes to Files rather than hidden app results;
the absolute-path editor retains its own Enter behavior. Invalid/stale selection
reports an error. Pending-open state rejects duplicate requests. Selection has
its own notifier so highlighting does not reset delegates/double-click state.

Native associations choose the application. URLs are passed as data, never shell
commands. Both executable-running and open-or-execute prompts are disabled in
OpenUrlJob. No file mutation, Open With chooser, preview, thumbnail or mount work
is included. Files whose association cannot be dispatched remain errors in the
drawer. A successful launch job ends the guest lease and uses existing launcher
dismissal; success means dispatch, not proof that the target app finished loading.

Verification: build/source/diff checks; real-backend/private-bus test validates
selected URL dispatch, absent selection, missing item, duplicate suppression and
error recovery, without launching real apps. QML tests validate Open and Enter
routing plus existing drawer controls. Synthetic touch events now have frame
spacing so moves are not coalesced before drag activation. No Kadunce changes.

Installer: ../../install-tette-files-open-20260914.sh. Restart Tette afterward.
J: select and Open a text document/image; confirm the associated app opens and
Tette dismisses. Reopen and double-tap another file. Check folders still navigate
and tabs/breadcrumbs remain intact. No freeze until J's acceptance.
