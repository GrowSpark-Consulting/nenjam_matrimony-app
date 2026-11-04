"""Agent portal responsive audit. Needs: cd agent-portal && VITE_USE_MOCKS=true npx vite --port 5180"""
import os
import sys

from playwright.sync_api import sync_playwright

from common import LANDSCAPE, OUT, VIEWPORTS, check_page, report

BASE = os.environ.get('PORTAL_URL', 'http://localhost:5180')
# label -> (phone, routes). Statuses are the seeded ones in mockAgentApi.
AGENTS = {
    'active': ('9000000005', ['/', '/referrals', '/earnings', '/payouts', '/payout-details', '/help', '/clients', '/clients/new', '/clients/c1']),
    'suspended': ('9000000003', ['/', '/earnings']),
    'terminated': ('9000000004', ['/earnings']),
    'pending': ('9000000001', ['/status']),
    'rejected': ('9000000002', ['/status', '/apply']),
    'applicant': ('9000000099', ['/apply']),
}


def login(page, phone):
    page.goto(BASE + '/sign-in')
    page.wait_for_load_state('networkidle')
    page.fill('#phone', phone)
    page.click('button[type=submit]')
    page.fill('#code', '123456')
    page.click('button[type=submit]')
    page.wait_for_timeout(600)


def main():
    results = []
    only = sys.argv[1:]
    with sync_playwright() as p:
        b = p.chromium.launch()
        for (w, h) in VIEWPORTS + LANDSCAPE:
            ctx = b.new_context(viewport={'width': w, 'height': h}, has_touch=w < 1024)
            page = ctx.new_page()
            errs = []
            page.on('console', lambda m: errs.append(m.text) if m.type == 'error' else None)
            page.on('pageerror', lambda e: errs.append(str(e)))
            page.goto(BASE + '/sign-in')
            page.wait_for_load_state('networkidle')
            check_page(page, 'sign-in (phone)', w, h, OUT + '/portal', results, list(errs))
            page.fill('#phone', '9000000005')
            page.click('button[type=submit]')
            page.wait_for_selector('#code')
            check_page(page, 'sign-in (otp)', w, h, OUT + '/portal', results, list(errs))
            for label, (phone, routes) in AGENTS.items():
                if only and label not in only:
                    continue
                page.evaluate('localStorage.clear()')
                errs.clear()
                login(page, phone)
                for r in routes:
                    page.goto(BASE + r)
                    page.wait_for_load_state('networkidle')
                    check_page(page, f'{label}:{r}', w, h, OUT + '/portal', results, list(errs))
            ctx.close()
        b.close()
    sys.exit(1 if report('portal', results) else 0)


main()
