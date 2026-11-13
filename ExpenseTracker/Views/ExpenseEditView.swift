import SwiftUI
import SwiftData
import PhotosUI

/// Add a new expense (expense == nil) or edit an existing one.
struct ExpenseEditView: View {
    let expense: Expense?
    /// Set when an existing expense is edited from a sheet (e.g. long-press ▸ Edit).
    var presentedAsSheet = false
    /// Pre-filled values from voice entry or a scanned receipt (new expenses only).
    var prefill: ExpensePrefill? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CategoryStore.key) private var customCategoriesData: Data = Data()   // refreshes the grid

    @State private var amount: Double?
    @State private var currency = AppSettings.defaultCurrency
    @State private var merchant = ""
    @State private var categoryRaw = ExpenseCategory.other.rawValue
    @State private var userPickedCategory = false
    @State private var date = Date.now
    @State private var isIncome = false
    @State private var note = ""
    @State private var bank = ""
    @State private var account = ""
    @State private var rawText: String?
    @State private var source: ExpenseSource = .manual
    @State private var photo: Data?
    @State private var rememberCategory = true
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var showVoice = false
    @State private var showScan = false
    @State private var showCamera = false
    @State private var showNewCategory = false
    @State private var showPhoto = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pasteError: String?
    @FocusState private var amountFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        // Embedded (voice / receipt flows) already provide a NavigationStack.
        if (expense == nil && prefill == nil) || presentedAsSheet {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                if expense == nil { quickEntryBar.appearAnimation() }
                amountHeader.appearAnimation()
                categoryCard.appearAnimation(delay: 0.05)
                detailsCard.appearAnimation(delay: 0.1)
                photoCard.appearAnimation(delay: 0.12)
                if let e = expense { sourceCard(e).appearAnimation(delay: 0.15) }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        .navigationTitle(expense == nil ? (isIncome ? "New income" : "New expense") : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if expense == nil || presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled((amount ?? 0) <= 0)
            }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let e = expense {
                    context.delete(e)
                    try? context.save()
                }
                dismiss()
            }
        }
        .alert("Couldn't read the SMS", isPresented: Binding(get: { pasteError != nil }, set: { if !$0 { pasteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pasteError ?? "")
        }
        .sheet(isPresented: $showVoice) {
            VoiceEntryView(onResult: apply).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showScan) { ReceiptScanView(onResult: apply) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let image { photo = image.jpegData(compressionQuality: 0.7) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showNewCategory) {
            NewCategoryView { created in
                userPickedCategory = true
                withAnimation(.snappy) { categoryRaw = created }
            }
        }
        .sheet(isPresented: $showPhoto) { if let photo { PhotoViewer(data: photo) } }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    photo = image.jpegData(compressionQuality: 0.7)
                }
                pickerItem = nil
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.selection, trigger: categoryRaw)
        .onAppear(perform: load)
    }

    // MARK: Sections

    /// Faster ways to fill the form: speak, scan a receipt, or paste a bank SMS.
    private var quickEntryBar: some View {
        HStack(spacing: 10) {
            quickButton("Speak", symbol: "mic.fill", color: Color(light: 0xEF4444, dark: 0xF87171)) { showVoice = true }
            quickButton("Scan receipt", symbol: "doc.viewfinder", color: Color(light: 0x3B82F6, dark: 0x60A5FA)) { showScan = true }
            quickButton("Paste SMS", symbol: "doc.on.clipboard", color: Color(light: 0x8B5CF6, dark: 0xA78BFA)) { pasteSMS() }
        }
    }

    private func quickButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                IconTile(symbol: symbol, color: color, size: 36)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
        }
        .buttonStyle(.plain)
    }

    private var amountHeader: some View {
        VStack(spacing: 14) {
            Picker("Type", selection: $isIncome.animation(.snappy)) {
                Text("Expense").tag(false)
                Text("Income").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Menu {
                    Picker("Currency", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(currency)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                TextField("0", value: $amount, format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(isIncome ? Theme.income : .primary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .card()
        .onTapGesture { amountFocused = true }
    }

    private var categoryOptions: [CategoryStyle] {
        _ = customCategoriesData   // re-evaluate when custom categories change
        var list = CategoryStyle.allExpense
        if isIncome { list.insert(CategoryStyle.of(ExpenseCategory.income.rawValue), at: 0) }
        // Keep the current value visible even if its custom category was deleted.
        if !list.contains(where: { $0.rawValue == categoryRaw }) { list.append(CategoryStyle.of(categoryRaw)) }
        return list
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Category")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(categoryOptions) { c in
                    let selected = categoryRaw == c.rawValue
                    Button {
                        userPickedCategory = true
                        withAnimation(.snappy) { categoryRaw = c.rawValue }
                    } label: {
                        VStack(spacing: 6) {
                            IconTile(symbol: c.symbol, color: c.color, size: 44, filled: selected)
                                .scaleEffect(selected ? 1.06 : 1)
                            Text(c.shortName)
                                .font(.caption2.weight(selected ? .semibold : .regular))
                                .lineLimit(1)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                Button { showNewCategory = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.emerald)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Theme.emerald.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        Text("New").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            let name = merchant.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !isIncome && name.lowercased() != "unknown" {
                Toggle(isOn: $rememberCategory) {
                    Text("Always use this category for “\(name)”").font(.footnote)
                }
                .tint(Theme.emerald)
            }
        }
        .card()
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            fieldRow(symbol: "storefront", color: Theme.emerald) {
                TextField(isIncome ? "From (optional)" : "Merchant (optional)", text: $merchant)
                    .textInputAutocapitalization(.words)
                    .onChange(of: merchant) { _, new in
                        guard !userPickedCategory, expense == nil else { return }
                        let guess = Categorizer.categoryRaw(merchant: new, text: nil, isIncome: isIncome)
                        if guess != categoryRaw { withAnimation(.snappy) { categoryRaw = guess } }
                    }
            }
            Divider().padding(.leading, 48)
            fieldRow(symbol: "building.columns.fill", color: Color(light: 0x0F766E, dark: 0x2DD4BF)) {
                TextField("Bank or account (optional)", text: $bank)
                    .textInputAutocapitalization(.words)
                TextField("Last 4", text: $account)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .onChange(of: account) { _, new in
                        let digits = String(new.filter(\.isNumber).suffix(4))
                        if digits != new { account = digits }
                    }
            }
            Divider().padding(.leading, 48)
            fieldRow(symbol: "calendar", color: Color(light: 0x3B82F6, dark: 0x60A5FA)) {
                DatePicker("Date", selection: $date).labelsHidden()
                Spacer()
            }
            Divider().padding(.leading, 48)
            fieldRow(symbol: "text.alignleft", color: Color(light: 0x8B5CF6, dark: 0xA78BFA)) {
                TextField("Add a note", text: $note, axis: .vertical)
            }
        }
        .card(padding: 6)
    }

    private func fieldRow<C: View>(symbol: String, color: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 32)
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    /// Supporting image (receipt / invoice).
    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Attachment")
            if let photo, let image = UIImage(data: photo) {
                HStack(spacing: 14) {
                    Button { showPhoto = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) { withAnimation { self.photo = nil } } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            Label("Take photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .tint(Theme.emerald)
                .font(.subheadline.weight(.medium))
            }
        }
        .card()
    }

    private func sourceCard(_ e: Expense) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Source")
            HStack(spacing: 8) {
                Pill(text: e.source.label, symbol: e.source.symbol)
                if let sender = e.sender { Pill(text: sender, symbol: "person", color: .secondary) }
            }
            if let raw = e.rawText {
                Text(raw)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                ExpenseStore.duplicate(e)
                saved.toggle()
                dismiss()
            } label: {
                Label("Duplicate as new expense today", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.emerald)
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete transaction", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.danger)
        }
        .card()
    }

    // MARK: Logic

    private var currencies: [String] {
        var list = AppSettings.commonCurrencies
        if !list.contains(currency) { list.insert(currency, at: 0) }
        return list
    }

    /// Fill the form from voice, a receipt scan or a pasted SMS.
    private func apply(_ p: ExpensePrefill) {
        withAnimation(.snappy) {
            if let a = p.amount { amount = a }
            if let c = p.currency { currency = c }
            if let m = p.merchant { merchant = m }
            if let raw = p.categoryRaw ?? p.category?.rawValue {
                categoryRaw = raw
                userPickedCategory = true
            }
            if let n = p.note, note.isEmpty { note = n }
            if let d = p.date { date = d }
            if let b = p.bank { bank = b }
            if let a = p.account { account = a }
            if let r = p.rawText { rawText = r; source = .sms }
            if let ph = p.photo { photo = ph }
        }
        amountFocused = false
    }

    private func pasteSMS() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            pasteError = "Copy a bank SMS first (long-press the message ▸ Copy), then tap Paste SMS."
            return
        }
        guard let parsed = TransactionParser.parse(text, defaultCurrency: AppSettings.defaultCurrency) else {
            pasteError = "No amount was found in the copied text."
            return
        }
        isIncome = parsed.isIncome
        var p = ExpensePrefill()
        p.amount = parsed.amount
        p.currency = parsed.currency
        p.merchant = parsed.merchant
        p.categoryRaw = Categorizer.categoryRaw(merchant: parsed.merchant, text: text, isIncome: parsed.isIncome)
        p.bank = BankDetector.detect(text: text, sender: nil)
        p.account = parsed.account
        p.rawText = text
        apply(p)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let e = expense else {
            if let p = prefill { apply(p) }
            amountFocused = prefill?.amount == nil
            return
        }
        amount = e.amount
        currency = e.currency
        merchant = e.hasMerchant ? e.merchant : ""
        categoryRaw = e.categoryRaw
        userPickedCategory = true
        date = e.date
        isIncome = e.isIncome
        note = e.note ?? ""
        bank = e.bank ?? ""
        account = e.account ?? ""
        photo = e.photo
    }

    private var bankValue: String? {
        let b = bank.trimmingCharacters(in: .whitespaces)
        return b.isEmpty ? nil : b
    }

    private func save() {
        guard let value = amount, value > 0 else { return }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        let storedName = name.isEmpty ? "Unknown" : name
        let finalRaw = isIncome && !userPickedCategory ? ExpenseCategory.income.rawValue : categoryRaw
        let shouldLearn = rememberCategory && !name.isEmpty && !isIncome && finalRaw != ExpenseCategory.other.rawValue

        if let e = expense {
            if shouldLearn && e.categoryRaw != finalRaw { Categorizer.learn(merchant: name, raw: finalRaw) }
            e.amount = value
            e.currency = currency
            e.merchant = storedName
            e.categoryRaw = finalRaw
            e.date = date
            e.isIncome = isIncome
            e.note = note.isEmpty ? nil : note
            e.bank = bankValue
            e.account = account.isEmpty ? nil : account
            e.photo = photo
            e.needsReview = false
            try? context.save()
            BudgetService.evaluate(after: e)
        } else {
            let new = Expense(amount: value, currency: currency, merchant: storedName,
                              category: ExpenseCategory(rawValue: finalRaw) ?? .other, date: date, source: source,
                              isIncome: isIncome, account: account.isEmpty ? nil : account,
                              bank: bankValue, rawText: rawText, note: note.isEmpty ? nil : note)
            new.categoryRaw = finalRaw
            new.photo = photo
            let result = ExpenseStore.save(new)
            NotificationService.confirm(result)
            if shouldLearn && userPickedCategory { Categorizer.learn(merchant: name, raw: finalRaw) }
        }
        try? context.save()
        saved.toggle()
        dismiss()
    }
}

// MARK: - New category

struct NewCategoryView: View {
    var onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = CategoryStore.symbols[0]
    @State private var colorHex = CategoryStore.colors[0]
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        IconTile(symbol: symbol, color: Color(hex: colorHex), size: 52, filled: true)
                        TextField("Category name", text: $name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                    }
                    .padding(.vertical, 4)
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                }
                Section("Colour") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CategoryStore.colors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 3 : 0))
                                .shadow(color: colorHex == hex ? Color(hex: hex).opacity(0.6) : .clear, radius: 4)
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CategoryStore.symbols, id: \.self) { s in
                            IconTile(symbol: s, color: Color(hex: colorHex), size: 38, filled: symbol == s)
                                .onTapGesture { symbol = s }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let c = CategoryStore.add(name: name, symbol: symbol, colorHex: colorHex) {
                            onCreate(c.name)
                            dismiss()
                        } else {
                            error = "That name is empty or already used."
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Photo helpers

struct PhotoViewer: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onFinish(info[.originalImage] as? UIImage)
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil)
            parent.dismiss()
        }
    }
}
