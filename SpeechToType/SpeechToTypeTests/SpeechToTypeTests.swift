//
//  SpeechToTypeTests.swift
//  SpeechToTypeTests
//
//  Created on 18.01.26.
//

import Testing
@testable import SpeechToType

struct SpeechToTypeTests {

    @Test func storedModelIDsStayOnModelsThatAreStillOffered() {
        #expect(GPTModel(storedValue: "gpt-6.1-sol") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-6-sol") == .gpt6Sol)
        #expect(GPTModel(storedValue: "gpt-5.6-sol") == .gpt56Sol)
        #expect(GPTModel(storedValue: "gpt-5.6-terra") == .gpt56Terra)
        #expect(GPTModel(storedValue: "gpt-4o") == .gpt4o)
        #expect(GPTModel(storedValue: "retired-model") == nil)

        #expect(AnthropicModel(storedValue: "claude-sonnet-5-5") == .claudeSonnet55)
        #expect(AnthropicModel(storedValue: "claude-haiku-5-5") == .claudeHaiku55)
        #expect(AnthropicModel(storedValue: "claude-opus-5") == .claudeOpus5)
        #expect(AnthropicModel(storedValue: "claude-opus-4-5-20251101") == .claudeOpus45)
        #expect(AnthropicModel(storedValue: "claude-sonnet-5") == .claudeSonnet5)
        #expect(AnthropicModel(storedValue: "claude-haiku-4-5") == .claudeHaiku45)
    }

    @Test func modelRequestCapabilitiesMatchTheAPI() {
        #expect(GPTModel.gpt61Sol.supportsReasoningEffort)
        #expect(GPTModel.gpt5.supportsReasoningEffort)
        #expect(GPTModel.o3.supportsReasoningEffort)
        #expect(!GPTModel.gpt41.supportsReasoningEffort)
        #expect(!GPTModel.gpt4o.supportsReasoningEffort)
        #expect(!GPTModel.gpt4oMini.supportsReasoningEffort)
        #expect(GPTModel.gpt41.supportsCustomTemperature)
        #expect(!GPTModel.gpt4o.usesMaxCompletionTokens)
        #expect(GPTModel.gpt41.usesMaxCompletionTokens)
        #expect(GPTModel.gpt6Astra.usesMaxCompletionTokens)

        #expect(AnthropicModel.claudeHaiku55.supportsEffort)
        #expect(AnthropicModel.claudeSonnet55.supportsEffort)
        #expect(AnthropicModel.claudeOpus45.supportsEffort)
        #expect(!AnthropicModel.claudeHaiku45.supportsEffort)

        let gptNames = Set(GPTModel.allCases.map(\.displayName))
        let claudeNames = Set(AnthropicModel.allCases.map(\.displayName))
        #expect(gptNames.count == GPTModel.allCases.count)
        #expect(claudeNames.count == AnthropicModel.allCases.count)
        #expect(gptNames.contains("GPT-6.1 Sol"))
        #expect(claudeNames.contains("Claude Sonnet 5.5"))
        #expect(claudeNames.contains("Claude Haiku 5.5"))
    }

}
