"""Daily: take the latest posokanei.gov.gr snapshot (public archive github.com/spyrosavl/posokanei, prices © the
platform) and keep only Sklavenitis prices, as a small file the Psonia app reads with its Update prices button.
Usage: python tools/posokanei_extract.py [snapshot.json]   (no argument: download the latest snapshot)
"""
import json, sys, urllib.request
RAW = "https://raw.githubusercontent.com/spyrosavl/posokanei/main/"
def get(path):
    with urllib.request.urlopen(RAW + path, timeout=300) as r:
        return json.load(r)
if len(sys.argv) > 1:
    snap = json.load(open(sys.argv[1], encoding="utf-8"))
else:
    snap = get(get("data/latest.json")["path"])
items = []
for p in snap["products"]:
    for r in p.get("retailer_prices") or []:
        if r.get("retailer") == "sklavenitis" and r.get("price") is not None:
            items.append([p["name"].strip(), r["price"], bool(r.get("is_discount")), r.get("discount_percentage"),
                          p.get("unit"), p.get("unit_quantity")])
out = {"date": snap["date"], "source": "posokanei.gov.gr (archive github.com/spyrosavl/posokanei)", "retailer": "sklavenitis",
       "fields": ["name", "price", "is_discount", "discount_percentage", "unit", "unit_quantity"], "items": items}
json.dump(out, open("data/sklavenitis-prices.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(out["date"], len(items), "Sklavenitis prices")
