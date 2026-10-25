import os
import time

import redis

r = redis.Redis.from_url(os.environ["REDIS_URL"])
interval = int(os.environ.get("CLEAN_INTERVAL", "300"))
while True:
    n = sum(1 for k in r.scan_iter("link:*") if r.ttl(k) == -1 and r.expire(k, 86400))
    print(f"期限の無いリンクに期限を付けました: {n}", flush=True)
    time.sleep(interval)
