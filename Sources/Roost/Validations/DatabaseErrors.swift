import Spectro
import PostgresNIO

/// Inspect PostgreSQL's structured SQLSTATE, including errors wrapped by Spectro.
/// Use alongside a database unique constraint; a preflight lookup alone can race.
public func isUniqueConstraintViolation(_ error: any Error) -> Bool {
    if let postgres = error as? PSQLError {
        return postgres.serverInfo?[.sqlState] == "23505"
    }
    guard let error = error as? SpectroError else { return false }
    switch error {
    case .queryExecutionFailed(_, let underlying), .transactionFailed(let underlying):
        return isUniqueConstraintViolation(underlying)
    case .transactionAndRollbackFailed(let original, _):
        return isUniqueConstraintViolation(original)
    default:
        return false
    }
}
