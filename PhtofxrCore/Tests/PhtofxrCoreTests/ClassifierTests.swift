import Foundation
import Testing
@testable import PhtofxrCore

@Suite("Classifier")
struct ClassifierTests {
    let now = moment(2026, 11, 12)
    var classifier: Classifier { Classifier(timeZone: amsterdam, now: now) }

    /// The user's case: about a thousand old photos imported on 11 October 2016, each now dated at import.
    func pile(count: Int = 60, day: Int = 11, addedDelay: TimeInterval = 0) -> [AssetSnapshot] {
        (0..<count).map { i in
            let created = moment(2016, 10, day, 14, 0, 0).addingTimeInterval(TimeInterval(i * 7))
            let month = 1 + i % 12
            let name = String(format: "IMG_2013%02d%02d_101500.jpg", month, 1 + i % 28)
            return snapshot(name, created: created, added: created.addingTimeInterval(addedDelay), id: "pile-\(day)-\(i)")
        }
    }

    func category(of id: String, in results: [Classification]) -> DateCategory? {
        results.first { $0.id == id }?.category
    }

    @Test("A bulk import that got one date is a confident proposal")
    func pileIsCertain() throws {
        let results = classifier.classify(pile())
        #expect(results.allSatisfy { $0.category == .certain })
        let first = try #require(results.first)
        #expect(first.reasons.contains(.nearAddedDate))
        #expect(first.reasons.contains(.pileDay(count: 60)))
        #expect(first.proposedDate == moment(2013, 1, 1, 10, 15, 0))
    }

    @Test("A pile day counts even when the added date is days later")
    func pileWithoutNearAddedDate() {
        let results = classifier.classify(pile(addedDelay: 3 * 24 * 3600))
        #expect(results.allSatisfy { $0.category == .certain })
        #expect(results.allSatisfy { $0.reasons == [.pileDay(count: 60)] })
    }

    @Test("A photo with its own date that clashes with the name is uncertain")
    func conflictIsUncertain() throws {
        let photo = snapshot("IMG_20170101_101010.jpg", created: moment(2018, 6, 1), added: moment(2019, 1, 1))
        let result = try #require(classifier.classify([photo]).first)
        #expect(result.category == .uncertain)
        #expect(result.reasons == [.conflictsWithOwnDate])
        #expect(result.proposedDate == moment(2017, 1, 1, 10, 10, 10))
    }

    @Test("Differences of a day up to a week are uncertain")
    func smallDifference() throws {
        let photo = snapshot("IMG_20161008_120000.jpg", created: moment(2016, 10, 11), added: moment(2016, 10, 11))
        let result = try #require(classifier.classify([photo]).first)
        #expect(result.category == .uncertain)
        #expect(result.reasons == [.smallDifference])
    }

    @Test("Threshold edges")
    func thresholdEdges() throws {
        let created = moment(2016, 10, 11, 12, 0, 0)
        // Exactly 24 hours: no longer "already correct".
        let dayOff = snapshot("IMG_20161010_120000.jpg", created: created, added: created, id: "day")
        // Exactly 7 days: still uncertain.
        let weekOff = snapshot("IMG_20161004_120000.jpg", created: created, added: created, id: "week")
        // 7 days and a second: a proposal (the creation date is at import).
        let beyond = snapshot("IMG_20161004_115959.jpg", created: created, added: created, id: "beyond")
        // Just under 24 hours: already correct.
        let under = snapshot("IMG_20161010_120001.jpg", created: created, added: created, id: "under")
        let results = classifier.classify([dayOff, weekOff, beyond, under])
        #expect(category(of: "day", in: results) == .uncertain)
        #expect(category(of: "week", in: results) == .uncertain)
        #expect(category(of: "beyond", in: results) == .certain)
        #expect(category(of: "under", in: results) == .alreadyCorrect)
    }

    @Test("A photo already matching its name is left alone, also when the hour differs")
    func alreadyCorrect() throws {
        let photo = snapshot("IMG_20170223_123456.jpg", created: moment(2017, 2, 23, 18, 0, 0), added: moment(2020, 1, 1))
        let result = try #require(classifier.classify([photo]).first)
        #expect(result.category == .alreadyCorrect)
        #expect(result.proposedDate == nil)
    }

    @Test("Names without a date")
    func noDate() throws {
        let plain = snapshot("IMG_1234.JPG", created: moment(2016, 10, 11), added: moment(2016, 10, 11))
        let noName = snapshot(nil, created: moment(2016, 10, 11), id: "nameless")
        let results = classifier.classify([plain, noName])
        #expect(results.allSatisfy { $0.category == .noDateInName && $0.proposedDate == nil })
    }

    @Test("A camera reset date without a name date is suspicious")
    func resetWithoutName() throws {
        let photo = snapshot("DSC_0001.JPG", created: moment(2000, 1, 1, 0, 12, 0), added: moment(2016, 10, 11))
        let result = try #require(classifier.classify([photo]).first)
        #expect(result.category == .suspicious)
        #expect(result.reasons == [.noDateInName, .cameraResetDate])
    }

    @Test("A camera reset date with a name date is a confident proposal")
    func resetWithName() throws {
        let photo = snapshot("IMG_20120505_101010.jpg", created: moment(1990, 1, 1, 0, 0, 0), added: moment(2016, 10, 11))
        let result = try #require(classifier.classify([photo]).first)
        #expect(result.category == .certain)
        #expect(result.reasons == [.cameraResetDate])
    }

    @Test("Reset date detection")
    func resetDates() {
        let c = classifier
        #expect(c.isCameraResetDate(moment(2000, 1, 1, 0, 0, 0)))
        #expect(c.isCameraResetDate(moment(2004, 1, 1, 5, 59, 0)))
        #expect(c.isCameraResetDate(moment(1994, 6, 15)))
        #expect(!c.isCameraResetDate(moment(2004, 1, 1, 6, 0, 0)))
        #expect(!c.isCameraResetDate(moment(2015, 1, 1, 0, 30, 0)))
        #expect(!c.isCameraResetDate(moment(2004, 1, 2, 0, 0, 0)))
    }

    @Test("Impossible or implausible name dates are suspicious")
    func suspiciousNames() {
        let created = moment(2016, 10, 11)
        let results = classifier.classify([
            snapshot("IMG_20170230_120000.jpg", created: created, id: "invalid"),
            snapshot("IMG_19800101_000000.jpg", created: created, id: "old"),
            snapshot("IMG_20300101_120000.jpg", created: created, id: "future"),
        ])
        #expect(results.allSatisfy { $0.category == .suspicious && $0.proposedDate == nil })
        #expect(results.first { $0.id == "invalid" }?.reasons == [.invalidDateInName])
        #expect(results.first { $0.id == "old" }?.reasons == [.nameBeforeMinimumYear])
        #expect(results.first { $0.id == "future" }?.reasons == [.nameInFuture])
    }

    @Test("Unreliable formats never become a confident proposal")
    func unreliableFormat() throws {
        let photo = snapshot("20130223_123456000_iOS.jpg", created: moment(2016, 10, 11), added: moment(2016, 10, 11))
        let result = try #require(classifier.classify([photo]).first)
        #expect(result.category == .uncertain)
        #expect(result.reasons == [.unreliableFormat])
    }

    @Test("WhatsApp names keep the current time of day")
    func whatsappKeepsTime() throws {
        let created = moment(2016, 10, 11, 14, 23, 17)
        let photo = snapshot("IMG-20150605-WA0003.jpg", created: created, added: created)
        let result = try #require(classifier.classify([photo]).first)
        #expect(result.category == .certain)
        #expect(result.proposedDate == moment(2015, 6, 5, 14, 23, 17))
    }

    @Test("Earlier decisions and the journal win")
    func decisions() {
        let photos = pile(count: 3)
        let results = classifier.classify(photos, skipped: ["pile-11-0"], changedByApp: ["pile-11-1"])
        #expect(category(of: "pile-11-0", in: results) == .skipped)
        #expect(category(of: "pile-11-1", in: results) == .changedByApp)
        #expect(category(of: "pile-11-2", in: results) == .certain)
    }

    @Test("A photo without a creation date gets an uncertain proposal")
    func missingCreationDate() throws {
        let result = try #require(classifier.classify([snapshot("IMG_20170223_123456.jpg", created: nil)]).first)
        #expect(result.category == .uncertain)
        #expect(result.reasons == [.missingCreationDate])
        #expect(result.proposedDate != nil)
    }

    @Test("A busy day where names agree is not a pile")
    func busyDayIsNotAPile() throws {
        let party = (0..<60).map { i in
            let created = moment(2019, 7, 1, 20, 0, 0).addingTimeInterval(TimeInterval(i * 60))
            let name = String(format: "IMG_20190701_20%02d00.jpg", i)
            return snapshot(name, created: created, added: moment(2019, 7, 10), id: "party-\(i)")
        }
        let stray = snapshot("IMG_20120101_101010.jpg", created: moment(2019, 7, 1, 21, 0, 0), added: moment(2019, 7, 10), id: "stray")
        let results = classifier.classify(party + [stray])
        #expect(results.filter { $0.id.hasPrefix("party") }.allSatisfy { $0.category == .alreadyCorrect })
        #expect(category(of: "stray", in: results) == .uncertain)
        #expect(results.first { $0.id == "stray" }?.reasons == [.conflictsWithOwnDate])
    }

    @Test("Turning a format off moves its photos to 'no date in name'")
    func formatOverride() throws {
        var settings = RecoverySettings()
        settings.formatOverrides["whatsapp"] = false
        let off = Classifier(settings: settings, timeZone: amsterdam, now: now)
        let photo = snapshot("IMG-20150605-WA0003.jpg", created: moment(2016, 10, 11), added: moment(2016, 10, 11))
        #expect(off.classify([photo]).first?.category == .noDateInName)
    }

    @Test("Counts per category")
    func counts() {
        let results = classifier.classify(pile(count: 5) + [snapshot("IMG_1234.JPG", created: moment(2016, 10, 11))])
        let counts = CategoryCounts(results)
        #expect(counts[.certain] == 5)
        #expect(counts[.noDateInName] == 1)
        #expect(counts[.suspicious] == 0)
        #expect(counts.reviewable == 5)
    }
}
