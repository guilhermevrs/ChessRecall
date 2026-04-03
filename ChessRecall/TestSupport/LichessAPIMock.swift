/// Compiled only in DEBUG builds.
/// Activated when the app is launched with MOCK_LICHESS=1 (used by UI tests).
#if DEBUG
import Foundation

enum LichessAPIMock {

    /// Call from AppDelegate/App init when MOCK_LICHESS env var is set.
    /// Registers a URLProtocol that serves inline fixture responses for lichess.org.
    static func register() {
        MockLichessProtocol.reset()
        MockLichessProtocol.responses = fixtureDataset
        // The protocol is injected into URLSession via config.protocolClasses in
        // LichessAPIService.init() — no need to call URLProtocol.registerClass here.
    }

    // MARK: - Inline fixtures (copied from ChessRecallTests/Fixtures/)

    private static var fixtureIndex = 0

    private static let fixtureDataset: [Data] = [
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        // Cycle: repeat for the full 30-puzzle fetch
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU, puzzleYtw4u,
        puzzleMgP8r, puzzleHxxIU,
    ].compactMap { $0.data(using: .utf8) }

    // swiftlint:disable line_length
    private static let puzzleMgP8r = #"{"game":{"id":"5fGQB9Yn","perf":{"key":"rapid","name":"Rapid"},"rated":true,"players":[{"name":"kukaradze1963","id":"kukaradze1963","color":"white","rating":1904},{"name":"TheRealMartian","flair":"symbols.fight-cloud","id":"therealmartian","color":"black","rating":1962}],"pgn":"e4 c6 Nf3 d5 exd5 cxd5 d4 Bg4 h3 Bxf3 Qxf3 e6 Nc3 Nc6 Bb5 Ne7 O-O Nf5 Ne2 Qb6 Bxc6+ bxc6 c3 Bd6 b4 O-O Qg4 a5 bxa5 Rxa5 Bd2 Rfa8 c4 Rxa2 Rxa2 Rxa2 c5 Bxc5 dxc5 Qxc5 Qf4 h6 Bb4 Qb6 Ng3 Nxg3 Qxg3 Qxb4 Qd3 Qd2 Qb3 c5 Qb5 c4 Qe8+ Kh7 Qxf7 Qe2 Qc7 d4 Qc5 Qc2 Qxd4 Qe2 Rc1 Rd2 Qxc4","clock":"10+5"},"puzzle":{"id":"MgP8r","rating":1507,"plays":5175,"solution":["e2f2","g1h2","f2g2"],"themes":["endgame","mateIn3","queensideAttack","short"],"fen":"8\/6pk\/4p2p\/8\/2Q5\/7P\/3rqPP1\/2R3K1 b - - 2 1","lastMove":"d4c4","initialPly":66}}"#

    private static let puzzleHxxIU = #"{"game":{"id":"Zv71QJ0S","perf":{"key":"rapid","name":"Rapid"},"rated":true,"players":[{"name":"Kutlubaev_AM","id":"kutlubaev_am","color":"white","rating":2265},{"name":"dmarcolino","id":"dmarcolino","color":"black","rating":2274}],"pgn":"c4 c6 d4 d5 cxd5 cxd5 Nc3 Nf6 Nf3 Nc6 Bg5 a6 e3 Bg4 Be2 e6 Qa4 Bxf3 Bxf3 Be7 O-O O-O a3 b5 Qc2 Rc8 Rac1 Na5 Be2 Nd7 Bxe7 Qxe7 Bd3 g6 Nxd5","clock":"10+5"},"puzzle":{"id":"HxxIU","rating":1649,"plays":1996,"solution":["e6d5","c2c8","f8c8"],"themes":["middlegame","advantage","hangingPiece","short"],"fen":"2r2rk1\/3nqp1p\/p3p1p1\/np1N4\/3P4\/P2BP3\/1PQ2PPP\/2R2RK1 b - - 0 1","lastMove":"c3d5","initialPly":34}}"#

    private static let puzzleYtw4u = #"{"game":{"id":"gBpLeEEl","perf":{"key":"rapid","name":"Rapid"},"rated":true,"players":[{"name":"lofic","id":"lofic","color":"white","rating":1785},{"name":"DjokerNovak24","id":"djokernov","color":"black","rating":1826}],"pgn":"e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e6 f3 b5 Qd2 Bb7 g4 Nfd7 O-O-O Nb6 Qf2 N8d7 h4 Rc8 g5 d5 exd5 Nxd5 Nxd5 Bxd5 Be2 Nc4 Bxc4 Rxc4 h5 Qc7 Kb1 Bxd4 Bxd4 Bc6 Rc1 Rd4 Rxc6 Qxc6 Qe3 Qd5 Qe1 Rxd4 Rxd4 Qxd4 Qa5 Ke7 Qc7+ Kf6 h6 gxh6 gxh6 Rg8 Bf3","clock":"10+0"},"puzzle":{"id":"Ytw4u","rating":1532,"plays":4821,"solution":["e1e8","f6e8","f3b7"],"themes":["endgame","mateIn2","middlegame","short"],"fen":"k3r3\/pp1r1ppp\/5n2\/8\/Pq1P1Q2\/5b1P\/5PP1\/4R1K1 w - - 2 1","lastMove":"e4f3","initialPly":49}}"#
    // swiftlint:enable line_length
}

// MARK: - URLProtocol for the app process

final class MockLichessProtocol: URLProtocol {
    static var responses: [Data] = []
    private static var index = 0

    static func reset() { responses = []; index = 0 }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.contains("lichess.org") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let idx = MockLichessProtocol.index % max(MockLichessProtocol.responses.count, 1)
        MockLichessProtocol.index += 1

        guard !MockLichessProtocol.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        let data = MockLichessProtocol.responses[idx]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
