import Roost
import Spectro

private struct TestRollback: Error {}

/// Run a test with a transaction-owned repository and always roll it back.
/// Pass the repository to `TestApp(..., repository: repo)` and to contexts.
/// Spectro currently rejects nested transactions; test operations that start
/// their own transaction against a separately owned test database instead.
public func withTestRollback(
    repository: any Repo,
    _ body: @escaping @Sendable (any Repo) async throws -> Void
) async throws {
    do {
        try await repository.transaction { transaction in
            try await body(transaction)
            throw TestRollback()
        }
    } catch {
        guard isTestRollback(error) else { throw error }
    }
}

private func isTestRollback(_ error: any Error) -> Bool {
    if error is TestRollback { return true }
    if case SpectroError.transactionFailed(let underlying) = error {
        return isTestRollback(underlying)
    }
    return false
}
