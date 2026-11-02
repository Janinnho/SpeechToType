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
            "gpt-6.1-terra",
            "gpt-6-luna"
        ])
        #expect(AnthropicModel.allCases.map(\.rawValue) == [
            "claude-opus-5-5",
            "claude-sonnet-5-5",
            "claude-haiku-5-5"
        ])
        #expect(!AnthropicModel.allCases.map(\.rawValue).contains { $0.contains("fable") })
        #expect(GeminiModel.allCases.map(\.rawValue) == [
            "gemini-4-argon",
            "gemini-3.8-flash",
            "gemini-3.1-pro-preview",
            "gemini-3.5-flash-lite"
        ])
        #expect(GPTModel.allCases.allSatisfy { $0.supportsReasoningEffort })
        #expect(GPTModel.allCases.allSatisfy { $0.usesMaxCompletionTokens })
        #expect(GPTModel.allCases.allSatisfy { !$0.supportsCustomTemperature })
        #expect(AnthropicModel.allCases.allSatisfy { $0.supportsEffort })
    }

    @Test func removedModelsMigrateToTheNewestOfTheSameFamily() {
        #expect(GPTModel(storedValue: "gpt-6-astra") == .gpt6Astra)
        #expect(GPTModel(storedValue: "gpt-6.1-sol") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-6.1-terra") == .gpt61Terra)
        #expect(GPTModel(storedValue: "gpt-6-luna") == .gpt6Luna)

        #expect(GPTModel(storedValue: "gpt-6-sol") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-5.6-sol") == .gpt61Sol)
        #expect(GPTModel(storedValue: "gpt-5.6-terra") == .gpt61Terra)
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

        #expect(GeminiModel(storedValue: "gemini-4-argon") == .gemini4Argon)
        #expect(GeminiModel(storedValue: "gemini-3.8-flash") == .gemini38Flash)
        #expect(GeminiModel(storedValue: "gemini-3.1-pro-preview") == .gemini31ProPreview)
        #expect(GeminiModel(storedValue: "gemini-3.5-flash-lite") == .gemini35FlashLite)
        #expect(GeminiModel(storedValue: "gemini-3.7-flash") == .gemini38Flash)
        #expect(GeminiModel(storedValue: "gemini-3.6-flash") == .gemini38Flash)
        #expect(GeminiModel(storedValue: "gemini-3.1-pro") == .gemini31ProPreview)
        #expect(GeminiModel(storedValue: "retired-model") == nil)

        #expect(GeminiModel.gemini4Argon.rewriteMaxOutputTokens == 32_768)
        #expect(GeminiModel.gemini4Argon.rewriteThinkingLevel == "LOW")
        #expect(GeminiModel.gemini4Argon.chatMaxOutputTokens == 65_536)
        #expect(GeminiModel.gemini4Argon.chatThinkingLevel == "MEDIUM")
        #expect(GeminiModel.gemini38Flash.rewriteMaxOutputTokens == 8_192)
        #expect(GeminiModel.gemini38Flash.rewriteThinkingLevel == nil)
        #expect(GeminiModel.gemini38Flash.chatMaxOutputTokens == nil)

        let terraChat = ChatModelSelection(provider: .openAI, modelID: "gpt-5.6-terra")
        #expect(terraChat.upgraded.modelID == GPTModel.gpt61Terra.rawValue)
        let flashChat = ChatModelSelection(provider: .gemini, modelID: "gemini-3.6-flash")
        #expect(flashChat.upgraded.modelID == GeminiModel.gemini38Flash.rawValue)
        let argonChat = ChatModelSelection(provider: .gemini, modelID: "gemini-4-argon")
        #expect(argonChat.upgraded == argonChat)
        let fableChat = ChatModelSelection(provider: .anthropic, modelID: "claude-fable-5-1")
        #expect(fableChat.upgraded.modelID == AnthropicModel.claudeSonnet55.rawValue)
    }

}
