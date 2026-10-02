import UIKit
import MultipeerConnectivity

// MARK: - Bill Sync Session (Multipeer Connectivity)
/// Thin networking helper — not an ObservableObject. All callbacks arrive on the main thread.
/// MultipeerConnectivity's delegate callbacks aren't guaranteed to land on any
/// particular thread, so every callback below hops to the main queue before
/// touching `mcSession`/stored closures or calling out — `@unchecked Sendable`
/// reflects that existing, manual synchronization rather than bypassing it.
final class BillSyncSession: NSObject, @unchecked Sendable {
    private let serviceType = "bi-billsplit"
    private let myPeerID: MCPeerID
    private var mcSession: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    var onBillReceived: ((Bill) -> Void)?
    var onPeersChanged: (([String]) -> Void)?
    var onInvitation: ((String, @escaping (Bool) -> Void) -> Void)?

    override init() {
        // `BillSyncSession` is only ever constructed from `BillViewModel`
        // (a `@MainActor` type), so this synchronous init always runs on the
        // main actor at runtime even though it isn't statically isolated —
        // `UIDevice.current` is main-actor-isolated in the current SDK.
        myPeerID = MCPeerID(displayName: MainActor.assumeIsolated { UIDevice.current.name })
        mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        super.init()
        mcSession.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        mcSession.disconnect()
        DispatchQueue.main.async { self.onPeersChanged?([]) }
    }

    func send(bill: Bill) {
        guard !mcSession.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(bill) else { return }
        try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
    }
}

extension BillSyncSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let names = session.connectedPeers.map { $0.displayName }
        DispatchQueue.main.async { self.onPeersChanged?(names) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let bill = try? JSONDecoder().decode(Bill.self, from: data) else { return }
        DispatchQueue.main.async { self.onBillReceived?(bill) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension BillSyncSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let name = peerID.displayName
        // MultipeerConnectivity's own handler type isn't marked `@Sendable`;
        // it's only ever invoked once, from the main-queue hop below, so this
        // is a safe, targeted opt-out rather than a blanket Sendable bypass.
        nonisolated(unsafe) let handler = invitationHandler
        // The inner closure is stored (in `pendingSyncInvitations`) until the
        // user responds, so it deliberately captures `self` weakly to avoid
        // extending BillSyncSession's lifetime — make the outer dispatch
        // closure weak too so the two capture lists are consistent.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onInvitation?(name) { [weak self] accepted in
                handler(accepted, accepted ? self?.mcSession : nil)
            }
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Sync advertiser error: \(error.localizedDescription)")
    }
}

extension BillSyncSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard !mcSession.connectedPeers.contains(peerID) else { return }
        // Both devices browse and advertise simultaneously, so without a
        // tie-break each side invites the other the moment it's found —
        // producing a duplicate, confusing invitation on both ends. Only the
        // peer whose name sorts first initiates; the other just waits to be
        // invited. (If both names happen to collide, fall back to inviting —
        // the previous, less surprising behavior — rather than neither side
        // ever connecting.)
        if myPeerID.displayName != peerID.displayName, myPeerID.displayName > peerID.displayName {
            return
        }
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Sync browser error: \(error.localizedDescription)")
    }
}

