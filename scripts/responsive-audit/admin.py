"""Admin panel responsive audit.

The panel is a static export that signs in through Firebase and then talks to
the NestJS /admin API. Neither is available here, so the browser is given:
  * a fake Firebase identity endpoint (intercepted, unsigned JWT),
  * a fake /admin API serving fixtures shaped like admin/src/lib/types.ts.
No backend or panel code is touched. Build the panel first:
  NEXT_PUBLIC_API_BASE_URL=http://127.0.0.1:5199 NEXT_PUBLIC_FIREBASE_API_KEY=fake-key \
  NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=fake.firebaseapp.com NEXT_PUBLIC_FIREBASE_PROJECT_ID=fake \
  NEXT_PUBLIC_FIREBASE_APP_ID=1:1:web:1 npx next build
"""
import base64
import functools
import http.server
import json
import os
import re
import sys
import threading
from urllib.parse import parse_qs, urlparse

from playwright.sync_api import sync_playwright

from common import LANDSCAPE, OUT, VIEWPORTS, check_page, report

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'admin', 'out'))
PORT = 5190
BASE = f'http://127.0.0.1:{PORT}'
API = 'http://127.0.0.1:5199'


def b64(o):
    return base64.urlsafe_b64encode(json.dumps(o).encode()).rstrip(b'=').decode()


JWT = f"{b64({'alg': 'none', 'typ': 'JWT'})}.{b64({'iss': 'https://securetoken.google.com/fake', 'aud': 'fake', 'auth_time': 1, 'user_id': 'u1', 'sub': 'u1', 'iat': 1, 'exp': 4102444800, 'email': 'admin@nenjam.test'})}."

NOW = '2026-11-03T09:30:00.000Z'
LONG_EMAIL = 'a.very.long.email.address.for.stress.testing@some-extremely-long-subdomain.example-company.co.in'
ALL_PERMS = ['agent.approve', 'agent.manage', 'agent.view', 'audit.view', 'commission.approve', 'commission.cancel',
             'commission.override', 'commission.view', 'dashboard.view', 'payout.execute', 'payout.view', 'plan.edit',
             'plan.publish', 'plan.view', 'rbac.manage', 'subscription.cancel', 'subscription.extend', 'subscription.view']

ME = {'adminAccountId': 'ad1', 'userId': 'u1', 'email': 'super.admin@nenjam.test', 'department': 'Ops', 'lastLoginAt': NOW,
      'roles': [{'key': 'SUPER_ADMIN', 'name': 'Super Admin'}], 'permissions': ALL_PERMS}

LONG_NAME = 'Venkataraghavan Subramaniam Ramachandran Iyer-Krishnamurthy'


def agent_row(i, status='ACTIVE'):
    return {'id': f'ag{i}', 'name': LONG_NAME if i == 0 else f'Agent Number {i}', 'phoneMasked': '+91 98***210', 'city': 'Thiruvananthapuram',
            'state': 'Tamil Nadu', 'status': status, 'createdAt': NOW, 'approvedAt': NOW, 'panOnFile': True, 'panVerified': i % 2 == 0,
            'payoutDetailsSet': True, 'payoutDetailsVerified': i % 2 == 0, 'primaryCode': f'NM7K2P{i}X'}


def commission(i, status='READY'):
    return {'id': f'c{i}', 'agentId': 'ag0', 'agentName': LONG_NAME, 'agentStatus': 'ACTIVE', 'referralId': f'r{i}', 'planName': 'Platinum 12 months',
            'paidPaise': 1299900, 'basePaise': 1100000, 'amountPaise': 110000, 'creditedPaise': 0, 'reversedPaise': 0,
            'rate': {'calcType': 'PERCENTAGE', 'value': 10}, 'status': status, 'publicStatus': 'Pending', 'earnedOn': NOW, 'holdEndsOn': NOW,
            'approvedOn': None, 'paidOn': None, 'payoutId': None}


PAYOUT = {'id': 'p1', 'agentId': 'ag0', 'agentName': LONG_NAME, 'agentCode': 'NM7K2P9X', 'period': '2026-10', 'amountPaise': 12345600,
          'taxWithheldPaise': 123456, 'netPaise': 12222144, 'status': 'CREATED', 'reference': None, 'paidAt': None, 'createdAt': NOW,
          'createdBy': LONG_EMAIL, 'commissionIds': ['c1', 'c2'], 'warnings': ['PAN is not verified, so tax is withheld at the higher rate.'],
          'cancelReason': None}

AGENT_DETAIL = {**{k: v for k, v in agent_row(0).items() if k in ('id', 'name', 'phoneMasked', 'city', 'state', 'status', 'createdAt', 'approvedAt', 'panOnFile')},
                'rejectionReason': None, 'updatedAt': NOW, 'panLast4': '1234', 'panVerifiedAt': None, 'payoutDetailsSet': True,
                'payoutDetails': {'method': 'UPI', 'display': 'venkataraghavan.subramaniam@okhdfcbank', 'verifiedAt': None, 'changedAt': NOW},
                'codes': [{'id': 'cd1', 'code': 'NM7K2P9X', 'isPrimary': True, 'isActive': True, 'createdAt': NOW}],
                'counts': {'referrals': 14, 'byAttributionStatus': {'CONFIRMED': 9, 'NEEDS_REVIEW': 2, 'PENDING': 3}, 'needsReview': 2},
                'commissions': None,
                'statusHistory': [{'from': 'PENDING_APPROVAL', 'to': 'ACTIVE', 'at': NOW, 'actorId': 'u1', 'actorType': 'STAFF', 'reason': 'Documents verified over a call with the applicant.'}]}

FEATURES = [
    {'key': 'chat.messages', 'kind': 'quota', 'section': 'Chat', 'label': 'Messages per month', 'period': 'MONTH'},
    {'key': 'profile.visibility', 'kind': 'level', 'section': 'Profile', 'label': 'Profile visibility', 'levels': ['BASIC', 'ENHANCED', 'PRIORITY']},
    {'key': 'profile.photos', 'kind': 'cap', 'section': 'Profile', 'label': 'Photos on profile'},
    {'key': 'verification.badge', 'kind': 'boolean', 'section': 'Trust', 'label': 'Verified badge'},
]
ENT = {'chat.messages': {'limit': 100, 'fairUse': 500}, 'profile.visibility': 'ENHANCED', 'profile.photos': {'limit': 6}, 'verification.badge': True}
DUR = {'months': 3, 'durationDays': 90, 'bonusDays': 7, 'priceInPaise': 299900, 'isActive': True}


def plan(code, name, tier):
    return {'code': code, 'name': name, 'description': 'The most complete membership with every feature included for serious seekers.', 'tier': tier,
            'displayOrder': tier, 'isActive': True, 'isFree': tier == 0, 'activeSubscribers': 1234 * tier,
            'currentVersion': {'id': f'v{tier}', 'version': 3, 'effectiveFrom': NOW, 'entitlements': ENT, 'problems': []},
            'versions': [{'id': f'v{tier}', 'version': 3, 'effectiveFrom': NOW, 'changeNote': 'Raised the monthly message quota', 'createdById': 'u1', 'createdAt': NOW, 'isCurrent': True, 'isScheduled': False}],
            'durations': [{**DUR, 'id': f'd{tier}{m}', 'months': m, 'currency': 'INR', 'displayOrder': m} for m in (3, 6, 12)],
            'openDraft': {'id': 'dr1', 'status': 'DRAFT'} if tier == 2 else None}


DRAFT = {'id': 'dr1', 'planCode': 'GOLD', 'planName': 'Gold', 'status': 'DRAFT', 'changeNote': 'Raise the message quota', 'entitlements': ENT,
         'durations': [DUR], 'baseVersion': 3, 'currentVersion': 3, 'stale': False, 'createdById': 'u1', 'updatedById': 'u1', 'submittedById': None,
         'submittedAt': None, 'decidedById': None, 'decidedAt': None, 'decisionNote': None, 'publishedVersionId': None, 'createdAt': NOW, 'updatedAt': NOW,
         'review': {'entitlementProblems': [], 'durationProblems': [], 'changedFeatures': ['chat.messages'], 'reductionsVsCurrent': [],
                    'durationChanges': [], 'hasChanges': True, 'publishable': True}}

SUB = {'id': 's1', 'status': 'ACTIVE', 'source': 'PURCHASE', 'plan': {'code': 'GOLD', 'name': 'Gold'}, 'months': 6, 'startDate': NOW, 'endDate': NOW,
       'priceInPaise': 599900, 'currency': 'INR', 'cancelledAt': None, 'cancellationReason': None, 'createdAt': NOW,
       'member': {'userId': 'm1', 'email': LONG_EMAIL, 'phone': '+919876543210', 'name': LONG_NAME},
       'lastPayment': {'status': 'CAPTURED', 'amountInPaise': 599900, 'paidAt': NOW}}
SUB_DETAIL = {**SUB, 'autoRenew': False, 'activatedAt': NOW, 'planVersion': 3,
              'events': [{'id': 'e1', 'type': 'ACTIVATED', 'fromStatus': 'PENDING', 'toStatus': 'ACTIVE', 'actorId': None, 'metadata': {'razorpayOrderId': 'order_Nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'}, 'createdAt': NOW}],
              'payments': [{'id': 'pay1', 'razorpayOrderId': 'order_Nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', 'razorpayPaymentId': 'pay_Nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                            'amountInPaise': 599900, 'currency': 'INR', 'status': 'CAPTURED', 'paidAt': NOW, 'failureReason': None,
                            'refundedAmount': 0, 'refundedAt': None, 'createdAt': NOW}]}

AUDIT = {'id': 'a1', 'createdAt': NOW, 'actorId': 'u1', 'actor': LONG_EMAIL, 'action': 'subscription.admin_grant.extend_with_a_long_action_name',
         'entity': 'UserSubscription', 'entityId': '0b5e2f0e-8f5e-4a62-9d2a-6e8f1c3a7b11', 'reason': 'Customer was charged twice and the extra days were agreed on a call with support',
         'before': {'endDate': NOW}, 'after': {'endDate': NOW}, 'metadata': {}, 'requestId': 'req-1', 'ipAddress': '203.0.113.7'}

OVERVIEW = {'generatedAt': NOW, 'members': {'total': 128430, 'byStatus': {'ACTIVE': 100000, 'PENDING_VERIFICATION': 20000, 'SUSPENDED': 8430}},
            'activeSubscriptions': [{'planCode': 'GOLD', 'planName': 'Gold', 'count': 4210}, {'planCode': 'PLATINUM', 'planName': 'Platinum', 'count': 980}],
            'planDrafts': {'open': 2, 'awaitingApproval': 1},
            'revenueLast30Days': {'payments': 842, 'grossInPaise': 98765432, 'refundedInPaise': 123400}}

ROLES = {'roles': [{'key': 'SUPER_ADMIN', 'name': 'Super Admin', 'description': 'Everything, including roles.', 'isSystem': True, 'permissions': ALL_PERMS,
                    'admins': [{'email': LONG_EMAIL, 'active': True, 'authenticatorEnrolled': True, 'lastLoginAt': NOW}]}],
         'permissions': [{'key': k, 'description': 'Lets the admin ' + k.replace('.', ' ') + ' for the whole platform', 'isSensitive': k.startswith('payout')} for k in ALL_PERMS]}


def page_of(items):
    return {'items': items, 'nextCursor': 'next1'}


def route_api(route):
    req = route.request
    u = urlparse(req.url)
    path = u.path
    cors = {'access-control-allow-origin': BASE, 'access-control-allow-headers': '*', 'access-control-allow-methods': '*'}
    if req.method == 'OPTIONS':
        return route.fulfill(status=204, headers=cors)

    def ok(body, status=200):
        route.fulfill(status=status, headers=cors, content_type='application/json', body=json.dumps(body))

    if path == '/admin/me':
        return ok(ME)
    if path == '/admin/auth/session':
        return ok({'sessionToken': 'sess', 'expiresAt': NOW, 'idleTimeoutSeconds': 1800})
    if path == '/admin/overview':
        return ok(OVERVIEW)
    if path == '/admin/agents/summary':
        return ok({'byStatus': {'PENDING_APPROVAL': 4, 'ACTIVE': 120, 'REJECTED': 3, 'SUSPENDED': 1, 'TERMINATED': 0},
                   'payoutDetailsAwaitingVerification': 5, 'referralsNeedingReview': 7, 'commissionsReady': 12, 'payoutsCreated': 3})
    if path == '/admin/agents':
        return ok(page_of([agent_row(i, 'PENDING_APPROVAL' if i % 3 == 1 else 'ACTIVE') for i in range(8)]))
    if re.fullmatch(r'/admin/agents/[^/]+', path):
        return ok(AGENT_DETAIL)
    if path == '/admin/commissions':
        return ok(page_of([commission(i, ['READY', 'IN_REVIEW', 'ON_HOLD', 'FROZEN'][i % 4]) for i in range(6)]))
    if path == '/admin/payouts/payable':
        return ok(page_of([{'agentId': 'ag0', 'agentName': LONG_NAME, 'agentCode': 'NM7K2P9X', 'agentStatus': 'ACTIVE', 'period': '2026-10',
                            'balancePaise': 12345600, 'commissionCount': 12, 'panVerified': False,
                            'payoutDetails': {'method': 'BANK', 'display': 'HDFC Bank ••••4321 (HDFC0001234)', 'verifiedAt': None},
                            'eligible': False, 'reasons': ['PAN_NOT_VERIFIED', 'DETAILS_NOT_VERIFIED'], 'warnings': []}]))
    if path == '/admin/payouts':
        return ok(page_of([{**PAYOUT, 'id': f'p{i}'} for i in range(5)]))
    if re.fullmatch(r'/admin/payouts/[^/]+', path):
        return ok({**PAYOUT, 'commissions': [commission(1, 'APPROVED'), commission(2, 'APPROVED')]})
    if path == '/admin/plans':
        return ok({'plans': [plan('FREE', 'Free', 0), plan('GOLD', 'Gold', 1), plan('PLATINUM', 'Platinum', 2)], 'features': FEATURES})
    if path == '/admin/plan-drafts':
        return ok([DRAFT])
    if re.fullmatch(r'/admin/plan-drafts/[^/]+', path):
        return ok(DRAFT)
    if path == '/admin/subscriptions':
        return ok(page_of([{**SUB, 'id': f's{i}', 'status': ['ACTIVE', 'EXPIRED', 'CANCELLED'][i % 3]} for i in range(6)]))
    if re.fullmatch(r'/admin/subscriptions/[^/]+', path):
        return ok(SUB_DETAIL)
    if path == '/admin/audit-logs':
        return ok(page_of([{**AUDIT, 'id': f'a{i}'} for i in range(6)]))
    if path == '/admin/roles':
        return ok(ROLES)
    return ok({'message': f'unmocked {path}'}, 404)


def route_firebase(route):
    url = route.request.url
    if 'signInWithPassword' in url:
        body = {'kind': 'identitytoolkit#VerifyPasswordResponse', 'localId': 'u1', 'email': 'admin@nenjam.test', 'idToken': JWT,
                'refreshToken': 'r', 'expiresIn': '3600', 'registered': True}
    elif 'lookup' in url:
        body = {'users': [{'localId': 'u1', 'email': 'admin@nenjam.test', 'emailVerified': True, 'passwordHash': 'x', 'providerUserInfo': [],
                           'validSince': '1', 'lastLoginAt': '1', 'createdAt': '1'}]}
    else:
        body = {'access_token': JWT, 'id_token': JWT, 'refresh_token': 'r', 'expires_in': '3600', 'user_id': 'u1', 'token_type': 'Bearer'}
    route.fulfill(status=200, content_type='application/json', headers={'access-control-allow-origin': '*'}, body=json.dumps(body))


ROUTES = ['/', '/agents/', '/agents/view/?id=ag0', '/commissions/', '/payouts/', '/payouts/view/?id=p1', '/plans/', '/plans/draft/?id=dr1',
          '/subscriptions/', '/subscriptions/view/?id=s1', '/audit/', '/roles/']


def serve():
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a, **k):
            pass
    handler = functools.partial(Quiet, directory=ROOT)
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def new_page(browser, w, h):
    ctx = browser.new_context(viewport={'width': w, 'height': h}, has_touch=w < 1024)
    ctx.route('**/identitytoolkit.googleapis.com/**', route_firebase)
    ctx.route('**/securetoken.googleapis.com/**', route_firebase)
    ctx.route(API + '/**', route_api)
    page = ctx.new_page()
    errs = []
    page.on('console', lambda m: errs.append(m.text + ' ' + (m.location.get('url') or '')) if m.type == 'error' else None)
    page.on('pageerror', lambda e: errs.append(str(e)))
    return ctx, page, errs


def sign_in(page):
    for attempt in range(3):
        try:
            return _sign_in(page)
        except Exception:
            if attempt == 2:
                raise
            page.evaluate('sessionStorage.clear()')


def _sign_in(page):
    page.goto(BASE + '/login/')
    page.wait_for_load_state('networkidle')
    page.fill('input[type=email], input[autocomplete=username]', 'admin@nenjam.test')
    page.fill('input[type=password]', 'password123')
    page.click('button[type=submit]')
    page.wait_for_url('**/verify/**', timeout=8000)
    page.fill('input[autocomplete=one-time-code]', '123456')
    page.click('button[type=submit]')
    page.wait_for_selector('#main', timeout=8000)


def main():
    serve()
    results = []
    only = sys.argv[1:]
    with sync_playwright() as p:
        b = p.chromium.launch()
        for (w, h) in VIEWPORTS + LANDSCAPE:
            ctx, page, errs = new_page(b, w, h)
            # signed-out screens
            page.goto(BASE + '/login/')
            page.wait_for_load_state('networkidle')
            check_page(page, 'login', w, h, OUT + '/admin', results, [e for e in errs if 'identitytoolkit' not in e and 'ERR_CONNECTION_REFUSED' not in e and 'Loading chunk' not in e])
            sign_in(page)
            errs.clear()
            for r in ROUTES:
                if only and not any(o in r for o in only):
                    continue
                page.goto(BASE + r)
                page.wait_for_load_state('networkidle')
                try:
                    page.wait_for_selector('#main', timeout=6000)
                except Exception:
                    pass
                check_page(page, 'admin:' + r, w, h, OUT + '/admin', results, [e for e in errs if 'ERR_CONNECTION_REFUSED' not in e and 'Loading chunk' not in e and 'RSC payload' not in e])
                errs.clear()
            ctx.close()
        b.close()
    sys.exit(1 if report('admin', results) else 0)


main()
