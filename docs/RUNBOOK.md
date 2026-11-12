# IndiaBizz Operational Runbook

This runbook contains common administrative routines, monitoring guidelines, and incident recovery workflows.

---

## 1. Routine Tasks

### A. Inviting New Delivery Staff
1. As an Owner, navigate to **Team & Partners** in `apps/seller_app`.
2. Click **Invite Staff**, enter the driver's phone number and select the role:
   - `OWN_DELIVERY_STAFF` (in-house driver)
   - `PARTNER_DELIVERY_STAFF` (third-party driver)
3. Share the unique 8-character invitation code.
4. The driver opens `apps/delivery_app`, clicks **Activate Staff Account**, inputs their phone, invite code, and sets their password.

### B. Adding a New Delivery Partner (3PL / Regional Fleet)
1. In `apps/seller_app`, open **Team & Partners** -> **Partners**.
2. Click **Register Partner**, supply Partner Business Name, Code, contact email, and phone.
3. Once approved, the partner administrator can log into the console and manage their fleet.

### C. Adding Serviceable Town & PIN Codes
1. In `apps/seller_app` -> **Team & Partners** -> **Coverage**.
2. Add the Town (Name, District, State).
3. Add serviceable 6-digit postal codes under that Town.
4. The website storefront and customer app will immediately recognize the postal code and permit checkout.

---

## 2. Cash on Delivery Reconciliation Routine

1. At the end of every shift or route, delivery staff declare handover via the **Cash & Custody** tab in `apps/delivery_app`.
2. The Hub Cashier / Owner navigates to **COD & Cash** in `apps/seller_app`.
3. Open the pending settlement for the driver.
4. Count the physical cash:
   - If exact: Click **Approve Settlement**.
   - If discrepancy: Record counted amount. Any shortage or excess is permanently attributed to the driver ledger with timestamp and cashier UUID.

---

## 3. Incident Management & Recovery

- **Customer did not receive OTP**:
  Delivery staff can press **Resend OTP** on the active delivery card in `apps/delivery_app`. This triggers `staff_resend_delivery_otp` to dispatch a new 6-digit OTP via Twilio.
- **Package damaged in transit**:
  Delivery staff marks **Report Failed** -> `PACKAGE_DAMAGED` in `apps/delivery_app`. The order status moves to `DELIVERY_FAILED`, stock adjustments are logged as `DAMAGE`, and the customer is notified.
