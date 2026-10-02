import SwiftUI

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @Environment(\.appearanceMode) private var appearanceMode
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @AppStorage("defaultTaxPercent") private var defaultTaxPercent: Double = 8.0
    @AppStorage("defaultTipPercent") private var defaultTipPercent: Double = 18.0
    @AppStorage("defaultZelleEmail") private var defaultZelleEmail: String = ""
    @AppStorage("defaultZellePhone") private var defaultZellePhone: String = ""
    @AppStorage("defaultVenmoUsername") private var defaultVenmoUsername: String = ""
    @AppStorage("defaultCashAppTag") private var defaultCashAppTag: String = ""
    @AppStorage("pdfLogoData") private var pdfLogoData: Data = Data()
    @AppStorage("pdfAccentColorHex") private var pdfAccentColorHex: String = ""
    @State private var showPaywall = false
    @State private var showLogoPicker = false

    private static let defaultPDFAccentColor = Color(red: 0.10, green: 0.16, blue: 0.26)

    private var pdfAccentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: pdfAccentColorHex) ?? Self.defaultPDFAccentColor },
            set: { pdfAccentColorHex = $0.toHexString() }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AppearanceMode.allCases) { mode in
                        appearanceModeRow(mode)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("\"System\" follows your iPhone's appearance setting in Settings → Display & Brightness.")
                }

                Section {
                    Stepper(value: $defaultTaxPercent, in: 0...25, step: 0.5) {
                        HStack {
                            Text("Default Tax")
                            Spacer()
                            Text("\(defaultTaxPercent, specifier: "%.1f")%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $defaultTipPercent, in: 0...40, step: 1) {
                        HStack {
                            Text("Default Tip")
                            Spacer()
                            Text("\(defaultTipPercent, specifier: "%.0f")%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Bill Defaults")
                } footer: {
                    Text("Applied automatically to every new bill. You can still adjust tax and tip per bill.")
                }

                Section {
                    ProStatusRow()
                } header: {
                    Text("Pro")
                }

                Section {
                    if purchaseManager.isUnlocked {
                        TextField("Default Zelle Email", text: $defaultZelleEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        TextField("Default Zelle Phone", text: $defaultZellePhone)
                            .keyboardType(.phonePad)
                        TextField("Default Venmo @username", text: $defaultVenmoUsername)
                            .textInputAutocapitalization(.never)
                        TextField("Default Cash App $cashtag", text: $defaultCashAppTag)
                            .textInputAutocapitalization(.never)
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Unlock to set default payment info", systemImage: "lock.fill")
                        }
                    }
                } header: {
                    Text("Payment Defaults")
                } footer: {
                    Text("Applied automatically to every new bill's payment fields. Requires Pro.")
                }

                Section {
                    if purchaseManager.isUnlocked {
                        HStack {
                            if let uiImage = UIImage(data: pdfLogoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(width: 44, height: 44)
                                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PDF Logo").font(.subheadline)
                                Text(pdfLogoData.isEmpty ? "No logo set" : "Shown on exported PDFs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Choose") { showLogoPicker = true }
                            if !pdfLogoData.isEmpty {
                                Button("Remove", role: .destructive) { pdfLogoData = Data() }
                            }
                        }
                        ColorPicker("Header Accent Color", selection: pdfAccentColorBinding, supportsOpacity: false)
                        if Color(hex: pdfAccentColorHex) != nil {
                            Button("Reset to Default Color") { pdfAccentColorHex = "" }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Unlock to customize PDF branding", systemImage: "lock.fill")
                        }
                    }
                } header: {
                    Text("PDF Branding")
                } footer: {
                    Text("Add your own logo and header color to every exported PDF receipt. Requires Pro.")
                }

                Section("Support") {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("How to Use This App", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showLogoPicker) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    if let image { setLogo(image) }
                }
            }
        }
    }

    /// Downscales the picked image to a small square before storing it, since
    /// a logo only ever renders at ~44pt in Settings or ~36pt in the PDF header.
    private func setLogo(_ image: UIImage) {
        let maxDimension: CGFloat = 240
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        pdfLogoData = resized.pngData() ?? Data()
    }

    private func appearanceModeRow(_ mode: AppearanceMode) -> some View {
        let isSelected = appearanceMode.wrappedValue == mode
        let iconForeground: Color = isSelected ? .white : .accentColor
        let iconBackground: Color = isSelected ? .accentColor : Color(.secondarySystemGroupedBackground)

        return Button {
            appearanceMode.wrappedValue = mode
        } label: {
            HStack(spacing: 14) {
                modeIcon(systemName: mode.icon, foreground: iconForeground, background: iconBackground)
                Text(mode.label)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func modeIcon(systemName: String, foreground: Color, background: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
            )
    }
}

// MARK: - Help View
struct HelpView: View {
    var body: some View {
        List {
            // MARK: Getting Started
            Section {
                DisclosureGroup {
                    helpText("""
                    1. Go to the **Bill** tab.
                    2. Enter the restaurant name (required), or tap 🔍 to search Maps — the name and address auto-fill from the result.
                    3. Add people using the manual field, Contacts, or a saved Group.
                    4. Optionally tap **Birthday** on someone's row to cover their share, or **Exclude** to opt someone out of the birthday contribution.
                    5. Add items and assign them — all people appear as a wrapping grid of toggle buttons, no scrolling needed.
                    6. Tap **Browse Menu** (Items section header) to fetch the restaurant's menu via AI and add items directly.
                    7. Adjust tip and tax as needed (or set defaults in the **Settings** tab).
                    8. Tap **Save** — the bill appears in the History tab.
                    """)
                } label: {
                    helpRow(icon: "list.bullet.clipboard", color: .blue, title: "Getting Started")
                }
            } header: {
                Text("Overview")
            }

            // MARK: Pro
            Section("Pro") {
                DisclosureGroup {
                    helpText("""
                    A one-time purchase unlocks these features everywhere in the app:
                    • **Not Paying ↪** — flag someone as not paying and pick exactly who covers their share, instead of splitting it evenly (People section below).
                    • **Payment Defaults** — save your Zelle email/phone, Venmo @username, and Cash App $cashtag once in Settings; every new bill is pre-filled automatically (Payments section below).
                    • **PDF Branding** — add your own logo and a custom header color to every exported PDF receipt (Sharing & Export section below).
                    • Tap **Unlock Pro** in Settings, or tap any locked feature, to purchase. Already bought it on another device? Use **Restore Purchases** on the paywall.
                    """)
                } label: {
                    helpRow(icon: "sparkles", color: .purple, title: "Pro Features")
                }
            }

            // MARK: Restaurant
            Section("Restaurant") {
                DisclosureGroup {
                    helpText("""
                    • **Name** — required before you can save, share, or export.
                    • **Address** — optional. Tap the 🔍 magnifying glass to search for the restaurant using Maps. Selecting a result **auto-fills both the name and address** from the map, so they always match. Once saved, the icon switches to a 🗺 map button — tap it to open the location in Apple Maps.
                    • **Date** — defaults to today; tap to change it.
                    """)
                } label: {
                    helpRow(icon: "fork.knife", color: .orange, title: "Restaurant Info")
                }
            }

            // MARK: People
            Section("People") {
                DisclosureGroup {
                    helpText("""
                    Add people to the bill using any of these methods:
                    • **Type manually** — enter a name (and optional phone number) then tap +.
                    • **Contacts** (blue button) — pick one or more people from your address book.
                    • **Add Group** (indigo button) — import everyone from a saved Contact Group in one tap. Anyone already in the bill by name is skipped automatically.
                    • **Save as Group** (teal button, visible when at least one person is added) — saves the current list of people as a new reusable Contact Group for future bills.
                    • Swipe left on a person to remove them from the bill.
                    """)
                } label: {
                    helpRow(icon: "person.2", color: .indigo, title: "Adding People")
                }

                DisclosureGroup {
                    helpText("""
                    Go to the **Groups** tab to create and manage reusable lists of people.
                    • Tap **+** to create a new group — give it a name and add members from your Contacts.
                    • Tap a group to edit its name or members.
                    • Swipe left to delete a group.
                    • Groups saved from a bill (via "Save as Group") also appear here.
                    """)
                } label: {
                    helpRow(icon: "folder.badge.person.crop", color: .purple, title: "Contact Groups")
                }

                DisclosureGroup {
                    helpText("""
                    Mark someone as the birthday person to make their share $0 — covered by everyone else.
                    • Tap the **Birthday** capsule button on any person's row to flag them. Tap **Remove Birthday** to unmark.
                    • Multiple people can be marked at the same time.
                    • The 🎂 icon and pink highlight appear on their row; payment buttons are hidden since they owe nothing.
                    • **How the split works:** items the birthday person ordered are redistributed to the non-birthday, non-excluded consumers of those items. If an item was ordered exclusively by birthday people, its cost is split among all non-birthday, non-excluded people.
                    • Birthday indicators appear in the Share Bill preview, on both pages of the exported PDF, in the Saved Bills list, and in the Analytics tab.
                    """)
                } label: {
                    helpRow(icon: "birthday.cake", color: .pink, title: "Birthday Person 🎂")
                }

                DisclosureGroup {
                    helpText("""
                    Use **Exclude** to let someone opt out of covering the birthday person's share.
                    • Tap the **Exclude** capsule on any person's row to mark them with ⊖. Tap **Remove Exclude** to undo.
                    • Excluded people pay only the items they personally consumed — their fair share is never redistributed to others.
                    • The birthday person's costs are absorbed only by people who are neither birthday nor excluded.
                    • You can combine Birthday and Exclude freely on the same bill — for example, a plus-one who only had one dish and doesn't want to chip in for the birthday.
                    • The ⊖ badge and "own items only" note appear on their row and on both pages of the exported PDF.
                    """)
                } label: {
                    helpRow(icon: "person.crop.circle.badge.minus", color: .orange, title: "Exclude from Birthday Share ⊖")
                }

                DisclosureGroup {
                    helpText("""
                    **Pro feature.** Flag someone as not paying and choose exactly who covers their entire share — rather than splitting it evenly among everyone else.
                    • Tap the **Not Paying** capsule on a person's row. If you haven't unlocked Pro yet, this opens the paywall.
                    • Once unlocked, tap it and pick the one person who will absorb their full share (items, tax, and tip).
                    • That person shows $0.00 and a purple "Paid by \\(name)" note; the payer's own total increases to cover it.
                    • Mutually exclusive with Birthday and Exclude — setting one clears the others.
                    • You can't designate someone who is themselves flagged Not Paying, to avoid chaining shares.
                    • Removing a person from the bill automatically clears any Not Paying assignment that pointed to them.
                    • The ↪ indicator appears on the person's row, in the exported PDF (both pages), and in the Share Bill preview.
                    """)
                } label: {
                    helpRow(icon: "arrowshape.turn.up.right.circle", color: .purple, title: "Not Paying ↪ (Pro)")
                }
            }

            // MARK: Items
            Section("Items") {
                DisclosureGroup {
                    helpText("""
                    • Tap **+ Add Item** to add a dish or drink with a name and price.
                    • Tap the pencil icon on any item to edit its name or price.
                    • Assign consumers by tapping names in the **wrapping grid** shown below each item — all people are visible at once, no horizontal scrolling. A checkmark means they're assigned to that item.
                    • The cost is split equally among all assigned consumers.
                    • Swipe left on an item to delete it.
                    • An item with no assigned consumers is split among all non-birthday, non-excluded people in the bill.
                    """)
                } label: {
                    helpRow(icon: "cart", color: .green, title: "Adding & Assigning Items")
                }

                DisclosureGroup {
                    helpText("""
                    Once a restaurant name is set, tap **Browse Menu** in the Items section header to fetch that restaurant's menu using AI.
                    • Each item shows its **name**, **price**, **description**, and **dietary tags** (🌱 Vegetarian, 🌿 Vegan, GF Gluten-Free, 🌶 Spicy).
                    • Use the **category chips** at the top to filter by Appetizers, Mains, Desserts, Drinks, etc.
                    • ⭐ **Popular** badges highlight the restaurant's best-known dishes.
                    • Use the **search bar** to filter by name or description.
                    • Tap items to select them (checkmark appears), then tap **Add Selected** to add them all to the bill at once.
                    • If the restaurant address is set, it is used alongside the name to fetch the correct location's menu.
                    • Results are **cached for the session** — opening Browse Menu again for the same restaurant is instant. Changing the restaurant name or starting a new bill fetches fresh results.
                    • Requires an internet connection. Prices are AI-generated estimates — always verify against the actual menu.
                    """)
                } label: {
                    helpRow(icon: "fork.knife.circle", color: .cyan, title: "Browse Menu (AI)")
                }
            }

            // MARK: Tip & Tax
            Section("Tip & Tax") {
                DisclosureGroup {
                    helpText("""
                    • Adjust the **Tip %** and **Tax %** sliders in the bill form.
                    • Toggle **Pre-tax tip** to calculate tip on the subtotal (before tax), or off to calculate tip on the post-tax total — varies by country convention.
                    • Each person's share updates instantly as you move the sliders.
                    • To avoid adjusting these on every bill, go to **Settings → Bill Defaults** and set your preferred default tax and tip — new bills open with those values pre-filled.
                    """)
                } label: {
                    helpRow(icon: "percent", color: .teal, title: "Tip & Tax")
                }
            }

            // MARK: Payments
            Section("Payments") {
                DisclosureGroup {
                    helpText("""
                    Collect payment from each person directly in the app:
                    • **Request** — tap the Request button on a person's row to ask for their share via Venmo's charge request, with a pre-filled text message fallback if Venmo isn't installed.
                    • Birthday and Not Paying people show $0.00 and no Request button since they owe nothing.
                    """)
                } label: {
                    helpRow(icon: "creditcard", color: .mint, title: "Collecting Payment")
                }

                DisclosureGroup {
                    helpText("""
                    Tell people how to pay you back by entering your own info in the People section — these fields appear on the exported PDF and are free to fill in on every bill:
                    • **Zelle** — email and/or phone number.
                    • **Venmo** — your @username.
                    • **Cash App** — your $cashtag.
                    **Pro feature:** save these once in **Settings → Payment Defaults** and every new bill pre-fills them automatically, so you never retype them.
                    """)
                } label: {
                    helpRow(icon: "banknote", color: .green, title: "Zelle, Venmo & Cash App Info")
                }
            }

            // MARK: Receipt Scanning & Photos
            Section("Receipt & Photos") {
                DisclosureGroup {
                    helpText("""
                    • **Scan Receipt** — uses the camera and on-device OCR to detect item names and prices from a physical receipt automatically. Review and correct any misread items before adding them.
                    • **Attach Photo** — tap to attach an image of the receipt to the bill. A prompt lets you choose between **Take Photo** (camera) or **Choose from Gallery** (photo library). The attached image appears on page 2 of the exported PDF.
                    • Scanning works best on flat, well-lit receipts with clear printed text.
                    """)
                } label: {
                    helpRow(icon: "camera.viewfinder", color: .red, title: "Scanning & Attaching Photos")
                }
            }

            // MARK: Sharing & Export
            Section("Sharing & Export") {
                DisclosureGroup {
                    helpText("""
                    • **Export PDF** — generates a professional two-page PDF receipt:
                      – Page 1: branded header with restaurant name, address and date; participant list with 🎂, ⊖, and ↪ indicators; formatted items table (Item | Shared By | Price) with alternating rows; totals block with subtotal, tax, tip, and Grand Total.
                      – Page 2: per-person breakdown cards showing items, tax, and tip share; birthday people show "Covered by group 🎉"; excluded people show "own items only"; Not Paying people show "Paid by \\(name)"; Zelle/Venmo/Cash App info; attached receipt photo.
                    • **PDF Branding (Pro)** — set a logo and custom header color in **Settings → PDF Branding**; they appear on both PDF pages in place of the default navy header.
                    • **Share Bill** — sends a deep-link URL that another iPhone with this app can open to load the exact same bill (people, items, birthday/exclude/not-paying flags, tip, and tax).
                    • The **Share Bill preview** shows a summary card including birthday, excluded, and Not Paying indicators.
                    • **History tab** — view all saved bills. Tap a bill to load it, swipe left to share it, or swipe to delete.
                    • **Export All Bills** — in the History tab, export every saved bill as a single JSON file for backup.
                    """)
                } label: {
                    helpRow(icon: "square.and.arrow.up", color: .blue, title: "Sharing & Exporting")
                }
            }

            // MARK: Saved Bills (History)
            Section("History") {
                DisclosureGroup {
                    helpText("""
                    The **Saved Bills** tab lists all your past bills with their total amount.
                    • **Filter by person** — use the search bar to type a name. The list narrows to bills that include that person, and each row shows that person's individual share for the bill.
                    • **Birthday indicator** — bills where someone was flagged as birthday show a pink 🎂 line with their name.
                    • Tap a bill to load it into the Bill tab for review or editing.
                    • Swipe left on a row to share the bill via deep-link.
                    • Swipe right on a row to delete it (deletion respects the active filter).
                    """)
                } label: {
                    helpRow(icon: "tray.full", color: .brown, title: "Saved Bills & History")
                }
            }

            // MARK: Analytics
            Section("Analytics") {
                DisclosureGroup {
                    helpText("""
                    The **Analytics** tab shows spending summaries across all your saved bills.
                    • **Over Time** — a line chart of total bill amounts over your chosen date range (1 month, 3 months, 6 months, or all time).
                    • **Top Spenders** — a ranked list and bar chart of the top 10 people by total spend across all bills. Each entry shows:
                      – Total spent across all bills
                      – Number of bills they appeared in
                      – Average spent per bill
                    • Birthday-flagged shares ($0) are correctly excluded from totals, so they don't skew the rankings.
                    """)
                } label: {
                    helpRow(icon: "chart.bar", color: .yellow, title: "Analytics")
                }
            }

            // MARK: Settings
            Section("Settings") {
                DisclosureGroup {
                    helpText("""
                    • **Appearance** — choose Light, Dark, or System to match your iPhone's display setting in Settings → Display & Brightness.
                    • **Bill Defaults** — set a default Tax % (0–25%, 0.5% steps) and Tip % (0–40%, 1% steps) that are pre-filled on every new bill. You can still change them per bill at any time.
                    • **Pro** — see your unlock status, or tap **Unlock Pro** / **Restore Purchases**.
                    • **Payment Defaults (Pro)** — save a default Zelle email/phone, Venmo @username, and Cash App $cashtag so every new bill is pre-filled.
                    • **PDF Branding (Pro)** — upload a logo and pick a custom header color for every exported PDF receipt.
                    • **How to Use This App** — you're reading it!
                    """)
                } label: {
                    helpRow(icon: "gearshape", color: .gray, title: "App Settings")
                }
            }
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.large)
    }

    private func helpRow(icon: String, color: Color, title: String) -> some View {
        Label {
            Text(title).fontWeight(.medium)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(color))
        }
    }

    private func helpText(_ markdown: String) -> some View {
        Text(LocalizedStringKey(markdown))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

