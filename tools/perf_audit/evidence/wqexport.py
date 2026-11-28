"""wqexport.py: Water Quality Off / Low / Medium / High, full 1600x900 frames and 1:1 crops (native pixels), from the PR 02 build.
D3D11 with the defaults (out/pr02/sr_d3d11), D3D12 with the detailed water off (out/wq6, scenes b..e), and D3D12 with the defaults (out/pr02/sr_d3d12)."""
import os, sys
from PIL import Image, ImageChops
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import evlib
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'evidence2', 'full')
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    os.remove(os.path.join(OUT, f))
def fr(tag, sub):
    return evlib.scene_frames(os.path.join(HERE, 'out', tag, sub))
d11 = fr('pr02', 'sr_d3d11'); d12 = fr('pr02', 'sr_d3d12'); wd0 = fr('wq6', '') if False else evlib.scene_frames(os.path.join(HERE, 'out', 'wq6'))
m11 = fr('master_a', 'sr_d3d11'); m12 = fr('master_a', 'sr_d3d12')
# the crop: 800 x 450 around the centre of the pixels that differ between Low and Medium (the soft shoreline)
a = Image.open(d11['wq1']).convert('RGB'); b = Image.open(d11['wq2']).convert('RGB')
bbox = ImageChops.difference(a, b).convert('L').point(lambda v: 255 if v else 0).getbbox()
cx = (bbox[0] + bbox[2]) // 2; cy = (bbox[1] + bbox[3]) // 2
x0 = min(max(cx - 400, 0), 1600 - 800); y0 = min(max(cy - 225, 0), 900 - 450)
CROP = (x0, y0, x0 + 800, y0 + 450)
print('difference bbox', bbox, 'crop', CROP)
def save(path, base):
    im = Image.open(path).convert('RGB')
    assert im.size == (1600, 900), im.size
    im.save(os.path.join(OUT, base + '.png'), optimize=True)
    im.crop(CROP).save(os.path.join(OUT, base + '_crop1to1.png'), optimize=True)
    print(base, os.path.getsize(os.path.join(OUT, base + '.png')))
save(m11['ships'], 'sr_d3d11_ships_master')
for lvl, name in ((0, 'off'), (1, 'low'), (2, 'medium'), (3, 'high')):
    save(d11['wq%d' % lvl], 'sr_d3d11_ships_waterquality_%s' % name)
save(m12['ships'], 'sr_d3d12_ships_master')
for key, name in (('b_wd0', 'off'), ('c_wd0_q1', 'low'), ('d_wd0_q2', 'medium'), ('e_wd0_q3', 'high')):
    save(wd0[key], 'sr_d3d12_detail0_ships_waterquality_%s' % name)
save(d12['wq0'], 'sr_d3d12_ships_waterquality_off')
save(d12['wq3'], 'sr_d3d12_ships_waterquality_high')
