# PsoniaTest — iPhone price-reader test

Answers one question: can an app on the user's own iPhone read sklavenitis.gr prices (the site blocks servers)?

1. Open `PsoniaTest.swiftpm` in Xcode (double-click).
2. Connect the iPhone, pick it as the run destination. Signing: your Apple ID ("Personal Team") — free; the app then runs for 7 days.
3. Press Run. On the iPhone: Settings → General → VPN & Device Management → trust your developer profile (first time only).
4. In the app: **Update prices** (121 products, about 4 minutes). **Eshop** opens sklavenitis.gr inside the app (sign in there if you like). **Send to Psonia** puts the prices into your household; reload Psonia.
