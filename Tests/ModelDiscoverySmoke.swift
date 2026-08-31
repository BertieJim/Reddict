import Foundation

@main
struct ModelDiscoverySmoke {
  static func main() throws {
    let openAI = #"{"data":[{"id":"gemini-2.5-flash"},{"id":"gemini-2.5-pro"}]}"#
      .data(using: .utf8)!
    let openAIModels = try LLMClient.modelIDs(from: openAI)
    precondition(openAIModels == ["gemini-2.5-flash", "gemini-2.5-pro"])

    let alternative =
      #"{"models":[{"name":"models/gemini-pro"},{"model":"custom-1"},"plain-model"]}"#
      .data(using: .utf8)!
    let alternativeModels = try LLMClient.modelIDs(from: alternative)
    precondition(alternativeModels == ["custom-1", "models/gemini-pro", "plain-model"])

    var configuration = LLMConfiguration.defaults(for: .gemini)
    precondition(configuration.model == "gemini-3.7-flash")
    precondition(
      configuration.modelsURL?.absoluteString
        == "https://generativelanguage.googleapis.com/v1beta/openai/models"
    )
    configuration.baseURL = "https://example.com/v1/chat/completions"
    precondition(configuration.modelsURL?.absoluteString == "https://example.com/v1/models")
    precondition(configuration.isCredentialTransportSecure)
    configuration.baseURL = "http://api.example.com/v1"
    precondition(!configuration.isCredentialTransportSecure)
    configuration.baseURL = "http://127.0.0.1:8080/v1"
    precondition(configuration.isCredentialTransportSecure)

    let fakeKey = "test-secret-key-that-must-never-appear"
    let reflectedError = #"{"error":{"message":"invalid test-secret-key-that-must-never-appear"}}"#
      .data(using: .utf8)!
    let redacted = LLMClient.redactedAPIError(from: reflectedError, apiKey: fakeKey) ?? ""
    precondition(!redacted.contains(fakeKey))
    precondition(redacted.contains("[REDACTED API KEY]"))
    print("MODEL_DISCOVERY_SMOKE_OK")
  }
}
