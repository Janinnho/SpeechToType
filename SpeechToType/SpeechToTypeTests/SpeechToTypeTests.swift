//
//  SpeechToTypeTests.swift
//  SpeechToTypeTests
//
//  Created on 18.01.26.
//

import Testing
@testable import SpeechToType

struct SpeechToTypeTests {

    @Test func pickersOfferOnlyTheNewestModelOfEachFamily() {
        #expect(GPTModel.allCases.map(\.rawValue) == [
            "gpt-6-astra",
            "gpt-6.1-sol",
            "gpt-6-luna"
        ])
        #expect(AnthropicModel.allCases.map(\.rawValue) == [
            "claude-opus-5-5",
            "claude-sonnet-5-5",
            "claude-haiku-5-5"
        ])
        #expect(GPTModel.allCases.allSatisfy { $0.supportsReasoningEffort })
        #expect(GPTModel.allCases.allSatisfy { $0.usesMaxCompletionTokens })
        #expect(GPTModel.allCases.allSatisfy { !$0.supportsCustomTemperature })
        #expect(AnthropicModel.allCases.allSatisfy { $0.supportsEffort })
    }

    @Test func removedModelsMigrateToTheNewestOfTheSameFamily() {
        #expect(GPTModel(storedValue: "gpt-6-astra") == .gpt6Astra)
        #expect(GPTModel(storedValue: "gpt-6.1-sol") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-6-luna") == .gpt6Luna)

        #expect(GPTModel(storedValue: "gpt-6-sol") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-5.6-sol") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-5.6-terra") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-5.6-luna") == .gpt6Luna)
        #expect(GPTModel(storedValue: "gpt-5.5") == .gpt6Astra)
        #expect(GPTModel(storedValue: "gpt-5.4") == .gpt6Astra)
        #expect(GPTModel(storedValue: "gpt-5.2") == .gpt6Astra)
        #expect(GPTModel(storedValue: "gpt-5") == .gpt6Astra)
        #expect(GPTModel(storedValue: "o3") == .gpt6Astra)
        #expect(GPTModel(storedValue: "gpt-5.4-mini") == .gpt6Luna)
        #expect(GPTModel(storedValue: "gpt-5-mini") == .gpt6Luna)
        #expect(GPTModel(storedValue: "gpt-5-nano") == .gpt6Luna)
        #expect(GPTModel(storedValue: "gpt-4.1") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-4.1-mini") == .gpt6Luna)
        #expect(GPTModel(storedValue: "gpt-4o") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-4o-mini") == .gpt6Luna)
        #expect(GPTModel(storedValue: "retired-model") == nil)

        #expect(AnthropicModel(storedValue: "claude-opus-5-5") == .claudeOpus55)
        #expect(AnthropicModel(storedValue: "claude-sonnet-5-5") == .claudeSonnet55)
        #expect(AnthropicModel(storedValue: "claude-haiku-5-5") == .claudeHaiku55)

        #expect(AnthropicModel(storedValue: "claude-fable-5-1") == .claudeSonnet55)
        #expect(AnthropicModel(storedValue: "claude-fable-5") == .claudeSonnet55)
        #expect(AnthropicModel(storedValue: "claude-opus-5") == .claudeOpus55)
        #expect(AnthropicModel(storedValue: "claude-opus-4-8") == .claudeOpus55)
        #expect(AnthropicModel(storedValue: "claude-opus-4-7") == .claudeOpus55)
        #expect(AnthropicModel(storedValue: "claude-opus-4-6") == .claudeOpus55)
        #expect(AnthropicModel(storedValue: "claude-opus-4-5") == .claudeOpus55)
        #expect(AnthropicModel(storedValue: "claude-opus-4-5-20251101") == .claudeOpus55)
        #expect(AnthropicModel(storedValue: "claude-sonnet-5") == .claudeSonnet55)
        #expect(AnthropicModel(storedValue: "claude-sonnet-4-6") == .claudeSonnet55)
        #expect(AnthropicModel(storedValue: "claude-haiku-4-5") == .claudeHaiku55)
        #expect(AnthropicModel(storedValue: "claude-haiku-4-5-20251001") == .claudeHaiku55)
        #expect(AnthropicModel(storedValue: "retired-model") == nil)
    }

}
