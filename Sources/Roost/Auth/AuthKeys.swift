/// String-based assign keys for authentication state.
///
/// Uses string keys (not typed `AssignKey`) so values can be cleared on logout.
public enum AuthAssign {
    /// The currently authenticated user (type-erased).
    public static let currentUser = "_roost_current_user"

    /// The authenticated user's ID string.
    public static let currentUserID = "_roost_current_user_id"

    /// Auth context: `"session"` or `"api"`.
    public static let authContext = "_roost_auth_context"
}
