import logging
import os
import sqlite3
import time

import requests

TOKEN = os.environ["TOKEN"]
CHAT_ID = os.environ.get("CHAT_ID", "")
DB_PATH = os.environ.get("DB_PATH", "notes.db")
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
log = logging.getLogger("notes-bot")


def main():
    db = sqlite3.connect(DB_PATH)
    db.execute("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, text TEXT)")
    offset = 0
    log.info("起動しました")
    while True:
        try:
            r = requests.get(f"https://api.telegram.org/bot{TOKEN}/getUpdates", params={"offset": offset, "timeout": 30}, timeout=40)
            for u in r.json().get("result", []):
                offset = u["update_id"] + 1
                text = u.get("message", {}).get("text")
                if text and (not CHAT_ID or str(u["message"]["chat"]["id"]) == CHAT_ID):
                    db.execute("INSERT INTO notes (text) VALUES (?)", (text,))
                    db.commit()
        except Exception as e:
            log.warning("取得に失敗しました: %s", e)
            time.sleep(5)


if __name__ == "__main__":
    main()
