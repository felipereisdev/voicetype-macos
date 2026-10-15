import Testing
import Foundation
@testable import Core

@Suite("RefineStyle")
struct RefineStyleTests {

    @Test func classifiesKnownBundleIDs() {
        #expect(RefineStyle.category(for: "com.apple.mail") == .email)
        #expect(RefineStyle.category(for: "com.tinyspeck.slackmacgap") == .chat)
        #expect(RefineStyle.category(for: "com.openai.chat") == .ai)
        #expect(RefineStyle.category(for: "com.apple.Notes") == .document)
        #expect(RefineStyle.category(for: "com.example.unknown") == .other)
    }

    @Test func overrideBeatsCategoryBeatsGlobal() {
        let categories = ["chat": "concise"]
        let overrides = ["com.tinyspeck.slackmacgap": "formal"]
        // override > category
        #expect(RefineStyle.resolve(bundleID: "com.tinyspeck.slackmacgap", global: "natural",
                                    categoryStyles: categories, appOverrides: overrides) == "formal")
        // category > global
        #expect(RefineStyle.resolve(bundleID: "com.apple.MobileSMS", global: "natural",
                                    categoryStyles: categories, appOverrides: overrides) == "concise")
        // no category style → global
        #expect(RefineStyle.resolve(bundleID: "com.apple.mail", global: "natural",
                                    categoryStyles: categories, appOverrides: overrides) == "natural")
    }

    @Test func unknownAppUsesGlobal() {
        #expect(RefineStyle.resolve(bundleID: "com.example.unknown", global: "concise",
                                    categoryStyles: RefineStyle.defaultCategoryStyles,
                                    appOverrides: [:]) == "concise")
    }

    @Test func overrideAppliesToUnknownAppsToo() {
        #expect(RefineStyle.resolve(bundleID: "com.example.unknown", global: "natural",
                                    categoryStyles: [:],
                                    appOverrides: ["COM.EXAMPLE.UNKNOWN": "formal"]) == "formal")
    }

    @Test func emptyValuesFallThrough() {
        #expect(RefineStyle.resolve(bundleID: "com.apple.mail", global: "concise",
                                    categoryStyles: ["email": ""],
                                    appOverrides: ["com.apple.mail": ""]) == "concise")
    }
}
