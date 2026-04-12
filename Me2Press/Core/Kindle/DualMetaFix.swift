//
//  DualMetaFix.swift
//  Me2Press
//
//  Fix MOBI metadata to EBOK/ASIN for Kindle recognition.
//  fix()      — synchronous, nonisolated; blocking file I/O.
//  fixAsync() — offloads to a non-isolated concurrent task; safe to call from MainActor.
//

import Foundation

enum DualMetaFix {
    // All constants and helpers are nonisolated so fix() can call them
    // from a Task.detached closure without crossing actor boundaries.

    // Byte offsets into the PDB file header and Mobi record 0, per the Palm/Mobi binary spec.
    // All multi-byte values in this format are big-endian.
    private nonisolated static let numberOfPdbRecordsOffset = 76 // PDB header: 16-bit record count
    private nonisolated static let firstPdbRecordOffset = 78 // PDB header: start of 8-byte-per-record descriptor array
    private nonisolated static let mobiHeaderBaseOffset = 16 // rec0: byte offset where the Mobi header begins (after PalmDOC header)
    private nonisolated static let mobiHeaderLengthOffset = 20 // Mobi header: 32-bit length field, used to locate the EXTH block
    private nonisolated static let mobiVersionOffset = 36 // Mobi header: format version (8 = KF8-only; anything else = KF6+KF8 combo)
    private nonisolated static let titleOffsetOffset = 84 // Mobi header: byte offset of the embedded full-title string within rec0

    // MARK: - Async entry point (call from MainActor / ViewModel)

    static func fixAsync(mobiPath: URL, uuid: String) async throws(Me2PressError) {
        do {
            try await Task.detached(priority: .userInitiated) {
                try fix(mobiPath: mobiPath, uuid: uuid)
            }.value
        } catch let e as Me2PressError {
            throw e
        } catch {
            throw Me2PressError.mobiInvalidFormat(reason: error.localizedDescription)
        }
    }

    // MARK: - Synchronous core (nonisolated; blocking file I/O)

    /// Rewrites EXTH records 501 (CDEType) and 113 (ASIN) in both the KF6 and KF8 headers
    /// of a MOBI/AZW3 file so Kindle recognises it as a purchased book (EBOK) with a unique ASIN.
    ///
    /// For a KF6+KF8 combo file the same fix is applied to the second Mobi header located
    /// at the section referenced by EXTH record 121 of the primary header.
    nonisolated static func fix(mobiPath: URL, uuid: String) throws(Me2PressError) {
        do {
            let data = try Data(contentsOf: mobiPath, options: .alwaysMapped)

            guard let cdetype = "EBOK".data(using: .ascii),
                  let asin = uuid.data(using: .ascii)
            else { return }

            let fileHandle = try FileHandle(forUpdating: mobiPath)
            defer { try? fileHandle.close() }

            var rec0 = try readSection(data, secno: 0)

            rec0 = try delExth(rec0, exthNum: 501)
            rec0 = try delExth(rec0, exthNum: 113)
            rec0 = try addExth(rec0, exthNum: 501, exthBytes: cdetype)
            rec0 = try addExth(rec0, exthNum: 113, exthBytes: asin)

            try replaceSection(fileHandle: fileHandle, datain: data, secno: 0, secdata: rec0)

            // Mobi version 8 means a KF8-only file; any other version indicates a KF6+KF8 combo
            // file where a second Mobi header starts at the section pointed to by EXTH record 121.
            let ver = try getUInt32BE(rec0, at: mobiVersionOffset)
            let isCombo = (ver != 8)

            if isCombo {
                let exth121 = try readExth(rec0, exthNum: 121)
                if let first121 = exth121.first, first121.count >= 4 {
                    let datainKf8 = try getUInt32BE(first121, at: 0)
                    if datainKf8 != 0xffffffff {
                        let kf8SecNo = Int(datainKf8)
                        var kfRec0 = try readSection(data, secno: kf8SecNo)

                        kfRec0 = try delExth(kfRec0, exthNum: 501)
                        kfRec0 = try delExth(kfRec0, exthNum: 113)
                        kfRec0 = try addExth(kfRec0, exthNum: 501, exthBytes: cdetype)
                        kfRec0 = try addExth(kfRec0, exthNum: 113, exthBytes: asin)

                        try replaceSection(fileHandle: fileHandle, datain: data, secno: kf8SecNo, secdata: kfRec0)
                    }
                }
            }
        } catch let e as Me2PressError {
            throw e
        } catch {
            throw Me2PressError.mobiInvalidFormat(reason: error.localizedDescription)
        }
    }

    // MARK: - Private helpers (all nonisolated)

    private nonisolated static func getUInt32BE(_ data: Data, at offset: Int) throws(Me2PressError) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw Me2PressError.mobiInvalidFormat(reason: "getUInt32BE out of bounds")
        }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private nonisolated static func getUInt16BE(_ data: Data, at offset: Int) throws(Me2PressError) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw Me2PressError.mobiInvalidFormat(reason: "getUInt16BE out of bounds")
        }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private nonisolated static func writeUInt32BE(_ value: UInt32, into data: inout Data, at offset: Int) throws(Me2PressError) {
        guard offset >= 0, offset + 4 <= data.count else {
            throw Me2PressError.mobiInvalidFormat(reason: "writeUInt32BE out of bounds")
        }
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { ptr in
            data.replaceSubrange(offset..<offset + 4, with: ptr)
        }
    }

    private nonisolated static func getSecAddr(_ data: Data, secno: Int) throws(Me2PressError) -> (Int, Int) {
        let nsec = try Int(getUInt16BE(data, at: numberOfPdbRecordsOffset))
        guard secno >= 0, secno < nsec else {
            throw Me2PressError.mobiInvalidFormat(reason: "Section number out of range")
        }
        let secStart = try Int(getUInt32BE(data, at: firstPdbRecordOffset + secno * 8))
        let secEnd: Int = if secno == nsec - 1 {
            data.count
        } else {
            try Int(getUInt32BE(data, at: firstPdbRecordOffset + (secno + 1) * 8))
        }
        return (secStart, secEnd)
    }

    private nonisolated static func readSection(_ data: Data, secno: Int) throws(Me2PressError) -> Data {
        let (start, end) = try getSecAddr(data, secno: secno)
        return data.subdata(in: start..<end)
    }

    /// Overwrites a PDB section in-place via `fileHandle`.
    ///
    /// IMPORTANT: The PDB record descriptor table in the file header is never rewritten,
    /// so `secdata.count` must equal the original section byte length exactly.
    private nonisolated static func replaceSection(
        fileHandle: FileHandle, datain: Data, secno: Int, secdata: Data
    ) throws(Me2PressError) {
        do {
            let (start, end) = try getSecAddr(datain, secno: secno)
            guard secdata.count == end - start else {
                throw Me2PressError.mobiInvalidFormat(reason: "Section length changed in replacesection")
            }
            try fileHandle.seek(toOffset: UInt64(start))
            try fileHandle.write(contentsOf: secdata)
        } catch let e as Me2PressError {
            throw e
        } catch {
            throw Me2PressError.mobiInvalidFormat(reason: error.localizedDescription)
        }
    }

    /// Locates the EXTH block within `rec0` and returns the parameters needed by add/del/read helpers.
    ///
    /// - Returns: `(ebase, elen, enumCount, rlen)` where
    ///   `ebase`     = byte offset of the "EXTH" tag within `rec0`,
    ///   `elen`      = total EXTH block length (tag + length + count fields + all records),
    ///   `enumCount` = number of EXTH records currently present,
    ///   `rlen`      = total byte length of `rec0` (used to preserve section size on writes).
    private nonisolated static func getExthParams(_ rec0: Data) throws(Me2PressError) -> (Int, Int, Int, Int) {
        let ebase = try mobiHeaderBaseOffset + Int(getUInt32BE(rec0, at: mobiHeaderLengthOffset))
        guard ebase + 4 <= rec0.count,
              String(data: rec0[ebase..<ebase + 4], encoding: .ascii) == "EXTH"
        else {
            throw Me2PressError.mobiInvalidFormat(reason: "EXTH tag not found")
        }
        let elen = try Int(getUInt32BE(rec0, at: ebase + 4))
        let enumCount = try Int(getUInt32BE(rec0, at: ebase + 8))
        return (ebase, elen, enumCount, rec0.count)
    }

    /// Inserts a new EXTH record into `rec0`, keeping the total section size constant.
    ///
    /// The EXTH block is followed by zero-padding up to the title string. Inserting a record
    /// expands the block into that padding; the trailing `newRecSize` zero bytes are then
    /// trimmed to restore the original byte length. The guard verifies no non-zero content
    /// is discarded — a failure here indicates incorrect title-offset arithmetic.
    /// The title-string offset field is adjusted upward by `newRecSize` to stay valid.
    private nonisolated static func addExth(_ rec0: Data, exthNum: UInt32, exthBytes: Data) throws(Me2PressError) -> Data {
        let (ebase, elen, enumCount, rlen) = try getExthParams(rec0)
        let newRecSize = 8 + exthBytes.count

        var newRec0 = rec0.subdata(in: 0..<ebase + 4)
        var elenBig = UInt32(elen + newRecSize).bigEndian
        withUnsafeBytes(of: &elenBig) { newRec0.append(contentsOf: $0) }

        var enumBig = UInt32(enumCount + 1).bigEndian
        withUnsafeBytes(of: &enumBig) { newRec0.append(contentsOf: $0) }

        var exthNumBig = exthNum.bigEndian
        withUnsafeBytes(of: &exthNumBig) { newRec0.append(contentsOf: $0) }

        var newRecSizeBig = UInt32(newRecSize).bigEndian
        withUnsafeBytes(of: &newRecSizeBig) { newRec0.append(contentsOf: $0) }

        newRec0.append(exthBytes)
        newRec0.append(rec0.subdata(in: ebase + 12..<rec0.count))

        let currentTitleOffset = try getUInt32BE(newRec0, at: titleOffsetOffset)
        try writeUInt32BE(currentTitleOffset + UInt32(newRecSize), into: &newRec0, at: titleOffsetOffset)

        guard newRec0.suffix(newRecSize).allSatisfy({ $0 == 0 }) else {
            throw Me2PressError.mobiInvalidFormat(reason: "addExth trimmed non-null bytes")
        }
        return newRec0.subdata(in: 0..<rlen)
    }

    /// Returns the data payloads of all EXTH records whose type matches `exthNum`.
    private nonisolated static func readExth(_ rec0: Data, exthNum: UInt32) throws(Me2PressError) -> [Data] {
        var values = [Data]()
        let (ebase, _, enumCount, _) = try getExthParams(rec0)
        var idx = ebase + 12
        for _ in 0..<enumCount {
            let exthId = try getUInt32BE(rec0, at: idx)
            let exthSize = try Int(getUInt32BE(rec0, at: idx + 4))
            if exthId == exthNum {
                values.append(rec0.subdata(in: idx + 8..<idx + exthSize))
            }
            idx += exthSize
        }
        return values
    }

    /// Removes the first EXTH record matching `exthNum` from `rec0`, keeping the total section size constant.
    ///
    /// After removal, `exthSize` zero bytes are appended to restore the original byte length,
    /// satisfying the `replaceSection` size invariant. The title-string offset is adjusted
    /// downward by `exthSize` to compensate for the shift.
    private nonisolated static func delExth(_ rec0: Data, exthNum: UInt32) throws(Me2PressError) -> Data {
        let (ebase, elen, enumCount, rlen) = try getExthParams(rec0)
        var idx = ebase + 12
        for _ in 0..<enumCount {
            let exthId = try getUInt32BE(rec0, at: idx)
            let exthSize = try Int(getUInt32BE(rec0, at: idx + 4))
            if exthId == exthNum {
                var newRec0 = rec0
                let currentTitleOffset = try getUInt32BE(newRec0, at: titleOffsetOffset)
                try writeUInt32BE(currentTitleOffset - UInt32(exthSize), into: &newRec0, at: titleOffsetOffset)

                newRec0.removeSubrange(idx..<idx + exthSize)

                try writeUInt32BE(UInt32(elen - exthSize), into: &newRec0, at: ebase + 4) // elen
                try writeUInt32BE(UInt32(enumCount - 1), into: &newRec0, at: ebase + 8) // enum ← Bug Fix

                newRec0.append(contentsOf: [UInt8](repeating: 0, count: exthSize))
                guard newRec0.count == rlen else {
                    throw Me2PressError.mobiInvalidFormat(reason: "delExth incorrect size change")
                }
                return newRec0
            }
            idx += exthSize
        }
        return rec0
    }
}
