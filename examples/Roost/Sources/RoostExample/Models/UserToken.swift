import Roost

@Schema("user_tokens")
struct UserToken: Sendable {
    @ID var id: UUID
    @ForeignKey var userId: UUID
    @Column var token: String
    @Column var context: String
    @Column var sentTo: String?
    @Timestamp var createdAt: Date
}