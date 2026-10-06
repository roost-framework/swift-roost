import Roost

@Schema("bookmarks")
struct Bookmark {
    @ID var id: UUID
    @ForeignKey var userId: UUID
    @Column var title: String
    @Column var url: String
    @Column var note: String
    @Column var read: Bool
    @Timestamp var createdAt: Date
    @Timestamp var updatedAt: Date
}
