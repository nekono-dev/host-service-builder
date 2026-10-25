import json
import os

from aiohttp import web

STORE = os.environ.get("STORE", "clips.json")
KEY = os.environ["KEY"]
MAX_ITEMS = int(os.environ.get("MAX_ITEMS", "50"))


def load():
    try:
        with open(STORE) as f:
            return json.load(f)
    except FileNotFoundError:
        return []


async def handle(request):
    if request.headers.get("X-Key") != KEY:
        raise web.HTTPForbidden()
    clips = load()
    if request.method == "POST":
        clips = ([await request.text()] + clips)[:MAX_ITEMS]
        with open(STORE, "w") as f:
            json.dump(clips, f)
    return web.json_response(clips)


app = web.Application()
app.router.add_route("*", "/", handle)
web.run_app(app, port=int(os.environ.get("PORT", "7070")))
