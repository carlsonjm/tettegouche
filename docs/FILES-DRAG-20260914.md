# Files dragging and edge scrolling

J passed all three installed checks. Accepted after box-selection checkpoint 39cd67c; remote main
remains 035b60c. J requests related features bundled in groups of 2–3 per pass.

## Combined scope

- Mouse item drag and touch hold-then-move drag selected files into a visible
  folder. An unselected source selects itself; selected sources retain the group.
- Touch 500ms hold arms dragging and selects the source if necessary. Release
  without dragging opens the context menu; movement before hold remains scrolling.
- Destination outline and floating Copy count/name communicate the operation.
- Edge scrolling for file drags and selection boxes, with speed increasing nearer
  the top/bottom edge. Box selection also starts in cell gutters.
- Escape cancels an active file drag. Hidden pane, navigation/listing change or
  canceled grab clears the drag; invalid/background drops perform no operation.

Internal drops only COPY, independently of clipboard data. Backend validates
listed sources/destination, rejects self/descendant folder copies (canonical paths),
deduplicates URLs, and uses existing asynchronous KIO no-overwrite handling and
quit deferral. Originals and clipboard are unchanged. No move, external drop,
cross-tab hover navigation, rename or Trash in this batch.

## Verification

QML controls suite passed (15.25s): hold-release, touch and mouse folder drop,
destination routing, file/box edge scrolling, Escape cancellation and prior
selection interactions. Native temporary-file suite passed (1.02s): copy content,
original/clipboard preservation, invalid/self-drop refusal and collision protection.
Build/source/diff checks passed. Physical touch acceptance remains J's check.

Installer: install-tette-files-drag-20260914.sh in workspace root.
Candidate SHA256: fcc1357518714cac1a9e8347b54fa72c0679ca816249dcd1615f7ff932457cae.
Rollback: accepted 607541b6 box-selection binary. Nothing installed or pushed.
