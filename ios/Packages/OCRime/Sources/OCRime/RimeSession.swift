// SPDX-License-Identifier: GPL-3.0-or-later
import CRime
import Foundation

/// One librime session (one composition). Not thread-safe; `RimeService` owns it
/// and calls it from its serial queue only.
final class RimeSession {
    private let api: UnsafeMutablePointer<RimeApi>
    private(set) var id: RimeSessionId = 0

    init?() {
        guard let api = rime_get_api() else { return nil }
        self.api = api
        id = api.pointee.create_session()
        if id == 0 { return nil }
    }

    /// Set when the engine was finalised underneath this session. librime session ids
    /// are addresses and may be reused by the next engine, so a stale id must never be destroyed.
    private var stale = false

    func markStale() { stale = true }

    deinit {
        if id != 0, !stale { _ = api.pointee.destroy_session(id) }
    }

    // MARK: input

    /// Returns whether librime consumed the key.
    func process(_ key: RimeKey) -> Bool {
        api.pointee.process_key(id, key.code, key.mask) != 0
    }

    func selectCandidate(at index: Int) -> Bool {
        api.pointee.select_candidate(id, index) != 0
    }

    func changePage(backward: Bool) -> Bool {
        api.pointee.change_page(id, backward ? 1 : 0) != 0
    }

    func clearComposition() {
        api.pointee.clear_composition(id)
    }

    @discardableResult
    func commitComposition() -> Bool {
        api.pointee.commit_composition(id) != 0
    }

    func setOption(_ name: String, _ value: Bool) {
        name.withCString { api.pointee.set_option(id, $0, value ? 1 : 0) }
    }

    func option(_ name: String) -> Bool {
        name.withCString { api.pointee.get_option(id, $0) != 0 }
    }

    func selectSchema(_ schemaID: String) -> Bool {
        schemaID.withCString { api.pointee.select_schema(id, $0) != 0 }
    }

    func currentSchema() -> String? {
        let capacity = 128
        var buffer = [CChar](repeating: 0, count: capacity)
        guard api.pointee.get_current_schema(id, &buffer, capacity) != 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: output

    /// Text to insert into the document, consumed (librime clears it).
    func takeCommit() -> String? {
        var commit = RimeCommit()
        commit.data_size = Int32(MemoryLayout<RimeCommit>.size - MemoryLayout<Int32>.size)
        guard api.pointee.get_commit(id, &commit) != 0 else { return nil }
        defer { _ = api.pointee.free_commit(&commit) }
        guard let text = commit.text else { return nil }
        let string = String(cString: text)
        return string.isEmpty ? nil : string
    }

    /// Composition and candidates. `limit` caps the number of candidates read.
    func snapshot(limit: Int, into update: inout RimeUpdate) {
        var context = RimeContext()
        context.data_size = Int32(MemoryLayout<RimeContext>.size - MemoryLayout<Int32>.size)
        if api.pointee.get_context(id, &context) != 0 {
            defer { _ = api.pointee.free_context(&context) }
            let composition = context.composition
            let preedit = composition.preedit.map { String(cString: $0) } ?? ""
            update.preedit = preedit
            update.cursor = RimeSession.characterOffset(in: preedit, byteOffset: Int(composition.cursor_pos))
            update.selectionStart = RimeSession.characterOffset(in: preedit, byteOffset: Int(composition.sel_start))
            update.selectionEnd = RimeSession.characterOffset(in: preedit, byteOffset: Int(composition.sel_end))
            update.isComposing = composition.length > 0
            let menu = context.menu
            update.pageSize = Int(menu.page_size)
            update.pageNumber = Int(menu.page_no)
            update.isLastPage = menu.is_last_page != 0
            update.highlighted = Int(menu.page_no) * Int(menu.page_size) + Int(menu.highlighted_candidate_index)
            if update.isComposing { update.candidates = readCandidates(limit: limit) }
        }
        update.asciiMode = option("ascii_mode")
    }

    private func readCandidates(limit: Int) -> [RimeCandidate] {
        var result: [RimeCandidate] = []
        var iterator = RimeCandidateListIterator()
        guard api.pointee.candidate_list_begin(id, &iterator) != 0 else { return result }
        defer { api.pointee.candidate_list_end(&iterator) }
        while result.count < limit, api.pointee.candidate_list_next(&iterator) != 0 {
            let text = iterator.candidate.text.map { String(cString: $0) } ?? ""
            let comment = iterator.candidate.comment.map { String(cString: $0) } ?? ""
            result.append(RimeCandidate(text: text, comment: comment))
        }
        return result
    }

    /// librime reports positions as UTF-8 byte offsets.
    static func characterOffset(in string: String, byteOffset: Int) -> Int {
        let bytes = Array(string.utf8)
        let clamped = max(0, min(byteOffset, bytes.count))
        return String(decoding: bytes[0..<clamped], as: UTF8.self).count
    }
}
