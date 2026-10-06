import Roost

@Schema("users")
struct User: Authenticatable {
    @ID var id: UUID
    @Column var email: String
    @Column var hashedPassword: String
    @Timestamp var createdAt: Date

    var authID: String { id.uuidString }
}