//
//  BI_Bill_SplitTests.swift
//  BI Bill SplitTests
//
//  Created by Ricardo Fong on 8/13/25.
//

import Testing
import Foundation
@testable import BI_Bill_Split

/// Covers `Bill.preTaxShare` / `Bill.totalForPerson` — the single source of
/// truth for splitting a bill across people, including the birthday and
/// exclude redistribution rules and the pre-tax-tip setting.
struct BI_Bill_SplitTests {

    private let tolerance = 0.0001

    /// Every person's `totalForPerson(...).total` should add up to `grandTotal`,
    /// no matter how birthday/exclude flags or consumer assignments are set —
    /// this is the invariant that caught the "unassigned item" and
    /// "pre-tax-tip not persisted" bugs.
    private func assertTotalsReconcile(_ bill: Bill, sourceLocation: SourceLocation = #_sourceLocation) {
        let summed = bill.people.reduce(0.0) { $0 + bill.totalForPerson($1.id).total }
        #expect(abs(summed - bill.grandTotal) < tolerance, sourceLocation: sourceLocation)
    }

    @Test func noBirthdayEqualSplit() {
        let a = Person(name: "A")
        let b = Person(name: "B")
        let item = Item(name: "Pizza", price: 20, consumers: [a.id, b.id])
        let bill = Bill(people: [a, b], items: [item], taxPercent: 10, tipPercent: 20)

        #expect(abs(bill.preTaxShare(for: a.id) - 10) < tolerance)
        #expect(abs(bill.preTaxShare(for: b.id) - 10) < tolerance)
        assertTotalsReconcile(bill)
    }

    @Test func birthdayOnlyItemIsRedistributedToAbsorbers() {
        let birthday = Person(name: "Birthday", isBirthday: true)
        let b = Person(name: "B")
        let c = Person(name: "C")
        // Only the birthday person consumed this item — cost should fall to B and C.
        let item = Item(name: "Cake", price: 30, consumers: [birthday.id])
        let bill = Bill(people: [birthday, b, c], items: [item], taxPercent: 0, tipPercent: 0)

        #expect(bill.preTaxShare(for: birthday.id) == 0)
        #expect(abs(bill.preTaxShare(for: b.id) - 15) < tolerance)
        #expect(abs(bill.preTaxShare(for: c.id) - 15) < tolerance)
        assertTotalsReconcile(bill)
    }

    @Test func birthdayAndExcludedCombo() {
        let birthday = Person(name: "Birthday", isBirthday: true)
        let excluded = Person(name: "Excluded", isExcluded: true)
        let absorber = Person(name: "Absorber")
        // All three "consumed" a $30 item: birthday pays nothing, excluded pays
        // only their own 1/3 fair share, absorber covers the rest.
        let item = Item(name: "Shared Entree", price: 30, consumers: [birthday.id, excluded.id, absorber.id])
        let bill = Bill(people: [birthday, excluded, absorber], items: [item], taxPercent: 0, tipPercent: 0)

        #expect(bill.preTaxShare(for: birthday.id) == 0)
        #expect(abs(bill.preTaxShare(for: excluded.id) - 10) < tolerance)
        #expect(abs(bill.preTaxShare(for: absorber.id) - 20) < tolerance)
        assertTotalsReconcile(bill)
    }

    @Test func itemWithNoConsumersIsRedistributedNotDropped() {
        let a = Person(name: "A")
        let b = Person(name: "B")
        // Nobody was assigned to this item — it must still be paid for.
        let unassigned = Item(name: "Forgotten Side", price: 10, consumers: [])
        let bill = Bill(people: [a, b], items: [unassigned], taxPercent: 0, tipPercent: 0)

        #expect(abs(bill.preTaxShare(for: a.id) - 5) < tolerance)
        #expect(abs(bill.preTaxShare(for: b.id) - 5) < tolerance)
        #expect(abs(bill.subtotal - 10) < tolerance)
        assertTotalsReconcile(bill)
    }

    @Test func unassignedItemFallsBackWhenEveryoneNonBirthdayIsExcluded() {
        let birthday = Person(name: "Birthday", isBirthday: true)
        let excluded = Person(name: "Excluded", isExcluded: true)
        let unassigned = Item(name: "Mystery Fee", price: 12, consumers: [])
        let bill = Bill(people: [birthday, excluded], items: [unassigned], taxPercent: 0, tipPercent: 0)

        // No bill-level absorbers exist (birthday + excluded only), so the
        // fallback chain lands on "all non-birthday people" — just `excluded`.
        #expect(bill.preTaxShare(for: birthday.id) == 0)
        #expect(abs(bill.preTaxShare(for: excluded.id) - 12) < tolerance)
        assertTotalsReconcile(bill)
    }

    @Test func preTaxTipPersistsOnTheBillAndAffectsTipAmount() {
        let a = Person(name: "A")
        let item = Item(name: "Meal", price: 100, consumers: [a.id])

        var preTaxBill = Bill(people: [a], items: [item], taxPercent: 10, tipPercent: 20, isPreTaxCalc: true)
        #expect(abs(preTaxBill.tipAmount - 20) < tolerance) // 20% of 100

        preTaxBill.isPreTaxCalc = false
        #expect(abs(preTaxBill.tipAmount - 22) < tolerance) // 20% of (100 + 10 tax)

        assertTotalsReconcile(preTaxBill)
    }

    @Test func reconciliationHoldsAcrossManyFlagCombinations() {
        let birthday = Person(name: "Birthday", isBirthday: true)
        let excluded = Person(name: "Excluded", isExcluded: true)
        let a = Person(name: "A")
        let b = Person(name: "B")
        let items = [
            Item(name: "Shared", price: 42.37, consumers: [birthday.id, excluded.id, a.id, b.id]),
            Item(name: "Birthday Only", price: 18.0, consumers: [birthday.id]),
            Item(name: "Unassigned", price: 9.5, consumers: []),
            Item(name: "Just A", price: 15.25, consumers: [a.id]),
        ]
        for isPreTax in [true, false] {
            let bill = Bill(people: [birthday, excluded, a, b], items: items,
                             taxPercent: 8.875, tipPercent: 18.5, isPreTaxCalc: isPreTax)
            assertTotalsReconcile(bill)
        }
    }
}
