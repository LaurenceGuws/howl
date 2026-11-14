# Original Howl test fixture, CC0-1.0. Requires fontTools only to regenerate.
# Two coloured halves; one is translucent. No third-party outlines or font data.
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.colorLib.builder import buildCOLR, buildCPAL
from pathlib import Path
b = FontBuilder(1000, isTTF=True)
b.setupGlyphOrder([".notdef", "emoji", "red", "blue", "up", "down"])
b.setupCharacterMap({0x1f600: "emoji", 0x25b2: "up", 0x25bc: "down"})
glyphs = {}
for name, bounds in [(".notdef", None), ("emoji", None), ("red", (0, 0, 500, 800)), ("blue", (500, 0, 1000, 800))]:
    pen = TTGlyphPen(None)
    if bounds:
        x0,y0,x1,y1 = bounds
        pen.moveTo((x0,y0)); pen.lineTo((x1,y0)); pen.lineTo((x1,y1)); pen.lineTo((x0,y1)); pen.closePath()
    glyphs[name] = pen.glyph()
for name, points in [("up", [(0,0), (1600,0), (800,1200)]), ("down", [(0,1200), (1600,1200), (800,0)])]:
    pen = TTGlyphPen(None)
    pen.moveTo(points[0])
    for point in points[1:]: pen.lineTo(point)
    pen.closePath()
    glyphs[name] = pen.glyph()
b.setupGlyf(glyphs)
b.setupHorizontalMetrics({n: (1800 if n in ("up", "down") else 1000, 500 if n == "blue" else 0) for n in glyphs})
b.setupHorizontalHeader(ascent=800, descent=-200)
b.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
b.setupNameTable({"familyName": "Howl Colour Fixture", "styleName": "Regular", "uniqueFontIdentifier": "HowlColourFixture-1", "fullName": "Howl Colour Fixture", "psName": "HowlColourFixture"})
b.setupPost()
b.setupMaxp()
b.font["COLR"] = buildCOLR({"emoji": [("red", 0), ("blue", 1)]}, version=0)
b.font["CPAL"] = buildCPAL([[(1,0,0,1), (0,0,1,0.5)]])
# Reproducible fixture timestamps, independent of regeneration time.
b.font["head"].created = b.font["head"].modified = 0
b.save(Path(__file__).with_name("colour.ttf"))
