import Foundation

/// A snapshot of the modem's current radio state, parsed from the ZTE
/// `goform_get_cmd_process` multi-data response. All fields are optional
/// because different firmwares expose different keys.
struct RouterStatus {
    var networkType: String?      // e.g. "LTE", "ENDC" (5G NSA), "NR5G"
    var networkProvider: String?
    var rssi: String?
    var lteRSRP: String?
    var lteRSRQ: String?
    var lteSINR: String?
    var lteBand: String?
    var lteCA: String?            // carrier aggregation summary
    var nr5gRSRP: String?
    var nr5gSINR: String?
    var nr5gBand: String?
    var cellID: String?
    var pci: String?

    /// Raw key/value pairs, so the UI can show anything not modelled above.
    var raw: [String: String] = [:]

    /// The status keys we ask the router for (comma-joined into `cmd=`).
    static let queryKeys = [
        "network_type", "network_provider", "rssi",
        "lte_rsrp", "lte_rsrq", "lte_snr", "lte_ca_pcell_band",
        "wan_lte_ca", "lte_pci", "cell_id",
        "Z5g_rsrp", "Z5g_SINR", "nr5g_pci", "nr5g_action_band",
        "lte_multi_ca_scell_info", "wan_active_band",
    ]

    init(raw: [String: String]) {
        self.raw = raw
        networkType = raw["network_type"]
        networkProvider = raw["network_provider"]
        rssi = raw["rssi"]
        lteRSRP = raw["lte_rsrp"]
        lteRSRQ = raw["lte_rsrq"]
        lteSINR = raw["lte_snr"]
        lteBand = raw["lte_ca_pcell_band"] ?? raw["wan_active_band"]
        lteCA = raw["wan_lte_ca"]
        nr5gRSRP = raw["Z5g_rsrp"]
        nr5gSINR = raw["Z5g_SINR"]
        nr5gBand = raw["nr5g_action_band"]
        cellID = raw["cell_id"]
        pci = raw["lte_pci"] ?? raw["nr5g_pci"]
    }

    /// A 0–4 quality bar from LTE RSRP (dBm), for a quick visual.
    var signalBars: Int {
        guard let s = lteRSRP ?? nr5gRSRP, let v = Double(s) else { return 0 }
        switch v {         // RSRP: >-80 excellent … <-110 poor
        case -80...:   return 4
        case -90..<(-80): return 3
        case -100..<(-90): return 2
        case -110..<(-100): return 1
        default:       return 0
        }
    }
}
