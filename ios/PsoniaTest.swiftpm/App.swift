// Psonia price-reader test (2026-10-30, Claude solo for Panos Frantzis).
// Question it answers: can an app on the user's own iPhone read sklavenitis.gr prices (the site blocks servers)?
// It opens each product page in a built-in browser view (WKWebView, the same engine as Safari), reads the price,
// the struck old price and the offer badge, and can send them to the household in Psonia.
import SwiftUI
import WebKit

struct Product: Codable, Identifiable, Hashable {
    let sku: String, name: String, category: String, url: String
    var id: String { sku }
}

struct Reading: Codable, Equatable {
    var price: Double?
    var unit: String?
    var old: Double?
    var badge: String?
    var icon: String?
    var nb: Bool?
    var blocked: Bool?
    var none: Bool?
    var at: Date = Date()
    enum CodingKeys: String, CodingKey { case price, unit, old, badge, icon, nb, blocked, none }
    var promo: Bool { old != nil || badge != nil }
}

@main
struct PsoniaTestApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

// MARK: - Reader: one hidden browser view, one page at a time, slowly (the site must not see a robot)

@MainActor
final class PriceReader: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var readings: [String: Reading] = [:]
    @Published var running = false
    @Published var status = "Ready"
    let web: WKWebView
    private var finish: CheckedContinuation<Void, Never>?
    private var stop = false

    // Same selectors as Pantry Stock-Up's site script (product page: .product-detail)
    private let js = #"""
    (() => {
      const head = (document.body && document.body.innerText || '').slice(0, 400);
      if (/Access Denied|Request unsuccessful/i.test(head)) return JSON.stringify({blocked: true});
      const m = document.querySelector('.product-detail');
      if (!m) return JSON.stringify({none: true});
      const num = s => { if (s == null) return null; const v = parseFloat(String(s).replace(/[^\d,.-]/g,'').replace(/\./g,'').replace(',','.')); return isNaN(v) ? null : v; };
      const pr = m.querySelector('.priceWrp .price'), del = m.querySelector('.deleted__price');
      const badge = [...m.querySelectorAll('.sign-badges .offer-span,.hightlight')].map(x => x.textContent.replace(/\s+/g,'')).join(' ') || null;
      const icon = (m.querySelector('.offerIcon__img') || {}).alt || null;
      return JSON.stringify({ price: num(pr && pr.getAttribute('data-price')),
        unit: ((pr && pr.querySelector('span') || {}).textContent || '').replace('/','').trim(),
        old: num(del && del.textContent), badge, icon, nb: /Προσωρινά μη διαθέσιμο/.test(m.innerText) });
    })()
    """#

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // keeps the eshop sign-in, like Safari
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: cfg)
        super.init()
        web.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish?.resume(); finish = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish?.resume(); finish = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish?.resume(); finish = nil }

    private func open(_ url: URL) async {
        await withCheckedContinuation { c in finish = c; web.load(URLRequest(url: url)) }
    }

    func cancel() { stop = true }

    func read(_ products: [Product]) async {
        guard !running else { return }
        running = true; stop = false
        var ok = 0, failed = 0
        for (i, p) in products.enumerated() {
            if stop { break }
            status = "Reading \(i + 1) of \(products.count)…"
            guard let url = URL(string: p.url) else { continue }
            await open(url)
            try? await Task.sleep(for: .milliseconds(900))
            if let s = try? await web.evaluateJavaScript(js) as? String, let d = s.data(using: .utf8),
               var r = try? JSONDecoder().decode(Reading.self, from: d) {
                r.at = Date()
                if r.blocked == true { readings[p.sku] = r; status = "The site stopped the reading after \(ok) products (Access Denied)."; running = false; return }
                readings[p.sku] = r
                if r.price != nil { ok += 1 } else { failed += 1 }
            } else { failed += 1 }
            try? await Task.sleep(for: .milliseconds(700))
        }
        status = "Done: \(ok) prices read\(failed > 0 ? ", \(failed) without a price" : "")\(stop ? " (stopped)" : "")."
        running = false
    }
}

// MARK: - Psonia (Supabase) — send the prices to the household, merged with what is there

struct Psonia {
    static let base = "https://hyxnwvnjiasjgfdohztx.supabase.co"
    static let key = "sb_publishable_9HaJlBsEsRmzW-YgffdlHg_R8ekR6Qd"

    static func request(_ path: String, method: String = "GET", token: String? = nil, body: Any? = nil, prefer: String? = nil) async throws -> Any {
        var r = URLRequest(url: URL(string: base + path)!)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + (token ?? key), forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (d, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw NSError(domain: "Psonia", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code): " + (String(data: d, encoding: .utf8) ?? "")]) }
        return d.isEmpty ? [:] : try JSONSerialization.jsonObject(with: d)
    }

    static func send(_ readings: [String: Reading], email: String, password: String) async throws -> Int {
        let auth = try await request("/auth/v1/token?grant_type=password", method: "POST", body: ["email": email, "password": password]) as? [String: Any]
        guard let token = auth?["access_token"] as? String else { throw NSError(domain: "Psonia", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sign-in failed"]) }
        guard let hh = (try await request("/rest/v1/households?select=id,name&order=created", token: token) as? [[String: Any]])?.first,
              let hid = hh["id"] as? String else { throw NSError(domain: "Psonia", code: 2, userInfo: [NSLocalizedDescriptionKey: "No household for this account"]) }
        let rows = try await request("/rest/v1/household_state?household_id=eq.\(hid)&key=eq.prices&select=data", token: token) as? [[String: Any]]
        var items = ((rows?.first?["data"] as? [String: Any])?["items"] as? [String: Any]) ?? [:]
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var n = 0
        for (sku, r) in readings where r.price != nil {
            var x: [String: Any] = ["at": iso.string(from: r.at), "sku": sku, "price": r.price!, "unit": (r.unit?.isEmpty == false ? r.unit! : "τεμ."),
                                    "promo": r.promo, "nb": r.nb ?? false, "src": "iPhone app"]
            x["old"] = r.old ?? NSNull(); x["badge"] = r.badge ?? NSNull(); x["icon"] = r.icon ?? NSNull()
            items[sku] = x; n += 1
        }
        _ = try await request("/rest/v1/household_state", method: "POST", token: token,
                              body: ["household_id": hid, "key": "prices", "data": ["at": iso.string(from: Date()), "items": items]],
                              prefer: "resolution=merge-duplicates,return=minimal")
        return n
    }
}

// MARK: - Screen

struct WebHolder: UIViewRepresentable {      // shows the reader's browser view (Eshop button: sign in, look around)
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var reader = PriceReader()
    @State private var products: [Product] = []
    @State private var showEshop = false
    @State private var showSend = false
    @AppStorage("psoniaEmail") private var email = ""
    @State private var password = ""
    @State private var sendMsg = ""

    private func eur(_ v: Double?) -> String { v.map { String(format: "%.2f €", $0).replacingOccurrences(of: ".", with: ",") } ?? "–" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(reader.status).font(.subheadline)
                    HStack {
                        Button(reader.running ? "Stop" : "Update prices") {
                            if reader.running { reader.cancel() } else { Task { await reader.read(products) } }
                        }.buttonStyle(.borderedProminent)
                        Button("Send to Psonia") { showSend = true }.buttonStyle(.bordered).disabled(reader.readings.isEmpty || reader.running)
                    }
                    Text("\(products.count) products bought regularly · about 2 s each").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(products) { p in
                    let r = reader.readings[p.sku]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.subheadline)
                        HStack(spacing: 8) {
                            if let r {
                                if r.blocked == true { Text("blocked by the site").foregroundStyle(.red) }
                                else if r.price == nil { Text("no price on the page").foregroundStyle(.secondary) }
                                else {
                                    Text(eur(r.price)).bold().foregroundStyle(r.promo ? Color.orange : Color.primary)
                                    if r.old != nil { Text(eur(r.old)).strikethrough().foregroundStyle(.secondary) }
                                    if let b = r.badge { Text(b).foregroundStyle(.orange) }
                                    if let i = r.icon { Text(i).foregroundStyle(.secondary) }
                                    if r.nb == true { Text("unavailable").foregroundStyle(.secondary) }
                                }
                            } else { Text("not read yet").foregroundStyle(.secondary) }
                        }.font(.caption)
                    }
                }
            }
            .navigationTitle("Psonia prices")
            .toolbar { Button("Eshop") { showEshop = true } }
            .sheet(isPresented: $showEshop) {
                NavigationStack {
                    WebHolder(web: reader.web).ignoresSafeArea(edges: .bottom)
                        .navigationTitle("sklavenitis.gr").navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { showEshop = false } }
                        .onAppear { if reader.web.url == nil { reader.web.load(URLRequest(url: URL(string: "https://www.sklavenitis.gr/")!)) } }
                }
            }
            .sheet(isPresented: $showSend) {
                Form {
                    Section("Your Psonia account") {
                        TextField("E-mail", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        SecureField("Password", text: $password)
                    }
                    Button("Send \(reader.readings.values.filter { $0.price != nil }.count) prices") {
                        Task {
                            do { let n = try await Psonia.send(reader.readings, email: email, password: password); sendMsg = "Sent \(n) prices. Reload Psonia." }
                            catch { sendMsg = error.localizedDescription }
                        }
                    }
                    if !sendMsg.isEmpty { Text(sendMsg).font(.footnote) }
                }
            }
        }
        .onAppear {
            if products.isEmpty, let u = Bundle.module.url(forResource: "products", withExtension: "json"),
               let d = try? Data(contentsOf: u), let list = try? JSONDecoder().decode([Product].self, from: d) { products = list }
        }
    }
}
