#!/usr/bin/env python3
"""MB-OS Face Authentication (OpenCV + OpenVINO)

Usage:
  face-auth.py enroll   - Capture face and save encoding
  face-auth.py verify   - Try to match face, exit 0=match, 1=no match
  face-auth.py download - Download required AI models

Uses OpenCV DNN with OpenVINO backend for Intel CPU acceleration.
Models: YuNet (detection) + SFace (recognition)
"""
import sys
import os
import json
import time
import numpy as np

MODEL_DIR = os.path.expanduser("~/.config/mb-os/models")
FACE_DATA = os.path.expanduser("~/.config/mb-os/face.json")
TIMEOUT = 5  # seconds to try verification

# Model URLs (OpenCV model zoo)
YUNET_URL = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
SFACE_URL = "https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx"

YUNET_PATH = os.path.join(MODEL_DIR, "yunet.onnx")
SFACE_PATH = os.path.join(MODEL_DIR, "sface.onnx")

COSINE_THRESHOLD = 0.363  # SFace recommended threshold


def download_models():
    """Download YuNet + SFace models if not present."""
    import urllib.request
    os.makedirs(MODEL_DIR, exist_ok=True)

    for url, path, name in [(YUNET_URL, YUNET_PATH, "YuNet (Gesichtserkennung)"),
                             (SFACE_URL, SFACE_PATH, "SFace (Gesichtsvergleich)")]:
        if os.path.exists(path):
            print(f"  ✓ {name} bereits vorhanden")
            continue
        print(f"  ↓ Lade {name}...")
        urllib.request.urlretrieve(url, path)
        size_mb = os.path.getsize(path) / (1024 * 1024)
        print(f"  ✓ {name} ({size_mb:.1f} MB)")

    print("Alle Modelle bereit!")


def get_detector_recognizer(frame_width=640, frame_height=480):
    """Initialize OpenCV face detector + recognizer with OpenVINO."""
    import cv2

    if not os.path.exists(YUNET_PATH) or not os.path.exists(SFACE_PATH):
        print("Modelle fehlen! Erst: face-auth.py download", file=sys.stderr)
        sys.exit(2)

    # YuNet face detector
    detector = cv2.FaceDetectorYN.create(
        YUNET_PATH, "", (frame_width, frame_height),
        score_threshold=0.7,
        nms_threshold=0.3,
        top_k=5
    )

    # Try OpenVINO backend for acceleration
    try:
        detector.setPreferableBackend(cv2.dnn.DNN_BACKEND_INFERENCE_ENGINE)
        detector.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
    except Exception:
        pass  # Fall back to default backend

    # SFace recognizer
    recognizer = cv2.FaceRecognizerSF.create(SFACE_PATH, "")

    return detector, recognizer


def detect_and_encode(frame, detector, recognizer):
    """Detect faces and return their encodings."""
    _, faces = detector.detect(frame)
    if faces is None or len(faces) == 0:
        return []

    encodings = []
    for face in faces:
        aligned = recognizer.alignCrop(frame, face)
        encoding = recognizer.feature(aligned)
        encodings.append(encoding.flatten().tolist())
    return encodings


def enroll():
    """Capture 3 face samples and save average encoding."""
    import cv2
    download_models()

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("FEHLER: Kamera nicht verfügbar!", file=sys.stderr)
        sys.exit(2)

    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    detector, recognizer = get_detector_recognizer(w, h)

    print("📷 Schaue in die Kamera... (3 Aufnahmen)")
    encodings = []
    attempts = 0

    while len(encodings) < 3 and attempts < 60:
        ret, frame = cap.read()
        if not ret:
            attempts += 1
            continue

        encs = detect_and_encode(frame, detector, recognizer)
        if encs:
            encodings.append(encs[0])
            print(f"  ✓ Foto {len(encodings)}/3 aufgenommen!")
            time.sleep(0.8)

        attempts += 1
        time.sleep(0.1)

    cap.release()

    if not encodings:
        print("FEHLER: Kein Gesicht erkannt!", file=sys.stderr)
        sys.exit(1)

    # Save encodings
    os.makedirs(os.path.dirname(FACE_DATA), exist_ok=True)
    with open(FACE_DATA, "w") as f:
        json.dump({"encodings": encodings, "count": len(encodings)}, f)

    print(f"✓ {len(encodings)} Gesichtsaufnahmen gespeichert!")


def verify():
    """Try to match face against stored encodings."""
    import cv2

    if not os.path.exists(FACE_DATA):
        sys.exit(1)  # No face enrolled

    with open(FACE_DATA) as f:
        data = json.load(f)

    known = [np.array(e, dtype=np.float32) for e in data["encodings"]]

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        sys.exit(1)

    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    detector, recognizer = get_detector_recognizer(w, h)

    start = time.time()
    matched = False

    while time.time() - start < TIMEOUT:
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.1)
            continue

        encs = detect_and_encode(frame, detector, recognizer)
        for enc in encs:
            enc_arr = np.array(enc, dtype=np.float32)
            for known_enc in known:
                # Cosine similarity
                score = recognizer.match(
                    known_enc.reshape(1, -1),
                    enc_arr.reshape(1, -1),
                    cv2.FaceRecognizerSF_FR_COSINE
                )
                if score >= COSINE_THRESHOLD:
                    matched = True
                    break
            if matched:
                break

        if matched:
            break
        time.sleep(0.05)

    cap.release()
    sys.exit(0 if matched else 1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "enroll":
        enroll()
    elif cmd == "verify":
        verify()
    elif cmd == "download":
        download_models()
    else:
        print(f"Unbekannt: {cmd}", file=sys.stderr)
        sys.exit(1)
