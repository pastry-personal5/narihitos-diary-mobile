# P1-M19: Validate the complete V1 experience overview

Status: Planned

Run one prioritized real-iPhone, real-iCloud validation pass over the finished v1 behavior and close the phone-evidence backlog that earlier milestones left open by owner decision.

## Entry and locked inputs

- Starts after M17 and M18 (see [Phase 1 order](phase-1.md)). The owner may run the pass earlier on completed milestones; items for unfinished milestones wait.
- Evidence lives in each milestone's device-evidence record and the [human test tracker](by-human-test-required.md). M19 adds no new product behavior; failures become fix tasks in the owning milestone or M20.
- Use only synthetic folders and recordings. Never purge real user data.

## Priority order (highest risk first)

1. **iCloud round trip (M8, M14, M15, M16, M21 Tasks 3–4):** select a synthetic iCloud folder after fresh install and relaunch; record, transcribe, save; confirm separate audio and Markdown upload proof, offline/foreground recovery, edit, Favorite, delete, and a real provider conflict.
2. **Capture and transcription (M9, M10, M11, M12, M20):** lock/background/five-minute/interruption capture; Apple Local and Cohere Q4/Q5 on English and Korean; restored-install quarantine; the M20 reported repros.
3. **Main, detail and replay (M15, M16):** paging/downloads, detail, replay with headphone loss, editor input including Korean composition.
4. **Accessibility and privacy (all):** VoiceOver, Reduce Motion, largest Dynamic Type, rotation, app-switcher privacy cover.
5. **Recovery and reminders (M17, M18):** the Pending/Failed/Incomplete/Conflict flows, the reminder, and weather/location context.

## Completion checklist

- [ ] Each device-evidence record's scenarios (M8–M18) have a redacted pass/fail observation or an explicit owner waiver with a reason.
- [ ] Every failure has a linked fix task; none is silently dropped.
- [ ] Verify Cohere/Q5 five-minute quality, energy and long-input completeness, or record an owner decision to ship without that evidence (P1-M6 did not establish it).
- [ ] `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh` pass on the final revision.
- [ ] Product, UX and architecture docs match shipped behavior, and Phase 1 statuses reflect actual evidence.
