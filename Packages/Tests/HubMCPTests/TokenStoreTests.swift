import Testing

@testable import HubMCP

struct TokenStoreTests {
  @Test func tokenIsStableUntilRegenerated() {
    let store = TokenStore(storage: InMemorySecretStorage())
    #expect(store.token() == store.token())
  }

  @Test func regenerateChangesToken() {
    let store = TokenStore(storage: InMemorySecretStorage())
    let first = store.token()
    let second = store.regenerate()
    #expect(first != second)
    #expect(store.token() == second)
  }

  @Test func tokenHasAtLeast43Characters() {
    #expect(TokenStore(storage: InMemorySecretStorage()).token().count >= 43)
  }

  @Test func tokenSurvivesANewStoreOnTheSameStorage() {
    let storage = InMemorySecretStorage()
    #expect(TokenStore(storage: storage).token() == TokenStore(storage: storage).token())
  }
}
