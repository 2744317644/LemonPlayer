import XCTest
@testable import LemonMedia

final class SeriesFolderResolverTests: XCTestCase {
    private func folder(_ id: String, _ parent: String, _ name: String) -> LibraryFolderNode {
        LibraryFolderNode(id: id, parentID: parent, name: name)
    }

    private func makeFolders(_ nodes: [LibraryFolderNode]) -> [String: LibraryFolderNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    /// 结构：番剧A / Fonts（字体目录） + 番剧A / 01.mkv
    func testFontsFolderGoesUpToSeriesFolder() {
        let folders = makeFolders([
            folder("root", "", ""),
            folder("series", "root", "葬送的芙莉莲"),
            folder("fonts", "series", "Fonts")
        ])

        let resolved = SeriesFolderResolver.resolveSeriesFolder(forFileParent: "fonts", folders: folders)
        XCTAssertEqual(resolved?.id, "series")
        XCTAssertEqual(resolved?.name, "葬送的芙莉莲")
    }

    func testSeasonFolderGoesUpToSeriesFolder() {
        let folders = makeFolders([
            folder("series", "", "Sousou no Frieren"),
            folder("s1", "series", "Season 1")
        ])
        XCTAssertEqual(SeriesFolderResolver.resolveSeriesFolder(forFileParent: "s1", folders: folders)?.id, "series")
    }

    func testQualityFolderGoesUp() {
        let folders = makeFolders([
            folder("series", "", "BanG Dream! It's MyGO!!!!!"),
            folder("q", "series", "1080p HEVC 简繁")
        ])
        XCTAssertEqual(SeriesFolderResolver.resolveSeriesFolder(forFileParent: "q", folders: folders)?.id, "series")
    }

    func testNormalFolderIsSeriesFolder() {
        let folders = makeFolders([
            folder("series", "", "[Nekomoe] 孤独摇滚!")
        ])
        XCTAssertEqual(SeriesFolderResolver.resolveSeriesFolder(forFileParent: "series", folders: folders)?.name, "[Nekomoe] 孤独摇滚!")
    }

    func testNoiseWords() {
        XCTAssertTrue(SeriesFolderResolver.isNoiseFolder("Fonts"))
        XCTAssertTrue(SeriesFolderResolver.isNoiseFolder("OP"))
        XCTAssertTrue(SeriesFolderResolver.isNoiseFolder("OP&ED"))
        XCTAssertTrue(SeriesFolderResolver.isNoiseFolder("Scans"))
        XCTAssertTrue(SeriesFolderResolver.isNoiseFolder("字幕"))
        XCTAssertTrue(SeriesFolderResolver.isNoiseFolder("特典"))
        XCTAssertFalse(SeriesFolderResolver.isNoiseFolder("孤独摇滚!"))
        XCTAssertFalse(SeriesFolderResolver.isNoiseFolder("BanG Dream! It's MyGO!!!!!"))
        XCTAssertFalse(SeriesFolderResolver.isNoiseFolder("Opera"))
    }

    func testCleanTitle() {
        XCTAssertEqual(
            SeriesFolderResolver.cleanTitle("[Nekomoe kissaten&VCB-Studio] BanG Dream! It’s MyGO!!!!! [Ma10p_1080p]"),
            "BanG Dream! It’s MyGO!!!!!"
        )
        XCTAssertEqual(
            SeriesFolderResolver.cleanTitle("[DBD-Raws][葬送的芙莉莲][01-28][1080P][BDRip]"),
            "葬送的芙莉莲"
        )
        XCTAssertEqual(SeriesFolderResolver.cleanTitle("Sousou no Frieren S01"), "Sousou no Frieren S01")
    }
}
