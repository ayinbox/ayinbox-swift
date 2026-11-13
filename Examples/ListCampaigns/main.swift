import AyInbox

// Lists every campaign. Run with: AYINBOX_API_KEY=aybox_... swift run list-campaigns
let client = try AyInbox()
let me = try await client.me.get()
print("Signed in as \(me.email ?? "?")")
for try await campaign in client.campaigns.listAll(limit: 50) {
    print("\(campaign.id)  \(campaign.status ?? "")  \(campaign.name ?? "")")
}
