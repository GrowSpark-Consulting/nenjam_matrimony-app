"""Admin: mobile drawer + dialog fit checks (real clicks in Chromium)."""
import sys
sys.argv = ['x']
src = open('admin.py').read().split('def main():')[0]
exec(compile(src, 'a', 'exec'))
serve()
from playwright.sync_api import sync_playwright

bad = 0
with sync_playwright() as p:
    b = p.chromium.launch()
    for (w, h) in [(320, 640), (390, 844), (768, 1024)]:
        ctx, page, errs = new_page(b, w, h)
        sign_in(page)
        page.goto(BASE + '/agents/'); page.wait_for_selector('#main')
        vis = lambda: page.is_visible('aside.sidebar')
        closed = not vis()
        page.click('button.menu-toggle')
        opened = vis()
        exp = page.get_attribute('button.menu-toggle', 'aria-expanded')
        link_ok = page.is_visible('aside a.nav-link.active')
        page.click('aside a:has-text("Plans")'); page.wait_for_selector('h1:has-text("Plans")')
        auto_closed = not vis()
        ok = closed and opened and exp == 'true' and link_ok and auto_closed
        print(f'drawer {w}x{h}: closed={closed} opened={opened} aria-expanded={exp} active-visible={link_ok} closes-on-nav={auto_closed} -> {"PASS" if ok else "FAIL"}')
        bad += not ok
        # dialog fit: open a reject dialog on a pending agent
        page.goto(BASE + '/agents/view/?id=ag0'); page.wait_for_selector('#main')
        btns = page.locator('button:has-text("Reveal"), button:has-text("Suspend"), button:has-text("Replace")')
        n = btns.count()
        if n:
            btns.first.click(); page.wait_for_timeout(300)
            dlg = page.locator('dialog[open], [role=dialog]').first
            if dlg.count():
                bb = dlg.bounding_box()
                fit = bb and bb['x'] >= -1 and bb['y'] >= -1 and bb['x'] + bb['width'] <= w + 1 and bb['y'] + bb['height'] <= h + 1
                print(f'dialog {w}x{h}: box={bb and {k: round(v) for k, v in bb.items()}} fits={fit}')
                page.screenshot(path=f'out/admin/dialog_{w}x{h}.png')
                bad += not fit
            else:
                print(f'dialog {w}x{h}: no dialog element found after click')
        ctx.close()
    b.close()
sys.exit(1 if bad else 0)
