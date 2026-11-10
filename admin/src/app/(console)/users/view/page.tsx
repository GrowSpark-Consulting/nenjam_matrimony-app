'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useEffect } from 'react';
import { RequirePermission } from '@/components/AppShell';
import { ErrorState, Loading } from '@/components/ui';

export default function UserViewRedirectPage() {
  return (
    <RequirePermission permission="member.view">
      <Suspense fallback={<Loading label="Loading member…" />}>
        <UserViewRedirect />
      </Suspense>
    </RequirePermission>
  );
}

function UserViewRedirect() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = searchParams.get('id');

  useEffect(() => {
    if (id) {
      router.replace(`/users/${id}`);
    }
  }, [id, router]);

  if (!id) {
    return <ErrorState message="No member ID provided in URL parameters." />;
  }

  return <Loading label="Redirecting to member profile…" />;
}
