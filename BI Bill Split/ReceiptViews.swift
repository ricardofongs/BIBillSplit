import SwiftUI
import UIKit

// MARK: - PDF Receipt View
struct ReceiptView: View {
    @EnvironmentObject var vm: BillViewModel
    @AppStorage("pdfLogoData") private var pdfLogoData: Data = Data()
    @AppStorage("pdfAccentColorHex") private var pdfAccentColorHex: String = ""

    private var ink: Color { Color(hex: pdfAccentColorHex) ?? Color(red: 0.10, green: 0.16, blue: 0.26) }   // navy, or Pro custom accent
    private var band: Color { ink.opacity(0.82) }   // section headers — a lighter tint of `ink`
    private let stripe = Color(red: 0.97, green: 0.97, blue: 0.985) // alternating rows
    private var curr: String { Locale.current.currency?.identifier ?? "USD" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Page header ──────────────────────────────────────────────
            HStack(alignment: .top) {
                if let logo = UIImage(data: pdfLogoData) {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.trailing, 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("BI SPLITTER")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(vm.bill.restaurantName.isEmpty ? "Bill Receipt" : vm.bill.restaurantName.uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    if let addr = vm.bill.restaurantAddress, !addr.isEmpty {
                        Text(addr)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(vm.bill.date, style: .date)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(vm.bill.people.count) guest\(vm.bill.people.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(vm.bill.items.count) item\(vm.bill.items.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(ink)

            // ── Participants ─────────────────────────────────────────────
            pdfSectionHeader("PARTY")

            let names: [String] = vm.bill.people.map {
                if $0.isBirthday { return "🎂 \($0.name)" }
                if $0.isExcluded { return "⊖ \($0.name)" }
                if $0.notPayingAssignedToID != nil { return "↪ \($0.name)" }
                return $0.name
            }
            let cols = 3
            let rows = max(1, Int(ceil(Double(names.count) / Double(cols))))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { col in
                            let idx = row * cols + col
                            Group {
                                if idx < names.count {
                                    HStack(spacing: 5) {
                                        Circle().fill(band).frame(width: 5, height: 5)
                                        Text(names[idx]).font(.system(size: 11)).foregroundStyle(.black)
                                    }
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                let bdayNames = vm.bill.people.filter { $0.isBirthday }.map { $0.name }
                if !bdayNames.isEmpty {
                    Text("🎂 \(bdayNames.joined(separator: ", ")) — share covered by the group")
                        .font(.system(size: 10)).foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.46))
                }
                let exclNames = vm.bill.people.filter { $0.isExcluded && !$0.isBirthday }.map { $0.name }
                if !exclNames.isEmpty {
                    Text("⊖ \(exclNames.joined(separator: ", ")) — only pay own items")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
                let notPayingLines = vm.bill.people.compactMap { person -> String? in
                    guard let payerID = person.notPayingAssignedToID,
                          let payerName = vm.bill.people.first(where: { $0.id == payerID })?.name
                    else { return nil }
                    return "\(person.name) → paid by \(payerName)"
                }
                if !notPayingLines.isEmpty {
                    Text("↪ \(notPayingLines.joined(separator: "; "))")
                        .font(.system(size: 10)).foregroundStyle(.purple)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            // ── Items ────────────────────────────────────────────────────
            pdfSectionHeader("ITEMS")

            // Column header
            HStack {
                Text("ITEM").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("SHARED BY").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: 160, alignment: .leading)
                Text("PRICE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 5)
            .background(band)

            ForEach(Array(vm.bill.items.enumerated()), id: \.element.id) { idx, item in
                HStack(alignment: .top) {
                    Text(item.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(
                        item.consumers.isEmpty ? "—" :
                        vm.bill.people.filter { item.consumers.contains($0.id) }.map {
                            $0.isBirthday ? "🎂 \($0.name)" :
                            $0.isExcluded  ? "⊖ \($0.name)" :
                            $0.notPayingAssignedToID != nil ? "↪ \($0.name)" : $0.name
                        }.joined(separator: ", ")
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray)
                    .frame(width: 160, alignment: .leading)
                    Text(item.price, format: .currency(code: curr))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 7)
                .background(idx.isMultiple(of: 2) ? Color.white : stripe)
            }

            // ── Totals ───────────────────────────────────────────────────
            pdfSectionHeader("TOTALS")

            VStack(spacing: 0) {
                pdfTotalRow(label: "Subtotal",
                            detail: nil,
                            value: vm.subtotal,
                            bold: false, highlight: false)
                pdfTotalRow(label: "Tax",
                            detail: String(format: "%.1f%%", vm.bill.taxPercent),
                            value: vm.taxAmount,
                            bold: false, highlight: false)
                pdfTotalRow(label: "Tip",
                            detail: String(format: "%.0f%%", vm.bill.tipPercent),
                            value: vm.tipAmount,
                            bold: false, highlight: false)
                HStack {
                    Text("GRAND TOTAL")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(vm.grandTotal, format: .currency(code: curr))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(ink)
            }

            Spacer(minLength: 8)

            // ── Footer ───────────────────────────────────────────────────
            HStack {
                Text("Generated by BI Splitter")
                Spacer()
                Text("© \(Calendar.current.component(.year, from: Date())) Ricardo Fong · All rights reserved.")
            }
            .font(.system(size: 8))
            .foregroundStyle(Color(white: 0.6))
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 6)
        }
        .background(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pdfSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 5)
            .background(band)
    }

    @ViewBuilder
    private func pdfTotalRow(label: String, detail: String?, value: Double, bold: Bool, highlight: Bool) -> some View {
        HStack {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 11, weight: bold ? .semibold : .regular))
                if let d = detail {
                    Text(d).font(.system(size: 10)).foregroundStyle(Color.gray)
                }
            }
            Spacer()
            Text(value, format: .currency(code: curr))
                .font(.system(size: 11, weight: bold ? .semibold : .regular))
        }
        .foregroundStyle(highlight ? Color.white : Color.black)
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(highlight ? ink : Color.white)
    }
}

// MARK: - PDF Receipt View Page 2
struct ReceiptView2: View {
    @EnvironmentObject var vm: BillViewModel
    @AppStorage("pdfLogoData") private var pdfLogoData: Data = Data()
    @AppStorage("pdfAccentColorHex") private var pdfAccentColorHex: String = ""

    private var ink: Color { Color(hex: pdfAccentColorHex) ?? Color(red: 0.10, green: 0.16, blue: 0.26) }
    private var band: Color { ink.opacity(0.82) }
    private let stripe = Color(red: 0.97, green: 0.97, blue: 0.985)
    private var curr: String { Locale.current.currency?.identifier ?? "USD" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Mini header ──────────────────────────────────────────────
            HStack {
                if let logo = UIImage(data: pdfLogoData) {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.trailing, 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("BI SPLITTER")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(vm.bill.restaurantName.isEmpty ? "Bill Receipt" : vm.bill.restaurantName.uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("INDIVIDUAL BREAKDOWN")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(ink)

            // Column headers
            HStack {
                Text("NAME").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("BREAKDOWN").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("TOTAL").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 5)
            .background(band)

            // ── Per-person rows ──────────────────────────────────────────
            ForEach(Array(vm.bill.people.enumerated()), id: \.element.id) { idx, person in
                let share = vm.totalForPerson(person.id)
                let payerName = person.notPayingAssignedToID.flatMap { payerID in
                    vm.bill.people.first(where: { $0.id == payerID })?.name
                }
                HStack(alignment: .center) {
                    // Name + avatar
                    HStack(spacing: 8) {
                        if person.isBirthday {
                            Text("🎂").font(.system(size: 16))
                        } else if person.isExcluded {
                            ZStack {
                                Circle()
                                    .stroke(Color.orange, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                Text("⊖").font(.system(size: 10)).foregroundStyle(.orange)
                            }
                        } else if payerName != nil {
                            ZStack {
                                Circle()
                                    .stroke(Color.purple, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                Text("↪").font(.system(size: 10)).foregroundStyle(.purple)
                            }
                        } else {
                            ZStack {
                                Circle().fill(band).frame(width: 22, height: 22)
                                Text(String(person.name.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    person.isBirthday ? Color(red: 0.78, green: 0.18, blue: 0.46) :
                                    person.isExcluded  ? .orange :
                                    payerName != nil   ? .purple : .black
                                )
                            if person.isExcluded {
                                Text("own items only")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                            } else if let payerName {
                                Text("paid by \(payerName)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Breakdown pills
                    if person.isBirthday {
                        Text("Covered by group 🎉")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.46))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let payerName {
                        Text("Paid by \(payerName)")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 0) {
                            breakdownCell("Items", value: share.preTax)
                            Text("·").font(.system(size: 9)).foregroundStyle(.gray).padding(.horizontal, 3)
                            breakdownCell("Tax", value: share.tax)
                            Text("·").font(.system(size: 9)).foregroundStyle(.gray).padding(.horizontal, 3)
                            breakdownCell("Tip", value: share.tip)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Total
                    if person.isBirthday {
                        Text("$0.00")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.46))
                            .frame(width: 70, alignment: .trailing)
                    } else if payerName != nil {
                        Text("$0.00")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.purple)
                            .frame(width: 70, alignment: .trailing)
                    } else {
                        Text(share.total, format: .currency(code: curr))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 11)
                .background(idx.isMultiple(of: 2) ? Color.white : stripe)

                Rectangle()
                    .fill(Color(white: 0.88))
                    .frame(height: 0.5)
            }

            // ── Payment info ─────────────────────────────────────────────
            let hasZelle = !(vm.bill.zelleEmail ?? "").isEmpty || !(vm.bill.zellePhone ?? "").isEmpty
            let hasVenmo = !(vm.bill.venmoUsername ?? "").isEmpty
            let hasCashApp = !(vm.bill.cashAppTag ?? "").isEmpty
            if hasZelle || hasVenmo || hasCashApp {
                HStack(spacing: 0) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 13))
                    Text("  SEND PAYMENT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .background(band)

                VStack(alignment: .leading, spacing: 6) {
                    if let email = vm.bill.zelleEmail, !email.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope").font(.system(size: 10)).foregroundStyle(.gray)
                            Text("Zelle: \(email)").font(.system(size: 11))
                        }
                    }
                    if let phone = vm.bill.zellePhone, !phone.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "phone").font(.system(size: 10)).foregroundStyle(.gray)
                            Text("Zelle: \(phone)").font(.system(size: 11))
                        }
                    }
                    if let venmo = vm.bill.venmoUsername, !venmo.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "at").font(.system(size: 10)).foregroundStyle(.gray)
                            Text("Venmo: \(venmo)").font(.system(size: 11))
                        }
                    }
                    if let cashtag = vm.bill.cashAppTag, !cashtag.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "dollarsign").font(.system(size: 10)).foregroundStyle(.gray)
                            Text("Cash App: \(cashtag)").font(.system(size: 11))
                        }
                    }
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }

            // ── Attached receipt photo ───────────────────────────────────
            if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                HStack(spacing: 0) {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(.white).font(.system(size: 11))
                    Text("  ATTACHED RECEIPT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .background(band)

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }

            Spacer(minLength: 8)

            // ── Footer ───────────────────────────────────────────────────
            HStack {
                Text("Generated by BI Splitter")
                Spacer()
                Text("© \(Calendar.current.component(.year, from: Date())) Ricardo Fong · All rights reserved.")
            }
            .font(.system(size: 8))
            .foregroundStyle(Color(white: 0.6))
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 6)
        }
        .background(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func breakdownCell(_ label: String, value: Double) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.gray)
            Text(value, format: .currency(code: curr)).font(.system(size: 9, weight: .medium)).foregroundStyle(.black)
        }
    }
}

