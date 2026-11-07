import Foundation

/// Recognises the bank / wallet behind a transaction from the SMS sender ID or message text.
/// Returns nil when nothing is recognised, so the field stays blank for manual entry.
enum BankDetector {

    /// (display name, phrases searched in text and sender, short codes matched against the sender only)
    private static let banks: [(name: String, phrases: [String], codes: [String])] = [
        // UAE
        ("Emirates NBD", ["emirates nbd", "emiratesnbd"], ["enbd", "emiratesnbd"]),
        ("Liv", ["liv bank", "liv."], ["liv"]),
        ("ADCB", ["adcb", "abu dhabi commercial"], ["adcb", "adcbalert"]),
        ("First Abu Dhabi Bank", ["first abu dhabi", "fab card", "fab credit", "fab debit"], ["fab", "fabbank"]),
        ("Mashreq", ["mashreq"], ["mashreq", "mashreqbnk"]),
        ("Dubai Islamic Bank", ["dubai islamic"], ["dib", "diblive"]),
        ("ADIB", ["adib", "abu dhabi islamic"], ["adib"]),
        ("Emirates Islamic", ["emirates islamic"], ["eib", "emiratesis"]),
        ("RAKBANK", ["rakbank", "rak bank"], ["rakbank"]),
        ("Commercial Bank of Dubai", ["commercial bank of dubai"], ["cbd", "cbduae"]),
        ("Wio", ["wio bank", "wio "], ["wio"]),
        ("Mashreq Neo", ["mashreq neo", "neo by mashreq"], ["neo"]),
        // India
        ("HDFC Bank", ["hdfc bank", "hdfcbank"], ["hdfcbk", "hdfc"]),
        ("ICICI Bank", ["icici"], ["icicib", "icici"]),
        ("SBI", ["state bank of india", "sbi card", "sbi credit", "sbi debit", "your sbi"], ["sbiinb", "sbipsg", "sbicrd", "sbi", "cbssbi"]),
        ("Axis Bank", ["axis bank"], ["axisbk", "axis"]),
        ("Kotak", ["kotak"], ["kotakb", "kotak"]),
        ("Yes Bank", ["yes bank"], ["yesbnk"]),
        ("IndusInd Bank", ["indusind"], ["indusb", "indus"]),
        ("IDFC First", ["idfc first", "idfc bank"], ["idfcfb", "idfc"]),
        ("Punjab National Bank", ["punjab national", "pnb "], ["pnbsms", "pnb"]),
        ("Bank of Baroda", ["bank of baroda", "bob card"], ["bobtxn", "bobsms"]),
        ("Canara Bank", ["canara"], ["canbnk"]),
        ("Federal Bank", ["federal bank"], ["fedbnk"]),
        ("AU Bank", ["au small finance", "au bank"], ["aubank"]),
        ("Paytm", ["paytm"], ["paytm", "iptmsg"]),
        // Pakistan
        ("HBL", ["habib bank", "hbl "], ["hbl"]),
        ("UBL", ["united bank", "ubl "], ["ubl"]),
        ("MCB", ["mcb bank", "mcb "], ["mcb"]),
        ("Meezan Bank", ["meezan"], ["meezan"]),
        ("Bank Alfalah", ["alfalah"], ["alfalah"]),
        ("Allied Bank", ["allied bank"], ["abl"]),
        ("Faysal Bank", ["faysal"], ["faysal"]),
        ("Askari Bank", ["askari"], ["askari"]),
        ("JazzCash", ["jazzcash"], ["jazzcash"]),
        ("Easypaisa", ["easypaisa"], ["easypaisa"]),
        ("SadaPay", ["sadapay"], ["sadapay"]),
        ("NayaPay", ["nayapay"], ["nayapay"]),
        // Saudi / Gulf
        ("Al Rajhi Bank", ["al rajhi", "alrajhi"], ["alrajhi", "rajhi"]),
        ("SNB", ["saudi national bank", "alahli"], ["snb", "alahli"]),
        ("Riyad Bank", ["riyad bank"], ["riyadbank"]),
        ("SAB", ["sabb", "saudi awwal"], ["sabb", "sab"]),
        ("Alinma", ["alinma"], ["alinma"]),
        ("STC Pay", ["stc pay"], ["stcpay"]),
        ("QNB", ["qnb"], ["qnb"]),
        // Bahrain / Kuwait
        ("KFH", ["kuwait finance house", "kfh"], ["kfh", "kfhbh", "kfhbahrain"]),
        ("Al Salam Bank", ["al salam bank", "alsalam bank", "al-salam bank"], ["alsalam", "alsalambank", "alsalambh"]),
        ("BBK", ["bank of bahrain and kuwait", "bbk"], ["bbk"]),
        ("NBB", ["national bank of bahrain", "nbb"], ["nbb"]),
        ("Ahli United Bank", ["ahli united"], ["aub", "ahliunited"]),
        ("Bahrain Islamic Bank", ["bahrain islamic", "bisb"], ["bisb"]),
        ("Khaleeji Bank", ["khaleeji"], ["khaleeji"]),
        ("ila Bank", ["ila bank"], ["ilabank", "ila"]),
        ("Boubyan Bank", ["boubyan"], ["boubyan"]),
        ("Gulf Bank", ["gulf bank"], ["gulfbank"]),
        ("Burgan Bank", ["burgan"], ["burgan"]),
        ("Warba Bank", ["warba"], ["warba"]),
        ("Commercial Bank of Kuwait", ["commercial bank of kuwait", "al-tijari"], ["cbk"]),
        ("ABK", ["al ahli bank of kuwait"], ["abk"]),
        ("KIB", ["kuwait international bank"], ["kib"]),
        ("NBK", ["national bank of kuwait"], ["nbk"]),
        // UK / US / Global
        ("HSBC", ["hsbc"], ["hsbc"]),
        ("Standard Chartered", ["standard chartered", "stanchart"], ["scb", "stanchart"]),
        ("Citibank", ["citibank", "citi card"], ["citi", "citibank"]),
        ("Barclays", ["barclays"], ["barclays"]),
        ("Lloyds", ["lloyds"], ["lloyds"]),
        ("NatWest", ["natwest"], ["natwest"]),
        ("Monzo", ["monzo"], ["monzo"]),
        ("Revolut", ["revolut"], ["revolut"]),
        ("Wise", ["wise card", "wise account"], ["wise"]),
        ("Chase", ["chase card", "chase account", "jpmorgan chase"], ["chase"]),
        ("Bank of America", ["bank of america", "bofa"], ["bofa"]),
        ("Wells Fargo", ["wells fargo"], ["wellsfargo"]),
        ("American Express", ["american express", "amex"], ["amex"]),
        ("Capital One", ["capital one"], ["capitalone"]),
    ]

    static func detect(text: String?, sender: String?) -> String? {
        let senderLower = normalizeSender(sender)
        let textLower = (text ?? "").lowercased()

        // 1. Sender ID is the most reliable signal.
        if !senderLower.isEmpty {
            for bank in banks {
                if bank.codes.contains(where: { senderLower == $0 || senderLower.hasPrefix($0) || senderLower.hasSuffix($0) }) {
                    return bank.name
                }
                if bank.phrases.contains(where: { senderLower.contains($0.replacingOccurrences(of: " ", with: "")) }) {
                    return bank.name
                }
            }
        }
        // 2. Bank name mentioned in the message.
        for bank in banks where bank.phrases.contains(where: { Categorizer.matches($0, in: textLower) }) {
            return bank.name
        }
        return nil
    }

    /// Normalises a card / pass name from Apple Wallet, e.g. "Emirates NBD Visa Infinite" → "Emirates NBD".
    static func fromWalletCard(_ card: String?) -> String? {
        guard let card, !card.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        // If it's only digits it's a card suffix, not a bank.
        if card.allSatisfy({ $0.isNumber || $0 == " " || $0 == "•" || $0 == "*" }) { return nil }
        return detect(text: card, sender: nil) ?? card.trimmingCharacters(in: .whitespaces)
    }

    /// "AD-HDFCBK" → "hdfcbk", "VM-SBIINB-S" → "sbiinb", "+97150…" → "" (phone numbers ignored)
    private static func normalizeSender(_ sender: String?) -> String {
        guard var s = sender?.lowercased().trimmingCharacters(in: .whitespaces), !s.isEmpty else { return "" }
        if s.filter(\.isLetter).isEmpty { return "" }
        let parts = s.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            // Indian DLT format: 2-letter operator prefix, header, optional suffix.
            s = parts.max(by: { $0.count < $1.count }) ?? s
        }
        return s.filter { $0.isLetter || $0.isNumber }
    }
}
