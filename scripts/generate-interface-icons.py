#!/usr/bin/env python3
"""Render original monochrome interface artwork using only the Python standard library.

This optional resource-authoring script is not part of the build. Coordinates use
24 units; supersampling preserves small-size stroke edges at every device scale.
"""
import json
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / 'NarihitosDiary/Assets.xcassets'


def circle(x, y, radius, count=48):
    return [(x + math.cos(i * math.tau / count) * radius,
             y + math.sin(i * math.tau / count) * radius) for i in range(count)]


def shapes(name):
    if name == 'main':
        return [([(3, 11), (12, 3), (21, 11)], False), ([(6, 10), (6, 21), (10, 21), (10, 15), (14, 15), (14, 21), (18, 21), (18, 10)], False)]
    if name == 'benefits':
        return [([(3, 9), (21, 9), (21, 14), (3, 14), (3, 9)], False), ([(5, 14), (5, 21), (19, 21), (19, 14)], False), ([(12, 9), (12, 21)], False), (circle(9, 6, 3), False), (circle(15, 6, 3), False)]
    if name == 'calendar':
        return [([(4, 5), (20, 5), (20, 21), (4, 21), (4, 5)], False), ([(4, 10), (20, 10)], False), ([(8, 3), (8, 7)], False), ([(16, 3), (16, 7)], False), ([(8, 14), (10, 14)], False), ([(14, 17), (16, 17)], False)]
    if name == 'plugins':
        return [([(4, 5), (10, 5), (10, 3), (14, 3), (14, 5), (20, 5), (20, 11), (22, 11), (22, 15), (20, 15), (20, 21), (14, 21), (14, 18), (10, 18), (10, 21), (4, 21), (4, 15), (7, 15), (7, 11), (4, 11), (4, 5)], False)]
    if name == 'all':
        return [([(x, y), (x+6, y), (x+6, y+6), (x, y+6), (x, y)], True) for x in (4, 14) for y in (4, 14)]
    if name == 'record':
        return [(circle(12, 8, 4), True), ([(8, 7), (8, 12), (16, 12), (16, 7)], True), ([(5, 10), (5, 13), (8, 17), (16, 17), (19, 13), (19, 10)], False), ([(12, 17), (12, 22)], False), ([(8, 22), (16, 22)], False)]
    if name == 'stop':
        return [([(5, 5), (19, 5), (19, 19), (5, 19), (5, 5)], True)]
    if name == 'settings':
        gear = [(12 + math.cos(i * math.pi/12) * (10 if i % 3 != 1 else 8), 12 + math.sin(i * math.pi/12) * (10 if i % 3 != 1 else 8)) for i in range(24)]
        return [(gear + [gear[0]], False), (circle(12, 12, 3.5), False)]
    if name == 'pending':
        return [(circle(12, 12, 9), False), ([(12, 6), (12, 12), (16, 14)], False)]
    if name == 'warning':
        return [([(12, 3), (22, 21), (2, 21), (12, 3)], False), ([(12, 9), (12, 14)], False), (circle(12, 18, 0.7), True)]
    if name == 'incomplete':
        return [([(7, 21), (4, 21), (4, 3), (15, 3), (20, 8), (20, 14)], False), ([(14, 3), (14, 9), (20, 9)], False), ([(12, 17), (12, 20)], False), (circle(12, 23, 0.6), True), ([(8, 12), (15, 12)], False)]
    if name == 'conflicts':
        return [([(3, 16), (3, 3), (15, 3), (15, 7)], False), ([(9, 8), (21, 8), (21, 22), (9, 22), (9, 8)], False), ([(13, 12), (17, 12)], False), ([(13, 16), (17, 16)], False)]
    raise ValueError(name)


def inside(x, y, points):
    result = False
    for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1]):
        if (ay > y) != (by > y) and x < (bx-ax)*(y-ay)/(by-ay)+ax:
            result = not result
    return result


def stroke(x, y, points, width):
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        dx, dy = bx-ax, by-ay
        t = max(0, min(1, ((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy))) if dx or dy else 0
        if (x-ax-t*dx)**2 + (y-ay-t*dy)**2 <= width*width/4:
            return True
    return False


def png(path, name, size, filled):
    art = shapes(name)
    rows = bytearray()
    for py in range(size):
        rows.append(0)
        for px in range(size):
            hits = 0
            for sy in range(3):
                for sx in range(3):
                    x, y = (px+(sx+0.5)/3)*24/size, (py+(sy+0.5)/3)*24/size
                    hits += any((fill and inside(x, y, points)) or stroke(x, y, points, 2.3 if filled else 1.7) for points, fill in art)
            rows.extend((0, 0, 0, round(hits*255/9)))
    def chunk(kind, payload):
        return struct.pack('!I', len(payload)) + kind + payload + struct.pack('!I', zlib.crc32(kind+payload) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    for name in ('main', 'benefits', 'calendar', 'plugins', 'all', 'record', 'stop', 'settings', 'pending', 'warning', 'incomplete', 'conflicts'):
        points = 25 if name in ('main', 'benefits', 'calendar', 'plugins', 'all') else 32 if name in ('record', 'stop') else 24
        for filled in (False, True):
            asset = 'ndm-' + name + ('-selected' if filled else '')
            folder = ROOT / (asset + '.imageset')
            folder.mkdir(parents=True, exist_ok=True)
            images = []
            for scale in (1, 2, 3):
                filename = asset + '@' + str(scale) + 'x.png'
                png(folder / filename, name, points*scale, filled)
                images.append({'filename': filename, 'idiom': 'universal', 'scale': str(scale)+'x'})
            (folder / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}, 'properties': {'template-rendering-intent': 'template'}}, indent=2)+'\n')
