import os
import time
import requests

SERVICE_URL = os.getenv("INVENTORY_URL", "http://inventory-service:8080")
INTERVAL = float(os.getenv("INTERVAL_SECONDS", "2"))


def main():
    print(f"Client started. Sending requests to {SERVICE_URL} every {INTERVAL}s")
    while True:
        try:
            resp = requests.get(SERVICE_URL, timeout=3)
            data = resp.json()
            print(
                f"[{resp.status_code}] pod={data.get('pod')}  "
                f"items={len(data.get('items', []))}  "
                f"status={data.get('status')}",
                flush=True,
            )
        except requests.exceptions.ConnectionError as e:
            print(f"[ERR] Connection failed: {e}", flush=True)
        except Exception as e:
            print(f"[ERR] {e}", flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()