"""
Shows the Colorblind safe look the way colorblind players see it. Lays the shots from
shots_colorblind.lua out as rows, with columns for normal vision and the three kinds of full
colorblindness (Machado, Oliveira and Fernandes 2009, severity 1.0). Writes out/colorblind_sheet.png.

    .venv\\Scripts\\python render.py shots_colorblind.lua
    .venv\\Scripts\\python colorblind_sheet.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
SHEET = os.path.join(OUT, 'colorblind_sheet.png')
SHOTS = ['cb_filling', 'cb_almost', 'cb_ready_on_you', 'cb_resting_full']

# How each kind of colorblindness changes a color, as a matrix on linear RGB.
MATRICES = {
    'normal': np.eye(3),
    'protanopia': np.array([[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216],
                            [-0.003882, -0.048116, 1.051998]]),
    'deuteranopia': np.array([[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413],
                              [-0.011820, 0.042940, 0.968881]]),
    'tritanopia': np.array([[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602],
                            [0.004733, 0.691367, 0.303900]]),
}


def simulate(img, matrix):
    rgb = np.asarray(img.convert('RGB')).astype(np.float64) / 255
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    seen = np.clip(linear @ matrix.T, 0, 1)
    srgb = np.where(seen <= 0.0031308, 12.92 * seen, 1.055 * seen ** (1 / 2.4) - 0.055)
    return Image.fromarray((srgb * 255 + 0.5).astype(np.uint8))


def main():
    shots = [Image.open(os.path.join(OUT, 'shot_%s.png' % name)) for name in SHOTS]
    width = max(s.width for s in shots)
    height = max(s.height for s in shots)
    sheet = Image.new('RGB', (width * 4 + 30, (height + 10) * len(shots) + 20), (20, 20, 20))
    draw = ImageDraw.Draw(sheet)
    for col, kind in enumerate(MATRICES):
        draw.text((col * (width + 10) + 4, 4), kind, fill=(230, 230, 230))
    for row, shot in enumerate(shots):
        for col, kind in enumerate(MATRICES):
            sheet.paste(simulate(shot, MATRICES[kind]), (col * (width + 10), 20 + row * (height + 10)))
    sheet.save(SHEET)
    print('wrote', SHEET)


if __name__ == '__main__':
    main()
