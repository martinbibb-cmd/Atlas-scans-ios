import XCTest
@testable import AtlasScan

// MARK: - VisitNotesConsolidatorTests

final class VisitNotesConsolidatorTests: XCTestCase {

    // MARK: - Voice notes: transcript preference

    func test_consolidate_voiceNoteWithReadyTranscript_usesTranscript() {
        let note = VoiceNote(
            localFilename: "a.m4a",
            caption: "Caption text",
            transcriptStatus: .completed,
            transcript: "Transcript text"
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertEqual(result.lines, ["Transcript text"])
    }

    func test_consolidate_voiceNoteWithPendingTranscript_usesCaptionFallback() {
        let note = VoiceNote(
            localFilename: "b.m4a",
            caption: "Caption fallback",
            transcriptStatus: .pending,
            transcript: nil
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertEqual(result.lines, ["Caption fallback"])
    }

    func test_consolidate_voiceNoteWithFailedTranscript_usesCaptionFallback() {
        let note = VoiceNote(
            localFilename: "c.m4a",
            caption: "Caption fallback",
            transcriptStatus: .failed,
            transcript: nil
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertEqual(result.lines, ["Caption fallback"])
    }

    func test_consolidate_completedTranscript_overridesCaption() {
        let note = VoiceNote(
            localFilename: "d.m4a",
            caption: "Old caption",
            transcriptStatus: .completed,
            transcript: "Better transcript"
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertEqual(result.lines, ["Better transcript"],
                       "Transcript must override caption when status is .completed")
    }

    // MARK: - Empty content filtering

    func test_consolidate_voiceNoteWithNilTranscriptAndEmptyCaption_isIgnored() {
        let note = VoiceNote(
            localFilename: "e.m4a",
            caption: "",
            transcriptStatus: .pending,
            transcript: nil
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertTrue(result.lines.isEmpty,
                      "Notes with no usable content must be ignored")
    }

    func test_consolidate_whitespaceOnlyCaption_isIgnored() {
        let note = VoiceNote(
            localFilename: "f.m4a",
            caption: "   ",
            transcriptStatus: .none,
            transcript: nil
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertTrue(result.lines.isEmpty)
    }

    func test_consolidate_whitespaceOnlyTranscript_fallsBackToCaption() {
        let note = VoiceNote(
            localFilename: "g.m4a",
            caption: "Valid caption",
            transcriptStatus: .completed,
            transcript: "   "
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertEqual(result.lines, ["Valid caption"],
                       "Whitespace-only transcript must fall back to caption")
    }

    func test_consolidate_emptyVoiceNotes_returnsEmpty() {
        let result = consolidateVisitNotes(voiceNotes: [])
        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertFalse(result.hasUsableContent)
    }

    // MARK: - Manual notes

    func test_consolidate_manualNotes_areAppended() {
        let result = consolidateVisitNotes(voiceNotes: [], manualNotes: ["Manual note one"])
        XCTAssertEqual(result.lines, ["Manual note one"])
    }

    func test_consolidate_emptyManualNote_isIgnored() {
        let result = consolidateVisitNotes(voiceNotes: [], manualNotes: ["  ", ""])
        XCTAssertTrue(result.lines.isEmpty)
    }

    func test_consolidate_manualNotesAppendedAfterVoiceNotes() {
        let note = VoiceNote(
            localFilename: "",
            caption: "Voice note",
            transcriptStatus: .completed,
            transcript: "Voice note"
        )
        let result = consolidateVisitNotes(voiceNotes: [note], manualNotes: ["Manual note"])
        XCTAssertEqual(result.lines, ["Voice note", "Manual note"])
    }

    // MARK: - Chronological ordering

    func test_consolidate_voiceNotesSortedByCreatedAt() {
        // Create two notes and rely on createdAt being distinct (auto-set to Date()).
        // We insert them in reverse order to verify the consolidator re-sorts.
        var older = VoiceNote(localFilename: "old.m4a", caption: "Older note", transcriptStatus: .none)
        var newer = VoiceNote(localFilename: "new.m4a", caption: "Newer note", transcriptStatus: .none)
        // Force a known ordering using the createdAt property.
        older.createdAt = Date(timeIntervalSinceNow: -100)
        newer.createdAt = Date(timeIntervalSinceNow: -10)

        let result = consolidateVisitNotes(voiceNotes: [newer, older])
        XCTAssertEqual(result.lines, ["Older note", "Newer note"],
                       "Voice notes must be sorted chronologically regardless of input order")
    }

    // MARK: - hasUsableContent

    func test_hasUsableContent_trueWhenTranscriptAvailable() {
        let note = VoiceNote(
            localFilename: "h.m4a",
            transcriptStatus: .completed,
            transcript: "Boiler in loft"
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertTrue(result.hasUsableContent)
    }

    func test_hasUsableContent_trueWhenCaptionFallbackAvailable() {
        let note = VoiceNote(
            localFilename: "i.m4a",
            caption: "Caption only",
            transcriptStatus: .failed,
            transcript: nil
        )
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertTrue(result.hasUsableContent)
    }

    func test_hasUsableContent_falseWhenAllNotesEmpty() {
        let note = VoiceNote(localFilename: "j.m4a", transcriptStatus: .pending)
        let result = consolidateVisitNotes(voiceNotes: [note])
        XCTAssertFalse(result.hasUsableContent,
                       "hasUsableContent must be false when all notes have empty content")
    }

    // MARK: - Preview helper

    func test_preview_limitsLines() {
        let notes = (1...10).map { i in
            VoiceNote(
                localFilename: "\(i).m4a",
                caption: "Note \(i)",
                transcriptStatus: .none
            )
        }
        let result = consolidateVisitNotes(voiceNotes: notes)
        XCTAssertEqual(result.preview(maxLines: 3).count, 3)
    }

    func test_preview_defaultIsThreeLines() {
        let notes = (1...5).map { i in
            VoiceNote(
                localFilename: "\(i).m4a",
                caption: "Note \(i)",
                transcriptStatus: .none
            )
        }
        let result = consolidateVisitNotes(voiceNotes: notes)
        XCTAssertEqual(result.preview().count, 3)
    }
}

// MARK: - FieldVisitStore Voice Recording Tests

@MainActor
final class FieldVisitStoreVoiceRecordingTests: XCTestCase {

    private func makeStore() -> FieldVisitStore {
        let session = PropertyScanSession(jobReference: "JOB-TEST", propertyAddress: "1 Test St")
        return FieldVisitStore(session: session, sessionStore: ScanSessionStore())
    }

    private func makeFullyReadyStore() -> FieldVisitStore {
        var session = PropertyScanSession(jobReference: "JOB-READY", propertyAddress: "2 Ready St")
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        session.addPhoto(TaggedPhoto(filename: "p.jpg"))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .cylinder))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .radiator))
        session.addVoiceNote(VoiceNote(localFilename: "note.m4a", duration: 30))
        return FieldVisitStore(session: session, sessionStore: ScanSessionStore())
    }

    // MARK: - addVoiceNoteRecording

    func test_addVoiceNoteRecording_appearsInSession() {
        let store = makeStore()
        let note = VoiceNote(localFilename: "rec.m4a", caption: "Boiler info")
        store.addVoiceNoteRecording(note)
        XCTAssertEqual(store.session.voiceNotes.count, 1)
    }

    func test_addVoiceNoteRecording_setsStatusToPending() {
        let store = makeStore()
        let note = VoiceNote(localFilename: "rec.m4a", transcriptStatus: .none)
        store.addVoiceNoteRecording(note)
        XCTAssertEqual(store.session.voiceNotes.first?.transcriptStatus, .pending,
                       "addVoiceNoteRecording must override status to .pending regardless of input status")
    }

    func test_addVoiceNoteRecording_satisfiesNotesReadiness() {
        let store = makeStore()
        XCTAssertFalse(store.visitReadiness.hasNotes)
        store.addVoiceNoteRecording(VoiceNote(localFilename: "rec.m4a"))
        XCTAssertTrue(store.visitReadiness.hasNotes)
    }

    func test_addVoiceNoteRecording_blockedAfterCompletion() {
        let store = makeFullyReadyStore()
        store.completeVisit()
        XCTAssertTrue(store.isCompleted)
        let countBefore = store.session.voiceNotes.count
        store.addVoiceNoteRecording(VoiceNote(localFilename: "new.m4a"))
        XCTAssertEqual(store.session.voiceNotes.count, countBefore,
                       "addVoiceNoteRecording must be a no-op on a completed visit")
    }

    // MARK: - applyTranscriptResult

    func test_applyTranscriptResult_updatesTranscriptAndStatus() {
        let store = makeStore()
        let note = VoiceNote(localFilename: "rec.m4a", transcriptStatus: .pending)
        store.addVoiceNoteRecording(note)

        store.applyTranscriptResult(
            noteID: note.id,
            transcript: "Boiler is in loft",
            status: .completed
        )

        let updated = store.session.voiceNotes.first
        XCTAssertEqual(updated?.transcript, "Boiler is in loft")
        XCTAssertEqual(updated?.transcriptStatus, .completed)
    }

    func test_applyTranscriptResult_failedStatusPreservesNote() {
        let store = makeStore()
        let note = VoiceNote(localFilename: "rec.m4a", caption: "Caption fallback", transcriptStatus: .pending)
        store.addVoiceNoteRecording(note)

        store.applyTranscriptResult(noteID: note.id, transcript: nil, status: .failed)

        let updated = store.session.voiceNotes.first
        XCTAssertNil(updated?.transcript)
        XCTAssertEqual(updated?.transcriptStatus, .failed)
        XCTAssertEqual(updated?.caption, "Caption fallback",
                       "Failed transcription must preserve caption fallback")
    }

    func test_applyTranscriptResult_allowedOnCompletedVisit() {
        let store = makeFullyReadyStore()

        // Add a voice note with pending transcription before completing.
        let note = VoiceNote(localFilename: "rec.m4a", transcriptStatus: .pending)
        store.addVoiceNoteRecording(note)
        store.completeVisit()
        XCTAssertTrue(store.isCompleted)

        // Transcript arrives after completion — must still be applied.
        store.applyTranscriptResult(noteID: note.id, transcript: "Late transcript", status: .completed)

        let match = store.session.voiceNotes.first(where: { $0.id == note.id })
        XCTAssertEqual(match?.transcript, "Late transcript",
                       "applyTranscriptResult must bypass the completion lock")
        XCTAssertEqual(match?.transcriptStatus, .completed)
    }

    func test_applyTranscriptResult_unknownID_isNoOp() {
        let store = makeStore()
        let unknownID = UUID()
        store.applyTranscriptResult(noteID: unknownID, transcript: "X", status: .completed)
        XCTAssertTrue(store.session.voiceNotes.isEmpty, "Unknown ID must not crash or mutate session")
    }

    // MARK: - removeVoiceNote

    func test_removeVoiceNote_removesRecord() {
        let store = makeStore()
        store.addTextNote("Text note")
        let id = store.session.voiceNotes.first!.id
        XCTAssertEqual(store.session.voiceNotes.count, 1)

        store.removeVoiceNote(id: id)

        XCTAssertEqual(store.session.voiceNotes.count, 0)
    }

    func test_removeVoiceNote_updatesNotesReadiness() {
        let store = makeStore()
        store.addTextNote("Some note")
        let id = store.session.voiceNotes.first!.id
        XCTAssertTrue(store.visitReadiness.hasNotes)

        store.removeVoiceNote(id: id)

        XCTAssertFalse(store.visitReadiness.hasNotes)
    }

    func test_removeVoiceNote_blockedAfterCompletion() {
        let store = makeFullyReadyStore()
        store.completeVisit()
        XCTAssertTrue(store.isCompleted)
        let countBefore = store.session.voiceNotes.count

        let id = store.session.voiceNotes.first!.id
        store.removeVoiceNote(id: id)

        XCTAssertEqual(store.session.voiceNotes.count, countBefore,
                       "removeVoiceNote must be a no-op on a completed visit")
    }

    // MARK: - consolidatedNotes

    func test_consolidatedNotes_emptySessionReturnsEmpty() {
        let store = makeStore()
        XCTAssertFalse(store.consolidatedNotes.hasUsableContent)
    }

    func test_consolidatedNotes_includesTextNotes() {
        let store = makeStore()
        store.addTextNote("Boiler needs servicing")
        XCTAssertTrue(store.consolidatedNotes.hasUsableContent)
        XCTAssertEqual(store.consolidatedNotes.lines.first, "Boiler needs servicing")
    }

    func test_consolidatedNotes_includesTranscriptBackedVoiceNote() {
        let store = makeStore()
        let note = VoiceNote(
            localFilename: "rec.m4a",
            caption: "Caption",
            transcriptStatus: .completed,
            transcript: "Transcript text"
        )
        store.update { $0.addVoiceNote(note) }
        XCTAssertEqual(store.consolidatedNotes.lines, ["Transcript text"])
    }

    func test_consolidatedNotes_usesCaptionFallback() {
        let store = makeStore()
        let note = VoiceNote(localFilename: "rec.m4a", caption: "Caption fallback", transcriptStatus: .failed)
        store.update { $0.addVoiceNote(note) }
        XCTAssertEqual(store.consolidatedNotes.lines, ["Caption fallback"])
    }

    func test_consolidatedNotes_excludesPendingNoteWithNoCaption() {
        let store = makeStore()
        let note = VoiceNote(localFilename: "rec.m4a", transcriptStatus: .pending)
        store.update { $0.addVoiceNote(note) }
        XCTAssertFalse(store.consolidatedNotes.hasUsableContent,
                       "A pending note with no caption must not contribute usable content")
    }
}
