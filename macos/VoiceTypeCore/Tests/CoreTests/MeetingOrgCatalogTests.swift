import Testing
@testable import Core

@Suite("MeetingOrg catalog editing")
struct MeetingOrgCatalogTests {
    @Test func parsesCommaSeparatedAliases() {
        #expect(MeetingOrg.parseAliases("a, b ,c") == ["a", "b", "c"])
        #expect(MeetingOrg.parseAliases(" , ,") == [])
        #expect(MeetingOrg.parseAliases("") == [])
    }

    @Test func defaultsAreValid() {
        #expect(MeetingOrg.validationIssues(MeetingOrg.defaults).isEmpty)
    }

    @Test func flagsEmptyAndDuplicateOrgNames() {
        let issues = MeetingOrg.validationIssues([
            MeetingOrg(name: "Acme"), MeetingOrg(name: " acme "), MeetingOrg(name: "  "),
        ])
        #expect(issues.count == 2)
    }

    @Test func flagsDuplicateClientsOnlyWithinTheSameOrg() {
        let shared = [MeetingClient(name: "Hooli")]
        #expect(MeetingOrg.validationIssues([
            MeetingOrg(name: "A", clients: shared), MeetingOrg(name: "B", clients: shared),
        ]).isEmpty)
        #expect(MeetingOrg.validationIssues([
            MeetingOrg(name: "A", clients: [MeetingClient(name: "Hooli"), MeetingClient(name: "hooli")]),
        ]).count == 1)
        #expect(MeetingOrg.validationIssues([
            MeetingOrg(name: "A", clients: [MeetingClient(name: "")]),
        ]).count == 1)
    }
}
