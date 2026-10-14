# ocr_probe.py - does rapidocr actually read a real card image, and are its boxes usable?
#
# This is the step our own text-band detector only half-solves: it finds which ROWS contain detail, but not
# which text is where. If OCR gives tight boxes, they can be fed straight to Export-I18nBandPreview (same
# y0/y1/x0/x1 shape) and the "cover this bit" decision stops being eyeballed.
#
# Run from the repo root:
#   local\scratch\python\python.exe tts\tools\ocr_probe.py <image> [--json]
import json
import sys
import time


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    if not args:
        print("usage: ocr_probe.py <image> [--json]")
        return 2
    img = args[0]

    from rapidocr_onnxruntime import RapidOCR

    t0 = time.time()
    ocr = RapidOCR()
    print("model loaded in %.2f s" % (time.time() - t0))

    t1 = time.time()
    result, _elapse = ocr(img)
    secs = time.time() - t1
    if not result:
        print("no text found  (%.2f s)" % secs)
        return 0

    boxes = []
    for box, text, score in result:
        xs = [p[0] for p in box]
        ys = [p[1] for p in box]
        boxes.append({
            "text": text,
            "score": round(float(score), 3),
            "x0": int(min(xs)), "y0": int(min(ys)),
            "x1": int(max(xs)), "y1": int(max(ys)),
            "w": int(max(xs) - min(xs)), "h": int(max(ys) - min(ys)),
        })

    if as_json:
        print(json.dumps(boxes, ensure_ascii=False, indent=1))
    else:
        print("boxes %d in %.2f s" % (len(boxes), secs))
        for b in sorted(boxes, key=lambda b: (b["y0"], b["x0"])):
            print("  y%-5d x%-5d %4dx%-3d  %-6s %s" % (b["y0"], b["x0"], b["w"], b["h"], b["score"], b["text"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
