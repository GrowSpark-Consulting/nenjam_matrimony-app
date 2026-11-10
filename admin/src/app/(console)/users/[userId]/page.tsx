'use client';

import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { Suspense, useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Badge,
  Button,
  Card,
  ConfirmDialog,
  EmptyState,
  ErrorState,
  Field,
  Loading,
  Notice,
  PageHeader,
  useToast,
} from '@/components/ui';
import { formatDate, formatDateTime, humanize } from '@/lib/format';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type {
  AdminUserDetail,
  BlockUserResult,
  MemberNoteResult,
  RevealPiiResult,
  UnblockUserResult,
} from '@/lib/types';
import { useApi } from '@/lib/use-api';

type TabKey =
  | 'basic'
  | 'matrimony'
  | 'preferences'
  | 'membership'
  | 'photos'
  | 'activity'
  | 'notes';

export default function UserDetailPage() {
  return (
    <RequirePermission permission="member.view">
      <Suspense fallback={<Loading label="Loading member details…" />}>
        <UserDetailLoader />
      </Suspense>
    </RequirePermission>
  );
}

function UserDetailLoader() {
  const params = useParams();
  const userId = typeof params.userId === 'string' ? params.userId : '';

  if (!userId) {
    return <ErrorState message="No member ID provided in route." />;
  }

  return <UserDetailView userId={userId} />;
}

function UserDetailView({ userId }: { userId: string }) {
  const router = useRouter();
  const { api, me } = useSession();
  const toast = useToast();

  const [activeTab, setActiveTab] = useState<TabKey>('basic');
  const [pendingAction, setPendingAction] = useState<
    'block' | 'unblock' | 'reveal' | null
  >(null);

  // Volatile revealed PII state (never stored in localStorage or URL)
  const [revealedPii, setRevealedPii] = useState<RevealPiiResult | null>(null);

  // New note form state
  const [noteContent, setNoteContent] = useState('');
  const [noteBusy, setNoteBusy] = useState(false);
  const [noteError, setNoteError] = useState<string | null>(null);

  const canSuspend = can(me?.permissions, 'member.suspend');
  const canReveal = can(me?.permissions, 'member.pii.reveal');

  const userQuery = useApi(
    (client) => client.get<AdminUserDetail>(`/admin/users/${userId}`),
    [userId],
  );

  const user = userQuery.data;

  if (userQuery.loading && !user) {
    return <Loading label="Loading member profile…" />;
  }

  if (userQuery.error) {
    return (
      <ErrorState
        message={userQuery.error}
        onRetry={userQuery.reload}
      />
    );
  }

  if (!user) return null;

  const handleBlockConfirm = async (reason: string) => {
    try {
      await api.patch<BlockUserResult>(`/admin/users/${user.id}/block`, {
        reason,
      });
      toast('success', `Member ${user.basicInfo.fullName || user.id} blocked successfully.`);
      userQuery.reload();
    } catch (err) {
      toast('error', err instanceof Error ? err.message : 'Failed to block member.');
      throw err;
    }
  };

  const handleUnblockConfirm = async (reason: string) => {
    try {
      await api.patch<UnblockUserResult>(`/admin/users/${user.id}/unblock`, {
        reason: reason.trim() || undefined,
      });
      toast('success', `Member ${user.basicInfo.fullName || user.id} unblocked.`);
      userQuery.reload();
    } catch (err) {
      toast('error', err instanceof Error ? err.message : 'Failed to unblock member.');
      throw err;
    }
  };

  const handleRevealConfirm = async (reason: string) => {
    try {
      const res = await api.post<RevealPiiResult>(
        `/admin/users/${user.id}/reveal-pii`,
        { reason: reason.trim() || undefined },
      );
      setRevealedPii(res);
      toast('success', 'Contact details revealed. Audit log recorded.');
    } catch (err) {
      toast('error', err instanceof Error ? err.message : 'Failed to reveal PII.');
      throw err;
    }
  };

  const handleAddNoteSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!noteContent.trim()) return;
    setNoteBusy(true);
    setNoteError(null);
    try {
      const newNote = await api.post<MemberNoteResult>(
        `/admin/users/${user.id}/notes`,
        { note: noteContent.trim() },
      );
      toast('success', 'Internal note added.');
      setNoteContent('');
      userQuery.setData({
        ...user,
        internalNotes: [
          {
            id: newNote.id,
            authorId: newNote.authorId,
            authorName: newNote.authorName,
            note: newNote.note,
            createdAt: newNote.createdAt,
            updatedAt: newNote.createdAt,
          },
          ...user.internalNotes,
        ],
      });
    } catch (err) {
      setNoteError(err instanceof Error ? err.message : 'Failed to save note.');
    } finally {
      setNoteBusy(false);
    }
  };

  // Contacts: unmasked if revealed, else masked from backend
  const displayPhone = revealedPii?.phone ?? user.contactInfo.phone ?? '—';
  const displayEmail = revealedPii?.email ?? user.contactInfo.email ?? '—';
  const isPhoneUnmasked = Boolean(revealedPii?.phone);
  const isEmailUnmasked = Boolean(revealedPii?.email);

  return (
    <>
      <PageHeader
        title={user.basicInfo.fullName || 'Member Profile'}
        description={
          <>
            <Badge value={user.status} /> · Registered {formatDate(user.createdAt)} ·{' '}
            Trust Score: <strong>{user.trustScore}</strong> · ID: <code>{user.id}</code>
          </>
        }
        actions={
          <div className="row-actions">
            <Link href="/users/">
              <Button tone="secondary">Back to Members</Button>
            </Link>

            {canReveal && !revealedPii ? (
              <Button
                tone="ghost"
                onClick={() => setPendingAction('reveal')}
              >
                Reveal PII
              </Button>
            ) : null}

            {canSuspend ? (
              user.status === 'BLOCKED' ? (
                <Button
                  tone="primary"
                  onClick={() => setPendingAction('unblock')}
                >
                  Unblock User
                </Button>
              ) : (
                <Button
                  tone="danger"
                  onClick={() => setPendingAction('block')}
                >
                  Block User
                </Button>
              )
            ) : null}
          </div>
        }
      />

      {/* Notice if PII is revealed */}
      {revealedPii ? (
        <Notice tone="warn">
          <strong>Sensitive PII Unmasked:</strong> Full phone and email are currently
          displayed. This access was audited under your staff account. Values are kept in
          volatile memory only.
        </Notice>
      ) : null}

      {/* Tab Navigation */}
      <div
        className="row-actions"
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '0.4rem',
          marginBottom: '1rem',
          borderBottom: '1px solid var(--border)',
          paddingBottom: '0.75rem',
        }}
      >
        <Button
          tone={activeTab === 'basic' ? 'primary' : 'ghost'}
          onClick={() => setActiveTab('basic')}
        >
          Basic & Contact
        </Button>
        <Button
          tone={activeTab === 'matrimony' ? 'primary' : 'ghost'}
          onClick={() => setActiveTab('matrimony')}
        >
          Career & Family
        </Button>
        <Button
          tone={activeTab === 'preferences' ? 'primary' : 'ghost'}
          onClick={() => setActiveTab('preferences')}
        >
          Preferences & Astrology
        </Button>
        <Button
          tone={activeTab === 'membership' ? 'primary' : 'ghost'}
          onClick={() => setActiveTab('membership')}
        >
          Subscriptions & Payments
        </Button>
        <Button
          tone={activeTab === 'photos' ? 'primary' : 'ghost'}
          onClick={() => setActiveTab('photos')}
        >
          Photos & Verification
        </Button>
        <Button
          tone={activeTab === 'activity' ? 'primary' : 'ghost'}
          onClick={() => setActiveTab('activity')}
        >
          Activity & Support
        </Button>
        <Button
          tone={activeTab === 'notes' ? 'primary' : 'ghost'}
          onClick={() => setActiveTab('notes')}
        >
          Internal Notes ({user.internalNotes.length})
        </Button>
      </div>

      {/* TAB 1: BASIC & CONTACT INFORMATION */}
      {activeTab === 'basic' ? (
        <div className="grid">
          <Card title="Basic Profile">
            <ul className="kv">
              <li>
                <span>Full Name</span>
                <span>{user.basicInfo.fullName || '—'}</span>
              </li>
              <li>
                <span>Gender & Age</span>
                <span>
                  {user.basicInfo.gender ? humanize(user.basicInfo.gender) : '—'}
                  {user.basicInfo.age ? ` · ${user.basicInfo.age} yrs` : ''}
                </span>
              </li>
              <li>
                <span>Date of Birth</span>
                <span>{formatDate(user.basicInfo.dob)}</span>
              </li>
              <li>
                <span>Marital Status</span>
                <span>
                  {user.basicInfo.maritalStatus
                    ? humanize(user.basicInfo.maritalStatus)
                    : '—'}
                </span>
              </li>
              <li>
                <span>Religion</span>
                <span>{user.basicInfo.religion || '—'}</span>
              </li>
              <li>
                <span>Caste / Sub-Caste</span>
                <span>
                  {[user.basicInfo.caste, user.basicInfo.subCaste]
                    .filter(Boolean)
                    .join(' · ') || '—'}
                </span>
              </li>
              <li>
                <span>Community</span>
                <span>{user.basicInfo.community || '—'}</span>
              </li>
              <li>
                <span>Mother Tongue</span>
                <span>{user.basicInfo.motherTongue || '—'}</span>
              </li>
              <li>
                <span>Languages Known</span>
                <span>
                  {user.basicInfo.languagesKnown.length > 0
                    ? user.basicInfo.languagesKnown.join(', ')
                    : '—'}
                </span>
              </li>
              <li>
                <span>Height & Weight</span>
                <span>
                  {user.basicInfo.heightCm ? `${user.basicInfo.heightCm} cm` : '—'}
                  {user.basicInfo.weightKg ? ` · ${user.basicInfo.weightKg} kg` : ''}
                </span>
              </li>
              <li>
                <span>Profile Completeness</span>
                <span>
                  <Badge
                    value={user.basicInfo.isProfileComplete ? 'COMPLETE' : 'INCOMPLETE'}
                    label={`${user.basicInfo.profileCompletePct}%`}
                  />
                </span>
              </li>
              {user.basicInfo.bio ? (
                <li style={{ flexDirection: 'column', alignItems: 'flex-start', gap: '0.3rem' }}>
                  <span style={{ fontWeight: 600 }}>About Me / Bio</span>
                  <p style={{ margin: 0 }} className="muted small">
                    {user.basicInfo.bio}
                  </p>
                </li>
              ) : null}
            </ul>
          </Card>

          <Card
            title="Contact Information"
            actions={
              canReveal && !revealedPii ? (
                <Button
                  tone="ghost"
                  className="small"
                  onClick={() => setPendingAction('reveal')}
                >
                  Reveal Contact Details
                </Button>
              ) : null
            }
          >
            <ul className="kv">
              <li>
                <span>Phone Number</span>
                <span>
                  {displayPhone}{' '}
                  {isPhoneUnmasked ? (
                    <Badge value="APPROVED" label="UNMASKED" />
                  ) : (
                    <span className="muted small">(masked)</span>
                  )}
                </span>
              </li>
              <li>
                <span>Email Address</span>
                <span>
                  {displayEmail}{' '}
                  {isEmailUnmasked ? (
                    <Badge value="APPROVED" label="UNMASKED" />
                  ) : (
                    <span className="muted small">(masked)</span>
                  )}
                </span>
              </li>
              <li>
                <span>Current Location</span>
                <span>
                  {[user.contactInfo.currentCity, user.contactInfo.currentState, user.contactInfo.country]
                    .filter(Boolean)
                    .join(', ') || '—'}
                </span>
              </li>
              <li>
                <span>Native City</span>
                <span>{user.contactInfo.nativeCity || '—'}</span>
              </li>
              <li>
                <span>Area & PIN</span>
                <span>
                  {[user.contactInfo.area, user.contactInfo.pinCode]
                    .filter(Boolean)
                    .join(' · ') || '—'}
                </span>
              </li>
            </ul>
          </Card>
        </div>
      ) : null}

      {/* TAB 2: CAREER & FAMILY */}
      {activeTab === 'matrimony' ? (
        <div className="grid">
          <Card title="Education & Profession">
            <ul className="kv">
              <li>
                <span>Highest Education</span>
                <span>{user.careerAndFamily.highestEducation || '—'}</span>
              </li>
              <li>
                <span>College / University</span>
                <span>{user.careerAndFamily.college || '—'}</span>
              </li>
              <li>
                <span>Education Details</span>
                <span>{user.careerAndFamily.educationDetails || '—'}</span>
              </li>
              <li>
                <span>Profession</span>
                <span>{user.careerAndFamily.profession || '—'}</span>
              </li>
              <li>
                <span>Employer Name</span>
                <span>{user.careerAndFamily.employerName || '—'}</span>
              </li>
              <li>
                <span>Work Industry</span>
                <span>
                  {user.careerAndFamily.workIndustry
                    ? humanize(user.careerAndFamily.workIndustry)
                    : '—'}
                </span>
              </li>
              <li>
                <span>Annual Income</span>
                <span>
                  {user.careerAndFamily.annualIncomeLakhs !== null
                    ? `₹ ${user.careerAndFamily.annualIncomeLakhs} Lakhs / yr`
                    : '—'}
                </span>
              </li>
            </ul>
          </Card>

          <Card title="Family & Lifestyle">
            <ul className="kv">
              <li>
                <span>Family Type</span>
                <span>
                  {user.careerAndFamily.familyType
                    ? humanize(user.careerAndFamily.familyType)
                    : '—'}
                </span>
              </li>
              <li>
                <span>Family Values</span>
                <span>
                  {user.careerAndFamily.familyValues
                    ? humanize(user.careerAndFamily.familyValues)
                    : '—'}
                </span>
              </li>
              <li>
                <span>Family Status</span>
                <span>
                  {user.careerAndFamily.familyStatus
                    ? humanize(user.careerAndFamily.familyStatus)
                    : '—'}
                </span>
              </li>
              <li>
                <span>Father’s Occupation</span>
                <span>{user.careerAndFamily.fatherOccupation || '—'}</span>
              </li>
              <li>
                <span>Mother’s Occupation</span>
                <span>{user.careerAndFamily.motherOccupation || '—'}</span>
              </li>
              <li>
                <span>Siblings</span>
                <span>
                  {user.careerAndFamily.siblings}{' '}
                  {user.careerAndFamily.siblingDetails.length > 0
                    ? `(${user.careerAndFamily.siblingDetails.join(', ')})`
                    : ''}
                </span>
              </li>
              <li>
                <span>Dietary Habits</span>
                <span>
                  {user.careerAndFamily.dietaryHabits
                    ? humanize(user.careerAndFamily.dietaryHabits)
                    : '—'}
                </span>
              </li>
              <li>
                <span>Smoking / Drinking</span>
                <span>
                  {[user.careerAndFamily.smokingHabits, user.careerAndFamily.drinkingHabits]
                    .filter(Boolean)
                    .map((s) => humanize(s!))
                    .join(' · ') || '—'}
                </span>
              </li>
            </ul>
          </Card>
        </div>
      ) : null}

      {/* TAB 3: PREFERENCES & ASTROLOGY */}
      {activeTab === 'preferences' ? (
        <div className="grid">
          <Card title="Partner Preferences">
            {user.partnerPreferences ? (
              <ul className="kv">
                <li>
                  <span>Age Range</span>
                  <span>
                    {user.partnerPreferences.minAge || 'Any'} –{' '}
                    {user.partnerPreferences.maxAge || 'Any'} yrs
                  </span>
                </li>
                <li>
                  <span>Height Range</span>
                  <span>
                    {user.partnerPreferences.minHeightCm
                      ? `${user.partnerPreferences.minHeightCm} cm`
                      : 'Any'}{' '}
                    –{' '}
                    {user.partnerPreferences.maxHeightCm
                      ? `${user.partnerPreferences.maxHeightCm} cm`
                      : 'Any'}
                  </span>
                </li>
                <li>
                  <span>Preferred Religions</span>
                  <span>
                    {user.partnerPreferences.preferredReligions.join(', ') || 'Any'}
                  </span>
                </li>
                <li>
                  <span>Preferred Castes</span>
                  <span>
                    {user.partnerPreferences.preferredCastes.join(', ') || 'Any'}
                  </span>
                </li>
                <li>
                  <span>Min Annual Income</span>
                  <span>
                    {user.partnerPreferences.minIncomeLakhs !== null
                      ? `₹ ${user.partnerPreferences.minIncomeLakhs} Lakhs+`
                      : 'Any'}
                  </span>
                </li>
                <li>
                  <span>Preferred Locations</span>
                  <span>
                    {[
                      user.partnerPreferences.preferredCities.join(', '),
                      user.partnerPreferences.preferredStates.join(', '),
                    ]
                      .filter(Boolean)
                      .join(' | ') || 'Any'}
                  </span>
                </li>
              </ul>
            ) : (
              <EmptyState title="No partner preferences specified" />
            )}
          </Card>

          <Card title="Astrology Details">
            {user.astrologyProfile ? (
              <ul className="kv">
                <li>
                  <span>Rasi (Moon Sign)</span>
                  <span>{user.astrologyProfile.rasi || '—'}</span>
                </li>
                <li>
                  <span>Nakshatra (Star)</span>
                  <span>{user.astrologyProfile.nakshatra || '—'}</span>
                </li>
                <li>
                  <span>Dosham</span>
                  <span>
                    {user.astrologyProfile.dosham
                      ? humanize(user.astrologyProfile.dosham)
                      : 'None'}
                  </span>
                </li>
                <li>
                  <span>Lagnam</span>
                  <span>{user.astrologyProfile.lagnam || '—'}</span>
                </li>
                <li>
                  <span>Gotram</span>
                  <span>{user.astrologyProfile.gotram || '—'}</span>
                </li>
                <li>
                  <span>Birth Time & Place</span>
                  <span>
                    {[user.astrologyProfile.birthTime, user.astrologyProfile.birthPlace]
                      .filter(Boolean)
                      .join(' · ') || '—'}
                  </span>
                </li>
              </ul>
            ) : (
              <EmptyState title="No astrology profile available" />
            )}
          </Card>
        </div>
      ) : null}

      {/* TAB 4: MEMBERSHIP & PAYMENTS */}
      {activeTab === 'membership' ? (
        <>
          <div className="grid">
            <Card title="Current Subscription">
              <ul className="kv">
                <li>
                  <span>Plan</span>
                  <span>
                    <Badge
                      value={user.membership.currentPlanCode}
                      label={user.membership.currentPlan}
                    />
                  </span>
                </li>
                <li>
                  <span>Status</span>
                  <span>
                    <Badge value={user.membership.subscriptionStatus} />
                  </span>
                </li>
                <li>
                  <span>Start Date</span>
                  <span>{formatDate(user.membership.startDate)}</span>
                </li>
                <li>
                  <span>Expiry Date</span>
                  <span>{formatDate(user.membership.expiryDate)}</span>
                </li>
                <li>
                  <span>Auto Renewal</span>
                  <span>{user.membership.autoRenew ? 'Enabled' : 'Disabled'}</span>
                </li>
              </ul>
            </Card>

            <Card title="Plan Privileges">
              <p className="muted small">
                Active paid subscribers can send unlimited direct connection requests, view
                unblurred family photos, and access matching horoscopes.
              </p>
            </Card>
          </div>

          <Card title="Subscription History">
            {user.membership.history.length === 0 ? (
              <EmptyState title="No past subscriptions recorded" />
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Plan</th>
                      <th scope="col">Tier</th>
                      <th scope="col">Status</th>
                      <th scope="col">Period</th>
                      <th scope="col">Auto Renew</th>
                      <th scope="col">Created</th>
                    </tr>
                  </thead>
                  <tbody>
                    {user.membership.history.map((sub) => (
                      <tr key={sub.id}>
                        <td>
                          <strong>{sub.planName}</strong>
                        </td>
                        <td>Tier {sub.tier}</td>
                        <td>
                          <Badge value={sub.status} />
                        </td>
                        <td>
                          {formatDate(sub.startDate)} – {formatDate(sub.endDate)}
                        </td>
                        <td>{sub.autoRenew ? 'Yes' : 'No'}</td>
                        <td className="nowrap">{formatDate(sub.createdAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>

          <Card title="Payment Transactions">
            {user.membership.history.flatMap((h) => h.payments).length === 0 ? (
              <EmptyState title="No payment transactions recorded" />
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Payment ID</th>
                      <th scope="col">Amount</th>
                      <th scope="col">Currency</th>
                      <th scope="col">Status</th>
                      <th scope="col">Paid Date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {user.membership.history
                      .flatMap((h) => h.payments)
                      .map((pay) => (
                        <tr key={pay.id}>
                          <td>
                            <code>{pay.id}</code>
                          </td>
                          <td>
                            <strong>₹ {pay.amountInr}</strong>
                          </td>
                          <td>{pay.currency}</td>
                          <td>
                            <Badge value={pay.status} />
                          </td>
                          <td className="nowrap">{formatDateTime(pay.paidAt)}</td>
                        </tr>
                      ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </>
      ) : null}

      {/* TAB 5: PHOTOS & VERIFICATION */}
      {activeTab === 'photos' ? (
        <>
          <Card title="Photos & Gallery">
            {user.photosAndMedia.photos.length === 0 ? (
              <EmptyState title="No profile photos uploaded yet" />
            ) : (
              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
                  gap: '1rem',
                  marginTop: '0.5rem',
                }}
              >
                {user.photosAndMedia.photos.map((photo) => (
                  <div
                    key={photo.id}
                    style={{
                      border: '1px solid var(--border)',
                      borderRadius: 'var(--radius)',
                      padding: '0.5rem',
                      background: 'var(--surface)',
                      display: 'flex',
                      flexDirection: 'column',
                      gap: '0.4rem',
                    }}
                  >
                    <div
                      style={{
                        position: 'relative',
                        width: '100%',
                        height: '180px',
                        borderRadius: '4px',
                        overflow: 'hidden',
                        background: 'var(--neutral-bg)',
                      }}
                    >
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={photo.cdnUrl}
                        alt="Profile photograph"
                        style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                      />
                    </div>
                    <div
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                      }}
                    >
                      {photo.isPrimary ? (
                        <Badge value="APPROVED" label="PRIMARY" />
                      ) : (
                        <span className="muted small">Photo #{photo.order}</span>
                      )}
                      <Badge
                        value={photo.isApproved ? 'ACTIVE' : 'PENDING'}
                        label={photo.isApproved ? 'Approved' : 'Pending'}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>

          <div className="grid">
            <Card title="Face Verification">
              <ul className="kv">
                <li>
                  <span>Face Verified</span>
                  <span>
                    <Badge
                      value={user.photosAndMedia.verification.faceVerified ? 'APPROVED' : 'PENDING'}
                      label={user.photosAndMedia.verification.faceVerificationStatus}
                    />
                  </span>
                </li>
              </ul>
            </Card>

            <Card title="Identity (KYC) Documents">
              {user.photosAndMedia.verification.kycVerifications.length === 0 ? (
                <EmptyState title="No identity documents submitted" />
              ) : (
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th scope="col">Document</th>
                        <th scope="col">Status</th>
                        <th scope="col">Reason / Notes</th>
                        <th scope="col">Date</th>
                      </tr>
                    </thead>
                    <tbody>
                      {user.photosAndMedia.verification.kycVerifications.map((kyc) => (
                        <tr key={kyc.id}>
                          <td>{humanize(kyc.docType)}</td>
                          <td>
                            <Badge value={kyc.status} />
                          </td>
                          <td>{kyc.rejectionReason || '—'}</td>
                          <td className="nowrap">{formatDate(kyc.createdAt)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>
          </div>
        </>
      ) : null}

      {/* TAB 6: ACTIVITY & SUPPORT */}
      {activeTab === 'activity' ? (
        <>
          <div className="grid">
            <Card title="Account Details">
              <ul className="kv">
                <li>
                  <span>User ID</span>
                  <code>{user.id}</code>
                </li>
                <li>
                  <span>Firebase UID</span>
                  <code>{user.firebaseUid}</code>
                </li>
                <li>
                  <span>Account Status</span>
                  <span>
                    <Badge value={user.status} />
                  </span>
                </li>
                <li>
                  <span>Trust Score</span>
                  <span>
                    <strong>{user.trustScore} / 100</strong>
                  </span>
                </li>
                <li>
                  <span>Registration Date</span>
                  <span>{formatDateTime(user.accountActivity.registrationDate)}</span>
                </li>
                <li>
                  <span>Last Profile Update</span>
                  <span>{formatDateTime(user.accountActivity.lastProfileUpdate)}</span>
                </li>
              </ul>
            </Card>

            <Card title="Safety & Moderation Counters">
              <ul className="kv">
                <li>
                  <span>Blocks Made (by member)</span>
                  <span>{user.accountActivity.blocksMadeCount}</span>
                </li>
                <li>
                  <span>Blocks Received (against member)</span>
                  <span>{user.accountActivity.blocksReceivedCount}</span>
                </li>
                <li>
                  <span>Reports Submitted (by member)</span>
                  <span>{user.accountActivity.reportsMadeCount}</span>
                </li>
                <li>
                  <span>Reports Filed (against member)</span>
                  <span>{user.accountActivity.reportsAgainstCount}</span>
                </li>
              </ul>
            </Card>
          </div>

          <Card title="Support Tickets">
            {user.supportTickets.length === 0 ? (
              <EmptyState title="No support tickets opened by this member" />
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Subject</th>
                      <th scope="col">Type</th>
                      <th scope="col">Status</th>
                      <th scope="col">Admin Response</th>
                      <th scope="col">Date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {user.supportTickets.map((t) => (
                      <tr key={t.id}>
                        <td>{t.subject}</td>
                        <td>{humanize(t.type)}</td>
                        <td>
                          <Badge value={t.status} />
                        </td>
                        <td>{t.adminResponse || '—'}</td>
                        <td className="nowrap">{formatDate(t.createdAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </>
      ) : null}

      {/* TAB 7: INTERNAL STAFF NOTES */}
      {activeTab === 'notes' ? (
        <>
          <Card title="Add Internal Staff Note">
            <form onSubmit={handleAddNoteSubmit}>
              <Field
                label="Note Content"
                hint="Only visible to Nenjam Matrimony staff. Kept with author identity and timestamp."
                error={noteError}
              >
                {(props) => (
                  <textarea
                    {...props}
                    rows={3}
                    placeholder="e.g. Spoke with candidate on phone; verified original bachelor's certificate..."
                    value={noteContent}
                    maxLength={5000}
                    onChange={(e) => setNoteContent(e.target.value)}
                    required
                  />
                )}
              </Field>
              <div style={{ marginTop: '0.75rem' }}>
                <Button
                  type="submit"
                  tone="primary"
                  busy={noteBusy}
                  disabled={!noteContent.trim()}
                >
                  Save Note
                </Button>
              </div>
            </form>
          </Card>

          <Card title="Notes History">
            {user.internalNotes.length === 0 ? (
              <EmptyState title="No internal notes recorded yet for this member" />
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                {user.internalNotes.map((note) => (
                  <div
                    key={note.id}
                    style={{
                      border: '1px solid var(--border)',
                      borderRadius: 'var(--radius)',
                      padding: '0.75rem 1rem',
                      background: 'var(--surface)',
                    }}
                  >
                    <div
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        marginBottom: '0.4rem',
                      }}
                    >
                      <strong>{note.authorName || 'Staff Member'}</strong>
                      <span className="muted small">{formatDateTime(note.createdAt)}</span>
                    </div>
                    <p style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{note.note}</p>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </>
      ) : null}

      {/* Block Confirmation Dialog */}
      <ConfirmDialog
        open={pendingAction === 'block'}
        title={`Block User: ${user.basicInfo.fullName || user.id}`}
        confirmLabel="Block Member"
        tone="danger"
        requireReason={true}
        reasonLabel="Reason for blocking (recorded in audit log)"
        onConfirm={handleBlockConfirm}
        onClose={() => setPendingAction(null)}
      >
        <p>
          Blocking will set this member’s status to <strong>BLOCKED</strong>, invalidate
          their session cache in Redis immediately, and hide them from search and discovery.
        </p>
      </ConfirmDialog>

      {/* Unblock Confirmation Dialog */}
      <ConfirmDialog
        open={pendingAction === 'unblock'}
        title={`Unblock User: ${user.basicInfo.fullName || user.id}`}
        confirmLabel="Unblock Member"
        tone="primary"
        requireReason={false}
        reasonLabel="Optional note for unblocking"
        onConfirm={handleUnblockConfirm}
        onClose={() => setPendingAction(null)}
      >
        <p>
          Unblocking will restore this account to <strong>ACTIVE</strong> status and record
          an audit log entry.
        </p>
      </ConfirmDialog>

      {/* PII Reveal Confirmation Dialog */}
      <ConfirmDialog
        open={pendingAction === 'reveal'}
        title="Reveal Full Contact Details"
        confirmLabel="Reveal PII"
        tone="primary"
        requireReason={false}
        reasonLabel="Reason for accessing sensitive PII (audit log)"
        onConfirm={handleRevealConfirm}
        onClose={() => setPendingAction(null)}
      >
        <p>
          Full phone numbers, emails, and address fields are protected personal data.
          Revealing them requires a fresh authenticator check (step-up) and creates an
          immutable audit trail.
        </p>
      </ConfirmDialog>
    </>
  );
}
