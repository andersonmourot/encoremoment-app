import SwiftUI

/// Terms of Use / EULA, presented before sign-in and account creation.
///
/// Required by App Store guideline 1.2 for apps with user-generated content:
/// it states zero tolerance for objectionable content and abusive users and
/// describes the report/block moderation tools.
struct TermsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    termSection(
                        title: "1. Acceptance",
                        body: "By creating an account or signing in to EncoreMoment, you agree to these Terms of Use. If you do not agree, do not create an account or sign in."
                    )
                    termSection(
                        title: "2. User-Generated Content",
                        body: "EncoreMoment lets users post events, photos, videos, comments, and profile information. You are responsible for the content you post. We do not endorse user content, but we moderate it."
                    )
                    termSection(
                        title: "3. Zero Tolerance for Objectionable Content and Abusive Users",
                        body: "EncoreMoment has ZERO TOLERANCE for objectionable content and abusive users. You may not post or share content that is unlawful, harmful, threatening, abusive, harassing, defamatory, hateful, discriminatory, sexually explicit, violent, misleading, or that infringes anyone's rights — including spam and any content that targets or bullies another person."
                    )
                    termSection(
                        title: "4. Moderation and Enforcement",
                        body: "Any user may flag objectionable content and block abusive users. Flagged content is reviewed by our moderation team, and blocking a user hides their content from you immediately and notifies our team. We may remove any content and suspend or terminate any account at our discretion, including for violations of these terms."
                    )
                    termSection(
                        title: "5. Your Account",
                        body: "You may delete your account at any time from Profile → Settings → Delete Account. Deletion removes your profile, events, media, comments, and associated data."
                    )
                    termSection(
                        title: "6. Changes",
                        body: "We may update these terms. Continued use of EncoreMoment after changes take effect constitutes acceptance of the updated terms."
                    )
                }
                .padding()
            }
            .navigationTitle("Terms of Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func termSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
