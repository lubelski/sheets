import SheetsCore
import Testing

@Suite struct AppUpdatesTests {
    @Test func aBuildWithTheFeedAndKeyUpdatesItself() {
        #expect(AppUpdates.hasFeed([
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "a-public-key",
        ]))
    }

    @Test func aBuildWithoutBothKeysNeverUpdatesItself() {
        #expect(!AppUpdates.hasFeed(nil))
        #expect(!AppUpdates.hasFeed([:]))
        #expect(!AppUpdates.hasFeed(["SUFeedURL": "https://example.com/appcast.xml"]))
        #expect(!AppUpdates.hasFeed(["SUPublicEDKey": "a-public-key"]))
    }

    @Test func anEmptyValueCountsAsMissing() {
        #expect(!AppUpdates.hasFeed(["SUFeedURL": "", "SUPublicEDKey": "a-public-key"]))
        #expect(!AppUpdates.hasFeed(["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": ""]))
    }

    @Test func aValueOfTheWrongTypeCountsAsMissing() {
        #expect(!AppUpdates.hasFeed(["SUFeedURL": 1, "SUPublicEDKey": "a-public-key"]))
    }
}
