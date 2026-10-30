# PsoniaTest — iPhone price-reader test

Answers one question: can an app on the user's own iPhone read sklavenitis.gr prices (the site blocks servers)?

1. Open `PsoniaTest.swiftpm` in Xcode (double-click).
2. Connect the iPhone, pick it as the run destination. Signing: your Apple ID ("Personal Team") — free; the app then runs for 7 days.
3. Press Run. On the iPhone: Settings → General → VPN & Device Management → trust your developer profile (first time only).
4. In the app: **Eshop** (top right): sign in to sklavenitis.gr once. **1 · Get my data** reads your whole order history by itself. **2 · Update prices** reads the current price and offer of every product found. **3 · Send to Psonia** puts orders and prices into your household; reload Psonia.
