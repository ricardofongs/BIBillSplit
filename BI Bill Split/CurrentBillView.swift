import SwiftUI
import UIKit

// MARK: - Zoomable Image Viewer
struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(1.0, lastScale * value.magnification)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { value in
                                        // Only allow panning when zoomed in
                                        guard scale > 1.0 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .background(Color.black)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("Pinch to zoom • Double-tap to fit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Current Bill View
struct CurrentBillView: View {
    @EnvironmentObject var vm: BillViewModel
    @State private var showingScanner = false
    @State private var exportURL: URL?
    @State private var showingReceipt = false
    @State private var showingImagePicker = false
    @State private var showingAttachOptions = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera
    @State private var showingReceiptZoom = false
    @State private var isParsingReceipt = false
    @State private var parsingError: String? = nil
    @State private var isPeopleExpanded: Bool = true
    /// Owned here so the sheet sits outside the Form and avoids Group/sheet conflicts.
    @State private var itemToEdit: Item? = nil
    @State private var billShareItem: IdentifiableURL? = nil
    @State private var showingRestaurantSearch = false
    @State private var showingMenuBrowser = false

    var body: some View {
        NavigationStack {
            VStack {
                // Parsing progress banner
                if isParsingReceipt {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading receipt with AI…")
                            .font(.subheadline)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 6)
                }
                if let errorMsg = parsingError {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Live sync status banner
                if vm.isSyncActive {
                    HStack(spacing: 8) {
                        if vm.syncPeerNames.isEmpty {
                            ProgressView().scaleEffect(0.75)
                            Text("Looking for nearby devices…")
                        } else {
                            Image(systemName: "person.2.wave.2.fill")
                                .foregroundStyle(.green)
                            Text(vm.syncPeerNames.joined(separator: ", "))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("· \(vm.syncPeerNames.count) connected")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { vm.toggleSync() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 6)
                }

                Form {
                    Section("Restaurant") {
                        TextField("Enter restaurant name", text: $vm.bill.restaurantName)
                            .textInputAutocapitalization(.words)
                        HStack {
                            TextField("Address (optional)", text: Binding(
                                get: { vm.bill.restaurantAddress ?? "" },
                                set: { vm.bill.restaurantAddress = $0.isEmpty ? nil : $0 }
                            ))
                            .textInputAutocapitalization(.words)
                            if let address = vm.bill.restaurantAddress, !address.isEmpty {
                                Button {
                                    let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    if let url = URL(string: "maps://?q=\(encoded)") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Image(systemName: "map.fill")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Button {
                                    showingRestaurantSearch = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        DatePicker("Date", selection: $vm.bill.date, displayedComponents: .date)
                    }
                    Section {
                        if isPeopleExpanded {
                            PeopleEditor()
                        }
                    } header: {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPeopleExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text("People")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                if !isPeopleExpanded && !vm.bill.people.isEmpty {
                                    Text("(\(vm.bill.people.count))")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: isPeopleExpanded ? "chevron.up" : "chevron.down")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Section {
                        ItemsEditor(itemToEdit: $itemToEdit)
                    } header: {
                        HStack {
                            Text("Items")
                            Spacer()
                            Button {
                                showingMenuBrowser = true
                            } label: {
                                Label("Browse Menu", systemImage: "fork.knife.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                            }
                            .disabled(vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .buttonStyle(.plain)
                        }
                    }
                    Section("Tax & Tip") {
                        HStack {
                            Text("Tax (%)")
                            Spacer()
                            TextField("0", value: $vm.bill.taxPercent, format: .number.precision(.fractionLength(3)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Tip (%)")
                            Spacer()
                            TextField("0", value: $vm.bill.tipPercent, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    SummarySection()
                    if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                        Section("Attached Receipt") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(.rect(cornerRadius: 8))
                                .onTapGesture { showingReceiptZoom = true }
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                        .padding(6)
                                        .allowsHitTesting(false)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Bill Split")
            .toolbar {
                // Leading: preview receipt + sync toggle + overflow menu
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { showingReceipt = true }) {
                        Image(systemName: "eye")
                    }

                    Button { vm.toggleSync() } label: {
                        Image(systemName: vm.isSyncActive
                              ? "antenna.radiowaves.left.and.right.circle.fill"
                              : "antenna.radiowaves.left.and.right.circle")
                            .foregroundStyle(vm.isSyncActive ? Color.green : Color.primary)
                            .symbolEffect(.pulse, options: .repeating, isActive: vm.isSyncActive && vm.syncPeerNames.isEmpty)
                    }

                    Menu {
                        Button { vm.loadSample() } label: {
                            Label("Load Sample", systemImage: "doc.badge.plus")
                        }
                        Button { showingScanner = true } label: {
                            Label("Scan Receipt", systemImage: "document.viewfinder.fill")
                        }
                        Button { showingAttachOptions = true } label: {
                            Label("Attach Photo", systemImage: "camera")
                        }
                        Divider()
                        Button(role: .destructive) { vm.clearCurrentBill() } label: {
                            Label("Clear Bill", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                // Trailing: primary actions always visible
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { vm.saveCurrentBill() } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        if let url = vm.shareBillURL() {
                            billShareItem = IdentifiableURL(url: url)
                        }
                    } label: {
                        Label("Share Bill", systemImage: "person.2.wave.2")
                    }
                    .disabled(vm.bill.people.isEmpty || vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button { exportPDF() } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.bill.people.isEmpty || vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            // All sheet presentations anchored here on the NavigationStack, not on toolbar buttons
            .sheet(isPresented: $showingReceipt) {
                VStack(alignment: .leading, spacing: 5) {
                    ScrollView {
                        ReceiptView()
                        ReceiptView2()
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .init(horizontal: .leading, vertical: .top))
            }
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
            .fullScreenCover(isPresented: $showingReceiptZoom) {
                if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                    ZoomableImageView(image: uiImage)
                }
            }
        }
            .sheet(isPresented: $showingScanner) {
                ReceiptScannerView { lines in
                    guard !lines.isEmpty else { return }
                    isParsingReceipt = true
                    parsingError = nil
                    Task {
                        let items = await ReceiptParser.parse(lines: lines)
                        await MainActor.run {
                            isParsingReceipt = false
                            if items.isEmpty {
                                parsingError = "No items found. Try scanning again or add items manually."
                            } else {
                                for item in items {
                                    vm.addItem(name: item.name, price: item.price)
                                }
                            }
                        }
                    }
                }
            }
            .confirmationDialog("Attach Photo", isPresented: $showingAttachOptions, titleVisibility: .visible) {
                Button("Take Photo") {
                    imagePickerSource = .camera
                    showingImagePicker = true
                }
                Button("Choose from Gallery") {
                    imagePickerSource = .photoLibrary
                    showingImagePicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(sourceType: imagePickerSource) { image in
                    if let image = image {
                        vm.attachReceiptImage(image)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(activityItems: [exportURL]) }
            }
            .sheet(item: $itemToEdit) { item in
                ItemEditSheet(item: item) { updated in
                    vm.updateItem(updated)
                }
            }
            .sheet(item: $billShareItem) { item in
                BillShareSheet(bill: vm.bill, shareURL: item.url)
            }
            .sheet(isPresented: $showingRestaurantSearch) {
                RestaurantSearchSheet(restaurantName: vm.bill.restaurantName) { name, address in
                    vm.bill.restaurantName    = name
                    vm.bill.restaurantAddress = address
                }
            }
            .sheet(isPresented: $showingMenuBrowser) {
                MenuBrowserSheet(
                    restaurantName: vm.bill.restaurantName,
                    restaurantAddress: vm.bill.restaurantAddress
                ) { fetched in
                    for item in fetched {
                        vm.addItem(name: item.name, price: item.price)
                    }
                }
            }
            // Invitations are queued — responding to one re-presents this alert
            // for the next, instead of a second invitation silently overwriting
            // (and permanently hanging) the first.
            .alert("Live Sync Invitation", isPresented: Binding(
                get: { !vm.pendingSyncInvitations.isEmpty },
                set: { _ in }
            )) {
                Button("Accept") {
                    if !vm.pendingSyncInvitations.isEmpty {
                        vm.pendingSyncInvitations.removeFirst().respond(true)
                    }
                }
                Button("Decline", role: .cancel) {
                    if !vm.pendingSyncInvitations.isEmpty {
                        vm.pendingSyncInvitations.removeFirst().respond(false)
                    }
                }
            } message: {
                if let inv = vm.pendingSyncInvitations.first {
                    Text("\(inv.peerName) wants to join your live bill session.")
                }
            }
            // Previously a failed save/load/delete was only printed to the
            // console — Save could silently do nothing with no visible sign.
            .alert("Storage Error", isPresented: Binding(
                get: { vm.storageErrorMessage != nil },
                set: { if !$0 { vm.storageErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { vm.storageErrorMessage = nil }
            } message: {
                Text(vm.storageErrorMessage ?? "")
            }

    }

    // MARK: - PDF Export
    func exportPDF() {
            let pdfMetaData = [
                kCGPDFContextCreator: "Bill Splitter",
                kCGPDFContextAuthor: "Ricardo Fong"
            ]
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = pdfMetaData as [String: Any]
        
            let pageWidth = 8.5 * 72.0
            let pageHeight = 11 * 72.0
            let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

            let data = renderer.pdfData { context in
                context.beginPage()
                let bounds = CGRect(origin: .zero, size: CGSize(width: 612, height: 792))
                let hosting1 = UIHostingController(rootView: ReceiptView().environmentObject(vm))
                hosting1.view.backgroundColor = .white
                hosting1.view.bounds = bounds.insetBy(dx: 24, dy: 24)
                let fitting = hosting1.sizeThatFits(in: bounds.size)
                hosting1.view.bounds.size = CGSize(width: bounds.width - 24 * 2, height: fitting.height)
                hosting1.view.layoutIfNeeded()
                hosting1.view.drawHierarchy(in: hosting1.view.bounds, afterScreenUpdates: true)
                
                // Page 2 - Summary
                context.beginPage()
                let hosting = UIHostingController(rootView: ReceiptView2().environmentObject(vm))
                hosting.view.backgroundColor = .white
                hosting.view.bounds = bounds.insetBy(dx: 24, dy: 24)
                let fitting1 = hosting.sizeThatFits(in: bounds.size)
                hosting.view.bounds.size = CGSize(width: bounds.width - 24 * 2, height: fitting1.height)
                hosting.view.layoutIfNeeded()
                hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
                
                // Page 3 - Receipt Image if available
                if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                    context.beginPage()
                    let maxRect = CGRect(x: 20, y: 20, width: pageRect.width - 40, height: pageRect.height - 40)
                    let aspect = uiImage.size.width / uiImage.size.height
                    var drawRect = maxRect
                    if aspect > maxRect.width / maxRect.height {
                        let newHeight = maxRect.width / aspect
                        drawRect = CGRect(x: maxRect.minX, y: maxRect.minY, width: maxRect.width, height: newHeight)
                    } else {
                        let newWidth = maxRect.height * aspect
                        drawRect = CGRect(x: maxRect.minX, y: maxRect.minY, width: newWidth, height: maxRect.height)
                    }
                    uiImage.draw(in: drawRect)
                }
            }
        let outputFormat = DateFormatter()
        outputFormat.dateFormat = "MM-dd-yyyy"
        // Restaurant names can contain characters that aren't valid in a filename
        // (e.g. "Dave's BBQ / Smokehouse"), which would make the file write fail.
        let invalidFilenameCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let safeName = vm.bill.restaurantName
            .components(separatedBy: invalidFilenameCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Bill_\(safeName.isEmpty ? "Receipt" : safeName)_\(outputFormat.string(from: vm.bill.date)).pdf")
            do {
                try data.write(to: url)
                exportURL = url
            } catch {
                print("Could not save PDF file: \(error)")
            }
        }
}

