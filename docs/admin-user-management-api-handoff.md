# Nenjam Matrimony Admin Panel — User Management API Handoff

**Primary Audience:** Dhatri (Frontend Developer 1 — Admin Console)  
**Secondary Audience:** Shaaz Alfaiz (Backend Developer 1 — Database & Core Domain)  
**Author:** Backend Developer 2 (Senior NestJS Backend Engineer)  
**Date:** 10 November 2026  
**Status:** Implemented & Verified on `feat/admin-user-management-api` (merged with `feat/admin-user-management-foundation`)

---

## A. Implementation Summary

Backend Developer 2 has completed the full assigned scope for the Admin User Management module without breaking existing functionality or introducing redundant infrastructure.

### 1. Responsibilities Completed
* **B-2 (DTOs & Validation):** Refined and completed `AdminUserListQueryDto` (aliased as `AdminUserListDto`), `BlockUserDto`, `UnblockUserDto`, `CreateMemberNoteDto`, and `RevealPiiDto` with class-validator, Swagger decorators, and proper string-to-boolean query transformation.
* **B-4 (`UserAdminController`):** Implemented all 7 required endpoints in `AdminUsersController` and registered the controller in `AdminModule`.
* **B-5 (Security & RBAC):** Wired `@AdminController('admin/users')` (combines `FirebaseAuthGuard` and `AdminGuard`) and applied `@RequirePermissions()` on every endpoint (`member.view`, `member.suspend`, and sensitive `member.pii.reveal`).
* **B-6 (Audit Logging & Security Context):** Verified end-to-end propagation of `@CurrentAdmin()` and `@AdminContext()` (IP address, user agent, request ID) to `AdminUsersService` for atomic transactional audit rows and Redis auth-cache invalidation.
* **B-8 (Integration & Unit Tests):** Authored integration tests (`admin-users.integration.spec.ts`) and comprehensive controller tests (`admin-users.controller.spec.ts`).
* **B-13 (Coordination):** Reviewed Backend 1's service implementation, confirmed full contract compatibility, and verified the build.

### 2. Files Created and Modified
* **Created:**
  * `backend/apps/api/src/modules/admin/controllers/admin-users.controller.ts` (7 HTTP endpoints)
  * `backend/apps/api/src/modules/admin/controllers/admin-users.controller.spec.ts` (8 unit tests)
  * `backend/apps/api/src/modules/admin/tests/admin-users.integration.spec.ts` (Supertest integration suite)
  * `docs/admin-user-management-api-handoff.md` (this documentation)
* **Modified:**
  * `backend/apps/api/src/modules/admin/dto/admin-users.dto.ts` (added `AdminUserListDto` alias & boolean query transform)
  * `backend/apps/api/src/modules/admin/admin.module.ts` (registered `AdminUsersController`)

### 3. Reused Infrastructure (No Duplicate Code)
* `@AdminController` + `@RequirePermissions` (existing Nenjam admin guard system)
* `AdminAuditService` for transactional audit logging
* `invalidateCachedUserId` via Redis for instant session termination of blocked users
* `maskEmailForDisplay` and `maskPhone` for zero-leak default presentation
* `createAdminTestApp` & `provisionAndEnrol` for test harness

---

## B. API Endpoint Reference

All endpoints are prefixed with `/admin/users` and require:
1. `Authorization: Bearer <FIREBASE_ID_TOKEN>`
2. `X-Admin-Session: <ADMIN_SESSION_TOKEN>` (obtained from `POST /admin/auth/session`)

| Method | Route | Permission | Step-Up Required? | Purpose |
|---|---|---|---|---|
| `GET` | `/admin/users` | `member.view` | No | Server-side paginated member directory with search and filters |
| `GET` | `/admin/users/stats` | `member.view` | No | Real-time aggregate counters for user dashboard cards |
| `GET` | `/admin/users/:id` | `member.view` | No | Complete 9-tab profile structure with masked contact details |
| `PATCH` | `/admin/users/:id/block` | `member.suspend` | No | Block user, update status to `BLOCKED`, write audit log, invalidate cache |
| `PATCH` | `/admin/users/:id/unblock` | `member.suspend` | No | Unblock user, restore status to `ACTIVE`, write audit log, invalidate cache |
| `POST` | `/admin/users/:id/reveal-pii` | `member.pii.reveal` | **YES** (≤10 min) | Reveal unmasked phone, email, and location; records immutable audit entry |
| `POST` | `/admin/users/:id/notes` | `member.view` | No | Add internal staff note to user profile |

---

## C. Listing and Pagination (`GET /admin/users`)

### Query Parameters
* `page` *(number, optional, default: 1)*: 1-based page index.
* `limit` *(number, optional, default: 20, min: 1, max: 100)*: Items per page.
* `search` *(string, optional, max: 100)*: Case-insensitive search matching:
  * Exact UUID (matches `user.id`)
  * Email containing search text
  * Phone digits containing search text
  * First name or Last name containing search text
* `gender` *(string, optional)*: `'MALE'` \| `'FEMALE'`.
* `membership` *(string, optional)*: Filter by active membership plan name (e.g. `'FREE'`, `'GOLD'`, `'PLATINUM'`).
* `status` *(string, optional)*: Account status: `'ACTIVE'`, `'BLOCKED'`, `'SUSPENDED'`, `'PENDING_VERIFICATION'`, `'DEACTIVATED'`, `'BANNED'`.
* `profileComplete` *(boolean, optional)*: `true` for 100% complete profiles, `false` for incomplete.
* `registeredFrom` *(string, optional, ISO 8601)*: Registered on or after this timestamp.
* `registeredTo` *(string, optional, ISO 8601)*: Registered on or before this timestamp.
* `sortBy` *(string, optional, default: 'createdAt')*: `'createdAt'` \| `'name'` \| `'status'`.
* `sortOrder` *(string, optional, default: 'desc')*: `'asc'` \| `'desc'`.

### Response Structure (`200 OK`)
```json
{
  "items": [
    {
      "id": "c1f7a28e-5d1b-4f8a-9e12-3456789abcde",
      "fullName": "Karthik Raman",
      "gender": "MALE",
      "age": 34,
      "location": "Chennai, Tamil Nadu",
      "phone": "+91 98***210",
      "email": "ka***@gmail.com",
      "membership": "Gold",
      "membershipCode": "GOLD",
      "profileStatus": "COMPLETE",
      "profileCompletePct": 100,
      "accountStatus": "ACTIVE",
      "primaryPhotoUrl": "https://cdn.nenjammatrimony.com/photos/profile1.jpg",
      "photoApproved": true,
      "registrationDate": "2026-08-15T09:30:00.000Z"
    }
  ],
  "total": 1250,
  "page": 1,
  "limit": 20,
  "totalPages": 63
}
```

---

## D. Statistics (`GET /admin/users/stats`)

Provides aggregate metrics for the cards at the top of the Users Directory page.

### Response Structure (`200 OK`)
```json
{
  "totalUsers": 1250,
  "activeUsers": 1100,
  "blockedUsers": 15,
  "registeredToday": 8,
  "incompleteProfiles": 135,
  "premiumMembers": 420
}
```

### UI Card Mapping for Dhatri
* **Total Users:** `stats.totalUsers` (All non-deleted registered users)
* **Active Users:** `stats.activeUsers` (`status: ACTIVE`)
* **Blocked Users:** `stats.blockedUsers` (`status: BLOCKED`)
* **Registered Today:** `stats.registeredToday` (Registered since midnight UTC today)
* **Incomplete Profiles:** `stats.incompleteProfiles` (Missing profile or `isProfileComplete: false`)
* **Premium Members:** `stats.premiumMembers` (Hold active paid subscription)

---

## E. User Detail Response (`GET /admin/users/:id`)

Returns comprehensive user information organized into 9 structured sections. Contacts are masked by default.

### Response Structure (`200 OK`)
```json
{
  "id": "c1f7a28e-5d1b-4f8a-9e12-3456789abcde",
  "firebaseUid": "fb-user-12345",
  "status": "ACTIVE",
  "role": "USER",
  "trustScore": 85,
  "createdAt": "2026-08-15T09:30:00.000Z",
  "updatedAt": "2026-11-01T14:20:00.000Z",

  "basicInfo": {
    "fullName": "Karthik Raman",
    "firstName": "Karthik",
    "lastName": "Raman",
    "dob": "1992-06-15T00:00:00.000Z",
    "age": 34,
    "gender": "MALE",
    "maritalStatus": "NEVER_MARRIED",
    "religion": "HINDU",
    "caste": "Brahmin",
    "subCaste": "Iyer",
    "community": "Vadama",
    "motherTongue": "Tamil",
    "languagesKnown": ["Tamil", "English"],
    "heightCm": 178,
    "weightKg": 72,
    "isProfileComplete": true,
    "profileCompletePct": 100,
    "bio": "Software engineer based in Chennai...",
    "profileCreatedAt": "2026-08-15T09:35:00.000Z",
    "profileUpdatedAt": "2026-11-01T14:20:00.000Z"
  },

  "contactInfo": {
    "phone": "+91 98***210",
    "email": "ka***@gmail.com",
    "isPhoneMasked": true,
    "isEmailMasked": true,
    "currentCity": "Chennai",
    "currentState": "Tamil Nadu",
    "country": "India",
    "nativeCity": "Madurai",
    "area": "T. Nagar",
    "pinCode": "600017"
  },

  "careerAndFamily": {
    "highestEducation": "B.Tech",
    "college": "Anna University",
    "educationDetails": "Computer Science",
    "profession": "Senior Software Engineer",
    "employerName": "Tech Corp",
    "workIndustry": "IT_SOFTWARE",
    "annualIncomeLakhs": 24,
    "familyType": "NUCLEAR",
    "familyValues": "MODERATE",
    "familyStatus": "MIDDLE_CLASS",
    "fatherOccupation": "Retired Govt Official",
    "motherOccupation": "Homemaker",
    "siblings": 1,
    "siblingDetails": ["1 younger sister (married)"],
    "dietaryHabits": "VEGETARIAN",
    "smokingHabits": "NO",
    "drinkingHabits": "NO"
  },

  "partnerPreferences": {
    "minAge": 24,
    "maxAge": 30,
    "minHeightCm": 160,
    "maxHeightCm": 175,
    "preferredReligions": ["HINDU"],
    "preferredCastes": ["Brahmin"],
    "minIncomeLakhs": 10,
    "preferredCities": ["Chennai", "Bangalore"],
    "preferredStates": ["Tamil Nadu", "Karnataka"]
  },

  "astrologyProfile": {
    "rasi": "MESHA",
    "nakshatra": "ASHWINI",
    "dosham": "NO_DOSHAM",
    "lagnam": "MESHA",
    "gotram": "KASHYAPA",
    "birthDate": "1992-06-15T00:00:00.000Z",
    "birthTime": "06:45:00",
    "birthPlace": "Madurai, Tamil Nadu"
  },

  "membership": {
    "currentPlan": "Gold",
    "currentPlanCode": "GOLD",
    "subscriptionStatus": "ACTIVE",
    "startDate": "2026-09-01T00:00:00.000Z",
    "expiryDate": "2026-12-01T00:00:00.000Z",
    "autoRenew": true,
    "history": [
      {
        "id": "sub-12345",
        "planName": "Gold",
        "planCode": "GOLD",
        "tier": 2,
        "status": "ACTIVE",
        "startDate": "2026-09-01T00:00:00.000Z",
        "endDate": "2026-12-01T00:00:00.000Z",
        "autoRenew": true,
        "createdAt": "2026-09-01T00:00:00.000Z",
        "payments": [
          {
            "id": "pay-987",
            "amountInr": "2999.00",
            "currency": "INR",
            "status": "SUCCESS",
            "paidAt": "2026-09-01T00:02:00.000Z",
            "createdAt": "2026-09-01T00:00:30.000Z"
          }
        ]
      }
    ]
  },

  "photosAndMedia": {
    "primaryPhotoUrl": "https://cdn.nenjammatrimony.com/photos/profile1.jpg",
    "photos": [
      {
        "id": "photo-001",
        "cdnUrl": "https://cdn.nenjammatrimony.com/photos/profile1.jpg",
        "isPrimary": true,
        "order": 1,
        "isApproved": true,
        "createdAt": "2026-08-15T10:00:00.000Z"
      }
    ],
    "verification": {
      "faceVerified": true,
      "faceVerificationStatus": "VERIFIED",
      "kycVerifications": [
        {
          "id": "kyc-001",
          "docType": "AADHAAR",
          "status": "APPROVED",
          "rejectionReason": null,
          "createdAt": "2026-08-16T11:00:00.000Z"
        }
      ]
    }
  },

  "internalNotes": [
    {
      "id": "note-001",
      "authorId": "admin-111",
      "authorName": "ops@nenjammatrimony.com",
      "note": "Document verified on phone.",
      "createdAt": "2026-08-16T12:00:00.000Z",
      "updatedAt": "2026-08-16T12:00:00.000Z"
    }
  ],

  "supportTickets": [
    {
      "id": "ticket-001",
      "type": "CONTACT_SUPPORT",
      "subject": "Photo upload inquiry",
      "status": "RESOLVED",
      "adminResponse": "Supported photo formats: JPEG, PNG.",
      "createdAt": "2026-08-17T14:00:00.000Z"
    }
  ],

  "accountActivity": {
    "registrationDate": "2026-08-15T09:30:00.000Z",
    "lastProfileUpdate": "2026-11-01T14:20:00.000Z",
    "trustScore": 85,
    "trustScoreHistory": [],
    "blocksMadeCount": 2,
    "blocksReceivedCount": 0,
    "reportsMadeCount": 0,
    "reportsAgainstCount": 0
  }
}
```

### Tab Mapping to Dhatri's Expected UI
| UI Tab | Backend Data Source |
|---|---|
| **1. Basic Info** | `data.basicInfo` |
| **2. Contact Info** | `data.contactInfo` |
| **3. Career & Family** | `data.careerAndFamily` |
| **4. Partner Preferences** | `data.partnerPreferences` |
| **5. Astrology** | `data.astrologyProfile` |
| **6. Subscriptions & Payments** | `data.membership` |
| **7. Photos & Verification** | `data.photosAndMedia` |
| **8. Internal Notes** | `data.internalNotes` |
| **9. Account Activity & Support** | `data.accountActivity` & `data.supportTickets` |

---

## F. Block / Unblock Workflow

### 1. Block User (`PATCH /admin/users/:id/block`)
* **Permission:** `member.suspend`
* **Request Body:**
  ```json
  {
    "reason": "Suspicious fraudulent activity reported by multiple users"
  }
  ```
  *(Mandatory, length: 3–500 characters)*
* **Response (`200 OK`):**
  ```json
  {
    "success": true,
    "userId": "c1f7a28e-5d1b-4f8a-9e12-3456789abcde",
    "previousStatus": "ACTIVE",
    "status": "BLOCKED",
    "reason": "Suspicious fraudulent activity reported by multiple users"
  }
  ```
* **Potential Errors:**
  * `400 Bad Request`: Reason missing or fewer than 3 characters (`VALIDATION_FAILED`)
  * `403 Forbidden`: Admin lacks `member.suspend` permission (`ADMIN_PERMISSION_DENIED`)
  * `404 Not Found`: Member account not found or deleted
  * `409 Conflict`: User is already blocked (`User is already blocked.`)

### 2. Unblock User (`PATCH /admin/users/:id/unblock`)
* **Permission:** `member.suspend`
* **Request Body:**
  ```json
  {
    "reason": "Identity documents verified by customer support"
  }
  ```
  *(Optional, max: 500 characters)*
* **Response (`200 OK`):**
  ```json
  {
    "success": true,
    "userId": "c1f7a28e-5d1b-4f8a-9e12-3456789abcde",
    "previousStatus": "BLOCKED",
    "status": "ACTIVE"
  }
  ```
* **Potential Errors:**
  * `400 Bad Request`: User is not currently blocked (`User is not blocked.`)
  * `403 Forbidden`: Admin lacks `member.suspend`
  * `404 Not Found`: User not found

### Frontend Refresh Behavior
After block or unblock succeeds, the frontend should:
1. Refresh the user details or mutate local state to show the updated `status` badge.
2. Invalidate/refetch `GET /admin/users/stats` to update dashboard counter cards.
3. Invalidate/refetch `GET /admin/users` query cache.

---

## G. PII Reveal Workflow (`POST /admin/users/:id/reveal-pii`)

Used when staff need to inspect actual contact numbers or unmasked emails for verified dispute resolution or fraud investigation.

* **Permission:** `member.pii.reveal`
* **Step-Up Requirement:** **Mandatory.** The staff member's session must have verified an authenticator code within the last 10 minutes. If older, the API responds with:
  ```json
  {
    "statusCode": 401,
    "error": "Unauthorized",
    "code": "ADMIN_STEP_UP_REQUIRED",
    "message": "This action needs a fresh code from your authenticator app."
  }
  ```
  When this happens, the frontend should trigger its existing step-up dialog (`POST /admin/auth/step-up`), and then re-issue the reveal request.

* **Request Body:**
  ```json
  {
    "reason": "Dispute investigation ticket #4582"
  }
  ```
  *(Optional string, max 500 characters)*

* **Response (`200 OK`):**
  ```json
  {
    "userId": "c1f7a28e-5d1b-4f8a-9e12-3456789abcde",
    "email": "karthik.raman@gmail.com",
    "phone": "+919876543210",
    "location": {
      "city": "Chennai",
      "state": "Tamil Nadu",
      "country": "India",
      "pinCode": "600017"
    }
  }
  ```

* **Frontend Security Rules for PII:**
  * Display revealed PII in-place or in a temporary reveal modal.
  * Never cache or persist unmasked PII in `localStorage` or `sessionStorage`.
  * Every reveal is immutably logged in `audit_logs` with the staff actor's ID and IP.

---

## H. Internal Staff Notes (`POST /admin/users/:id/notes`)

Internal notes allow operations and moderation staff to record case notes directly on a user's record.

* **Permission:** `member.view`
* **Request Body:**
  ```json
  {
    "note": "Spoke to the user. Verified graduation certificate with college registrar."
  }
  ```
  *(Mandatory, length: 1–5000 characters)*

* **Response (`201 Created`):**
  ```json
  {
    "id": "e6a2b89f-8c3d-4e5a-9b12-7890abcdef12",
    "userId": "c1f7a28e-5d1b-4f8a-9e12-3456789abcde",
    "authorId": "admin-user-456",
    "authorName": "ops@nenjammatrimony.com",
    "note": "Spoke to the user. Verified graduation certificate with college registrar.",
    "createdAt": "2026-11-10T08:15:00.000Z"
  }
  ```

* **Frontend Integration:**
  * Append the new note immediately to the top of `data.internalNotes` in the "Internal Notes" tab.
  * Notes display `note`, `authorName`, and relative timestamp (`createdAt`).

---

## I. Frontend Security Instructions

1. **Deny by Default:** Do not show administrative action buttons (Block, Reveal PII) if the current admin session's permissions (from `GET /admin/me`) do not include `member.suspend` or `member.pii.reveal`.
2. **Handle 401 Step-Up Gracefully:** On `code === 'ADMIN_STEP_UP_REQUIRED'`, prompt for the 6-digit TOTP code, call `POST /admin/auth/step-up`, and repeat the user action automatically upon success.
3. **No Unmasked PII in Browser Storage:** Masked fields (`ka***@gmail.com`, `+91 98***210`) are safe for UI rendering. Unmasked values returned by `reveal-pii` must remain in volatile React state only.
4. **Cache Invalidation:** Block operations invalidate the Redis cache on the server, cutting off user access instantly. The frontend does not need to manage Redis.

---

## J. Integration Checklist for Dhatri

- [ ] **Directory Page (`/users/`):**
  - [ ] Connect `GET /admin/users/stats` to summary cards.
  - [ ] Connect `GET /admin/users` to table component with query params `page`, `limit`, `search`, `status`, `membership`, `gender`, `profileComplete`.
  - [ ] Wire server-side pagination with `totalPages` and `total`.
- [ ] **User Details Page (`/users/[userId]`):**
  - [ ] Connect `GET /admin/users/:userId` on page load.
  - [ ] Render 9 tabs: Basic Info, Contact Info, Career & Family, Partner Preferences, Astrology, Subscriptions & Payments, Photos & Verification, Internal Notes, Account Activity.
- [ ] **Actions:**
  - [ ] Block User dialog with mandatory `reason` calling `PATCH /admin/users/:id/block`.
  - [ ] Unblock User confirmation dialog calling `PATCH /admin/users/:id/unblock`.
  - [ ] "Reveal PII" button calling `POST /admin/users/:id/reveal-pii`, handling step-up challenge when 401 returned.
  - [ ] "Add Note" form calling `POST /admin/users/:id/notes`, refetching or appending to note list.

---

## K. Backend Verification

1. **Prisma Schema & Migrations:**
   * `BLOCKED` enum value deployed in migration `20261110070820_add_user_status_blocked_and_member_notes`.
   * `MemberNote` model deployed and verified.
   * Prisma client generated (`@prisma/client v7.8.0`).
2. **Unit Tests Passing:**
   * `admin-users.service.spec.ts`: **15 passed, 15 total**.
   * `admin-users.controller.spec.ts`: **8 passed, 8 total**.
   * `admin-route-check.spec.ts`: **2 passed, 2 total** (validates all routes have explicit permissions).
   * `permissions.spec.ts`: **3 passed, 3 total** (validates RBAC registry consistency).
3. **Total Admin Module Test Suite:**
   * **11 suites passed, 74 tests passed, 0 failures**.
4. **Build Status:**
   * `nest build api` (webpack 5.106.2): **Compiled successfully in 44.7s with 0 errors**.

---

## L. Coordination Notes for Shaaz

* `AdminUsersService` is used as authored with zero breaking modifications.
* Parameter orders in `AdminUsersController` strictly adhere to `AdminUsersService` method signatures:
  * `blockUser(id, admin, body.reason, context)`
  * `unblockUser(id, admin, context, body.reason)`
  * `revealPii(id, admin, context, body.reason)`
  * `addNote(id, admin, body.note)`
* Added `AdminUserListDto` alias in `admin-users.dto.ts` alongside `AdminUserListQueryDto` and implemented boolean transformation for query parameters.
* Controller registered in `AdminModule` under `controllers: [...]`.
* All database transactions, Redis invalidations, and audit entries continue to run through your service methods without duplication.
