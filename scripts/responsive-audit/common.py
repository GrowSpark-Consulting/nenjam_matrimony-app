"""Shared responsive checks for the admin panel and the agent portal.

Real Chromium via Playwright. Every (route, viewport) pair is opened, measured
and screenshotted. Findings are objective measurements, not CSS inspection.
"""
import json
import os
import re

VIEWPORTS = [
    (320, 640), (360, 800), (375, 812), (390, 844), (414, 896), (430, 932),
    (600, 960), (768, 1024), (820, 1180), (1024, 768), (1280, 720),
    (1366, 768), (1440, 900), (1600, 900), (1920, 1080), (2560, 1440),
]
# Landscape counterparts for the phone sizes.
LANDSCAPE = [(640, 320), (800, 360), (812, 375), (844, 390)]
SHOT_WIDTHS = {320, 390, 768, 1024, 1366, 1920}

OUT = os.environ.get('AUDIT_OUT', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out'))

MEASURE = r"""() => {
  const vw = document.documentElement.clientWidth;
  const doc = document.documentElement;
  const res = { vw, scrollWidth: doc.scrollWidth, offenders: [], small: [], clippedText: [] };
  const insideScroller = (el) => {
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const o = getComputedStyle(p).overflowX;
      if (o === 'auto' || o === 'scroll' || o === 'hidden' || o === 'clip') return true;
    }
    return false;
  };
  const sel = (el) => el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
    (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : '');
  for (const el of document.querySelectorAll('body *')) {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || el.matches('.skip-link, .sr-only, .visually-hidden')) continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    if ((r.right > vw + 1 || r.left < -1) && !insideScroller(el) && cs.position !== 'fixed') {
      res.offenders.push(sel(el) + ' [' + Math.round(r.left) + '..' + Math.round(r.right) + ']');
    }
    if (el.matches('a[href],button,input:not([type=hidden]),select,textarea,[role=button],[role=tab]')) {
      const tiny = r.width < 24 || r.height < 24;
      if (tiny && !el.matches('input[type=radio],input[type=checkbox]')) {
        res.small.push(sel(el) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height) + ' "' + (el.textContent || '').trim().slice(0, 20) + '"');
      }
    }
    if (el.children.length === 0 && el.scrollWidth > el.clientWidth + 2 &&
        ['hidden', 'clip'].includes(cs.overflowX) && cs.textOverflow !== 'ellipsis') {
      res.clippedText.push(sel(el) + ' "' + (el.textContent || '').trim().slice(0, 30) + '"');
    }
  }
  res.offenders = [...new Set(res.offenders)].slice(0, 8);
  res.small = [...new Set(res.small)].slice(0, 6);
  res.clippedText = [...new Set(res.clippedText)].slice(0, 6);
  return res;
}"""


def check_page(page, name, w, h, shots_dir, results, console_errors):
    page.wait_for_timeout(250)
    m = page.evaluate(MEASURE)
    issues = []
    if m['scrollWidth'] > m['vw'] + 1:
        issues.append(f"PAGE OVERFLOW scrollWidth={m['scrollWidth']} > {m['vw']}")
    if m['offenders']:
        issues.append('offscreen: ' + '; '.join(m['offenders']))
    if m['small']:
        issues.append('tiny targets: ' + '; '.join(m['small']))
    if m['clippedText']:
        issues.append('clipped text: ' + '; '.join(m['clippedText']))
    if console_errors:
        issues.append('console: ' + ' | '.join(console_errors[:3]))
    if w in SHOT_WIDTHS:
        os.makedirs(shots_dir, exist_ok=True)
        safe = re.sub(r'[^A-Za-z0-9_.()-]', '_', name)
        page.screenshot(path=os.path.join(shots_dir, f'{safe}__{w}x{h}.png'), full_page=True)
    results.append({'route': name, 'viewport': f'{w}x{h}', 'ok': not issues, 'issues': issues})
    return issues


def report(app, results):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f'{app}-results.json'), 'w') as f:
        json.dump(results, f, indent=1)
    bad = [r for r in results if not r['ok']]
    print(f"{app}: {len(results)} checks, {len(results) - len(bad)} passed, {len(bad)} failed, 0 skipped")
    seen = {}
    for r in bad:
        for i in r['issues']:
            seen.setdefault((r['route'], i), []).append(r['viewport'])
    for (route, issue), vps in seen.items():
        print(f"  FAIL {route} @ {','.join(vps[:6])}{'...' if len(vps) > 6 else ''}\n     - {issue}")
    return len(bad)
