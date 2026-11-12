"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  errorMessage,
  formatDate,
  formatPhoneDisplay,
  hasErrors,
  initials,
  relativeTime,
  validateProfile,
  type Address,
  type FieldErrors,
  type NotificationItem,
  type Town,
} from "@indibizz/shared";
import {
  deleteAddress,
  getAddresses,
  getTowns,
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  updateProfile,
} from "@/lib/api";
import { useAuth, useToast } from "@/components/providers";
import { AddressForm } from "@/components/address-form";
import { EmptyState, ErrorPanel, LoadingBlock, PageHead } from "@/components/ui";
import {
  ArrowRightIcon,
  BellIcon,
  CheckIcon,
  HomeIcon,
  LogOutIcon,
  MapPinIcon,
  PackageIcon,
  PlusIcon,
  UserIcon,
} from "@/components/icons";

export default function AccountPage() {
  const router = useRouter();
  const { user, profile, loading: authLoading, profileLoading, profileError, refreshProfile, signOut } = useAuth();
  const { showToast } = useToast();

  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [profileErrors, setProfileErrors] = useState<FieldErrors>({});
  const [savingProfile, setSavingProfile] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const [addresses, setAddresses] = useState<Address[]>([]);
  const [towns, setTowns] = useState<Town[]>([]);
  const [addressLoading, setAddressLoading] = useState(true);
  const [showAddressForm, setShowAddressForm] = useState(false);
  const [editingAddress, setEditingAddress] = useState<Address | null>(null);
  const [addressError, setAddressError] = useState<string | null>(null);

  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const [notificationLoading, setNotificationLoading] = useState(true);
  const [notificationError, setNotificationError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile) return;
    setFullName(profile.full_name ?? "");
    setEmail(profile.email ?? "");
  }, [profile]);

  const loadAddresses = useCallback(async () => {
    setAddressLoading(true);
    setAddressError(null);
    try {
      const [addressRows, townRows] = await Promise.all([getAddresses(), getTowns()]);
      setAddresses(addressRows);
      setTowns(townRows);
    } catch (caught) {
      setAddressError(errorMessage(caught, "Your addresses could not be loaded."));
    } finally {
      setAddressLoading(false);
    }
  }, []);

  const loadNotifications = useCallback(async () => {
    setNotificationLoading(true);
    setNotificationError(null);
    try {
      setNotifications(await listNotifications());
    } catch (caught) {
      setNotificationError(errorMessage(caught, "Notifications could not be loaded."));
    } finally {
      setNotificationLoading(false);
    }
  }, []);

  useEffect(() => {
    if (authLoading) return;
    if (!user) {
      setAddressLoading(false);
      setNotificationLoading(false);
      return;
    }
    void loadAddresses();
    void loadNotifications();
  }, [authLoading, loadAddresses, loadNotifications, user]);

  const unread = useMemo(() => notifications.filter((item) => !item.read_at).length, [notifications]);

  async function saveProfile(event: React.FormEvent) {
    event.preventDefault();
    setActionError(null);
    const errors = validateProfile(fullName, email);
    setProfileErrors(errors);
    if (hasErrors(errors)) return;
    setSavingProfile(true);
    try {
      await updateProfile(fullName.trim(), email.trim());
      await refreshProfile();
      showToast("Profile updated.", "success");
    } catch (caught) {
      setActionError(errorMessage(caught));
    } finally {
      setSavingProfile(false);
    }
  }

  async function removeAddress(address: Address) {
    if (!window.confirm(`Delete the ${address.label} address? This cannot be undone.`)) return;
    setAddressError(null);
    try {
      await deleteAddress(address.id);
      await loadAddresses();
      showToast("Address deleted.", "success");
    } catch (caught) {
      setAddressError(errorMessage(caught));
    }
  }

  async function readNotification(id: string) {
    const previous = notifications;
    setNotifications((current) => current.map((item) => (item.id === id ? { ...item, read_at: new Date().toISOString() } : item)));
    try {
      await markNotificationRead(id);
    } catch {
      setNotifications(previous);
    }
  }

  async function readAll() {
    try {
      await markAllNotificationsRead();
      setNotifications((current) => current.map((item) => ({ ...item, read_at: item.read_at ?? new Date().toISOString() })));
      showToast("All notifications marked as read.", "success");
    } catch (caught) {
      showToast(errorMessage(caught), "error");
    }
  }

  async function handleSignOut() {
    await signOut();
    showToast("Signed out.");
    router.replace("/");
  }

  if (authLoading) return <div className="page"><div className="container"><LoadingBlock /></div></div>;

  if (!user) {
    return (
      <div className="page">
        <div className="container">
          <EmptyState
            title="Sign in to your account"
            description="Manage your delivery addresses, profile and notifications after verifying your phone number."
            action={<Link href="/login?next=/account" className="btn btn-primary btn-sm">Sign in with phone</Link>}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="page">
      <div className="container">
        <PageHead
          eyebrow="Account"
          title={profile?.full_name ? `Hello, ${profile.full_name.split(" ")[0]}` : "Your account"}
          description="Your verified phone number anchors every order, address and notification."
          action={<Link href="/shop" className="btn btn-outline btn-sm">Shop again</Link>}
        />

        <div className="account-grid">
          <aside className="card profile-card">
            <div className="avatar">{initials(profile?.full_name)}</div>
            <h2 style={{ fontSize: "1.15rem" }}>{profile?.full_name || "IndiaBizz customer"}</h2>
            <p className="muted small" style={{ marginTop: 3 }}>{formatPhoneDisplay(profile?.phone)}</p>
            {profile && <span className="badge info" style={{ marginTop: 10 }}>{profile.role.replaceAll("_", " ").toLowerCase()}</span>}
            <p className="help" style={{ marginTop: 12 }}>Member since {formatDate(profile?.created_at)}</p>

            <div className="stack-sm" style={{ marginTop: 18 }}>
              <Link href="/orders" className="btn btn-outline btn-sm btn-block"><PackageIcon size={15} /> Your orders</Link>
              <Link href="/cart" className="btn btn-outline btn-sm btn-block">Your cart</Link>
              <button type="button" className="btn btn-ghost btn-sm btn-block" onClick={handleSignOut}>
                <LogOutIcon size={15} /> Sign out
              </button>
            </div>

            {profile?.role && profile.role !== "CUSTOMER" && (
              <div className="alert" style={{ marginTop: 15, textAlign: "left" }}>
                <UserIcon size={17} />
                <span>This is the customer website. Operational seller and delivery workflows live in the dedicated apps.</span>
              </div>
            )}
          </aside>

          <div className="stack">
            {actionError && <ErrorPanel message={actionError} />}
            {profileError && (
              <div className="alert warning">
                <span>{profileError}</span>
                <button type="button" className="link-btn" onClick={() => void refreshProfile()}>Retry</button>
              </div>
            )}

            <section className="card card-pad" id="profile">
              <h2 style={{ fontSize: "1.12rem", marginBottom: 5 }}>Profile</h2>
              <p className="muted small" style={{ marginBottom: 15 }}>Your phone number is verified and cannot be edited here.</p>
              <form onSubmit={saveProfile} className="stack" noValidate>
                <div className="form-grid">
                  <div className={`field ${profileErrors.full_name ? "invalid" : ""}`}>
                    <label className="label" htmlFor="profile-name">Full name</label>
                    <input
                      id="profile-name"
                      className="input"
                      value={fullName}
                      onChange={(event) => setFullName(event.target.value)}
                      maxLength={160}
                      autoComplete="name"
                    />
                    {profileErrors.full_name && <span className="error-text">{profileErrors.full_name}</span>}
                  </div>
                  <div className={`field ${profileErrors.email ? "invalid" : ""}`}>
                    <label className="label" htmlFor="profile-email">Email <span className="muted">(optional)</span></label>
                    <input
                      id="profile-email"
                      className="input"
                      type="email"
                      value={email}
                      onChange={(event) => setEmail(event.target.value)}
                      maxLength={320}
                      autoComplete="email"
                    />
                    {profileErrors.email && <span className="error-text">{profileErrors.email}</span>}
                  </div>
                  <div className="field">
                    <span className="label">Verified phone</span>
                    <input className="input" value={formatPhoneDisplay(profile?.phone)} disabled />
                  </div>
                </div>
                <div>
                  <button type="submit" className="btn btn-primary" disabled={savingProfile || profileLoading}>
                    {savingProfile ? <span className="spinner" /> : <CheckIcon size={16} />}
                    {savingProfile ? "Saving…" : "Save profile"}
                  </button>
                </div>
              </form>
            </section>

            <section className="card card-pad" id="addresses">
              <div className="spread" style={{ marginBottom: 14 }}>
                <div>
                  <h2 style={{ fontSize: "1.12rem" }}>Delivery addresses</h2>
                  <p className="muted small" style={{ marginTop: 3 }}>Only serviceable towns and PIN codes can be saved.</p>
                </div>
                {!showAddressForm && (
                  <button
                    type="button"
                    className="btn btn-outline btn-sm"
                    onClick={() => {
                      setEditingAddress(null);
                      setShowAddressForm(true);
                    }}
                  >
                    <PlusIcon size={15} /> Add
                  </button>
                )}
              </div>

              {addressError && <div style={{ marginBottom: 12 }}><ErrorPanel message={addressError} retry={loadAddresses} /></div>}

              {showAddressForm ? (
                <AddressForm
                  key={editingAddress?.id ?? "new"}
                  towns={towns}
                  initial={editingAddress}
                  defaultPhone={profile?.phone ?? ""}
                  onSaved={async () => {
                    setShowAddressForm(false);
                    setEditingAddress(null);
                    await loadAddresses();
                    showToast("Address saved.", "success");
                  }}
                  onCancel={() => {
                    setShowAddressForm(false);
                    setEditingAddress(null);
                  }}
                />
              ) : addressLoading ? (
                <LoadingBlock label="Loading addresses…" />
              ) : addresses.length === 0 ? (
                <EmptyState
                  icon={<MapPinIcon size={26} />}
                  title="No delivery address yet"
                  description="Add the address where you want your COD parcel delivered."
                  action={
                    <button type="button" className="btn btn-primary btn-sm" onClick={() => setShowAddressForm(true)}>
                      Add your first address
                    </button>
                  }
                />
              ) : (
                <div className="address-grid">
                  {addresses.map((address) => (
                    <article key={address.id} className="card address-card">
                      <div className="address-title">
                        <MapPinIcon size={15} /> {address.label}
                        {address.is_default && <span className="address-tag">Default</span>}
                      </div>
                      <p className="small" style={{ fontWeight: 700 }}>{address.recipient_name} · {address.phone}</p>
                      <p className="muted small">
                        {[address.line1, address.line2, address.landmark].filter(Boolean).join(", ")}
                        <br />
                        {address.town_name}, {address.district}, {address.state} — {address.pincode}
                      </p>
                      <div className="address-actions">
                        <button
                          type="button"
                          className="btn btn-outline btn-sm"
                          onClick={() => {
                            setEditingAddress(address);
                            setShowAddressForm(true);
                          }}
                        >
                          Edit
                        </button>
                        <button type="button" className="btn btn-danger btn-sm" onClick={() => removeAddress(address)}>
                          Delete
                        </button>
                      </div>
                    </article>
                  ))}
                </div>
              )}
            </section>

            <section className="card card-pad" id="notifications">
              <div className="spread" style={{ marginBottom: 6 }}>
                <div>
                  <h2 style={{ fontSize: "1.12rem" }}>Notifications</h2>
                  <p className="muted small" style={{ marginTop: 3 }}>
                    {unread > 0 ? `${unread} unread update${unread === 1 ? "" : "s"}` : "You are up to date."}
                  </p>
                </div>
                {unread > 0 && (
                  <button type="button" className="btn btn-ghost btn-sm" onClick={readAll}>
                    Mark all read
                  </button>
                )}
              </div>

              {notificationError ? (
                <ErrorPanel message={notificationError} retry={loadNotifications} />
              ) : notificationLoading ? (
                <LoadingBlock label="Loading notifications…" />
              ) : notifications.length === 0 ? (
                <EmptyState
                  icon={<BellIcon size={26} />}
                  title="No notifications yet"
                  description="Order confirmations, pickup updates and delivery OTP notices will appear here."
                />
              ) : (
                <div>
                  {notifications.map((item) => {
                    const orderId = typeof item.data?.order_id === "string" ? item.data.order_id : null;
                    const content = (
                      <>
                        <span className="notification-dot" />
                        <span style={{ flex: 1 }}>
                          <span className="notification-title">{item.title}</span>
                          <span className="notification-body" style={{ display: "block" }}>{item.body}</span>
                          <span className="notification-time">{relativeTime(item.created_at)}</span>
                        </span>
                        {!item.read_at && (
                          <button
                            type="button"
                            className="btn btn-ghost btn-sm"
                            onClick={(event) => {
                              event.preventDefault();
                              void readNotification(item.id);
                            }}
                          >
                            Mark read
                          </button>
                        )}
                      </>
                    );
                    return orderId ? (
                      <Link
                        key={item.id}
                        href={`/orders/${orderId}`}
                        className={`notification-item ${item.read_at ? "read" : ""}`}
                        onClick={() => void readNotification(item.id)}
                      >
                        {content}
                      </Link>
                    ) : (
                      <div key={item.id} className={`notification-item ${item.read_at ? "read" : ""}`}>
                        {content}
                      </div>
                    );
                  })}
                </div>
              )}
            </section>

            <section className="card card-pad">
              <div className="spread">
                <div>
                  <h2 style={{ fontSize: "1.05rem" }}>Sign out of this device</h2>
                  <p className="muted small" style={{ marginTop: 3 }}>Your session tokens are removed from this browser.</p>
                </div>
                <button type="button" className="btn btn-outline btn-sm" onClick={handleSignOut}>
                  <LogOutIcon size={15} /> Sign out
                </button>
              </div>
            </section>
          </div>
        </div>
      </div>
    </div>
  );
}
