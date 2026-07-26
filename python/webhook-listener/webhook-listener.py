#!/usr/bin/env python3

# Installation:
# python3 -m venv venv
# source venv/bin/activate
# pip install flask

# Usage
# Start by running
# ./webhook_listener.py
# Send webhooks to:
# http://{host-ip-address}:30239/webhook

# Test case using curl
# curl -X POST http://localhost:30239/webhook \
#   -H "Content-Type: application/json" \
#   -d '{
#     "event": "test",
#     "message": "hello"
#   }'


from flask import Flask, request, jsonify
import json

app = Flask(__name__)


@app.route("/webhook", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
def webhook():
    print("\n" + "=" * 80)
    print("Webhook received")
    print(f"Method: {request.method}")
    print(f"Path: {request.path}")
    print(f"Remote IP: {request.remote_addr}")

    print("\nHeaders:")
    for key, value in request.headers.items():
        print(f"  {key}: {value}")

    print("\nQuery Parameters:")
    print(dict(request.args))

    print("\nBody:")

    if request.is_json:
        try:
            payload = request.get_json()
            print(json.dumps(payload, indent=2))
        except Exception as e:
            print(f"JSON parse error: {e}")
    else:
        print(request.get_data(as_text=True))

    print("=" * 80 + "\n")

    return jsonify({
        "status": "received"
    }), 200


@app.route("/health", methods=["GET"])
def health():
    return "OK", 200


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=30239,
        debug=False
    )