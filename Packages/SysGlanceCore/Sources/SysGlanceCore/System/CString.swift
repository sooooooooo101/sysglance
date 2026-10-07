extension String {
    /// NUL 終端の C 文字列バッファから生成する（`String(cString:)` は非推奨のため）。
    init(nulTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }
}
