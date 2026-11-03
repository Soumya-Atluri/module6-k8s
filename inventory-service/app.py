import os
import socket
from flask import Flask, jsonify, request

app = Flask(__name__)

_ready = True


@app.route("/")
def inventory():
    return jsonify({
        "service": "inventory",
        "pod": socket.gethostname(),
        "items": ["widget-A", "widget-B", "widget-C", "gadget-X", "gadget-Y"],
        "status": "ready" if _ready else "not-ready"
    })


@app.route("/health/readiness")
def readiness():
    if _ready:
        return jsonify({"ready": True}), 200
    return jsonify({"ready": False}), 503


@app.route("/health/liveness")
def liveness():
    return jsonify({"alive": True}), 200


@app.route("/toggle-ready", methods=["POST"])
def toggle_ready():
    global _ready
    _ready = not _ready
    return jsonify({"ready": _ready, "pod": socket.gethostname()})


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port)